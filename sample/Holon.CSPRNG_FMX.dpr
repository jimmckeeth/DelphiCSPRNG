program Holon.CSPRNG_FMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  Holon.CSPRNG_FMX_Main in 'Holon.CSPRNG_FMX_Main.pas' {Form28};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm28, Form28);
  Application.Run;
end.
