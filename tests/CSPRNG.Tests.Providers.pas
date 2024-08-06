unit CSPRNG.Tests.Providers;

interface

uses
  SysUtils,
  DUnitX.TestFramework,
  CSPRNG,
  CSPRNG.Interfaces;

type

  [TestFixture]
  TCSPRNGProviderTests = class
  private
    FCSPRNGProvider: ICSPRNGProvider;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestGetBytes_Length;
    [Test]
    procedure TestGetBytes_Randomness;

    [Test]
    procedure TestPadBytes_EmptyArrayTo4;
    [Test]
    procedure TestPadBytes_ExactLengthTo4;
    [Test]
    procedure TestPadBytes_LongArrayTo4;
    [Test]
    procedure TestPadBytes_ShortArrayTo4;
    [Test]
    procedure TestPadBytes_ShortArrayTo8;
    [Test]
    procedure TestPadBytes_ExactLengthTo8;
    [Test]
    procedure TestPadBytes_LongArrayTo8;
    [Test]
    procedure TestPadBytes_EmptyArrayTo8;

    [Test]
    [TestCase('UInt32_DefaultRange', '123456')]
    [TestCase('UInt32_SmallRange', '20')]
    procedure TestGetUInt32(const ExpectedMax: string);

    [Test]
    [TestCase('Int64_DefaultRange', '9223372036854775807')]
    [TestCase('Int64_SmallRange', '1000000')]
    [TestCase('Int64_SingleValue', '5')]
    procedure TestGetInt64(const ExpectedMax: string);

    [Test]
    [TestCase('Int32_DefaultRange', '2147483647')]
    [TestCase('Int32_SmallRange', '100')]
    [TestCase('Int32_SingleValue', '5')]
    procedure TestGetInt32(const ExpectedMax: string);

    [Test]
    [TestCase('UInt64_DefaultRange', '$FFFFFFFFFFFFFFFF')]
    [TestCase('UInt64_SmallRange', '1000000')]
    [TestCase('UInt64_SingleValue', '5')]
    procedure TestGetUInt64(const ExpectedMax: string);

    [Test]
    [TestCase('Len64','64')]
    [TestCase('Len512','512')]
    [TestCase('Len2048','2048')]
    procedure TestGetBase64_CustomLength(const Len: String);
    [Test]
    procedure TestGetBase64_Length;
    [Test]
    procedure TestGetBase64_Randomness;
    [Test]
    procedure TestGetBase64_ValidEncoding;

    [Test]
    procedure TestGetFloat_Range;
    [Test]
    procedure TestSeedFromBytes;
    [Test]
    procedure TestSeedFromEntropySource;
  end;

implementation

uses
  System.Math,
  System.NetEncoding,
  System.Generics.Collections,
  System.Classes,
  CSPRNG.Provider.Base;

{ TCSPRNGProviderTests }

procedure TCSPRNGProviderTests.Setup;
begin
  FCSPRNGProvider := GetCSPRNGProvider;
end;

procedure TCSPRNGProviderTests.TearDown;
begin
  FCSPRNGProvider := nil;
end;

procedure TCSPRNGProviderTests.TestGetBytes_Length;
const
  ByteCount = 1024;
var
  Bytes: TBytes;
begin
  Bytes := FCSPRNGProvider.GetBytes(ByteCount);
  Assert.AreEqual(UInt64(ByteCount), UInt64(Length(Bytes)),
    'Incorrect number of bytes generated');
end;

procedure TCSPRNGProviderTests.TestGetBytes_Randomness;
const
  ByteCount = 1024 * 1024; // 1MB of data
begin
  var Bytes := FCSPRNGProvider.GetBytes(ByteCount);

  var Frequencies := TDictionary<Byte, Integer>.Create;
  for var Byte in Bytes do
  begin
    var Frequency: Integer;
    if Frequencies.TryGetValue(Byte, Frequency) then
      Frequencies[Byte] := Frequency + 1
    else
      Frequencies.Add(Byte, 1);
  end;

  // Roughly check for uniform distribution (this is not a perfect statistical test)
  for var Frequency in Frequencies.Values do
    Assert.IsTrue(Frequency > ByteCount * 0.9 / 256, 'Insufficient randomness detected'); // 10% tolerance
end;


procedure TCSPRNGProviderTests.TestGetUInt32(const ExpectedMax: string);
begin
  var MaxVal: Cardinal := StrToInt(ExpectedMax);

  for var i := 1 to 1000 do
  begin
    var Value := FCSPRNGProvider.GetUInt32(MaxVal);
    Assert.IsTrue(Value <= MaxVal, 'UInt32 above maximum');
  end;
end;

procedure TCSPRNGProviderTests.TestGetUInt64(const ExpectedMax: string);
var
  MaxVal, Value: UInt64;
  i: Integer;
begin
  MaxVal := StrToUInt64(ExpectedMax);

  for i := 1 to 1000 do
  begin
    Value := FCSPRNGProvider.GetUInt64(MaxVal);
    Assert.IsTrue(Value >= 0, 'UInt64 below minimum (0)');
    Assert.IsTrue(Value <= MaxVal, 'UInt64 above maximum');
  end;
end;

procedure TCSPRNGProviderTests.TestGetInt32(const ExpectedMax: string);
var
  MaxVal, Value: Int32;
  i: Integer;
begin
  MaxVal := StrToInt(ExpectedMax);

  for i := 1 to 1000 do
  begin
    Value := FCSPRNGProvider.GetInt32(MaxVal);
    Assert.IsTrue(Value >= 0, 'Int32 below minimum (0)');
    Assert.IsTrue(Value <= MaxVal, 'Int32 above maximum');
  end;
end;

procedure TCSPRNGProviderTests.TestGetInt64(const ExpectedMax: string);
var
  MaxVal, Value: Int64;
  i: Integer;
begin
  MaxVal := StrToInt64(ExpectedMax);

  for i := 1 to 1000 do
  begin
    Value := FCSPRNGProvider.GetInt64(MaxVal);
    Assert.IsTrue(Value >= 0, 'Int64 below minimum (0)');
    Assert.IsTrue(Value <= MaxVal, 'Int64 above maximum');
  end;
end;

procedure TCSPRNGProviderTests.TestGetFloat_Range;
begin
  for var i := 1 to 1000 do
  begin
    var Value := FCSPRNGProvider.GetFloat;
    Assert.IsTrue(Value >= 0, 'Float below 0');
    Assert.IsTrue(Value < 1, 'Float not strictly less than 1');
  end;
end;

procedure TCSPRNGProviderTests.TestSeedFromBytes;
begin
  // ... (Implement a test for SeedFromBytes.
  // This could involve checking for changes in the random output after seeding
  // or verifying that the same seed produces the same output sequence.)
end;

procedure TCSPRNGProviderTests.TestSeedFromEntropySource;
begin
  // ... (Implement a test for SeedFromEntropySource.
  // This is more challenging, as it relies on system entropy.
  // You could potentially check if the output changes after reseeding, but it's not guaranteed.)
end;

procedure TCSPRNGProviderTests.TestPadBytes_ShortArrayTo4;
begin
  var InputBytes: TBytes := [ $1, $2 ];
  var ExpectedBytes: TBytes := [ $0, $0, $1, $2 ];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt32));
  Assert.AreEqual(ExpectedBytes, ResultBytes);
end;

procedure TCSPRNGProviderTests.TestPadBytes_ExactLengthTo4;
begin
  var InputBytes: TBytes := [ $1, $2, $3, $4 ];
  var ExpectedBytes: TBytes := [ $1, $2, $3, $4 ];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt32));
  Assert.AreEqual(ExpectedBytes, ResultBytes);
end;

procedure TCSPRNGProviderTests.TestPadBytes_LongArrayTo4;
begin
  var InputBytes: TBytes := [ $1, $2, $3, $4, $5, $6 ];
  var ExpectedBytes: TBytes := [ $1, $2, $3, $4 ];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt32));
  Assert.AreEqual(ExpectedBytes, ResultBytes);
end;

procedure TCSPRNGProviderTests.TestPadBytes_EmptyArrayTo4;
begin
  var InputBytes: TBytes := [];
  var ExpectedBytes: TBytes := [ $0, $0, $0, $0 ];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt32));
  Assert.AreEqual(ExpectedBytes, ResultBytes);
end;

procedure TCSPRNGProviderTests.TestPadBytes_ShortArrayTo8;
begin
  var InputBytes: TBytes := [$1, $2, $3, $4];
  var ExpectedBytes: TBytes := [$0, $0, $0, $0, $1, $2, $3, $4];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt64));
  Assert.AreEqual(ExpectedBytes, ResultBytes, 'Incorrect padding: ShortArrayTo8');
end;

procedure TCSPRNGProviderTests.TestPadBytes_ExactLengthTo8;
begin
  var InputBytes: TBytes := [$1, $2, $3, $4, $5, $6, $7, $8];
  var ExpectedBytes: TBytes := [$1, $2, $3, $4, $5, $6, $7, $8];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt64));
  Assert.AreEqual(ExpectedBytes, ResultBytes, 'Incorrect padding: ExactLengthTo8');
end;

procedure TCSPRNGProviderTests.TestPadBytes_LongArrayTo8;
begin
  var InputBytes: TBytes := [$1, $2, $3, $4, $5, $6, $7, $8, $9, $A];
  var ExpectedBytes: TBytes := [$1, $2, $3, $4, $5, $6, $7, $8];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt64));
  Assert.AreEqual(ExpectedBytes, ResultBytes, 'Incorrect padding: LongArrayTo8');
end;

procedure TCSPRNGProviderTests.TestPadBytes_EmptyArrayTo8;
begin
  var InputBytes: TBytes := [];
  var ExpectedBytes: TBytes := [$0, $0, $0, $0, $0, $0, $0, $0];
  var ResultBytes := TCSPRNGProviderBase.PadBytes(InputBytes, SizeOf(UInt64));
  Assert.AreEqual(ExpectedBytes, ResultBytes, 'Incorrect padding: EmptyArrayTo8');
end;

procedure TCSPRNGProviderTests.TestGetBase64_Length;
begin
  var Bytes := TNetEncoding.Base64.DecodeStringToBytes(FCSPRNGProvider.GetBase64(1024));
  Assert.AreEqual(UInt64(1024), UInt64(Length(Bytes)), 'Incorrect Base64 string length');
end;

function GetBase64EncodedLength(ByteLength: Integer): Integer;
begin
  Result := ((ByteLength + 2) div 3) * 4;
end;

procedure TCSPRNGProviderTests.TestGetBase64_CustomLength(const Len: String);
var
  Base64String: string;
  iLen: Integer;
  ExpectedLength: Integer;
begin
  iLen := StrToInt(Len);
  Base64String := FCSPRNGProvider.GetBase64(iLen);

  // Calculate expected length with padding
  ExpectedLength := GetBase64EncodedLength(iLen);

  Assert.AreEqual(ExpectedLength, Length(Base64String),
    'Incorrect Base64 string length for custom length: ' + Len);
end;

procedure TCSPRNGProviderTests.TestGetBase64_Randomness;
var
  Strings: TStringList;
  Base64String: string;
  i: Integer;
begin
  Strings := TStringList.Create;
  try
    for i := 1 to 100 do
    begin
      Base64String := FCSPRNGProvider.GetBase64(64);
      Assert.IsFalse(Strings.Contains(Base64String), 'Duplicate Base64 string generated');
      Strings.Add(Base64String);
    end;
  finally
    Strings.Free;
  end;
end;

procedure TCSPRNGProviderTests.TestGetBase64_ValidEncoding;
var
  Bytes: TBytes;
begin
  var Base64String := FCSPRNGProvider.GetBase64;
  var Encoding := TBase64Encoding.Create(0);
  try
  Assert.WillNotRaiseAny(
    procedure
    begin
      Bytes := Encoding.DecodeStringToBytes(Base64String);
    end,
    'Invalid Base64 encoding');
  Assert.AreEqual(Base64String, Encoding.EncodeBytesToString(Bytes),
    'Failed round trip back to Base64.');
  finally
    Encoding.Free;
  end;
end;

initialization
  TDUnitX.Options.ExitBehavior := TDUnitXExitBehavior.Pause
end.

