unit CSPRNG.Provider.Base;

interface

uses
  System.SysUtils, CSPRNG.Interfaces,
  System.NetEncoding;

type
  /// <summary>
  /// Abstract base class for CSPRNG providers.
  /// </summary>
  TCSPRNGProviderBase = class abstract(TInterfacedObject, ICSPRNGProvider)

  protected
    function GetBytes(const Count: Integer): TBytes; virtual; abstract;
  public

    function GetFloat: Double;
    function GetUInt32(max: UInt32 = High(UInt32)): UInt32;
    function GetInt32(max: Int32 = High(Int32)): Int32;
    function GetInt64(max: Int64 = High(Int64)): Int64;
    function GetUInt64(max: UInt64 = High(UInt64)): UInt64;
    function GetBase64(len: Integer = 1024): String;

    // Helpers
    class function ToUInt32(const Bytes: TBytes): UInt32;
    class function ToInt32(const Bytes: TBytes): Int32;
    class function ToInt64(const Bytes: TBytes): Int64;
    class function ToUInt64(const Bytes: TBytes): UInt64;
    class function PadBytes(const Bytes: TBytes; PadLength: Integer): TBytes; static;

  end;

implementation

{ TCSPRNGProviderBase }

function TCSPRNGProviderBase.GetUInt32(max: UInt32 = High(UInt32)): UInt32;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max = 0 then
    Exit(0); // Handle the case where max is 0

  RandomBytes := GetBytes(SizeOf(UInt32)); // Get 4 random bytes
  Value := ToUInt64(RandomBytes);

  Result := UInt32(Value mod (UInt64(max) + 1));  // Modulo and cast to UInt32
end;

function TCSPRNGProviderBase.GetInt32(max: Int32 = High(Int32)): Int32;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max < 0 then
    raise Exception.Create('Max value must be greater than or equal to 0');

  RandomBytes := GetBytes(SizeOf(Int32)); // Get 4 random bytes
  Value := ToUInt64(RandomBytes); // Convert to UInt64

  // Calculate the range size and adjust the modulo operation for signed values
  var rangeSize := UInt64(max) + 1; // Range from 0 to max (inclusive)
  var adjustedValue := Value mod rangeSize;

  // If the adjusted value is too large to fit in Int32 after conversion, subtract the range size
  if adjustedValue > High(Int32) then
    adjustedValue := adjustedValue - rangeSize;

  Result := Int32(adjustedValue); // Safely cast to Int32
end;

function TCSPRNGProviderBase.GetInt64(max: Int64 = High(Int64)): Int64;
var
  RandomBytes: TBytes;
  Value: UInt64;
begin
  if max < 0 then
    raise Exception.Create('Max value must be greater than or equal to 0');

  RandomBytes := GetBytes(SizeOf(Int64));
  Value := ToUInt64(RandomBytes);

  var rangeSize := UInt64(max) + 1;
  var adjustedValue := Value mod rangeSize;

  if adjustedValue > High(Int64) then
    adjustedValue := adjustedValue - rangeSize;

  Result := Int64(adjustedValue);
end;

function TCSPRNGProviderBase.GetUInt64(max: UInt64 = High(UInt64)): UInt64;
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

  RandomBytes := GetBytes(SizeOf(UInt64)); // Get 8 random bytes
  Value := ToUInt64(RandomBytes);

  // Optimized range reduction without a loop
  var divisor := High(UInt64) div (max + 1);
  Result := Value div divisor; // Integer division ensures the result is in the range
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
  RandomInt := PUInt64(@Bytes[0])^; // Assuming little-endian
  Result := RandomInt / UInt64(High(UInt64)); // Scale to [0, 1)
end;

function TCSPRNGProviderBase.GetBase64(len: Integer = 1024): String;
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
