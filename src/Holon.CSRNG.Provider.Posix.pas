unit Holon.CSRNG.Provider.Posix;

interface

{$IFDEF POSIX}

uses
  Holon.CSRNG.Provider.Base, Holon.CSRNG.Interfaces, SysUtils, Classes;

type
  /// <summary>
  /// Generic POSIX implementation of the CSPRNG provider, reading directly from
  /// /dev/urandom. Used as-is for Android. Linux64 uses Holon.CSRNG.Provider.Linux's
  /// TCSPRNGProviderLinux instead, which descends from this class and adds a
  /// getrandom(2) fast path ahead of the /dev/urandom fallback implemented here.
  /// </summary>
  TCSPRNGProviderPosix = class(TCSPRNGProviderBase)
  protected
    /// <summary>
    /// Generates cryptographically secure random bytes by reading /dev/urandom, which is
    /// world-readable without any special permission and is Android's own recommended
    /// approach for native code (Android's getrandom() libc wrapper is only available
    /// from API level 28 onward, so /dev/urandom remains the more broadly compatible
    /// choice here).
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

{ TCSPRNGProviderPosix }

function TCSPRNGProviderPosix.GetBytes(const Count: Integer): TBytes;
var
  FileStream: TFileStream;
begin
  if Count < 0 then
    raise ECSPRNGError.Create('Count must be zero or greater');

  SetLength(Result, Count);
  if Count = 0 then
    Exit; // Nothing to fill, and Result[0] would be an out-of-bounds access below.

  FileStream := TFileStream.Create('/dev/urandom', fmOpenRead);
  try
    if FileStream.Read(Result[0], Count) <> Count then
      raise ECSPRNGError.Create('Unable to read sufficient random bytes from /dev/urandom');
  finally
    FileStream.Free;
  end;
end;

{$ELSE}
implementation
{$ENDIF}

end.
