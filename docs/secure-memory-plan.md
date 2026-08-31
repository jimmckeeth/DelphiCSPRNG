# Design proposal: secure memory container for DelphiCSPRNG

**Status:** proposed, not implemented. Captured for later.

## Context

DelphiCSPRNG generates secrets (keys, tokens, Base64 material) but hands them back as `TBytes`/`String` and never wipes its own intermediates. A code review flagged this as the one remaining defense-in-depth gap.

The goal is a cross-platform secure container for secret bytes. The intuitive aim — "always encrypted, never in a non-encrypted state" — **is not achievable in-process**, and not because of Delphi: to *use* a secret the CPU needs plaintext, and any masking key must live in the same address space as the data it protects. This is why .NET deprecated `SecureString` (and why, on .NET Core for Linux/macOS, it never encrypted at all — just a plain array).

Industry best practice has therefore moved toward **MMU-enforced access control** rather than obfuscation. This proposal follows the **libsodium** model (`sodium_malloc` / `sodium_mlock` / `sodium_mprotect_*`): guard pages, canary, swap-locking, dump exclusion, and `PROT_NONE` when idle. Optional keystream masking is included as defense-in-depth, not as the load-bearing mechanism.

Two other references informed this:

- **OpenSSL's secure heap** (`CRYPTO_secure_malloc`) teaches a hard practical lesson: `RLIMIT_MEMLOCK` is commonly only 64 KB, and tighter on Android, so locking many small buffers *fails*. OpenSSL mlocks one arena and sub-allocates.
- **Go's memguard** does keep an encrypt-at-rest layer, but mitigates key-adjacency by splitting the key across two separately-protected regions and re-randomizing — the honest way to do that layer if you want it.

**Scope note:** this subsystem is comparable in size to the RNG library itself. It is phased so work can stop after Phase 1 or 2 and still leave the repo coherent and better off.

## Key design constraint (Delphi-specific)

**`TBytes` and `String` cannot be secured.** `SetLength` may realloc-and-copy, stranding plaintext in freed heap you can't reach; strings are copy-on-write and refcounted, so copies multiply invisibly. The container must own a page-aligned block it allocates itself and never reallocs.

## Verified available (Delphi 37.0 RTL, no external dependencies)

| Need | Windows | POSIX |
|---|---|---|
| Page-aligned alloc | `VirtualAlloc` | `mmap` + `MAP_ANONYMOUS` |
| Page protection | `VirtualProtect` | `mprotect` + `PROT_NONE` |
| Swap locking | `VirtualLock` / `VirtualUnlock` | `mlock` / `munlock` (`Posix.SysMman`) |
| Dump exclusion | `WerRegisterExcludedMemoryBlock` (Win10+, optional) | `madvise(MADV_DONTDUMP)` — Linux only |
| Keystream (Phase 3) | `THashSHA2` / HMAC-SHA256 (`System.Hash`) | same |

`MADV_DONTDUMP` (Linux, value 16) is not in Delphi's headers; declare the constant locally.

## Design

New unit `src/CSPRNG.SecureMemory.pas`, plus a thin platform layer. Delphi 10.4+ only, so **Custom Managed Records** give deterministic wipe on scope exit — including during exception unwind, which is better than .NET's GC-dependent behavior.

Memory layout per allocation (page-granular):

```
[ guard page: PROT_NONE ][ canary | user data ][ guard page: PROT_NONE ]
```

Core type:

```pascal
TSecureBytes = record
private
  FBlock: Pointer;        // page-aligned base of the whole mapping
  FData: PByte;           // start of user region
  FSize: NativeInt;
  FAccessDepth: Integer;  // atomic; supports nested/concurrent Access
  FLocked: Boolean;       // did mlock/VirtualLock succeed?
  class operator Initialize(out Dest: TSecureBytes);
  class operator Finalize(var Dest: TSecureBytes);   // canary check -> wipe -> unlock -> free
  class operator Assign(var Dest: TSecureBytes; const [ref] Src: TSecureBytes); // deep copy into a new secure block
public
  class function Allocate(ASize: NativeInt): TSecureBytes; static;
  class function FromProvider(const AProvider: ICSPRNGProvider; ASize: NativeInt): TSecureBytes; static;
  function Access: TSecureAccess;   // scoped unseal
  procedure Wipe;
  property Size: NativeInt read FSize;
end;
```

Scoped accessor — a second CMR that unseals on construction and re-seals on scope exit:

```pascal
var Key := TSecureBytes.FromProvider(GetCSPRNGProvider, 32);
begin
  var A := Key.Access;          // pages -> READWRITE
  Move(A.Data^, Target^, Key.Size);
end;                            // pages -> PROT_NONE; Key wiped+freed at its own scope exit
```

`Assign` performs a deep copy into a fresh secure block rather than being blocked outright — blocking would prevent returning a `TSecureBytes` from a function, making the API awkward.

## Phases

### Phase 1 — Foundation (highest value, lowest risk)

- `SecureZeroBytes` that cannot be optimised away. Delphi's Win32 backend rarely elides dead stores, but the Linux/macOS/iOS targets are LLVM-backed and will. Defeat it by writing through a `volatile`-style indirection the optimiser can't prove dead, and keep the routine in its own unit so it isn't inlined into a provably-dead context. **Verify by inspecting generated code on Linux64, not by assuming.**
- Wipe the library's own intermediates: the `RandomBytes` locals in `GetUInt32` / `GetInt32` / `GetInt64` / `GetUInt64` / `GetFloat`, and the `Bytes` local in `GetBase64` (`src/CSPRNG.Provider.Base.pas`).
- Document that `GetBase64` returns a `String`, which is COW/refcounted and therefore *cannot* be wiped — callers wanting a wipeable token should use `GetBytes` + `TSecureBytes`.

### Phase 2 — Secure allocation (the libsodium core)

- `CSPRNG.SecureMemory.Platform.pas`: page size, alloc/free, protect, lock/unlock, dump-exclude — `{$IFDEF}`-split Windows/POSIX, mirroring the existing provider unit structure.
- `TSecureBytes` with guard pages, canary, mlock, `MADV_DONTDUMP`, `PROT_NONE`-when-idle, CMR lifetime, and `TSecureAccess`.
- **Graceful degradation is mandatory**, not optional: a failed `mlock` must set `FLocked := False` and continue, never raise. Expose it as a readable property so callers can assert if they need to.

### Phase 3 — Optional masking (defense-in-depth)

- Keystream from HMAC-SHA256 in counter mode via `System.Hash`, keyed per-instance from the CSPRNG.
- XOR-mask the buffer while sealed; unmask inside `Access`.
- Follow memguard's mitigation: hold the mask key in a *separate* `TSecureBytes` (own guard pages, own `PROT_NONE`), and re-key on each re-seal.
- Document plainly that this defeats crash-dump scraping and naive high-entropy heap scanning, but not a debugger.

## Files

- `src/CSPRNG.SecureMemory.pas` — new; `TSecureBytes`, `TSecureAccess`, `SecureZeroBytes`
- `src/CSPRNG.SecureMemory.Platform.pas` — new; `{$IFDEF MSWINDOWS}` / `{$IFDEF POSIX}` primitives
- `src/CSPRNG.Provider.Base.pas` — wipe intermediates (Phase 1)
- `src/CSPRNG.Interfaces.pas` — reuse existing `ECSPRNGError`; add `ESecureMemoryError` descendant
- `tests/CSPRNG.Tests.SecureMemory.pas` — new fixture
- `tests/CSPRNG.Tests.dpr` / `.dproj`, `sample/CSPRNG_sample.dpr` / `.dproj` — register new units (same edit pattern used when `CSPRNG.Provider.Linux.pas` was added)

Reuse `ICSPRNGProvider` / `GetCSPRNGProvider` for all key and mask generation — do not introduce a second entropy path.

## Verification

Build each target with the usual script:

```
& "C:\Users\jim\git\DelphiStandards\DelphiBuildDPROJ.ps1" -ProjectFile "<proj>" -Config Debug -Platform <Win32|Win64|Linux64> -DelphiVersion "37.0"
```

Then run `tests/Win32/Debug/CSPRNG.Tests.exe --exitbehavior:Continue` (34/34 passing at time of writing — must stay green).

New tests:

- Round-trip: data written under `Access` reads back identically
- `Wipe` zeroes the region (check while still alive, before `Finalize` frees it)
- Canary corruption raises `ESecureMemoryError` on finalize
- Deep-copy `Assign` produces an independent block; mutating one doesn't affect the other
- Nested `Access` calls balance correctly (seal only on outermost exit)
- `mlock` failure path degrades gracefully — request an allocation past the lock limit, assert no exception and `Locked = False`
- Phase 3: sealed buffer does not contain plaintext

Guard-page traps and the non-elidable-zeroing guarantee **cannot be asserted portably from DUnitX** — a guard-page hit is a segfault, and dead-store elimination is a codegen property. Verify both manually: guard pages via a deliberate overrun under SEH on Windows, and zeroing by disassembling the Linux64 release build to confirm the stores survive. Document as manual checks rather than faking automated coverage.

## Out of scope

- **OS keyrings / hardware**: Keychain + Secure Enclave (Apple), DPAPI/CNG (Windows), kernel keyring (Linux), TPM. These keep secrets out of the address space entirely and are *strictly stronger* than anything here — on iOS/macOS, Keychain is the actual best practice. Worth a README pointer so readers aren't misled into thinking this container is the top of the ladder.
- Anti-debugging / `PT_DENY_ATTACH`.
- Securing `String`-typed returns — not fixable given COW semantics; documented instead.
