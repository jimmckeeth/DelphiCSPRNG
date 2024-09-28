unit CSPRNG.Provider.MacOS64;

interface

uses
  CSPRNG.Provider.Base, SysUtils, Classes, Posix.Base, Posix.Unistd, Posix.Fcntl, Posix.Errno;

type
  /// <summary>
  /// macOS (64-bit) implementation of the CSPRNG provider using platform entropy sources.
  /// </summary>
  TCSPRNGProviderMacOS64 = class(TCSPRNGProviderBase)
  protected
    /// <summary>
    /// Seeds the CSPRNG using the provided byte array.
    /// </summary>
    procedure SeedFromBytes(const SeedData: TBytes); override;

    /// <summary>
    /// Seeds the CSPRNG using the platform's entropy source (/dev/urandom).
    /// </summary>
    procedure SeedFromEntropySource; override;

    /// <summary>
    /// Generates a specified number of cryptographically secure random bytes using /dev/urandom.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

{ TCSPRNGProviderMacOS64 }

procedure TCSPRNGProviderMacOS64.SeedFromBytes(const SeedData: TBytes);
begin
  // Like on Linux, custom seeding is generally not necessary or supported.
  raise Exception.Create('Custom seeding is not supported for the macOS provider');
end;

procedure TCSPRNGProviderMacOS64.SeedFromEntropySource;
begin
  // On macOS, no extra action is needed since /dev/urandom provides entropy.
end;

function TCSPRNGProviderMacOS64.GetBytes(const Count: Integer): TBytes;
var
  FileStream: TFileStream;
  BytesRead: Integer;
begin
  SetLength(Result, Count);

  // Open /dev/urandom as a file stream on macOS to get random bytes
  FileStream := TFileStream.Create('/dev/urandom', fmOpenRead);
  try
    BytesRead := FileStream.Read(Result[0], Count);
    if BytesRead <> Count then
      raise Exception.Create('Unable to read sufficient random bytes from /dev/urandom on macOS');
  finally
    FileStream.Free;
  end;
end;

end.

