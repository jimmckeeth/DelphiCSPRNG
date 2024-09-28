unit CSPRNG.Provider.iOS;

interface

{$ifdef IOS}
uses
  CSPRNG.Provider.Base, Macapi.CoreFoundation, Macapi.Security, SysUtils;

type
  /// <summary>
  /// iOS implementation of the CSPRNG provider using SecRandomCopyBytes.
  /// </summary>
  TCSPRNGProvideriOS = class(TCSPRNGProviderBase)
  protected
    procedure SeedFromBytes(const SeedData: TBytes); override;
    procedure SeedFromEntropySource; override;
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

{ TCSPRNGProvideriOS }

procedure TCSPRNGProvideriOS.SeedFromBytes(const SeedData: TBytes);
begin
  // Seeding is not necessary on iOS.
  raise Exception.Create('Custom seeding is not supported on iOS.');
end;

procedure TCSPRNGProvideriOS.SeedFromEntropySource;
begin
  // Seeding is not necessary for iOS.
end;

function TCSPRNGProvideriOS.GetBytes(const Count: Integer): TBytes;
var
  Status: Integer;
begin
  SetLength(Result, Count);
  Status := SecRandomCopyBytes(kSecRandomDefault, Count, @Result[0]);

  if Status <> errSecSuccess then
    raise Exception.Create('Unable to generate random bytes using SecRandomCopyBytes');
end;

{$ELSE}
implementation
{$endif}

end.

