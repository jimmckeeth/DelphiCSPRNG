unit Holon.SecureMemory.Platform;

{
  Low-level, page-granular memory primitives used by Holon.SecureMemory to build
  guarded, swap-locked allocations. Every routine here is a thin wrapper around a
  single platform API (VirtualAlloc/mmap and friends) and fails soft: allocation
  failures return nil/False rather than raising, so Holon.SecureMemory can decide
  how to react (e.g. treat a failed mlock as reduced hardening rather than a hard
  error - see the "graceful degradation" note in the design plan, since
  RLIMIT_MEMLOCK is commonly as low as 64 KB and is tighter still on Android/iOS).
}

interface

uses
  System.SysUtils
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF}
  {$IFDEF POSIX}
  , Posix.Base
  , Posix.SysTypes
  , Posix.SysMman
  {$ENDIF}
  ;

/// <summary>
/// Returns the platform's memory page size in bytes. Allocation sizes passed to
/// the other routines in this unit must be a multiple of this value.
/// </summary>
function GetPageSize: NativeUInt;

/// <summary>
/// Reserves and commits Size bytes (must be a multiple of GetPageSize) as a fresh,
/// page-aligned, anonymous, readable/writable mapping - never backed by a file and
/// never shared with a child process across fork/exec. Returns nil on failure.
/// </summary>
function AllocPages(const Size: NativeUInt): Pointer;

/// <summary>
/// Releases a mapping previously returned by AllocPages. Size must match the value
/// originally passed to AllocPages.
/// </summary>
function FreePages(const P: Pointer; const Size: NativeUInt): Boolean;

/// <summary>
/// Makes the Size bytes at P completely inaccessible (any read, write, or execute
/// attempt faults the process). P and Size must both be page-aligned.
/// </summary>
function ProtectNone(const P: Pointer; const Size: NativeUInt): Boolean;

/// <summary>
/// Makes the Size bytes at P readable and writable (but not executable). P and Size
/// must both be page-aligned.
/// </summary>
function ProtectReadWrite(const P: Pointer; const Size: NativeUInt): Boolean;

/// <summary>
/// Best-effort request to lock the Size bytes at P into physical memory so they are
/// never written to swap/the pagefile. Returns False, without raising, if the
/// platform refuses - most commonly because the process's mlock budget
/// (RLIMIT_MEMLOCK on POSIX, the working-set-based limit VirtualLock enforces on
/// Windows) is exhausted. Callers must treat this as reduced hardening, not a fatal
/// error: locking is a hardening measure layered on top of the guard-page/wipe
/// protection this unit provides, not a correctness requirement.
/// </summary>
function LockPages(const P: Pointer; const Size: NativeUInt): Boolean;

/// <summary>
/// Releases a lock previously taken by LockPages. Safe to call even if LockPages
/// returned False (i.e. nothing was actually locked).
/// </summary>
procedure UnlockPages(const P: Pointer; const Size: NativeUInt);

/// <summary>
/// Best-effort request to exclude the Size bytes at P from crash dumps / core
/// dumps. Silently does nothing where the current platform offers no such
/// mechanism (every POSIX target except Linux) or the API is unavailable (Windows
/// versions before Windows 10). Never raises.
/// </summary>
procedure ExcludeFromDump(const P: Pointer; const Size: NativeUInt);

implementation

{$IFDEF MSWINDOWS}

function GetPageSize: NativeUInt;
var
  SysInfo: TSystemInfo;
begin
  GetSystemInfo(SysInfo);
  Result := SysInfo.dwPageSize;
end;

function AllocPages(const Size: NativeUInt): Pointer;
begin
  Result := VirtualAlloc(nil, Size, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
end;

function FreePages(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  // Size is ignored: MEM_RELEASE requires releasing the entire allocation that was
  // originally reserved, which VirtualFree tracks internally from the base address.
  Result := VirtualFree(P, 0, MEM_RELEASE);
end;

function ProtectNone(const P: Pointer; const Size: NativeUInt): Boolean;
var
  OldProtect: DWORD;
begin
  Result := VirtualProtect(P, Size, PAGE_NOACCESS, OldProtect);
end;

function ProtectReadWrite(const P: Pointer; const Size: NativeUInt): Boolean;
var
  OldProtect: DWORD;
begin
  Result := VirtualProtect(P, Size, PAGE_READWRITE, OldProtect);
end;

function LockPages(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  Result := VirtualLock(P, Size);
end;

procedure UnlockPages(const P: Pointer; const Size: NativeUInt);
begin
  VirtualUnlock(P, Size);
end;

type
  TWerRegisterExcludedMemoryBlock = function(Address: Pointer; Size: DWORD): HRESULT; stdcall;

var
  WerFuncResolved: Boolean;
  WerRegisterExcludedMemoryBlockProc: TWerRegisterExcludedMemoryBlock;

procedure ExcludeFromDump(const P: Pointer; const Size: NativeUInt);
var
  Kernel32Handle: HMODULE;
begin
  // WerRegisterExcludedMemoryBlock is Windows 10+ only and not declared in older
  // Winapi.Windows headers, so it's resolved dynamically, once, and cached; a
  // process linked against an older SDK still runs fine on Windows 10+, and this
  // is a no-op (not a failure) on any Windows version that lacks the API.
  if not WerFuncResolved then
  begin
    Kernel32Handle := GetModuleHandle('kernel32.dll');
    if Kernel32Handle <> 0 then
      WerRegisterExcludedMemoryBlockProc := TWerRegisterExcludedMemoryBlock(
        GetProcAddress(Kernel32Handle, 'WerRegisterExcludedMemoryBlock'));
    WerFuncResolved := True;
  end;
  if Assigned(WerRegisterExcludedMemoryBlockProc) then
    WerRegisterExcludedMemoryBlockProc(P, DWORD(Size)); // best-effort; result ignored
end;

{$ENDIF}

{$IFDEF POSIX}

{$WARN SYMBOL_PLATFORM OFF} // MAP_ANONYMOUS is marked `platform`; every target we build for has it.

const
  // Linux-specific madvise() advice value; not exposed by Delphi's Posix headers
  // because it has no equivalent on the other POSIX targets (macOS, iOS, Android).
  MADV_DONTDUMP = 16;

// Not declared anywhere in Delphi's Posix.* units. getpagesize() is used instead of
// sysconf(_SC_PAGESIZE) because the numeric value of _SC_PAGESIZE itself differs
// across POSIX C libraries (glibc vs. Bionic vs. Darwin's libc), and Delphi's headers
// only supply that constant for some of them; getpagesize() takes no arguments, so
// there is no platform-specific value to get wrong. Named libc_getpagesize, not
// getpagesize, because Delphi identifiers are case-insensitive and that name would
// otherwise collide with GetPageSize below.
function libc_getpagesize: Integer; cdecl; external libc name _PU + 'getpagesize';

function GetPageSize: NativeUInt;
begin
  Result := NativeUInt(libc_getpagesize);
end;

function AllocPages(const Size: NativeUInt): Pointer;
begin
  Result := mmap(nil, Size, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if Result = MAP_FAILED then
    Result := nil;
end;

function FreePages(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  Result := munmap(P, Size) = 0;
end;

function ProtectNone(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  Result := mprotect(P, Size, PROT_NONE) = 0;
end;

function ProtectReadWrite(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  Result := mprotect(P, Size, PROT_READ or PROT_WRITE) = 0;
end;

function LockPages(const P: Pointer; const Size: NativeUInt): Boolean;
begin
  Result := mlock(P, Size) = 0;
end;

procedure UnlockPages(const P: Pointer; const Size: NativeUInt);
begin
  munlock(P, Size);
end;

procedure ExcludeFromDump(const P: Pointer; const Size: NativeUInt);
begin
  {$IFDEF LINUX}
  madvise(P, Size, MADV_DONTDUMP); // best-effort; result ignored
  {$ENDIF}
  // No equivalent exists on Android, macOS, or iOS - silently a no-op there.
end;

{$ENDIF}

end.
