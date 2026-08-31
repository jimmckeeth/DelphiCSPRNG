# [DelphiCSPRNG](https://github.com/jimmckeeth/DelphiCSPRNG)
_A cross-platform Cryptographically-Secure Pseudo-Random Number Generator for Delphi_

I wanted an easy to use cross-platform random number generator that was more reliable than the built in Random. It is modular so you can just include the parts you want. Makes use of the platform secure random provider for each platform, with a common provider interface. I've only tested it on Win32, Win64, Android64, and Linux64. 

There are some basic tests and a sample app. Open to feedback, [issues](https://github.com/jimmckeeth/DelphiCSPRNG/issue) reports, and [pull requests](https://github.com/jimmckeeth/DelphiCSPRNG/fork). Especially if you want to test it on Apple hardware.

**Disclaimer**: _Make sure you understand any code before using it for anything important._ Just because I am calling this "Cryptographically-Secure" doesn't necessarily mean it is secure or suitable for cryptography.  

## Basic usage

```Delphi
uses CSPRNG, CSPRNG.Interfaces;

///
var rng: ICSPRNGProvider :=  GetCSPRNGProvider;
Writeln(rng.GetFloat);
Writeln(rng.GetUInt64);
Writeln(rng.GetBase64); 
```

## The provider interface

```Delphi
type 
  ICSPRNGProvider = interface
    // Generates a specified number of cryptographically secure random bytes.
    function GetBytes(const Count: Integer): TBytes;

    // Generates a cryptographically secure random unsigned 32-bit integer.
    function GetUInt32(const max: UInt32 = High(UInt32)): UInt32;

    // Generates a cryptographically secure random signed 32-bit integer.
    function GetInt32(const max: Int32 = High(Int32)): Int32;

    // Generates a cryptographically secure random signed 64-bit integer.
    function GetInt64(const max: Int64 = High(Int64)): Int64;

    // Generates a cryptographically secure random unsigned 64-bit integer.
    function GetUInt64(const max: UInt64 = High(UInt64)): UInt64;

    // Generates a cryptographically secure random float between 0 and 1
    function GetFloat: Double;

    // Generates a BASE64 encoded random string
    function GetBase64(const len: Integer = 1024): String;
  end;
```

Most of the functionality comes from the base implementation, with the platform specific implementation providing the **`GetBytes`** function. Every public type and method also carries an XML doc comment (`///`) in the source, so signatures, parameter meaning, and caveats show up in Code Insight/tooltips in the IDE, not just in this README.

All of these methods raise `ECSPRNGError` (declared in `CSPRNG.Interfaces.pas`, descends from `Exception`) rather than a bare `Exception` - both for a negative `Count`/`len`/`max` argument, and if the underlying platform API fails to produce random data. Catch `ECSPRNGError` specifically to distinguish CSPRNG failures from unrelated exceptions.

## How it works

`GetCSPRNGProvider` (in `CSPRNG.pas`) picks a platform-specific `ICSPRNGProvider` implementation at **compile time**, using an `{$IF}/{$ELSEIF}` chain over conditional defines (`MSWINDOWS`, `MACOS`, `LINUX`, `POSIX`) — there's no runtime platform detection. The branches are mutually exclusive and ordered from most to least specific: Delphi defines `POSIX` for macOS, iOS, Linux, *and* Android, and `LINUX` for Linux64 in addition to `POSIX`, so `MACOS` and then `LINUX` are checked before the generic `POSIX` fallback (which is what Android actually falls through to) to make sure each platform gets its most specific provider.

`CSPRNG.Provider.Linux.pas`'s `TCSPRNGProviderLinux` descends from `CSPRNG.Provider.Posix.pas`'s `TCSPRNGProviderPosix` rather than being folded into the same unit with an inner `{$IFDEF LINUX}`: Linux and Android share the same `/dev/urandom` fallback behavior, but Linux additionally prefers `getrandom(2)`. Making that a subclass override (falling back to `inherited GetBytes` for the shared `/dev/urandom` path) keeps the Android/generic-POSIX unit free of any Linux-specific code, rather than mixing both platforms' logic into one class body.

`TCSPRNGProviderBase` (`CSPRNG.Provider.Base.pas`) implements every method in `ICSPRNGProvider` except `GetBytes`, which is `abstract`. Each platform unit only has to implement `GetBytes`; everything else — `GetUInt32`, `GetInt32`, `GetUInt64`, `GetInt64`, `GetFloat`, `GetBase64` — is built on top of it:

- `GetUInt32`/`GetInt32` request 4 random bytes, interpret them as a little-endian `UInt32` (`ToUInt32`), then reduce that into `[0, max]` with `value mod (max + 1)`.
- `GetUInt64`/`GetInt64` request 8 random bytes, interpret them as a little-endian `UInt64` (`ToUInt64`). `GetInt64` reduces with `value mod (max + 1)`; `GetUInt64` uses rejection sampling (see below) to stay unbiased and in-range.
- `GetFloat` requests 8 random bytes and divides the `UInt64` value by `High(UInt64)` to scale it into `[0, 1)`.
- `GetBase64` requests `len` random bytes (this is a byte count, not the length of the resulting string) and Base64-encodes them.

## Platform providers / APIs used

| Platform | Unit | API used | Notes |
|---|---|---|---|
| Windows | `CSPRNG.Provider.Windows.pas` | `BCryptGenRandom` (`bcrypt.dll`, Windows CNG) with the `BCRYPT_USE_SYSTEM_PREFERRED_RNG` flag | No algorithm provider handle to manage - `hAlgorithm` is `NULL` and Windows itself picks (and can change, across OS updates) its preferred RNG implementation, which is Microsoft's documented recommendation for callers with no specific reason to pin an algorithm. This is Microsoft's current recommended CSPRNG API, superseding the older, deprecated `CryptGenRandom`/`RtlGenRandom`. |
| Linux | `CSPRNG.Provider.Linux.pas` (`TCSPRNGProviderLinux`, descends from `TCSPRNGProviderPosix`) | `getrandom(2)` (via `libc.so.6`), falling back to the inherited `/dev/urandom` implementation | `getrandom()` (Linux kernel 3.17+ / glibc 2.25+) is preferred over opening `/dev/urandom` directly: it blocks until the kernel's CSPRNG is actually seeded (avoiding a real, historically-exploited early-boot weakness class) and doesn't depend on `/dev` being mounted, so it keeps working in minimal containers/chroots. Falls back to `/dev/urandom` only if the syscall is unavailable (pre-3.17 kernels) or fails. |
| Android | `CSPRNG.Provider.Posix.pas` (`TCSPRNGProviderPosix`) | Reads `/dev/urandom` via `TFileStream` | Shared with Linux only in the sense that `TCSPRNGProviderLinux` descends from this class for its fallback path; Android itself uses this base class directly, with no Linux-specific code compiled in (`{$IFDEF LINUX}` excludes it). Android sticks to `/dev/urandom` rather than `getrandom()`: Android's libc wrapper for the syscall only exists from API level 28 onward, while the kernel entropy pool is reliably seeded by `init`/zygote before any app process runs (unlike a generic early-boot Linux scenario), so `/dev/urandom` is both simpler and Android's own recommended approach for native code. |
| macOS and iOS | `CSPRNG.Provider.Apple.pas` (`TCSPRNGProviderApple`, shared) | `SecRandomCopyBytes` (Apple `Security` framework) | Both platforms share this unit because Delphi defines `MACOS` for both. This is Apple's documented, recommended CSPRNG API — preferred over reading `/dev/urandom` directly because it does no file I/O, can't be blocked by App Sandbox file-system entitlements, and never blocks. |

## Assumptions and caveats

- **Providers always return exactly the requested number of bytes, in one call.** The base class's integer/float helpers never check `Length()` on what `GetBytes` returns — a provider that raises on failure but otherwise returns a short read isn't handled.
- **Byte order is little-endian throughout.** `ToUInt32`/`ToInt32`/`ToInt64`/`ToUInt64` explicitly assemble bytes in little-endian order, and `GetFloat` reuses `ToUInt64` rather than doing its own raw pointer cast, so the whole class is consistent. This only matters if Delphi ever targets a big-endian platform, which none of its current platforms are.
- **`GetInt32`/`GetInt64` never actually return negative numbers.** Despite being documented as "signed" values, both only ever produce a value in `[0, max]`; a negative `max` raises an exception instead of expanding the range.
- **Range reduction uses `value mod (max + 1)`** for `GetUInt32`/`GetInt32`/`GetInt64`, which has the standard small modulo bias toward lower values whenever `max + 1` doesn't evenly divide the sampled domain (2^32 or 2^64). `GetUInt64` instead uses rejection sampling (draws are retried whenever they'd fall in the leftover, non-uniform region at the top of the range), which is both unbiased and guaranteed to stay within `[0, max]`.
- **Windows**: assumes `bcrypt.dll` is present (it has been since Windows Vista) and exports `BCryptGenRandom`.
- **Linux**: assumes either the `getrandom` symbol is resolvable in `libc.so.6` at load time (true for any glibc from the last decade-plus) or `/dev/urandom` exists and is world-readable.
- **Android/macOS/iOS**: Android assumes `/dev/urandom` exists and is world-readable, which holds on every real device. macOS/iOS assume the Security framework's `SecRandomCopyBytes` is available, which it has been since macOS 10.7/iOS 2.0.
- **PadBytes pads/truncates on the high (most-significant) side.** `ToUInt32`/`ToUInt64` only ever call it with byte arrays that already match the target width exactly (4 or 8 bytes), so in normal use `PadBytes` never actually pads or truncates anything — it's effectively a no-op guard, not something exercised on the hot path.

### Hardcoded algorithm/provider choices

None of these are configurable or overridable by a caller - each platform unit hardcodes exactly one underlying RNG source, chosen at compile time as described above:

- **Windows**: hardcoded to CNG's system-preferred RNG, via the `BCRYPT_USE_SYSTEM_PREFERRED_RNG` flag (`hAlgorithm = NULL`). There's no way to request a specific named algorithm (e.g. pinning to `'RNG'`/`BCRYPT_RNG_ALGORITHM` specifically, or to `BCRYPT_RNG_FIPS186_DSA_ALGORITHM`) - Windows' own choice of "preferred" implementation is trusted as-is.
- **Linux**: hardcoded to the `getrandom` symbol exported by `libc.so.6`, called with `flags = 0` (i.e. blocking, non-`GRND_RANDOM`, using `/dev/urandom`'s underlying CSPRNG rather than the legacy blocking `/dev/random` pool), falling back to reading `/dev/urandom` directly by path.
- **Android**: hardcoded to reading `/dev/urandom` by path; never uses `getrandom()` even where the OS supports it (API 28+).
- **macOS/iOS**: hardcoded to `SecRandomCopyBytes` with `kSecRandomDefault`; never uses `/dev/urandom`, `arc4random_buf`, or any other Apple RNG entry point.

If a future consumer needs a different source (e.g. a hardware RNG, a specific FIPS-validated algorithm, or a deterministic RNG for testing), that would require either a new `ICSPRNGProvider` implementation entirely, or extending the provider construction path (`GetCSPRNGProvider`) to accept a selector - today it always returns the one hardcoded choice for the current platform.

## Fixed since the initial version

A code review turned up several real bugs, since fixed:

- **`GetUInt32`/`GetInt32` returned `0` every time `max + 1` was a power of two — including their default, no-argument call.** They requested 4 random bytes and ran them through `ToUInt64` (an 8-byte conversion), so `PadBytes` zero-padded the missing 4 bytes at the *start*; combined with the little-endian interpretation, the real random data ended up in the *high* 32 bits, leaving the low bits - the only ones a power-of-two modulus looks at - always zero. Fixed by converting through `ToUInt32` (no padding needed) instead. This was caught by actually running the sample app, not by static review or the existing unit tests, since none of the test cases happened to use a power-of-two range.
- **`GetUInt64` could return a value above `max`.** Its old division-based range reduction didn't discard the leftover, non-uniform region at the top of the `UInt64` range (e.g. `GetUInt64(1)` could return `2`). Replaced with rejection sampling, which is both unbiased and provably bounded.
- **macOS and iOS did not compile.** `CSPRNG.pas` dispatched on `{$IFDEF MACOS}` (which Delphi defines for both macOS and iOS), but the macOS provider class was only compiled in under `{$IFDEF OSX}` (macOS only), so the type didn't exist on iOS; and because `POSIX` is *also* defined for both platforms, the old three independent `{$IFDEF}` blocks in `CSPRNG.pas` would each compile in, producing a duplicate `GetCSPRNGProvider` declaration. Fixed by widening the macOS provider's guard to `MACOS` (so it now covers iOS directly, using the same `SecRandomCopyBytes` API the old, separate, never-wired-up iOS provider used) and rewriting the dispatch in `CSPRNG.pas` as a single mutually-exclusive `{$IF}/{$ELSEIF}` chain. The old standalone `CSPRNG.Provider.iOS.pas` was removed as fully redundant.
- **The macOS/Posix providers crashed on `GetBytes(0)`**, indexing `Result[0]` on a zero-length dynamic array. Fixed with an early-return guard.
- **Windows' `SeedFromEntropySource` was a no-op** (`BCryptGenRandom(FHandle, nil, 0, 0)`) called unconditionally from the constructor, implying it did something it didn't. Removed — CNG's `'RNG'` algorithm is already continuously self-seeded from the system entropy pool.
- Removed the unused `SeedFromBytes`/`SeedFromEntropySource` methods from the macOS/iOS provider (they weren't part of `ICSPRNGProvider`, so nothing could call them through the interface anyway; they'd also been declared `override` on methods that didn't exist as `virtual` anywhere in the ancestor chain, which was its own compile error), and the corresponding empty, assertion-free test stubs.
- Removed several unused imports (`Posix.Base`, `Posix.Unistd`, `Posix.Fcntl`, `Posix.Errno`) and a dead, unreachable "negative value adjustment" branch in `GetInt32`/`GetInt64` left over from before `max` was constrained non-negative.
- **Windows was opening an explicit `'RNG'` algorithm provider handle and passing `dwFlags = 0` to `BCryptGenRandom`**, rather than using the simpler, documented-as-recommended `BCRYPT_USE_SYSTEM_PREFERRED_RNG` pattern (`hAlgorithm = NULL`). Switched to the latter, which also removed the need for a constructor/destructor pair managing that handle's lifetime.
- **Linux and Android were sharing a single `GetBytes` implementation with an inner `{$IFDEF LINUX}` branch for the `getrandom()` fast path.** Split into `TCSPRNGProviderPosix` (the plain `/dev/urandom` implementation, used as-is by Android) and `TCSPRNGProviderLinux` (a `CSPRNG.Provider.Linux.pas` subclass that tries `getrandom()` first, then calls `inherited GetBytes` for the `/dev/urandom` fallback) so the Android code path carries no Linux-specific logic.
- **Every provider raised the generic `Exception` class.** Added `ECSPRNGError` (in `CSPRNG.Interfaces.pas`) and switched every `raise` in the library to it, so callers can catch CSPRNG-specific failures distinctly.
- **`GetBytes` didn't validate `Count`; `GetBase64` didn't validate `len`.** A negative value fell through to `SetLength` and surfaced as an opaque RTL range-check error rather than a clear message. Every provider's `GetBytes` now raises `ECSPRNGError` up front for `Count < 0` (which `GetBase64`'s `len` also flows through).
- **`CSPRNG.Provider.MacOS64.pas`/`TCSPRNGProviderMacOS64` was misleadingly named** after the macOS provider was widened to cover iOS as well (see above). Renamed to `CSPRNG.Provider.Apple.pas`/`TCSPRNGProviderApple`.
- **`GetUInt64`'s rejection-sampling logic had no direct test coverage**, only the black-box "run it 1000 times and check the bounds" style tests already in the suite - which can't reliably catch a bug like the original one, since it only manifests for a handful of exact `UInt64` values out of 2^64 (astronomically unlikely to hit by chance in a test run). Extracted the single-draw accept/reject/reduce step into a pure, directly-testable `class function TryReduceUInt64(const Value, max: UInt64; out Reduced: UInt64): Boolean`, and added tests that feed it the exact `Value` that used to overflow (e.g. `TryReduceUInt64(High(UInt64), 5, Reduced)`, which the old code reduced to `6`) and assert it's now correctly rejected. Also added tests asserting `GetUInt32`/`GetInt32`'s default (power-of-two) range doesn't return the same value 30 times in a row, as a regression guard for the other fixed bug.

## Known limitations

- Only Win32, Win64, Android64, and Linux64 have actually been built and run. macOS/iOS now compile against the same logic Windows/Linux/Android use and call Apple's documented API, but haven't been verified on real Apple hardware/toolchain — feedback and PRs especially welcome there.
