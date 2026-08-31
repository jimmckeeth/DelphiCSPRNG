unit CSPRNG.Provider.Linux;

interface

{$IFDEF LINUX}

uses
  SysUtils, CSPRNG.Interfaces, CSPRNG.Provider.Posix;

type
  /// <summary>
  /// Linux64 implementation of the CSPRNG provider. Descends from TCSPRNGProviderPosix
  /// purely to reuse its /dev/urandom implementation as a fallback; this override tries
  /// the modern getrandom(2) syscall first, which Android does not get (see
  /// CSPRNG.Provider.Posix for why), keeping platform-specific behavior out of the
  /// shared Android/generic-POSIX unit.
  /// </summary>
  TCSPRNGProviderLinux = class(TCSPRNGProviderPosix)
  protected
    /// <summary>
    /// Generates cryptographically secure random bytes, preferring the getrandom(2)
    /// syscall (Linux kernel 3.17+ / glibc 2.25+), which - unlike reading /dev/urandom
    /// directly - blocks until the kernel's CSPRNG is fully seeded, and does not depend
    /// on /dev being mounted (relevant in minimal containers/chroots). Falls back to the
    /// inherited /dev/urandom implementation if the kernel doesn't support getrandom
    /// (pre-3.17) or the call fails.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

function getrandom(Buf: Pointer; BufLen: NativeUInt; Flags: Cardinal): NativeInt; cdecl;
  external 'libc.so.6' name 'getrandom';

{ TCSPRNGProviderLinux }

function TCSPRNGProviderLinux.GetBytes(const Count: Integer): TBytes;
begin
  if Count < 0 then
    raise ECSPRNGError.Create('Count must be zero or greater');

  SetLength(Result, Count);
  if Count = 0 then
    Exit;

  if getrandom(@Result[0], NativeUInt(Count), 0) = Count then
    Exit;

  // Fall back to /dev/urandom if the kernel doesn't support getrandom (pre-3.17) or the
  // call was interrupted/incomplete.
  Result := inherited GetBytes(Count);
end;

{$ELSE}
implementation
{$ENDIF}

end.
