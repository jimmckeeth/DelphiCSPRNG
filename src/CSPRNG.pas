unit CSPRNG;

interface

uses
  System.SysUtils, CSPRNG.Interfaces;

function GetCSPRNGProvider: ICSPRNGProvider;

implementation

{$IF Defined(MSWINDOWS)}
uses CSPRNG.Provider.Windows;
function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TWindowsCSPRNGProvider.Create; // Create Windows provider
end;
{$ENDIF}

{$IFDEF POSIX}
uses CSPRNG.Provider.Posix;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TCSPRNGProviderPosix.Create;
end;
{$ENDIF}

{$IFDEF MACOS}
uses CSPRNG.Provider.MacOS64;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TCSPRNGProviderMacOS64.Create;
end;
{$ENDIF}

initialization

finalization

end.

