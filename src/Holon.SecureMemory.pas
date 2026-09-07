unit Holon.SecureMemory;

{
  Guarded, swap-locked storage for secret bytes (keys, tokens, passwords), modeled
  on libsodium's sodium_malloc/sodium_mlock/sodium_mprotect_* family rather than on
  encrypt-at-rest schemes like the (now-deprecated) .NET SecureString: a masking key
  necessarily lives in the same address space as the data it protects, so
  obfuscation is a speed bump, not a wall. What actually helps is MMU-enforced
  access control - see docs/secure-memory-plan.md for the full rationale.

  TBytes and String cannot be secured (SetLength may realloc-and-copy, stranding
  plaintext in freed heap; strings are copy-on-write and refcounted, multiplying
  copies invisibly), so TSecureBytes owns a page-aligned block it allocates itself
  and never reallocates. Each allocation is laid out as:

    [ guard page: PROT_NONE ] [ padding ] [ canary ] [ user data ] [ guard page: PROT_NONE ]

  with the user data flush against the trailing guard page (so an overflow off the
  end faults immediately) and the canary immediately before it (so an underflow
  corrupts the canary before it can reach the leading guard page). The middle
  region - canary and data together - is only readable/writable while a
  TSecureAccess obtained from TSecureBytes.Access is alive; it is otherwise sealed
  (PROT_NONE) and, where the platform allows it, kept out of swap (mlock/VirtualLock)
  and crash dumps (madvise(MADV_DONTDUMP) on Linux; WerRegisterExcludedMemoryBlock
  on Windows 10+).

  Locking is best-effort: RLIMIT_MEMLOCK is commonly as low as 64 KB, and tighter
  still on Android/iOS, so a failed mlock/VirtualLock is not treated as an error -
  see the Locked property.

  Phase 3 of the design plan (optional HMAC-keystream masking as extra
  defense-in-depth against crash-dump scraping) is not implemented here; the guard
  page and canary protections above are the load-bearing mechanism.
}

interface

uses
  System.SysUtils,
  Holon.CSRNG,
  Holon.CSRNG.Interfaces,
  Holon.SecureMemory.Platform;

type
  /// <summary>
  /// Raised for Holon.SecureMemory-specific errors: an invalid size, a failed
  /// allocation, or - most importantly - a detected canary corruption (a buffer
  /// underflow into the region immediately preceding a TSecureBytes' data).
  /// Descends from ECSPRNGError since TSecureBytes.FromProvider draws its data
  /// from an ICSPRNGProvider; catch ECSPRNGError to handle both uniformly, or
  /// ESecureMemoryError specifically to distinguish memory-safety failures from
  /// random-generation failures.
  /// </summary>
  ESecureMemoryError = class(ECSPRNGError);

  /// <summary>
  /// A scope-bound, read/write window onto a TSecureBytes' data, obtained via
  /// TSecureBytes.Access. Copying a live TSecureAccess (e.g. returning it from a
  /// function, or `B := A;`) takes out an additional, independently-expiring
  /// borrow on the same underlying TSecureBytes, so nested/nesting-via-copy usage
  /// stays balanced.
  /// </summary>
  TSecureAccess = record
  private
    FOwner: Pointer; // address of the originating TSecureBytes; nil if unborrowed
  public
    /// <summary>Pointer to the first byte of the underlying TSecureBytes' data.</summary>
    Data: PByte;
    /// <summary>The number of bytes available at Data.</summary>
    Size: NativeInt;

    // Class operators must be public: Delphi checks declared visibility even for
    // the implicit calls it inserts at every use of a managed record, including
    // from other units. Fields must precede them - Delphi records don't allow a
    // field declaration after a method/property in the same section.
    class operator Initialize(out Dest: TSecureAccess);
    class operator Finalize(var Dest: TSecureAccess);
    class operator Assign(var Dest: TSecureAccess; const [ref] Src: TSecureAccess);
  end;

  TSecureBytes = record
  private
    FBlock: Pointer;        // base of the entire mapping, including both guard pages
    FTotalSize: NativeUInt; // size of FBlock, for FreePages
    FMiddleBase: Pointer;   // base of the region between the two guard pages
    FMiddleSize: NativeUInt;// size of that region (canary + padding + user data)
    FData: PByte;           // first byte of user data, flush against the trailing guard page
    FSize: NativeInt;       // user-requested size in bytes
    FCanaryValue: UInt64;   // expected canary value, kept in ordinary (non-secret) memory
    FAccessDepth: Integer;  // count of live TSecureAccess values borrowed from this instance
    FLocked: Boolean;       // whether LockPages succeeded for the middle region

    /// <summary>
    /// Does the actual allocation/layout/seal work shared by Allocate and
    /// FromProvider. Populates Rec's fields directly (as an out parameter) rather
    /// than returning a TSecureBytes by value, and only after every fallible step
    /// has already succeeded, so a partially-constructed value is never observable
    /// - either Rec ends up fully valid, or an exception propagates and any
    /// mapping already reserved is freed first.
    /// </summary>
    class procedure DoAllocate(const ASize: NativeInt; const InitialData: PByte;
      out Rec: TSecureBytes); static;

    /// <summary>
    /// Checks the canary, wipes the middle region, unlocks and frees the mapping
    /// (all unconditionally - even if the canary is wrong, since leaking the
    /// mapping would be worse than reporting a corrupted one), and clears every
    /// field of Rec to its empty state. Returns False if the canary did not match,
    /// which Finalize and Assign turn into a raised ESecureMemoryError after this
    /// cleanup has already completed. A no-op, returning True, if Rec was never
    /// allocated (FBlock = nil).
    /// </summary>
    class function ReleaseBlock(var Rec: TSecureBytes): Boolean; static;
  public
    // Class operators must be public: Delphi checks declared visibility even for
    // the implicit calls it inserts at every use of a managed record, including
    // from other units.
    class operator Initialize(out Dest: TSecureBytes);
    class operator Finalize(var Dest: TSecureBytes);
    class operator Assign(var Dest: TSecureBytes; const [ref] Src: TSecureBytes);

    /// <summary>
    /// Reserves a new secure, zero-filled block of ASize bytes. The caller is
    /// responsible for writing the actual secret into it (via Access) and for
    /// wiping any plaintext source buffer separately - Allocate itself has no way
    /// to do that on the caller's behalf.
    /// </summary>
    class function Allocate(const ASize: NativeInt): TSecureBytes; static;

    /// <summary>
    /// Reserves a new secure block of ASize bytes and fills it directly from
    /// AProvider. Note this is honest, not magic: AProvider.GetBytes still returns
    /// an ordinary, unprotected TBytes internally (ICSPRNGProvider has no way to
    /// write into a caller-supplied secure buffer directly) - what FromProvider
    /// actually buys over doing this by hand is guaranteeing that intermediate
    /// TBytes is wiped immediately after the copy, via SecureZeroBytes, rather
    /// than relying on the caller to remember to do so.
    /// </summary>
    class function FromProvider(const AProvider: ICSPRNGProvider;
      const ASize: NativeInt): TSecureBytes; static;

    /// <summary>
    /// Grants scoped read/write access to the underlying data: the backing pages
    /// are made readable/writable for as long as the returned TSecureAccess (or any
    /// copy of it) is alive, and are resealed (PROT_NONE) when the last one goes
    /// out of scope. Access calls may be nested (each one increments an internal
    /// count; the pages reseal only when the count returns to zero). Raises
    /// ESecureMemoryError if this TSecureBytes was never allocated, or if the
    /// canary is found to be corrupted when unsealing. The TSecureBytes that
    /// produced the result must remain valid (in scope, not reassigned) for the
    /// entire lifetime of that result.
    /// </summary>
    function Access: TSecureAccess;

    /// <summary>
    /// Zeroes the underlying data immediately (leaving the canary and the
    /// allocation itself intact), without waiting for this TSecureBytes to go out
    /// of scope. Safe to call whether or not an Access is currently outstanding.
    /// A no-op if this TSecureBytes was never allocated.
    /// </summary>
    procedure Wipe;

    /// <summary>The size in bytes passed to Allocate/FromProvider.</summary>
    property Size: NativeInt read FSize;

    /// <summary>
    /// Whether the underlying pages were successfully locked out of swap
    /// (mlock/VirtualLock). False does not mean anything is wrong - the platform's
    /// lockable-memory budget (RLIMIT_MEMLOCK on POSIX) is often small and easily
    /// exhausted - only that this particular hardening measure did not apply;
    /// guard pages, sealing, and wiping are unaffected either way.
    /// </summary>
    property Locked: Boolean read FLocked;
  end;

/// <summary>
/// Zeroes Size bytes at P using a call that the compiler cannot optimize away as a
/// dead store, unlike a plain FillChar immediately before memory is freed or goes
/// out of scope (which every one of Delphi's LLVM-backed backends - Linux, macOS,
/// iOS, Android - is entitled to eliminate as unobservable). A no-op if P is nil or
/// Size is 0.
/// </summary>
procedure SecureZeroBytes(const P: Pointer; const Size: NativeUInt);

implementation

type
  TZeroProc = procedure(P: Pointer; Size: NativeUInt);

procedure InternalZero(P: Pointer; Size: NativeUInt);
begin
  FillChar(P^, Size, 0);
end;

var
  // Calling through this indirection - rather than calling FillChar/InternalZero
  // directly - is what defeats dead-store elimination: since DoZero is a plain
  // global variable (not a const), the compiler cannot assume, at the call site in
  // SecureZeroBytes, which routine will actually run, and so cannot prove the
  // call's effects are unobservable and eligible to be dropped. This mirrors the
  // standard C technique used by OPENSSL_cleanse/explicit_bzero
  // (`extern void *(*volatile memset_ptr)(...) = memset;`). Verify on Linux64 by
  // disassembling a release build and confirming the writes survive - this is a
  // codegen property the automated test suite cannot assert.
  DoZero: TZeroProc = InternalZero;

procedure SecureZeroBytes(const P: Pointer; const Size: NativeUInt);
begin
  if (P = nil) or (Size = 0) then
    Exit;
  DoZero(P, Size);
end;

{ TSecureBytes }

class procedure TSecureBytes.DoAllocate(const ASize: NativeInt; const InitialData: PByte;
  out Rec: TSecureBytes);
const
  CanarySize = SizeOf(UInt64);
var
  PageSz, NeededMiddle, MiddlePages, MiddleSize, TotalSize: NativeUInt;
  Block, MiddleBase, GuardB: Pointer;
  DataPtr: PByte;
  CanaryPtr: PUInt64;
  Provider: ICSPRNGProvider;
  CanaryBytes: TBytes;
  CanaryValue: UInt64;
begin
  if ASize < 0 then
    raise ESecureMemoryError.Create('Size must be zero or greater');

  PageSz := Holon.SecureMemory.Platform.GetPageSize;
  NeededMiddle := NativeUInt(CanarySize) + NativeUInt(ASize);
  MiddlePages := (NeededMiddle + PageSz - 1) div PageSz;
  MiddleSize := MiddlePages * PageSz;
  TotalSize := PageSz + MiddleSize + PageSz; // guard + middle + guard

  Block := Holon.SecureMemory.Platform.AllocPages(TotalSize);
  if Block = nil then
    raise ESecureMemoryError.Create('Failed to allocate secure memory');

  try
    MiddleBase := Pointer(NativeUInt(Block) + PageSz);
    GuardB := Pointer(NativeUInt(MiddleBase) + MiddleSize);
    // Data ends flush against Guard B, and the canary sits immediately before it -
    // see the layout diagram in this unit's header comment.
    DataPtr := PByte(NativeUInt(MiddleBase) + MiddleSize - NativeUInt(ASize));
    CanaryPtr := PUInt64(NativeUInt(DataPtr) - CanarySize);

    if not Holon.SecureMemory.Platform.ProtectNone(Block, PageSz) or
       not Holon.SecureMemory.Platform.ProtectNone(GuardB, PageSz) then
      raise ESecureMemoryError.Create('Failed to seal guard pages');

    Provider := Holon.CSRNG.GetCSPRNGProvider;
    CanaryBytes := Provider.GetBytes(CanarySize);
    try
      Move(CanaryBytes[0], CanaryPtr^, CanarySize);
      CanaryValue := CanaryPtr^;
    finally
      SecureZeroBytes(@CanaryBytes[0], CanarySize);
    end;

    if ASize > 0 then
    begin
      if InitialData <> nil then
        Move(InitialData^, DataPtr^, ASize)
      else
        FillChar(DataPtr^, ASize, 0);
    end;
  except
    Holon.SecureMemory.Platform.FreePages(Block, TotalSize);
    raise;
  end;

  // Only now, after every fallible step above has already succeeded, is Rec
  // actually populated.
  Rec.FBlock := Block;
  Rec.FTotalSize := TotalSize;
  Rec.FMiddleBase := MiddleBase;
  Rec.FMiddleSize := MiddleSize;
  Rec.FData := DataPtr;
  Rec.FSize := ASize;
  Rec.FCanaryValue := CanaryValue;
  Rec.FAccessDepth := 0;
  // Best-effort hardening; never fatal - see the Locked property and this unit's
  // header comment on RLIMIT_MEMLOCK.
  Rec.FLocked := Holon.SecureMemory.Platform.LockPages(MiddleBase, MiddleSize);
  Holon.SecureMemory.Platform.ExcludeFromDump(MiddleBase, MiddleSize);
  Holon.SecureMemory.Platform.ProtectNone(MiddleBase, MiddleSize); // sealed until Access
end;

class function TSecureBytes.ReleaseBlock(var Rec: TSecureBytes): Boolean;
var
  ActualCanary: UInt64;
begin
  if Rec.FBlock = nil then
    Exit(True);

  // Reopen unconditionally, even if an Access was somehow still outstanding (a
  // caller failing to let a TSecureAccess expire first) - this routine must never
  // raise partway through and leak the mapping.
  Holon.SecureMemory.Platform.ProtectReadWrite(Rec.FMiddleBase, Rec.FMiddleSize);

  ActualCanary := PUInt64(NativeUInt(Rec.FData) - SizeOf(UInt64))^;
  Result := ActualCanary = Rec.FCanaryValue;

  SecureZeroBytes(Rec.FMiddleBase, Rec.FMiddleSize);

  if Rec.FLocked then
    Holon.SecureMemory.Platform.UnlockPages(Rec.FMiddleBase, Rec.FMiddleSize);

  Holon.SecureMemory.Platform.FreePages(Rec.FBlock, Rec.FTotalSize);

  Rec.FBlock := nil;
  Rec.FTotalSize := 0;
  Rec.FMiddleBase := nil;
  Rec.FMiddleSize := 0;
  Rec.FData := nil;
  Rec.FSize := 0;
  Rec.FCanaryValue := 0;
  Rec.FAccessDepth := 0;
  Rec.FLocked := False;
end;

class operator TSecureBytes.Initialize(out Dest: TSecureBytes);
begin
  Dest.FBlock := nil;
  Dest.FTotalSize := 0;
  Dest.FMiddleBase := nil;
  Dest.FMiddleSize := 0;
  Dest.FData := nil;
  Dest.FSize := 0;
  Dest.FCanaryValue := 0;
  Dest.FAccessDepth := 0;
  Dest.FLocked := False;
end;

class operator TSecureBytes.Finalize(var Dest: TSecureBytes);
begin
  if not ReleaseBlock(Dest) then
    raise ESecureMemoryError.Create(
      'Secure memory canary corrupted - buffer underflow detected');
end;

class operator TSecureBytes.Assign(var Dest: TSecureBytes; const [ref] Src: TSecureBytes);
var
  OldValid: Boolean;
  NewRec: TSecureBytes;
begin
  OldValid := ReleaseBlock(Dest); // Dest is now the empty/all-nil state either way

  if Src.FBlock <> nil then
  begin
    DoAllocate(Src.FSize, nil, NewRec);
    // DoAllocate always leaves its result sealed (PROT_NONE), so NewRec's own
    // region must be reopened before writing into it, in addition to Src's.
    Holon.SecureMemory.Platform.ProtectReadWrite(Src.FMiddleBase, Src.FMiddleSize);
    Holon.SecureMemory.Platform.ProtectReadWrite(NewRec.FMiddleBase, NewRec.FMiddleSize);
    try
      if Src.FSize > 0 then
        Move(Src.FData^, NewRec.FData^, Src.FSize);
    finally
      // NewRec always reseals - Assign hands Dest back sealed, matching the state
      // a fresh Allocate/FromProvider would leave it in.
      Holon.SecureMemory.Platform.ProtectNone(NewRec.FMiddleBase, NewRec.FMiddleSize);
      // Only reseal Src if it wasn't already open for an outstanding Access of
      // its own - copying must not disturb a borrow the caller still holds.
      if Src.FAccessDepth = 0 then
        Holon.SecureMemory.Platform.ProtectNone(Src.FMiddleBase, Src.FMiddleSize);
    end;

    // Transplant NewRec's fields into Dest one at a time - never `Dest := NewRec;`,
    // which would recursively invoke this very operator - then neutralize NewRec
    // so its own Finalize (about to run when this operator returns) is a no-op.
    Dest.FBlock := NewRec.FBlock;
    Dest.FTotalSize := NewRec.FTotalSize;
    Dest.FMiddleBase := NewRec.FMiddleBase;
    Dest.FMiddleSize := NewRec.FMiddleSize;
    Dest.FData := NewRec.FData;
    Dest.FSize := NewRec.FSize;
    Dest.FCanaryValue := NewRec.FCanaryValue;
    Dest.FAccessDepth := NewRec.FAccessDepth;
    Dest.FLocked := NewRec.FLocked;
    NewRec.FBlock := nil;
  end;

  if not OldValid then
    raise ESecureMemoryError.Create(
      'Secure memory canary corrupted - buffer underflow detected');
end;

class function TSecureBytes.Allocate(const ASize: NativeInt): TSecureBytes;
begin
  DoAllocate(ASize, nil, Result);
end;

class function TSecureBytes.FromProvider(const AProvider: ICSPRNGProvider;
  const ASize: NativeInt): TSecureBytes;
var
  Temp: TBytes;
begin
  Temp := AProvider.GetBytes(ASize);
  try
    if ASize > 0 then
      DoAllocate(ASize, @Temp[0], Result)
    else
      DoAllocate(ASize, nil, Result);
  finally
    if Length(Temp) > 0 then
      SecureZeroBytes(@Temp[0], Length(Temp));
  end;
end;

function TSecureBytes.Access: TSecureAccess;
begin
  if FBlock = nil then
    raise ESecureMemoryError.Create('Cannot access an unallocated TSecureBytes');

  if FAccessDepth = 0 then
  begin
    if not Holon.SecureMemory.Platform.ProtectReadWrite(FMiddleBase, FMiddleSize) then
      raise ESecureMemoryError.Create('Failed to unseal secure memory for access');
    if PUInt64(NativeUInt(FData) - SizeOf(UInt64))^ <> FCanaryValue then
    begin
      Holon.SecureMemory.Platform.ProtectNone(FMiddleBase, FMiddleSize);
      raise ESecureMemoryError.Create(
        'Secure memory canary corrupted - buffer underflow detected');
    end;
  end;

  Inc(FAccessDepth);

  Result.FOwner := @Self;
  Result.Data := FData;
  Result.Size := FSize;
end;

procedure TSecureBytes.Wipe;
var
  WasSealed: Boolean;
begin
  if FBlock = nil then
    Exit;

  WasSealed := FAccessDepth = 0;
  if WasSealed then
    Holon.SecureMemory.Platform.ProtectReadWrite(FMiddleBase, FMiddleSize);
  if FSize > 0 then
    SecureZeroBytes(FData, NativeUInt(FSize));
  if WasSealed then
    Holon.SecureMemory.Platform.ProtectNone(FMiddleBase, FMiddleSize);
end;

{ TSecureAccess }

class operator TSecureAccess.Initialize(out Dest: TSecureAccess);
begin
  Dest.FOwner := nil;
  Dest.Data := nil;
  Dest.Size := 0;
end;

class operator TSecureAccess.Finalize(var Dest: TSecureAccess);
var
  Owner: ^TSecureBytes;
begin
  if Dest.FOwner = nil then
    Exit;

  Owner := Dest.FOwner;
  Dec(Owner^.FAccessDepth);
  if Owner^.FAccessDepth <= 0 then
  begin
    Owner^.FAccessDepth := 0;
    Holon.SecureMemory.Platform.ProtectNone(Owner^.FMiddleBase, Owner^.FMiddleSize);
  end;

  Dest.FOwner := nil;
end;

class operator TSecureAccess.Assign(var Dest: TSecureAccess; const [ref] Src: TSecureAccess);
var
  Owner: ^TSecureBytes;
begin
  if Dest.FOwner <> nil then
  begin
    // Dest already held its own borrow; release it before taking on Src's, exactly
    // as Finalize would.
    Owner := Dest.FOwner;
    Dec(Owner^.FAccessDepth);
    if Owner^.FAccessDepth <= 0 then
    begin
      Owner^.FAccessDepth := 0;
      Holon.SecureMemory.Platform.ProtectNone(Owner^.FMiddleBase, Owner^.FMiddleSize);
    end;
  end;

  Dest.FOwner := Src.FOwner;
  Dest.Data := Src.Data;
  Dest.Size := Src.Size;

  if Src.FOwner <> nil then
  begin
    // Copying a live access takes out an additional, independently-expiring
    // borrow, so nested/copied usage stays balanced regardless of how many
    // TSecureAccess values end up referring to the same TSecureBytes.
    Owner := Src.FOwner;
    Inc(Owner^.FAccessDepth);
  end;
end;

end.
