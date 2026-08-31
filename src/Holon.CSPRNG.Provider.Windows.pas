unit Holon.CSPRNG.Provider.Windows;

interface

{$IFDEF MSWINDOWS}

uses
  System.SysUtils,
  Winapi.Windows,
  Holon.CSPRNG.Interfaces,
  Holon.CSPRNG.Provider.Base;

type
  /// <summary>
  /// Windows implementation of the CSPRNG provider, using the CNG (Cryptography API: Next
  /// Generation) BCryptGenRandom function with the BCRYPT_USE_SYSTEM_PREFERRED_RNG flag -
  /// Microsoft's documented recommendation when the caller has no specific reason to pin a
  /// particular RNG algorithm, letting Windows itself choose (and potentially change,
  /// across OS updates) its preferred implementation. This also means there's no algorithm
  /// provider handle to open/close: every call is self-contained.
  /// </summary>
  TWindowsCSPRNGProvider = class(TCSPRNGProviderBase, ICSPRNGProvider)
  protected
    /// <summary>
    /// Generates cryptographically secure random bytes using BCryptGenRandom.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

function BCryptGenRandom(hAlgorithm: PVOID; pbBuffer: PBYTE;
  cbBuffer: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

const
  STATUS_SUCCESS = 0; // NTSTATUS Success value


{ TWindowsCSPRNGProvider }

function TWindowsCSPRNGProvider.GetBytes(const Count: Integer): TBytes;
var
  pBytes: PByte;
begin
  if Count < 0 then
    raise ECSPRNGError.Create('Count must be zero or greater');

  SetLength(Result, Count);
  pBytes := PByte(Result);
  // hAlgorithm must be NULL when BCRYPT_USE_SYSTEM_PREFERRED_RNG is set.
  if BCryptGenRandom(nil, pBytes, Count, BCRYPT_USE_SYSTEM_PREFERRED_RNG) <> STATUS_SUCCESS then
    raise ECSPRNGError.Create('Failed to generate random bytes');
end;
{$ELSE}
implementation
{$ENDIF}

end.
