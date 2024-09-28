unit CSPRNG_FMX_Main;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,

  CSPRNG, CSPRNG.Interfaces, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo,
  FMX.Controls.Presentation, FMX.StdCtrls;

type
  TForm28 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
    rng: ICSPRNGProvider;
  public
    { Public declarations }
  end;

var
  Form28: TForm28;

implementation

{$R *.fmx}

procedure TForm28.Button1Click(Sender: TObject);
begin
  memo1.Lines.Text := rng.GetBase64()
end;

procedure TForm28.FormCreate(Sender: TObject);
begin
   rng := GetCSPRNGProvider;
end;

end.
