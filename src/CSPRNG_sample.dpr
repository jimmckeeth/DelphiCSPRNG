program CSPRNG_sample;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  CSPRNG in 'CSPRNG.pas',
  CSPRNG.Provider.Windows in 'CSPRNG.Provider.Windows.pas',
  CSPRNG.Interfaces in 'CSPRNG.Interfaces.pas',
  CSPRNG.Provider.Base in 'CSPRNG.Provider.Base.pas';

begin
  try
    var rnd := GetCSPRNGProvider;
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
