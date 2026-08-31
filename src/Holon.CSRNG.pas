unit Holon.CSRNG;

interface

uses
  System.SysUtils, Holon.CSRNG.Interfaces;

/// <summary>
/// Returns a cryptographically secure random number provider appropriate for the
/// current platform, chosen at compile time: Windows CNG (BCryptGenRandom) on Windows,
/// the Security framework (SecRandomCopyBytes) on macOS/iOS, getrandom(2) - falling back
/// to /dev/urandom - on Linux, and /dev/urandom directly on Android.
/// </summary>
function GetCSPRNGProvider: ICSPRNGProvider;

implementation

// MACOS and LINUX are both checked before the generic POSIX fallback: Delphi defines
// POSIX for macOS and iOS as well as for Linux and Android, and LINUX specifically for
// Linux64 as well as POSIX, so checking POSIX first would either shadow the more specific
// provider or - since more than one branch would then be compiled in - produce a
// duplicate GetCSPRNGProvider declaration. Using {$ELSEIF} keeps the branches mutually
// exclusive regardless of how broadly each symbol is defined.
{$IF Defined(MSWINDOWS)}
uses Holon.CSRNG.Provider.Windows;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TWindowsCSPRNGProvider.Create; // Create Windows provider
end;
{$ELSEIF Defined(MACOS)}
uses Holon.CSRNG.Provider.Apple;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TCSPRNGProviderApple.Create; // Create macOS/iOS provider
end;
{$ELSEIF Defined(LINUX)}
uses Holon.CSRNG.Provider.Linux;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TCSPRNGProviderLinux.Create; // Create Linux64 provider
end;
{$ELSEIF Defined(POSIX)}
uses Holon.CSRNG.Provider.Posix;

function GetCSPRNGProvider: ICSPRNGProvider;
begin
  Result := TCSPRNGProviderPosix.Create; // Create Android/generic POSIX provider
end;
{$ENDIF}

end.
