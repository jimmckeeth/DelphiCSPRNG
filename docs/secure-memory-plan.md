# Design proposal: secure memory container for DelphiCSPRNG

**Status:** Phases 1 and 2 implemented, on the `securememory` branch (`src/Holon.SecureMemory.pas`,
`src/Holon.SecureMemory.Platform.pas`). Phase 3 (optional keystream masking) is
deliberately not implemented - see "Implementation notes" at the end of this
document for what shipped, what was verified and how, and what deviated from the
plan below (which is otherwise left as originally written, for context).

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

New unit `src/Holon.SecureMemory.pas`, plus a thin platform layer. Delphi 10.4+ only, so **Custom Managed Records** give deterministic wipe on scope exit — including during exception unwind, which is better than .NET's GC-dependent behavior.

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
  class function FromProvider(const AProvider: Holon.CSRNG.ICSPRNGProvider; ASize: NativeInt): TSecureBytes; static;
  function Access: TSecureAccess;   // scoped unseal
  procedure Wipe;
  property Size: NativeInt read FSize;
end;
```

Scoped accessor — a second CMR that unseals on construction and re-seals on scope exit:

```pascal
var Key := TSecureBytes.FromProvider(Holon.CSRNG.GetCSPRNGProvider, 32);
begin
  var A := Key.Access;          // pages -> READWRITE
  Move(A.Data^, Target^, Key.Size);
end;                            // pages -> PROT_NONE; Key wiped+freed at its own scope exit
```

`Assign` performs a deep copy into a fresh secure block rather than being blocked outright — blocking would prevent returning a `TSecureBytes` from a function, making the API awkward.

## Phases

### Phase 1 — Foundation (highest value, lowest risk)

- `SecureZeroBytes` that cannot be optimised away. Delphi's Win32 backend rarely elides dead stores, but the Linux/macOS/iOS targets are LLVM-backed and will. Defeat it by writing through a `volatile`-style indirection the optimiser can't prove dead, and keep the routine in its own unit so it isn't inlined into a provably-dead context. **Verify by inspecting generated code on Linux64, not by assuming.**
- Wipe the library's own intermediates: the `RandomBytes` locals in `GetUInt32` / `GetInt32` / `GetInt64` / `GetUInt64` / `GetFloat`, and the `Bytes` local in `GetBase64` (`src/Holon.CSRNG.Provider.Base.pas`).
- Document that `GetBase64` returns a `String`, which is COW/refcounted and therefore *cannot* be wiped — callers wanting a wipeable token should use `GetBytes` + `TSecureBytes`.

### Phase 2 — Secure allocation (the libsodium core)

- `Holon.SecureMemory.Platform.pas`: page size, alloc/free, protect, lock/unlock, dump-exclude — `{$IFDEF}`-split Windows/POSIX, mirroring the existing provider unit structure.
- `TSecureBytes` with guard pages, canary, mlock, `MADV_DONTDUMP`, `PROT_NONE`-when-idle, CMR lifetime, and `TSecureAccess`.
- **Graceful degradation is mandatory**, not optional: a failed `mlock` must set `FLocked := False` and continue, never raise. Expose it as a readable property so callers can assert if they need to.

### Phase 3 — Optional masking (defense-in-depth)

- Keystream from HMAC-SHA256 in counter mode via `System.Hash`, keyed per-instance from the CSPRNG.
- XOR-mask the buffer while sealed; unmask inside `Access`.
- Follow memguard's mitigation: hold the mask key in a *separate* `TSecureBytes` (own guard pages, own `PROT_NONE`), and re-key on each re-seal.
- Document plainly that this defeats crash-dump scraping and naive high-entropy heap scanning, but not a debugger.

## Files

- `src/Holon.SecureMemory.pas` — new; `TSecureBytes`, `TSecureAccess`, `SecureZeroBytes`
- `src/Holon.SecureMemory.Platform.pas` — new; `{$IFDEF MSWINDOWS}` / `{$IFDEF POSIX}` primitives
- `src/Holon.CSRNG.Provider.Base.pas` — wipe intermediates (Phase 1)
- `src/Holon.CSRNG.Interfaces.pas` — reuse existing `ECSPRNGError`; add `ESecureMemoryError` descendant
- `tests/CSPRNG.Tests.SecureMemory.pas` — new fixture
- `tests/CSPRNG.Tests.dpr` / `.dproj`, `sample/CSPRNG_sample.dpr` / `.dproj` — register new units (same edit pattern used when `Holon.CSRNG.Provider.Linux.pas` was added)

Reuse `Holon.CSRNG.ICSPRNGProvider` / `Holon.CSRNG.GetCSPRNGProvider` for all key and mask generation — do not introduce a second entropy path.

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

## Implementation notes

What actually shipped, on the `securememory` branch, differs from the plan above in a few places - noted here rather than silently left inconsistent:

- **`ESecureMemoryError`** is defined in `src/Holon.SecureMemory.pas` itself, as `class(ECSPRNGError)`, rather than by editing `Holon.CSRNG.Interfaces.pas`. Same inheritance relationship the plan called for ("reuse existing `ECSPRNGError`"); it just didn't require touching the CSRNG unit, since `Holon.SecureMemory.pas` already imports `Holon.CSRNG.Interfaces` for `ICSPRNGProvider`.
- **Layout matches the plan's diagram exactly**: guard page (`PROT_NONE`) / padding / 8-byte canary / user data flush against the trailing guard page / guard page (`PROT_NONE`). The canary is generated per-allocation from `Holon.CSRNG.GetCSPRNGProvider`, independently of whichever provider a `FromProvider` caller supplied for the payload itself.
- **`TSecureBytes.Allocate`/`FromProvider`/`ReleaseBlock` are implemented as `out`-parameter procedures internally** (`DoAllocate(...; out Rec: TSecureBytes)`), not as functions returning `TSecureBytes` by value, and every internal field transfer is done one field at a time rather than via `:=`. This was load-bearing, not stylistic: `class operator Assign` fires on *any* `TSecureBytes := TSecureBytes` assignment, including ones the type's own methods would otherwise perform internally (e.g. `Result := AllocateInternal(...)`), which risks infinite recursion or accidental double-allocation if the internal construction path itself uses `:=`. Populating fields directly sidesteps the question entirely rather than depending on exact compiler codegen behavior for record return-value construction.
- **`TSecureAccess` needed its own `class operator Assign`**, which the plan's sketch didn't include. `var A := Key.Access;` copies the function's return value into `A`; without a defined `Assign`, nothing would keep `FAccessDepth` on the originating `TSecureBytes` balanced across that copy. `Assign` treats copying a live `TSecureAccess` as taking out an additional, independently-expiring borrow (incrementing the owner's `FAccessDepth`), which stays correct regardless of the exact mechanics the compiler uses for the return-value copy.
- **A real bug was caught by the test suite, not by review**: the first version of `class operator TSecureBytes.Assign` unsealed the *source*'s pages before the deep-copy `Move`, but not the freshly-allocated destination's pages (`DoAllocate` always returns sealed) — an immediate access-violation on `TestAssign_DeepCopy_Independent`, i.e. the guard-page mechanism catching a real bug in the code meant to respect it. Fixed by unsealing both sides before the copy.
- **Phase 3 (keystream masking) was not implemented.** Guard pages + canary + swap-locking (Phases 1–2) are the load-bearing mechanism per the plan's own framing; masking was explicitly "defense-in-depth, not load-bearing," and the added complexity (a second guarded key allocation, re-keying on every reseal) wasn't judged worth it for a first pass. Tracked here as the actual remaining follow-up, not silently dropped.
- **Verification actually performed**: full DUnitX suite (50 tests total, including the new `TSecureMemoryTests` fixture) passes on Win32. The Linux64 build compiles and links cleanly against the real Ubuntu 26.04 SDK/libc (`mmap`/`mprotect`/`mlock`/`munlock`/`madvise`/`getpagesize` all resolve). The non-elidable-zeroing claim was verified concretely, not assumed: `llvm-objdump` (bundled with Delphi 37.0, at `bin64\llvm-objdump.exe`) against the Release Linux64 build of `Holon.SecureMemory.o` shows `SecureZeroBytes` loading the `DoZero` function pointer from memory (`movq (%rip), %rax`) and calling through it (`callq *(%rax)`) rather than inlining or eliding the `FillChar`. What was **not** verified: actually running the Linux64 binary (no WSL/Linux host was available in the build environment - the build script only compiles/links) and deliberately triggering a guard-page fault under SEH on Windows (covered instead by the two canary-corruption tests, which exercise the "detected corruption" path without needing to catch a hardware exception from within DUnitX). Both remain open manual checks, consistent with how the plan itself flagged them as non-automatable.
- **The sample app** (`sample/Holon.CSRNG_sample.dpr`) now demonstrates `TSecureBytes.FromProvider` generating and printing a 32-byte key and reporting whether `mlock`/`VirtualLock` succeeded, serving as an additional real, compiled-and-run smoke test beyond the unit tests.
