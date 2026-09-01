# Design notes: Holon.ValidateRNG, a NIST SP 800-22 subset

**Status:** implemented, on the `validation` branch (`src/Holon.ValidateRNG.pas`, `tests/Holon.ValidateRNG.Tests.pas`). 7 of NIST SP 800-22 Rev 1a's 15 statistical tests are implemented; the other 8 are deliberately deferred - see below.

## Why NIST SP 800-22, and why not the other candidates

Four sources were considered: NIST SP 800-22, TestU01, Dieharder, and ISO/IEC 18031.

- **TestU01** (L'Ecuyer) and **Dieharder** are large C codebases (dozens of tests, thousands of lines) built around their own RNG-object abstractions. Porting either meaningfully to Delphi would be a multi-week project on its own, not a unit alongside an RNG library.
- **ISO/IEC 18031** is a paywalled standard with no public algorithm text to implement against. Its Annex tests are themselves closely aligned with the NIST battery, so it doesn't add independently implementable content.
- **NIST SP 800-22** is free (`nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-22r1a.pdf`), its test algorithms are precisely specified, and it's the standard most directly relevant to validating a CSPRNG library.

## Why 7 of the 15 tests, and which ones

The 7 implemented here - **Frequency (Monobit)**, **Frequency within a Block**, **Runs**, **Longest Run of Ones in a Block**, **Binary Matrix Rank**, **Cumulative Sums (Cusum)**, and **Approximate Entropy** - share exactly two special functions (the complementary error function `Erfc` and the regularized incomplete gamma function `Igamc`/`Igam`) and need no exotic machinery beyond that.

The other 8 - Discrete Fourier Transform/Spectral, Non-overlapping Template Matching, Overlapping Template Matching, Maurer's Universal, Serial, Linear Complexity, Random Excursions, and Random Excursions Variant - each need something substantially higher-risk: an FFT, a template-matching state machine, Berlekamp-Massey linear-complexity synthesis, or full random-walk cycle enumeration. A subtle bug is much easier to introduce in those, and much harder to catch without exact reference vectors. Shipping 7 correct, thoroughly-verified tests beats shipping 15 where some are quietly wrong - the same reasoning `Holon.SecureMemory` used to phase its own work (Phase 1-2 shipped, Phase 3 explicitly deferred).

`LongestRunOfOnes` further only supports NIST's smallest regime (M=8, K=3, valid for `128 <= BitCount < 6272`) rather than all three of NIST's size-dependent regimes (M=128 for larger inputs, M=10000 for very large ones) - the M=8 regime is the one with a directly reproducible worked example; the larger regimes would be implemented from the same published tables but without independent numeric verification, so they're left out rather than shipped unverified.

## Verification: real reference data, not approximation

The design plan's original intent was to hand-verify one or two worked examples from memory. It ended up going further, and that mattered: **three real bugs were found and fixed** by insisting on exact-match verification against real NIST reference data rather than "close enough."

**Getting the reference data.** A first attempt to read NIST's source PDF via WebFetch failed (couldn't extract text from the compressed PDF). Installed `markitdown[pdf]` (`pip install "markitdown[pdf]"`) and converted the downloaded PDF to text - this worked cleanly, and every worked example used below was extracted from that text, not from memory:

- Sections 2.1.8, 2.2.8, 2.3.8, 2.12.8, and 2.13.8 all reuse the same NIST-provided 100-bit example sequence, giving exact expected P-values for Frequency, Block Frequency, Runs, Approximate Entropy, and both directions of Cusum.
- Section 2.4.8 (Longest Run) gives its own 128-bit example.
- Section 2.5.8 (Binary Matrix Rank) uses "the first 100,000 binary digits in the expansion of e" as input - not embedded in the document text, but a well-known reference dataset (`data.e`) from NIST's own STS reference software, sourced from a public GitHub mirror (`terrillmoore/NIST-Statistical-Test-Suite`), independently confirmed to actually start with the correct binary digits of e before use, and embedded as packed hex in the test file.

**Three bugs this caught:**

1. **Approximate Entropy's degrees-of-freedom formula was wrong.** The initial implementation used `df = 2^(m-1)`, which for NIST's worked example (m=2) gave P=0.0623 against an expected 0.235301 - not a rounding difference, an order-of-magnitude-wrong result. The intermediate values (`ApEn(2)=0.665393`, `chi2=5.550792`) matched NIST exactly, isolating the bug to the final `Igamc` degrees-of-freedom parameter. Solved by testing both `df=2^(m-1)` and `df=2^m` numerically against the exact expected P-value; `df=2^m` reproduces it exactly.

2. **Longest Run of Ones used NIST's document-printed probabilities**, rounded to 4 places (0.2148/0.3672/0.2305/0.1875), which reproduced NIST's stated per-block classification counts exactly (`V=[4,9,3,0]`, matching the document's own numbers) but gave chi2=4.882605 against an expected 4.882457 - close, but not exact. Since M=8 is small enough to enumerate exhaustively (256 possible blocks), the true probabilities were computed directly: 55/256, 94/256, 59/256, 48/256. These reproduce chi2=4.882457463 - matching NIST's stated value to 7 significant figures, where the rounded constants did not.

3. **Binary Matrix Rank had the same class of issue.** NIST's document prints the full-rank probability as 0.2888 (with P(rank=M-1) = 0.5776, exactly double). The true asymptotic value is the well-known constant `∏(1 - 2^-i, i=1..∞) ≈ 0.28878809508660242` (OEIS A048651). Using that instead of the rounded value reproduces NIST's stated chi2=1.2619656 and P-value=0.532069 almost exactly (vs. chi2=1.2625804 with the rounded constants).

In all three cases, the *classification/counting* logic was already correct (verified by exact agreement with NIST's own intermediate integer counts); only the final numeric constants or formula needed correction. That distinction mattered for debugging - it ruled out bugs in bit extraction, block splitting, and pattern counting, and pointed straight at the actual issue.

**Special-function accuracy** was additionally verified against exact known constants independent of any NIST-specific text: `Erfc(0)=1`, `Erfc(1)≈0.15729920705028513`, `Φ(0)=0.5`, `Igamc(1,x)=e^-x` (a closed-form identity used both as a direct check and as the closed form for the Rank test's own P-value).

**Live-CSRNG integration** is covered by a smoke test that draws real bytes from `Holon.CSRNG.GetCSPRNGProvider`, runs the full 7-test suite, and asserts every result is either a valid P-value in `[0,1]` or a clearly-labeled skip (for tests whose minimum-length requirement the input doesn't meet). It deliberately does not assert `Passed=True` for every test - each test has a roughly 1% expected false-fail rate by design (α=0.01), so requiring universal pass on live random data would make the test suite flaky.

## What's out of scope

- The other 8 NIST SP 800-22 tests, as described above. A natural next slice for anyone picking this up: the Discrete Fourier Transform/Spectral test alone, since it needs "only" an FFT (no template matching, no random-walk cycle enumeration) and is one of the more commonly cited tests.
- The M=128 and M=10000 regimes of `LongestRunOfOnes`, for the reason given above.
- TestU01 and Dieharder ports.
- ISO/IEC 18031, for the reason given above.

## Files

- `src/Holon.ValidateRNG.pas` - `ERandomnessTestError`, `TRandomnessTestResult`, `TCusumMode`, `TRandomnessTests` (the 7 test class functions plus `RunSuite`), and the shared special functions `Erfc`, `Phi`, `Igam`, `Igamc`.
- `tests/Holon.ValidateRNG.Tests.pas` - special-function accuracy tests, one exact NIST-worked-example match per test, degenerate-sequence sanity checks (all-zeros/all-ones/alternating), minimum-length validation tests, and the live-CSRNG smoke test.
- `tests/CSPRNG.Tests.dpr`/`.dproj`, `sample/Holon.CSRNG_sample.dpr`/`CSPRNG_sample.dproj` - register the new units (same pattern used when `Holon.SecureMemory` was added).

## Verification

```
& "C:\Users\jim\git\DelphiStandards\DelphiBuildDPROJ.ps1" -ProjectFile "tests/CSPRNG.Tests.dproj" -Config Debug -Platform Win32 -DelphiVersion "37.0"
& "C:\Users\jim\git\DelphiStandards\DelphiBuildDPROJ.ps1" -ProjectFile "tests/CSPRNG.Tests.dproj" -Config Debug -Platform Linux64 -DelphiVersion "37.0"
```

Both platforms build clean. `tests/Win32/Debug/Holon.CSRNG.Tests.exe --exitbehavior:Continue` passes 71/71 (up from 50/50 before this change), including all 7 exact NIST worked-example matches. The Win32 sample (`sample/Win32/Debug/Holon.CSRNG_sample.exe`) demonstrates `TRandomnessTests.RunSuite` against live CSRNG output.
