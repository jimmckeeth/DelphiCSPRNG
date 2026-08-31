unit Holon.CSPRNG.Provider.Apple;

interface

{$IFDEF MACOS}

uses
  Holon.CSPRNG.Provider.Base, Holon.CSPRNG.Interfaces, Macapi.CoreFoundation, Macapi.Security, SysUtils;

type
  /// <summary>
  /// macOS and iOS implementation of the CSPRNG provider. Both platforms intentionally
  /// share this single unit rather than duplicating near-identical code: Delphi's compiler
  /// defines the MACOS symbol for both macOS and iOS, and both expose the same Security
  /// framework API.
  /// </summary>
  TCSPRNGProviderApple = class(TCSPRNGProviderBase)
  protected
    /// <summary>
    /// Generates cryptographically secure random bytes using SecRandomCopyBytes, Apple's
    /// documented and recommended CSPRNG API (Security framework). This is preferred over
    /// reading /dev/urandom directly: it performs no file I/O, cannot fail due to
    /// App Sandbox file-system entitlements, and never blocks.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

{ TCSPRNGProviderApple }

function TCSPRNGProviderApple.GetBytes(const Count: Integer): TBytes;
var
  Status: Integer;
begin
  if Count < 0 then
    raise ECSPRNGError.Create('Count must be zero or greater');

  SetLength(Result, Count);
  if Count = 0 then
    Exit; // Nothing to fill, and @Result[0] would be an out-of-bounds access below.

  Status := SecRandomCopyBytes(kSecRandomDefault, Count, @Result[0]);

  if Status <> errSecSuccess then
    raise ECSPRNGError.Create('Unable to generate random bytes using SecRandomCopyBytes');
end;

{$ELSE}
implementation
{$ENDIF}

end.
