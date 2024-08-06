unit CSPRNG;

interface

uses
  System.SysUtils, CSPRNG.Interfaces;

function GetCSPRNGProvider: ICSPRNGProvider;

implementation

{$IF Defined(MSWINDOWS)}
  uses CSPRNG.Provider.Windows;
{$ELSEIF Linux}
  uses CSPRNG.Provuder.Linux;
{$ENDIF}

function GetCSPRNGProvider: ICSPRNGProvider;
begin
{$IFDEF MSWINDOWS}
  Result := TWindowsCSPRNGProvider.Create; // Create Windows provider
{$ENDIF}
end;


initialization

finalization

end.

