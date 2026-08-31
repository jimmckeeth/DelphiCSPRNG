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
  Holon.CSRNG.Provider.Apple in '..\src\Holon.CSRNG.Provider.Apple.pas';

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
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
  Writeln;
  Writeln('Done!');
  Readln;
end.
