program CSPRNG_FMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  CSPRNG_FMX_Main in 'CSPRNG_FMX_Main.pas' {Form28};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm28, Form28);
  Application.Run;
end.
