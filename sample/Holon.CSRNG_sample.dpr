program Holon.CSRNG_sample;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Holon.CSRNG in '..\src\Holon.CSRNG.pas',
  Holon.CSRNG.Provider.Windows in '..\src\Holon.CSRNG.Provider.Windows.pas',
  Holon.CSRNG.Interfaces in '..\src\Holon.CSRNG.Interfaces.pas',
  Holon.CSRNG.Provider.Base in '..\src\Holon.CSRNG.Provider.Base.pas',
  Holon.CSRNG.Provider.Posix in '..\src\Holon.CSRNG.Provider.Posix.pas',
  Holon.CSRNG.Provider.Linux in '..\src\Holon.CSRNG.Provider.Linux.pas',
  Holon.CSRNG.Provider.Apple in '..\src\Holon.CSRNG.Provider.Apple.pas',
  Holon.SecureMemory in '..\src\Holon.SecureMemory.pas',
  Holon.SecureMemory.Platform in '..\src\Holon.SecureMemory.Platform.pas',
  Holon.ValidateRNG in '..\src\Holon.ValidateRNG.pas';

begin
  try
    var rnd := Holon.CSRNG.GetCSPRNGProvider;
    for var b in rnd.GetBytes(1000) do
    begin
      write(IntToHex(b, 2).ToLower);
    end;
    Writeln;
    const limit = 5;
    writeln(' - Float -');
    for var i := 0 to limit do Writeln(rnd.GetFloat);
    writeln(' - UInt32(max) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt32);
    writeln(' - UInt32(quarter) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt32(High(UInt32) div 4));
    writeln(' - UInt32(small) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt32($F0));


    writeln(' - Int32(max) -');
    for var i := 0 to limit do Writeln(rnd.GetInt32());
    writeln(' - Int32(quarter) -');
    for var i := 0 to limit do Writeln(rnd.GetInt32(High(Int32) div 2));
    writeln(' - Int32(small) -');
    for var i := 0 to limit do Writeln(rnd.GetInt32($F0));

    writeln(' - UInt64(max) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt64);
    writeln(' - UInt64(quarter) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt64(High(UInt64) div 4));
    writeln(' - UInt64(small) -');
    for var i := 0 to limit do Writeln(rnd.GetUInt64($F0));

    writeln(' - Int64(max) -');
    for var i := 0 to limit do Writeln(rnd.GetInt64);
    writeln(' - Int64(quarter) -');
    for var i := 0 to limit do Writeln(rnd.GetInt64(High(UInt64) div 4));
    writeln(' - Int64(small) -');
    for var i := 0 to limit do Writeln(rnd.GetInt64($F0));

    writeln(' - Holon.SecureMemory -');
    var Key := TSecureBytes.FromProvider(rnd, 32);
    Write('  32-byte secure key: ');
    var A := Key.Access;
    for var i := 0 to A.Size - 1 do
      Write(IntToHex(A.Data[i], 2).ToLower);
    Writeln;
    Writeln('  Locked out of swap: ', Key.Locked);

    writeln(' - Holon.ValidateRNG (NIST SP 800-22 subset) -');
    var TestResults := TRandomnessTests.RunSuite(rnd, 40000); // 40,000 bits = 5,000 bytes
    for var TR in TestResults do
    begin
      if TR.PValue = -1 then
        Writeln(Format('  %-32s SKIPPED (%s)', [TR.TestName, TR.Detail]))
      else if TR.Passed then
        Writeln(Format('  %-32s p=%.6f PASS (%s)', [TR.TestName, TR.PValue, TR.Detail]))
      else
        Writeln(Format('  %-32s p=%.6f FAIL (%s)', [TR.TestName, TR.PValue, TR.Detail]));
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
  Writeln;
  Writeln('Done!');
  Readln;
end.
