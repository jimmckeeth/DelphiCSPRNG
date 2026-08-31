unit CSPRNG.Provider.Base;

interface

uses
  System.SysUtils, CSPRNG.Interfaces,
  System.NetEncoding;

type
  /// <summary>
  /// Abstract base class for CSPRNG providers. Implements every method of ICSPRNGProvider in
  /// terms of the single abstract GetBytes method that each platform-specific subclass must
  /// implement.
  /// </summary>
  TCSPRNGProviderBase = class abstract(TInterfacedObject, ICSPRNGProvider)

  protected
    /// <summary>
    /// Generates the specified number of cryptographically secure random bytes. Every
    /// implementation must always return exactly Count bytes or raise an exception - callers
    /// never check the length of the result.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; virtual; abstract;
  public

    /// <summary>
    /// Generates a cryptographically secure random Double in the range [0, 1).
    /// </summary>
    function GetFloat: Double;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 32-bit integer in the
    /// range [0, max].
    /// </summary>
    function GetUInt32(const max: UInt32 = High(UInt32)): UInt32;

    /// <summary>
    /// Generates a cryptographically secure random integer in the range [0, max]. Despite
    /// the "Int32" name (inherited from ICSPRNGProvider), this never returns a negative
    /// value; max must be zero or greater.
    /// </summary>
    function GetInt32(const max: Int32 = High(Int32)): Int32;

    /// <summary>
    /// Generates a cryptographically secure random integer in the range [0, max]. Despite
    /// the "Int64" name (inherited from ICSPRNGProvider), this never returns a negative
    /// value; max must be zero or greater.
    /// </summary>
    function GetInt64(const max: Int64 = High(Int64)): Int64;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 64-bit integer in the
    /// range [0, max]. Uses rejection sampling (rather than a plain modulo) so the
    /// result is uniformly distributed with no modulo bias and can never exceed max.
    /// </summary>
    function GetUInt64(const max: UInt64 = High(UInt64)): UInt64;

    /// <summary>
    /// Generates len cryptographically secure random bytes and returns them
    /// Base64-encoded. Note that len is the number of source bytes, not the length
    /// of the resulting string.
    /// </summary>
    function GetBase64(const len: Integer = 1024): String;

    // Helpers

    /// <summary>
    /// Interprets Bytes as a little-endian 32-bit unsigned integer, zero-padding or
    /// truncating it to 4 bytes first via PadBytes.
    /// </summary>
    class function ToUInt32(const Bytes: TBytes): UInt32; static;

    /// <summary>
    /// Interprets Bytes as a little-endian 32-bit signed integer, zero-padding or
    /// truncating it to 4 bytes first via PadBytes.
    /// </summary>
    class function ToInt32(const Bytes: TBytes): Int32; static;

    /// <summary>
    /// Interprets Bytes as a little-endian 64-bit signed integer, zero-padding or
    /// truncating it to 8 bytes first via PadBytes.
    /// </summary>
    class function ToInt64(const Bytes: TBytes): Int64; static;

    /// <summary>
    /// Interprets Bytes as a little-endian 64-bit unsigned integer, zero-padding or
    /// truncating it to 8 bytes first via PadBytes.
    /// </summary>
    class function ToUInt64(const Bytes: TBytes): UInt64; static;

    /// <summary>
    /// Returns Bytes resized to exactly PadLength bytes: if Bytes is shorter, the result
    /// is zero-padded at the start (the most-significant end, given the little-endian
    /// interpretation used by ToUInt32/ToInt32/ToInt64/ToUInt64); if longer, it is
    /// truncated to the first PadLength bytes. In normal use this is a no-op, since every
    /// provider's GetBytes always returns exactly the number of bytes requested.
    /// </summary>
    class function PadBytes(const Bytes: TBytes; PadLength: Integer): TBytes; static;

    /// <summary>
    /// The single-draw core of GetUInt64's rejection sampling, split out so it can be
    /// unit-tested directly against hand-picked worst-case Value inputs rather than only
    /// via statistical sampling of real random data (some biased/out-of-range outcomes,
    /// like the one this replaced, occur for only a handful of UInt64 values out of 2^64,
    /// far too rare to reliably catch by generating real random draws in a test run).
    /// Returns False if Value falls in the "leftover" cycle at the top of the UInt64
    /// range and must be discarded and redrawn; otherwise returns True and sets Reduced
    /// to Value reduced into [0, max] with no modulo bias. max must not be High(UInt64)
    /// (that case needs no reduction at all - see GetUInt64) or 0.
    /// </summary>
    class function TryReduceUInt64(const Value, max: UInt64; out Reduced: UInt64): Boolean; static;

  end;

implementation

{ TCSPRNGProviderBase }

function TCSPRNGProviderBase.GetUInt32(const max: UInt32 = High(UInt32)): UInt32;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max = 0 then
    Exit(0); // Handle the case where max is 0

  RandomBytes := GetBytes(SizeOf(UInt32)); // Get 4 random bytes
  // Use ToUInt32 (not ToUInt64): PadBytes zero-pads short input at the start, so
  // widening these 4 bytes straight through ToUInt64 would push them into the high
  // 32 bits of the result, leaving the low bits - the only ones a power-of-two modulus
  // like the default `max` looks at - always zero.
  Value := UInt64(ToUInt32(RandomBytes));

  Result := UInt32(Value mod (UInt64(max) + 1));  // Modulo and cast to UInt32
end;

function TCSPRNGProviderBase.GetInt32(const max: Int32 = High(Int32)): Int32;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max < 0 then
    raise ECSPRNGError.Create('Max value must be greater than or equal to 0');

  RandomBytes := GetBytes(SizeOf(Int32)); // Get 4 random bytes
  // See GetUInt32 for why this must be ToUInt32, not ToUInt64.
  Value := UInt64(ToUInt32(RandomBytes));

  // Value mod (max+1) is always in [0, max], and max <= High(Int32), so the result
  // always fits Int32 without needing any further adjustment.
  Result := Int32(Value mod (UInt64(max) + 1));
end;

function TCSPRNGProviderBase.GetInt64(const max: Int64 = High(Int64)): Int64;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max < 0 then
    raise ECSPRNGError.Create('Max value must be greater than or equal to 0');

  RandomBytes := GetBytes(SizeOf(Int64));
  Value := ToUInt64(RandomBytes);

  // Value mod (max+1) is always in [0, max], and max <= High(Int64), so the result
  // always fits Int64 without needing any further adjustment.
  Result := Int64(Value mod (UInt64(max) + 1));
end;

function TCSPRNGProviderBase.GetUInt64(const max: UInt64 = High(UInt64)): UInt64;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max = 0 then
    Exit(0); // Handle the case where max is 0

  // Special handling when max is High(UInt64) to avoid overflow
  if max = High(UInt64) then
  begin
    RandomBytes := GetBytes(SizeOf(UInt64)); // Get 8 random bytes
    Exit(ToUInt64(RandomBytes));
  end;

  repeat
    RandomBytes := GetBytes(SizeOf(UInt64)); // Get 8 random bytes
    Value := ToUInt64(RandomBytes);
  until TryReduceUInt64(Value, max, Result);
end;

class function TCSPRNGProviderBase.TryReduceUInt64(const Value, max: UInt64; out Reduced: UInt64): Boolean;
var
  RangeSize, Threshold: UInt64;
begin
  RangeSize := max + 1;

  // Reject draws that fall in the partial "leftover" cycle at the top of the UInt64
  // range, so that "Value mod RangeSize" is uniformly distributed across [0, max] with
  // no modulo bias and can never exceed max.
  // ((High(UInt64) mod RangeSize) + 1) mod RangeSize, computed with UInt64 wraparound,
  // equals exactly (2^64 mod RangeSize) - i.e. the size of that leftover cycle -
  // without ever needing to represent 2^64 itself.
  Threshold := High(UInt64) - ((High(UInt64) mod RangeSize + 1) mod RangeSize);

  Result := Value <= Threshold;
  if Result then
    Reduced := Value mod RangeSize;
end;


class function TCSPRNGProviderBase.PadBytes(const Bytes: TBytes; PadLength: Integer): TBytes;
begin
  if Length(Bytes) < PadLength then
  begin
    SetLength(Result, PadLength);
    FillChar(Result[0], PadLength, 0); // Fill with zeros
    if Length(Bytes) > 0 then // Only move bytes if the input array is not empty
      Move(Bytes[0], Result[PadLength - Length(Bytes)], Length(Bytes));
  end
  else
    Result := Copy(Bytes, 0, PadLength); // Copy only the required bytes
end;

class function TCSPRNGProviderBase.ToUInt32(const Bytes: TBytes): UInt32;
begin
  var localBytes := PadBytes(Bytes, SizeOf(UInt32));

  // Combine bytes using bit shifting to avoid potential endianness issues
  Result := UInt32(localBytes[0]) +
            (UInt32(localBytes[1]) shl 8) +
            (UInt32(localBytes[2]) shl 16) +
            (UInt32(localBytes[3]) shl 24);
end;

class function TCSPRNGProviderBase.ToInt32(const Bytes: TBytes): Int32;
var
  localBytes: TBytes;
begin
  localBytes := PadBytes(Bytes, SizeOf(Int32));

  // Combine bytes using bit shifting to avoid potential endianness issues
  Result := Int32(localBytes[0]) +
            (Int32(localBytes[1]) shl 8) +
            (Int32(localBytes[2]) shl 16) +
            (Int32(localBytes[3]) shl 24);
end;

class function TCSPRNGProviderBase.ToInt64(const Bytes: TBytes): Int64;
var
  localBytes: TBytes;
begin
  localBytes := PadBytes(Bytes, SizeOf(Int64));

  // Combine bytes using bit shifting
  Result := Int64(localBytes[0]) +
            (Int64(localBytes[1]) shl 8) +
            (Int64(localBytes[2]) shl 16) +
            (Int64(localBytes[3]) shl 24) +
            (Int64(localBytes[4]) shl 32) +
            (Int64(localBytes[5]) shl 40) +
            (Int64(localBytes[6]) shl 48) +
            (Int64(localBytes[7]) shl 56);
end;

class function TCSPRNGProviderBase.ToUInt64(const Bytes: TBytes): UInt64;
var
  localBytes: TBytes;
begin
  localBytes := PadBytes(Bytes, SizeOf(UInt64));

  // Combine bytes using bit shifting
  Result := UInt64(localBytes[0]) +
            (UInt64(localBytes[1]) shl 8) +
            (UInt64(localBytes[2]) shl 16) +
            (UInt64(localBytes[3]) shl 24) +
            (UInt64(localBytes[4]) shl 32) +
            (UInt64(localBytes[5]) shl 40) +
            (UInt64(localBytes[6]) shl 48) +
            (UInt64(localBytes[7]) shl 56);
end;

function TCSPRNGProviderBase.GetFloat: Double;
var
  Bytes: TBytes;
  RandomInt: UInt64;
begin
  Bytes := GetBytes(SizeOf(UInt64));
  RandomInt := ToUInt64(Bytes); // Use the same endian-safe conversion as the integer getters
  Result := RandomInt / UInt64(High(UInt64)); // Scale to [0, 1)
end;

function TCSPRNGProviderBase.GetBase64(const len: Integer = 1024): String;
var
  Bytes: TBytes;
begin
  Bytes := GetBytes(len);
  var Encoding := TBase64Encoding.Create(0);
  try
    Result := Encoding.EncodeBytesToString(Bytes); // Convert to Base64
  finally
    Encoding.Free;
  end;
end;

end.
