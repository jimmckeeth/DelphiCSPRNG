unit Holon.ValidateRNG;

{
  A curated subset of the NIST SP 800-22 Rev 1a statistical test suite ("A
  Statistical Test Suite for Random and Pseudorandom Number Generators for
  Cryptographic Applications") for validating that a bit sequence - typically
  drawn from an ICSPRNGProvider - is statistically indistinguishable from random.

  This implements 7 of the 15 tests in SP 800-22: Frequency (Monobit), Frequency
  within a Block, Runs, Longest Run of Ones in a Block, Binary Matrix Rank,
  Cumulative Sums (Cusum), and Approximate Entropy. These share only two special
  functions (the complementary error function and the regularized incomplete
  gamma function) and don't need an FFT, Berlekamp-Massey linear-complexity
  synthesis, or full random-walk cycle enumeration - unlike the other 8 tests
  (Discrete Fourier Transform/Spectral, Non-overlapping and Overlapping Template
  Matching, Maurer's Universal, Serial, Linear Complexity, Random Excursions, and
  Random Excursions Variant), which are deliberately not implemented here. See
  docs/rng-validate-plan.md for the full 15-test landscape and why these 7 came
  first.

  Every formula here was cross-checked against NIST's own worked examples in the
  source document (extracted to text and verified against real computed output,
  not transcribed from memory) - see tests/Holon.ValidateRNG.Tests.pas.

  As with the rest of this library: passing this suite indicates a sequence is
  statistically well-behaved, not that it is cryptographically secure - these are
  the same tests a well-built PRNG (not just a CSPRNG) can pass. Statistical
  quality and unpredictability are different properties.
}

interface

uses
  System.SysUtils,
  System.Math,
  Holon.CSRNG.Interfaces;

type
  /// <summary>
  /// Raised for Holon.ValidateRNG-specific errors, most commonly an input sequence
  /// shorter than a given test's minimum recommended length (in which case the
  /// computed P-value would not be meaningful). Descends from ECSPRNGError since
  /// the provider-based RunSuite overload draws its input from an ICSPRNGProvider.
  /// </summary>
  ERandomnessTestError = class(ECSPRNGError);

  /// <summary>
  /// The outcome of a single statistical test: its name, the computed P-value,
  /// whether that P-value met the significance threshold (Passed), and a short
  /// human-readable Detail string with the key intermediate statistic(s).
  /// </summary>
  TRandomnessTestResult = record
    TestName: string;
    PValue: Double;
    Passed: Boolean;
    Detail: string;
  end;

  /// <summary>Forward (mode 0) or reverse (mode 1) processing order for the Cumulative Sums test.</summary>
  TCusumMode = (cmForward, cmReverse);

  /// <summary>
  /// Static class implementing the 7 NIST SP 800-22 tests described in this unit's
  /// header comment, plus a convenience RunSuite that runs all of them.
  /// </summary>
  TRandomnessTests = class
  private
    // Runs TestFunc and, if it raises ERandomnessTestError (an input too short
    // for that particular test), converts that into a "skipped" result instead
    // of letting the exception propagate out of RunSuite.
    class function RunOne(const Name: string;
      const TestFunc: TFunc<TRandomnessTestResult>): TRandomnessTestResult; static;
  public
    /// <summary>NIST's standard significance level: a P-value below this indicates non-randomness.</summary>
    const DefaultAlpha = 0.01;

    /// <summary>
    /// The Frequency (Monobit) Test: checks that the proportion of ones and zeros
    /// is close to 1/2, the most basic randomness check. Requires BitCount >= 100.
    /// </summary>
    class function Frequency(const Bits: TBytes; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Frequency Test within a Block: like Frequency, but checks the
    /// proportion of ones within each of N non-overlapping M-bit blocks, so it can
    /// catch local imbalances a whole-sequence average would hide. Requires
    /// BitCount >= 100; NIST recommends BlockSize >= 20 and BlockSize > 0.01 *
    /// BitCount for real use (its own worked example uses a smaller BlockSize=10
    /// purely for illustration, which this does not prohibit).
    /// </summary>
    class function BlockFrequency(const Bits: TBytes; BitCount: Integer;
      BlockSize: Integer = 128; Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Runs Test: checks that the number of uninterrupted runs of identical
    /// bits is neither too high (oscillating faster than random) nor too low
    /// (too clustered). If the input's overall proportion of ones is too far from
    /// 1/2 for the test to be meaningful, NIST defines the result as an automatic
    /// P-value of 0 rather than skipping the test - this follows that convention.
    /// Requires BitCount >= 100.
    /// </summary>
    class function Runs(const Bits: TBytes; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Test for the Longest Run of Ones in a Block: checks that the longest
    /// run of ones within each of several 8-bit blocks is distributed as expected.
    /// This implementation only supports NIST's smallest regime (M=8, K=3, valid
    /// for 128 &lt;= BitCount &lt; 6272) - the M=128 and M=10000 regimes for larger
    /// inputs are not implemented; see docs/rng-validate-plan.md.
    /// </summary>
    class function LongestRunOfOnes(const Bits: TBytes; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Binary Matrix Rank Test: splits the input into 32x32-bit matrices and
    /// checks that their ranks over GF(2) are distributed as expected for random
    /// matrices - catches linear dependencies among the bits. Requires
    /// BitCount >= 38*32*32 = 38912 (NIST's minimum for at least 38 matrices).
    /// </summary>
    class function BinaryMatrixRank(const Bits: TBytes; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Cumulative Sums (Cusum) Test: treats the bits as a +1/-1 random walk
    /// and checks that its maximum excursion from zero is neither too large nor
    /// too small. Requires BitCount >= 100.
    /// </summary>
    class function CumulativeSums(const Bits: TBytes; BitCount: Integer;
      Mode: TCusumMode = cmForward; Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// The Approximate Entropy Test: compares the frequency of overlapping m-bit
    /// and (m+1)-bit patterns to the frequency expected for a random sequence.
    /// Requires M >= 1 and BitCount >= 1. NIST recommends M &lt; log2(BitCount) - 5
    /// for good statistical power, but this is advisory, not enforced - NIST's
    /// own worked example (M=2, BitCount=100) does not meet it either.
    /// </summary>
    class function ApproximateEntropy(const Bits: TBytes; BitCount: Integer;
      M: Integer = 2; Alpha: Double = DefaultAlpha): TRandomnessTestResult; static;

    /// <summary>
    /// Runs all 7 tests above against Bits/BitCount with default parameters
    /// (BlockFrequency's BlockSize=128, Cusum forward only, ApproximateEntropy's
    /// M=2). If a given test's minimum-length requirement isn't met, that test's
    /// result has Passed=False, PValue=-1, and a Detail explaining it was skipped
    /// - RunSuite itself never raises for a too-short input, so a caller always
    /// gets back a result for every implemented test.
    /// </summary>
    class function RunSuite(const Bits: TBytes; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TArray<TRandomnessTestResult>; overload; static;

    /// <summary>
    /// Draws Ceil(BitCount / 8) bytes from AProvider and runs the same suite as
    /// the TBytes overload - reuses Holon.CSRNG's existing entropy path rather
    /// than introducing a second one.
    /// </summary>
    class function RunSuite(const AProvider: ICSPRNGProvider; BitCount: Integer;
      Alpha: Double = DefaultAlpha): TArray<TRandomnessTestResult>; overload; static;
  end;

/// <summary>
/// The complementary error function, erfc(x) = 1 - erf(x), computed as
/// Igamc(0.5, x^2) for x >= 0 (a standard identity), extended to negative x via
/// erfc(-x) = 2 - erfc(x).
/// </summary>
function Erfc(const X: Double): Double;

/// <summary>The standard normal (Gaussian) cumulative distribution function.</summary>
function Phi(const X: Double): Double;

/// <summary>The regularized lower incomplete gamma function P(a, x).</summary>
function Igam(const A, X: Double): Double;

/// <summary>The regularized upper incomplete gamma function Q(a, x) = 1 - P(a, x).</summary>
function Igamc(const A, X: Double): Double;

implementation

const
  MachEp = 1.11022302462515654042E-16; // double-precision machine epsilon
  MaxLog = 709.782712893384;           // ln(MaxDouble), beyond which Exp() would overflow
  Big = 4.503599627370496E15;          // 2^52, used to rescale Igamc's continued fraction
  BigInv = 2.22044604925031308085E-16; // 1 / Big

{ Bit access }

function GetBit(const Bits: TBytes; Index: Integer): Integer; inline;
begin
  Result := (Bits[Index shr 3] shr (7 - (Index and 7))) and 1;
end;

{ Special functions }

// Lanczos approximation for ln(Gamma(x)), g=7, 9 terms - the standard,
// widely-reproduced public formulation (see e.g. the Wikipedia "Lanczos
// approximation" article), accurate to about 15 significant digits for x > 0.
function LnGamma(X: Double): Double;
const
  G = 7;
  Coef: array[0..8] of Double = (
    0.99999999999980993, 676.5203681218851, -1259.1392167224028,
    771.32342877765313, -176.61502916214059, 12.507343278686905,
    -0.13857109526572012, 9.9843695780195716E-6, 1.5056327351493116E-7);
var
  I: Integer;
  A, T: Double;
  XX: Double;
begin
  if X < 0.5 then
    // Reflection formula - not exercised by any call in this unit (every `a`
    // passed to Igam/Igamc here is >= 0.5), but included for robustness.
    Result := Ln(Pi / Sin(Pi * X)) - LnGamma(1 - X)
  else
  begin
    XX := X - 1;
    A := Coef[0];
    T := XX + G + 0.5;
    for I := 1 to 8 do
      A := A + Coef[I] / (XX + I);
    Result := 0.5 * Ln(2 * Pi) + (XX + 0.5) * Ln(T) - T + Ln(A);
  end;
end;

function Igam(const A, X: Double): Double;
var
  Ax, R, C, Ans: Double;
begin
  if (X <= 0) or (A <= 0) then
    Exit(0);
  if (X > 1) and (X > A) then
    Exit(1 - Igamc(A, X));

  Ax := A * Ln(X) - X - LnGamma(A);
  if Ax < -MaxLog then
    Exit(0);
  Ax := Exp(Ax);

  R := A;
  C := 1;
  Ans := 1;
  repeat
    R := R + 1;
    C := C * X / R;
    Ans := Ans + C;
  until (C / Ans) <= MachEp;

  Result := Ans * Ax / A;
end;

function Igamc(const A, X: Double): Double;
var
  Ax, Y, Z, C, T, R, Ans: Double;
  Pkm2, Qkm2, Pkm1, Qkm1, Pk, Qk, Yc: Double;
begin
  if (X <= 0) or (A <= 0) then
    Exit(1);
  if (X < 1) or (X < A) then
    Exit(1 - Igam(A, X));

  Ax := A * Ln(X) - X - LnGamma(A);
  if Ax < -MaxLog then
    Exit(0);
  Ax := Exp(Ax);

  Y := 1 - A;
  Z := X + Y + 1;
  C := 0;
  Pkm2 := 1;
  Qkm2 := X;
  Pkm1 := X + 1;
  Qkm1 := Z * X;
  Ans := Pkm1 / Qkm1;

  repeat
    C := C + 1;
    Y := Y + 1;
    Z := Z + 2;
    Yc := Y * C;
    Pk := Pkm1 * Z - Pkm2 * Yc;
    Qk := Qkm1 * Z - Qkm2 * Yc;
    if Qk <> 0 then
    begin
      R := Pk / Qk;
      T := Abs((Ans - R) / R);
      Ans := R;
    end
    else
      T := 1;
    Pkm2 := Pkm1;
    Pkm1 := Pk;
    Qkm2 := Qkm1;
    Qkm1 := Qk;
    if Abs(Pk) > Big then
    begin
      Pkm2 := Pkm2 * BigInv;
      Pkm1 := Pkm1 * BigInv;
      Qkm2 := Qkm2 * BigInv;
      Qkm1 := Qkm1 * BigInv;
    end;
  until T <= MachEp;

  Result := Ans * Ax;
end;

function Erfc(const X: Double): Double;
begin
  if X >= 0 then
    Result := Igamc(0.5, X * X)
  else
    Result := 2.0 - Igamc(0.5, X * X);
end;

function Phi(const X: Double): Double;
begin
  Result := 0.5 * Erfc(-X / Sqrt(2));
end;

{ TRandomnessTests }

class function TRandomnessTests.Frequency(const Bits: TBytes; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TRandomnessTestResult;
var
  I: Integer;
  S: Int64;
  SObs: Double;
begin
  if BitCount < 100 then
    raise ERandomnessTestError.Create('Frequency test requires at least 100 bits');

  S := 0;
  for I := 0 to BitCount - 1 do
    if GetBit(Bits, I) = 1 then Inc(S) else Dec(S);

  SObs := Abs(S) / Sqrt(BitCount);

  Result.TestName := 'Frequency (Monobit)';
  Result.PValue := Erfc(SObs / Sqrt(2));
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('S=%d, s_obs=%.6f', [S, SObs]);
end;

class function TRandomnessTests.BlockFrequency(const Bits: TBytes; BitCount: Integer;
  BlockSize: Integer = 128; Alpha: Double = DefaultAlpha): TRandomnessTestResult;
var
  N, I, J, Ones: Integer;
  PiI, ChiSq: Double;
begin
  if BitCount < 100 then
    raise ERandomnessTestError.Create('Block Frequency test requires at least 100 bits');
  if BlockSize <= 0 then
    raise ERandomnessTestError.Create('BlockSize must be positive');

  N := BitCount div BlockSize;
  if N < 1 then
    raise ERandomnessTestError.CreateFmt('BitCount too small for BlockSize %d', [BlockSize]);

  ChiSq := 0;
  for I := 0 to N - 1 do
  begin
    Ones := 0;
    for J := 0 to BlockSize - 1 do
      if GetBit(Bits, I * BlockSize + J) = 1 then Inc(Ones);
    PiI := Ones / BlockSize;
    ChiSq := ChiSq + Sqr(PiI - 0.5);
  end;
  ChiSq := ChiSq * 4 * BlockSize;

  Result.TestName := 'Frequency within a Block';
  Result.PValue := Igamc(N / 2, ChiSq / 2);
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('N=%d, chi2=%.6f', [N, ChiSq]);
end;

class function TRandomnessTests.Runs(const Bits: TBytes; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TRandomnessTestResult;
var
  I, Ones, Vn: Integer;
  PiHat: Double;
begin
  if BitCount < 100 then
    raise ERandomnessTestError.Create('Runs test requires at least 100 bits');

  Result.TestName := 'Runs';

  Ones := 0;
  for I := 0 to BitCount - 1 do
    if GetBit(Bits, I) = 1 then Inc(Ones);
  PiHat := Ones / BitCount;

  // NIST defines the test as an automatic non-random result (P-value 0) if the
  // proportion of ones is too far from 1/2 for the run count to be meaningful,
  // rather than the test being inapplicable/undefined.
  if Abs(PiHat - 0.5) >= 2 / Sqrt(BitCount) then
  begin
    Result.PValue := 0.0;
    Result.Passed := False;
    Result.Detail := Format('pi=%.6f too far from 0.5 for this test to apply', [PiHat]);
    Exit;
  end;

  Vn := 1;
  for I := 0 to BitCount - 2 do
    if GetBit(Bits, I) <> GetBit(Bits, I + 1) then Inc(Vn);

  Result.PValue := Erfc(Abs(Vn - 2 * BitCount * PiHat * (1 - PiHat)) /
    (2 * Sqrt(2 * BitCount) * PiHat * (1 - PiHat)));
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('pi=%.6f, V_n=%d', [PiHat, Vn]);
end;

class function TRandomnessTests.LongestRunOfOnes(const Bits: TBytes; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TRandomnessTestResult;
const
  M = 8;
  K = 3;
  // Exact category probabilities for the longest run of ones in an 8-bit
  // block, computed by exhaustively classifying all 256 possible blocks
  // (55, 94, 59, 48 out of 256 respectively) rather than using NIST's
  // document text, which prints these rounded to 4 places (0.2148/0.3672/
  // 0.2305/0.1875); the exact fractions below reproduce the worked example's
  // stated chi2=4.882457 (section 2.4.8) to 7 significant figures, where the
  // rounded values do not.
  PiCat: array[0..3] of Double = (55 / 256, 94 / 256, 59 / 256, 48 / 256);
var
  N, I, J, Run, MaxRun, Cat: Integer;
  V: array[0..3] of Integer;
  ChiSq: Double;
begin
  // Only NIST's smallest regime (M=8, K=3) is implemented - see this method's
  // XML doc comment and docs/rng-validate-plan.md.
  if (BitCount < 128) or (BitCount >= 6272) then
    raise ERandomnessTestError.Create(
      'LongestRunOfOnes currently supports 128 <= BitCount < 6272 only (the M=8 regime)');

  N := BitCount div M;
  FillChar(V, SizeOf(V), 0);

  for I := 0 to N - 1 do
  begin
    Run := 0;
    MaxRun := 0;
    for J := 0 to M - 1 do
    begin
      if GetBit(Bits, I * M + J) = 1 then
      begin
        Inc(Run);
        if Run > MaxRun then MaxRun := Run;
      end
      else
        Run := 0;
    end;
    if MaxRun <= 1 then Cat := 0
    else if MaxRun = 2 then Cat := 1
    else if MaxRun = 3 then Cat := 2
    else Cat := 3;
    Inc(V[Cat]);
  end;

  ChiSq := 0;
  for I := 0 to 3 do
    ChiSq := ChiSq + Sqr(V[I] - N * PiCat[I]) / (N * PiCat[I]);

  Result.TestName := 'Longest Run of Ones in a Block';
  Result.PValue := Igamc(K / 2, ChiSq / 2);
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('N=%d, chi2=%.6f, V=[%d,%d,%d,%d]', [N, ChiSq, V[0], V[1], V[2], V[3]]);
end;

// Gaussian elimination over GF(2). Rows holds NumRows values, each with its
// NumCols-bit row packed into the low NumCols bits (MSB-first, matching the bit
// order the matrix was built with). Mutates Rows in place; returns the rank.
function ComputeRankGF2(var Rows: TArray<UInt32>; NumRows, NumCols: Integer): Integer;
var
  Col, Row, PivotRow, Rank: Integer;
  Mask, Tmp: UInt32;
begin
  Rank := 0;
  for Col := 0 to NumCols - 1 do
  begin
    Mask := UInt32(1) shl (NumCols - 1 - Col);
    PivotRow := -1;
    for Row := Rank to NumRows - 1 do
      if (Rows[Row] and Mask) <> 0 then
      begin
        PivotRow := Row;
        Break;
      end;
    if PivotRow = -1 then
      Continue;

    if PivotRow <> Rank then
    begin
      Tmp := Rows[Rank];
      Rows[Rank] := Rows[PivotRow];
      Rows[PivotRow] := Tmp;
    end;

    for Row := 0 to NumRows - 1 do
      if (Row <> Rank) and ((Rows[Row] and Mask) <> 0) then
        Rows[Row] := Rows[Row] xor Rows[Rank];

    Inc(Rank);
    if Rank = NumRows then Break;
  end;
  Result := Rank;
end;

class function TRandomnessTests.BinaryMatrixRank(const Bits: TBytes; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TRandomnessTestResult;
const
  M = 32;
  Q = 32;
  // The full-rank probability for a random MxM GF(2) matrix converges to
  // prod(1 - 2^-i, i=1..infinity) =~ 0.28878809508660242... (a well-known
  // constant; see e.g. OEIS A048651) as M grows; P(rank=M-1) is asymptotically
  // exactly twice that. NIST's document prints these rounded to 4 places
  // (0.2888/0.5776/0.1336), but its own reference software evidently uses
  // the fuller precision below - confirmed empirically: using the rounded
  // 4-place values reproduces the worked example's chi2 as 1.2625804, but
  // these values reproduce NIST's stated 1.2619656 (and P-value 0.532069)
  // to 7 significant figures.
  ProbM = 0.2887880951;
  ProbM1 = 0.5775761902;
  ProbRest = 1 - ProbM - ProbM1;
var
  N, B, R, C, BitIdx, Rank, FM, FM1: Integer;
  Rows: TArray<UInt32>;
  ChiSq: Double;
begin
  if BitCount < 38 * M * Q then
    raise ERandomnessTestError.CreateFmt('BinaryMatrixRank requires at least %d bits', [38 * M * Q]);

  N := BitCount div (M * Q);
  FM := 0;
  FM1 := 0;
  SetLength(Rows, M);

  for B := 0 to N - 1 do
  begin
    for R := 0 to M - 1 do
    begin
      Rows[R] := 0;
      for C := 0 to Q - 1 do
      begin
        BitIdx := B * (M * Q) + R * Q + C;
        Rows[R] := (Rows[R] shl 1) or UInt32(GetBit(Bits, BitIdx));
      end;
    end;
    Rank := ComputeRankGF2(Rows, M, Q);
    if Rank = M then Inc(FM)
    else if Rank = M - 1 then Inc(FM1);
  end;

  ChiSq := Sqr(FM - ProbM * N) / (ProbM * N) +
           Sqr(FM1 - ProbM1 * N) / (ProbM1 * N) +
           Sqr(N - FM - FM1 - ProbRest * N) / (ProbRest * N);

  Result.TestName := 'Binary Matrix Rank';
  // Closed form for 2 degrees of freedom (3 categories); equals Igamc(1, ChiSq/2)
  // - NIST's own document states both forms are equivalent for this test.
  Result.PValue := Exp(-ChiSq / 2);
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('N=%d, F_M=%d, F_(M-1)=%d, chi2=%.7f', [N, FM, FM1, ChiSq]);
end;

class function TRandomnessTests.CumulativeSums(const Bits: TBytes; BitCount: Integer;
  Mode: TCusumMode = cmForward; Alpha: Double = DefaultAlpha): TRandomnessTestResult;
var
  I, Idx, S, MaxAbsS: Integer;
  Z, N, Sum1, Sum2: Double;
  K, KStart, KEnd: Int64;
begin
  if BitCount < 100 then
    raise ERandomnessTestError.Create('Cumulative Sums test requires at least 100 bits');

  S := 0;
  MaxAbsS := 0;
  for I := 0 to BitCount - 1 do
  begin
    if Mode = cmForward then Idx := I else Idx := BitCount - 1 - I;
    if GetBit(Bits, Idx) = 1 then Inc(S) else Dec(S);
    if Abs(S) > MaxAbsS then MaxAbsS := Abs(S);
  end;

  Z := MaxAbsS;
  N := BitCount;

  Sum1 := 0;
  KStart := Ceil((-N / Z + 1) / 4);
  KEnd := Floor((N / Z - 1) / 4);
  for K := KStart to KEnd do
    Sum1 := Sum1 + (Phi(((4 * K + 1) * Z) / Sqrt(N)) - Phi(((4 * K - 1) * Z) / Sqrt(N)));

  Sum2 := 0;
  KStart := Ceil((-N / Z - 3) / 4);
  KEnd := Floor((N / Z - 1) / 4);
  for K := KStart to KEnd do
    Sum2 := Sum2 + (Phi(((4 * K + 3) * Z) / Sqrt(N)) - Phi(((4 * K + 1) * Z) / Sqrt(N)));

  if Mode = cmForward then
    Result.TestName := 'Cumulative Sums (forward)'
  else
    Result.TestName := 'Cumulative Sums (reverse)';
  Result.PValue := 1 - Sum1 + Sum2;
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('z=%.0f', [Z]);
end;

class function TRandomnessTests.ApproximateEntropy(const Bits: TBytes; BitCount: Integer;
  M: Integer = 2; Alpha: Double = DefaultAlpha): TRandomnessTestResult;

  function PhiM(MM: Integer): Double;
  var
    NumPatterns, I, J, Idx, Pattern: Integer;
    Counts: TArray<Integer>;
    P: Double;
  begin
    NumPatterns := 1 shl MM;
    SetLength(Counts, NumPatterns);
    for I := 0 to BitCount - 1 do
    begin
      Pattern := 0;
      for J := 0 to MM - 1 do
      begin
        Idx := (I + J) mod BitCount; // cyclic wraparound, per NIST's construction
        Pattern := (Pattern shl 1) or GetBit(Bits, Idx);
      end;
      Inc(Counts[Pattern]);
    end;
    Result := 0;
    for I := 0 to NumPatterns - 1 do
    begin
      if Counts[I] = 0 then Continue; // by convention, 0 * ln(0) contributes 0
      P := Counts[I] / BitCount;
      Result := Result + P * Ln(P);
    end;
  end;

var
  ApEn, ChiSq: Double;
  Df: Integer;
begin
  // NIST's "M < log2(n) - 5" is a recommendation for good statistical power,
  // not a hard requirement the algorithm needs - NIST's own worked example
  // (section 2.12.8, reproduced in this unit's tests) uses M=2, BitCount=100,
  // which itself violates that recommendation (log2(100)-5 =~ 1.64). So this
  // only rejects genuinely nonsensical input, not merely under-powered input.
  if M < 1 then
    raise ERandomnessTestError.Create('M must be 1 or greater');
  if BitCount < 1 then
    raise ERandomnessTestError.Create('BitCount must be positive');

  ApEn := PhiM(M) - PhiM(M + 1);
  ChiSq := 2 * BitCount * (Ln(2) - ApEn);
  Df := 1 shl M; // NIST: chi2 has 2^m degrees of freedom, confirmed numerically
                  // against the worked example in section 2.12.8 (m=2 -> df=4,
                  // reproducing P-value=0.235301 exactly)

  Result.TestName := 'Approximate Entropy';
  Result.PValue := Igamc(Df / 2, ChiSq / 2);
  Result.Passed := Result.PValue >= Alpha;
  Result.Detail := Format('ApEn(%d)=%.6f, chi2=%.6f', [M, ApEn, ChiSq]);
end;

class function TRandomnessTests.RunOne(const Name: string;
  const TestFunc: TFunc<TRandomnessTestResult>): TRandomnessTestResult;
begin
  try
    Result := TestFunc();
  except
    on E: ERandomnessTestError do
    begin
      Result.TestName := Name;
      Result.PValue := -1;
      Result.Passed := False;
      Result.Detail := 'skipped: ' + E.Message;
    end;
  end;
end;

class function TRandomnessTests.RunSuite(const Bits: TBytes; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TArray<TRandomnessTestResult>;
begin
  SetLength(Result, 7);
  Result[0] := RunOne('Frequency (Monobit)',
    function: TRandomnessTestResult begin Result := Frequency(Bits, BitCount, Alpha); end);
  Result[1] := RunOne('Frequency within a Block',
    function: TRandomnessTestResult begin Result := BlockFrequency(Bits, BitCount, 128, Alpha); end);
  Result[2] := RunOne('Runs',
    function: TRandomnessTestResult begin Result := Runs(Bits, BitCount, Alpha); end);
  Result[3] := RunOne('Longest Run of Ones in a Block',
    function: TRandomnessTestResult begin Result := LongestRunOfOnes(Bits, BitCount, Alpha); end);
  Result[4] := RunOne('Binary Matrix Rank',
    function: TRandomnessTestResult begin Result := BinaryMatrixRank(Bits, BitCount, Alpha); end);
  Result[5] := RunOne('Cumulative Sums (forward)',
    function: TRandomnessTestResult begin Result := CumulativeSums(Bits, BitCount, cmForward, Alpha); end);
  Result[6] := RunOne('Approximate Entropy',
    function: TRandomnessTestResult begin Result := ApproximateEntropy(Bits, BitCount, 2, Alpha); end);
end;

class function TRandomnessTests.RunSuite(const AProvider: ICSPRNGProvider; BitCount: Integer;
  Alpha: Double = DefaultAlpha): TArray<TRandomnessTestResult>;
var
  Data: TBytes;
begin
  Data := AProvider.GetBytes((BitCount + 7) div 8);
  Result := RunSuite(Data, BitCount, Alpha);
end;

end.
