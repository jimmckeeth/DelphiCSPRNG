unit Holon.SecureMemory.Tests;

interface

uses
  SysUtils,
  DUnitX.TestFramework,
  Holon.CSRNG,
  Holon.CSRNG.Interfaces,
  Holon.SecureMemory,
  Holon.SecureMemory.Platform;

type
  [TestFixture]
  TSecureMemoryTests = class
  public
    [Test]
    procedure TestAllocate_ZeroFilled;
    [Test]
    procedure TestAllocate_ZeroSize;
    [Test]
    procedure TestAccess_RoundTrip;
    [Test]
    procedure TestFromProvider_FillsFromProvider;
    [Test]
    procedure TestWipe_ZeroesDataWhileStillAlive;
    [Test]
    procedure TestAssign_DeepCopy_Independent;
    [Test]
    procedure TestNestedAccess_Balances;
    [Test]
    procedure TestSequentialAccess_ReopensCorrectly;
    [Test]
    procedure TestAccessedValueCopy_KeepsOwnerOpenUntilBothExpire;
    [Test]
    procedure TestAccess_OnUnallocated_Raises;
    [Test]
    procedure TestCanaryCorruption_RaisesOnFinalize;
    [Test]
    procedure TestCanaryCorruption_RaisesOnAccess;
    [Test]
    procedure TestSecureZeroBytes_ZeroesBuffer;
    [Test]
    procedure TestSecureZeroBytes_NilOrZeroSize_NoOp;
    [Test]
    procedure TestPlatform_AllocProtectLockFree_RoundTrip;
    [Test]
    procedure TestLockedProperty_DoesNotRaiseEitherWay;
  end;

implementation

{ TSecureMemoryTests }

procedure TSecureMemoryTests.TestAllocate_ZeroFilled;
var
  S: TSecureBytes;
  I: Integer;
  AllZero: Boolean;
begin
  S := TSecureBytes.Allocate(64);
  Assert.AreEqual(NativeInt(64), S.Size);

  AllZero := True;
  var A := S.Access;
  for I := 0 to 63 do
    if A.Data[I] <> 0 then
    begin
      AllZero := False;
      Break;
    end;
  Assert.IsTrue(AllZero, 'Freshly allocated TSecureBytes must be zero-filled');
end;

procedure TSecureMemoryTests.TestAllocate_ZeroSize;
var
  S: TSecureBytes;
begin
  S := TSecureBytes.Allocate(0);
  Assert.AreEqual(NativeInt(0), S.Size);
  var A := S.Access; // must not raise, even though there's nothing to read
  Assert.AreEqual(NativeInt(0), A.Size);
end;

procedure TSecureMemoryTests.TestAccess_RoundTrip;
const
  Source: array[0..7] of Byte = ($DE, $AD, $BE, $EF, $01, $02, $03, $04);
var
  S: TSecureBytes;
  Readback: array[0..7] of Byte;
begin
  S := TSecureBytes.Allocate(8);
  var A := S.Access;
  Move(Source[0], A.Data^, 8);

  FillChar(Readback, 8, 0);
  var A2 := S.Access;
  Move(A2.Data^, Readback[0], 8);

  Assert.IsTrue(CompareMem(@Source[0], @Readback[0], 8), 'Data written under Access must read back identically');
end;

procedure TSecureMemoryTests.TestFromProvider_FillsFromProvider;
var
  Provider: ICSPRNGProvider;
  S1, S2: TSecureBytes;
  A1, A2: TSecureAccess;
begin
  Provider := GetCSPRNGProvider;
  S1 := TSecureBytes.FromProvider(Provider, 32);
  S2 := TSecureBytes.FromProvider(Provider, 32);

  A1 := S1.Access;
  A2 := S2.Access;
  // Two independent 32-byte draws from a CSPRNG matching is astronomically
  // unlikely; this is a smoke test that FromProvider actually filled the buffer
  // with something (not left it zeroed).
  Assert.IsFalse(CompareMem(A1.Data, A2.Data, 32), 'FromProvider should not produce all-matching output across two calls');
end;

procedure TSecureMemoryTests.TestWipe_ZeroesDataWhileStillAlive;
var
  S: TSecureBytes;
  I: Integer;
  AllZero: Boolean;
begin
  S := TSecureBytes.Allocate(16);
  var A := S.Access;
  FillChar(A.Data^, 16, $AA);

  S.Wipe;

  var A2 := S.Access;
  AllZero := True;
  for I := 0 to 15 do
    if A2.Data[I] <> 0 then
    begin
      AllZero := False;
      Break;
    end;
  Assert.IsTrue(AllZero, 'Wipe must zero the data while the container is still alive');
  Assert.AreEqual(NativeInt(16), S.Size, 'Wipe must not change Size');
end;

procedure TSecureMemoryTests.TestAssign_DeepCopy_Independent;
var
  S1, S2: TSecureBytes;
begin
  S1 := TSecureBytes.Allocate(4);
  var A1 := S1.Access;
  FillChar(A1.Data^, 4, $11);

  S2 := S1; // deep copy via class operator Assign

  var A2 := S2.Access;
  Assert.IsTrue(CompareMem(A1.Data, A2.Data, 4), 'Assign must copy the current contents');

  // Mutate S1's copy after the assignment; S2 must be unaffected.
  FillChar(A1.Data^, 4, $22);
  Assert.IsFalse(CompareMem(A1.Data, A2.Data, 4), 'Assign must produce an independent block, not aliasing the source');
end;

procedure TSecureMemoryTests.TestNestedAccess_Balances;
const
  Value: Byte = $5A;
var
  S: TSecureBytes;
begin
  S := TSecureBytes.Allocate(1);
  begin
    var Outer := S.Access;
    Outer.Data^ := Value;
    begin
      var Inner := S.Access; // nested - must not reseal on Inner's own exit
      Assert.AreEqual(Value, Inner.Data^);
    end;
    // Outer must still be valid/open here.
    Assert.AreEqual(Value, Outer.Data^);
  end;

  // After both have gone out of scope, a fresh Access must still work correctly.
  var Final := S.Access;
  Assert.AreEqual(Value, Final.Data^);
end;

procedure TSecureMemoryTests.TestSequentialAccess_ReopensCorrectly;
const
  IterationCount = 50;
var
  S: TSecureBytes;
  I: Byte;
begin
  S := TSecureBytes.Allocate(1);
  for I := 0 to IterationCount - 1 do
  begin
    var A := S.Access;
    A.Data^ := I;
    Assert.AreEqual(I, A.Data^);
  end; // A reseals here each iteration; the next Access must reopen cleanly.
end;

procedure TSecureMemoryTests.TestAccessedValueCopy_KeepsOwnerOpenUntilBothExpire;
const
  Value: Byte = $42;
var
  S: TSecureBytes;
begin
  S := TSecureBytes.Allocate(1);
  var Outer := S.Access;
  Outer.Data^ := Value;
  begin
    var Copy: TSecureAccess := Outer; // exercises TSecureAccess.Assign
    Assert.AreEqual(Value, Copy.Data^);
  end;
  // Outer must still be usable after Copy expired - the copy must not have
  // resealed the pages out from under Outer.
  Assert.AreEqual(Value, Outer.Data^);
end;

procedure TSecureMemoryTests.TestAccess_OnUnallocated_Raises;
var
  S: TSecureBytes;
begin
  Assert.WillRaise(
    procedure
    begin
      var A := S.Access;
    end,
    ESecureMemoryError);
end;

procedure TSecureMemoryTests.TestCanaryCorruption_RaisesOnFinalize;
begin
  Assert.WillRaise(
    procedure
    var
      S: TSecureBytes;
    begin
      S := TSecureBytes.Allocate(4);
      var A := S.Access;
      // Corrupt the byte immediately preceding the data - i.e. the canary itself
      // - while the region is still open for writing, so this hits the canary
      // check rather than faulting a guard page.
      PByte(NativeUInt(A.Data) - 1)^ := PByte(NativeUInt(A.Data) - 1)^ xor $FF;
      // S (and A) go out of scope here: A reseals first (no canary check), then
      // S's own Finalize checks the canary and must raise.
    end,
    ESecureMemoryError);
end;

procedure TSecureMemoryTests.TestCanaryCorruption_RaisesOnAccess;
begin
  Assert.WillRaise(
    procedure
    var
      S: TSecureBytes;
      Raised: Boolean;
    begin
      S := TSecureBytes.Allocate(4);
      begin
        var A := S.Access;
        PByte(NativeUInt(A.Data) - 1)^ := PByte(NativeUInt(A.Data) - 1)^ xor $FF;
      end; // reseals; TSecureAccess.Finalize does not itself check the canary

      Raised := False;
      try
        var A2 := S.Access; // canary check happens here, on reopen
      except
        on E: ESecureMemoryError do
          Raised := True;
      end;
      Assert.IsTrue(Raised, 'Access must raise immediately when reopening a corrupted block');
      // S still holds the corrupted canary and raises again from its own
      // Finalize when this anonymous procedure returns - that second raise is
      // what the outer Assert.WillRaise validates, confirming both raise points.
    end,
    ESecureMemoryError);
end;

procedure TSecureMemoryTests.TestSecureZeroBytes_ZeroesBuffer;
var
  Buf: array[0..15] of Byte;
  I: Integer;
begin
  for I := 0 to 15 do
    Buf[I] := I + 1;
  SecureZeroBytes(@Buf[0], 16);
  for I := 0 to 15 do
    Assert.AreEqual(Byte(0), Buf[I]);
end;

procedure TSecureMemoryTests.TestSecureZeroBytes_NilOrZeroSize_NoOp;
var
  Buf: Byte;
begin
  Buf := $7F;
  SecureZeroBytes(nil, 16); // must not access nil
  SecureZeroBytes(@Buf, 0); // must not touch Buf
  Assert.AreEqual(Byte($7F), Buf);
end;

procedure TSecureMemoryTests.TestPlatform_AllocProtectLockFree_RoundTrip;
var
  PageSz: NativeUInt;
  P: Pointer;
begin
  PageSz := Holon.SecureMemory.Platform.GetPageSize;
  Assert.IsTrue(PageSz > 0, 'Page size must be positive');

  P := Holon.SecureMemory.Platform.AllocPages(PageSz);
  Assert.IsNotNull(P, 'AllocPages should succeed for one page');
  try
    Assert.IsTrue(Holon.SecureMemory.Platform.ProtectReadWrite(P, PageSz));
    PByte(P)^ := $99;
    Assert.AreEqual(Byte($99), PByte(P)^);

    Assert.IsTrue(Holon.SecureMemory.Platform.ProtectNone(P, PageSz));
    // Deliberately not dereferencing P here - that would fault by design; this
    // just confirms the calls themselves succeed. Guard-page fault behavior is a
    // manual check (see docs/secure-memory-plan.md), not something DUnitX can
    // assert without crashing the test runner.
  finally
    // Pages must be made writable again before munmap/VirtualFree on some
    // platforms' bookkeeping; harmless either way.
    Holon.SecureMemory.Platform.ProtectReadWrite(P, PageSz);
    Assert.IsTrue(Holon.SecureMemory.Platform.FreePages(P, PageSz));
  end;
end;

procedure TSecureMemoryTests.TestLockedProperty_DoesNotRaiseEitherWay;
var
  S: TSecureBytes;
begin
  S := TSecureBytes.Allocate(16);
  // Locked may legitimately be True or False depending on the platform's
  // RLIMIT_MEMLOCK budget - only that reading it, and using the container
  // regardless of its value, never raises.
  var Dummy := S.Locked;
  var A := S.Access;
  A.Data^ := 1;
  Assert.Pass('Locked=' + BoolToStr(Dummy, True) + ' did not affect normal use');
end;

end.
