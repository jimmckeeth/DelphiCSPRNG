program Holon.CSRNG_FMX;

uses
  System.StartUpCopy,
  FMX.Forms,
  Holon.CSRNG_FMX_Main in 'Holon.CSRNG_FMX_Main.pas' {Form28};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm28, Form28);
  Application.Run;
end.
