program CSPRNG_sample;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  CSPRNG in '..\src\CSPRNG.pas',
  CSPRNG.Interfaces in '..\src\CSPRNG.Interfaces.pas',
  CSPRNG.ProviderInfo in '..\src\CSPRNG.ProviderInfo.pas';

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
