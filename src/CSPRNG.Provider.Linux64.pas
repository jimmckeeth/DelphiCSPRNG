unit CSPRNG.Provider.Linux64;

interface

{$IFDEF POSIX}

uses
  CSPRNG.Provider.Base, SysUtils, Classes, Posix.Base, Posix.Unistd, Posix.Fcntl, Posix.Errno;

type
  /// <summary>
  /// Linux (64-bit) implementation of the CSPRNG provider using platform entropy sources.
  /// </summary>
  TCSPRNGProviderLinux64 = class(TCSPRNGProviderBase)
  protected
    /// <summary>
    /// Generates a specified number of cryptographically secure random bytes using /dev/urandom.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

{ TCSPRNGProviderLinux64 }

function TCSPRNGProviderLinux64.GetBytes(const Count: Integer): TBytes;
var
  FileStream: TFileStream;
  BytesRead: Integer;
begin
  SetLength(Result, Count);

  // Open /dev/urandom as a file stream
  FileStream := TFileStream.Create('/dev/urandom', fmOpenRead);
  try
    BytesRead := FileStream.Read(Result[0], Count);
    if BytesRead <> Count then
      raise Exception.Create('Unable to read sufficient random bytes from /dev/urandom');
  finally
    FileStream.Free;
  end;
end;

{$ELSE}
implementation
{$ENDIF}

end.


