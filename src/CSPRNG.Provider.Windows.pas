unit CSPRNG.Provider.Windows;

interface

{$IFDEF MSWINDOWS}

uses
  System.SysUtils,
  Winapi.Windows,
  CSPRNG.Interfaces,
  CSPRNG.Provider.Base;

type
  BCRYPT_ALG_HANDLE = PVOID;
  TWindowsCSPRNGProvider = class(TCSPRNGProviderBase, ICSPRNGProvider)
  private
    FHandle: BCRYPT_ALG_HANDLE;
    FSeedData: TBytes;
    procedure SeedFromEntropySource;           // Add a field to store the seed

  public
    constructor Create;
    destructor Destroy; override;

    // ICSPRNGProvider implementation
    function GetBytes(const Count: Integer): TBytes; override;
  end;

implementation

uses
  System.Math;

const
  BCRYPT_RNG_ALGORITHM = 'RNG';
  BCRYPT_RNG_USE_ENTROPY_IN_BUFFER = $00000001;

type
  PBCRYPT_ALG_HANDLE = ^BCRYPT_ALG_HANDLE;

function BCryptOpenAlgorithmProvider(phAlgorithm: PBCRYPT_ALG_HANDLE;
  pszAlgId: LPCWSTR; pszImplementation: LPCWSTR; dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

function BCryptCloseAlgorithmProvider(hAlgorithm: BCRYPT_ALG_HANDLE;
  dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

function BCryptGenRandom(hAlgorithm: BCRYPT_ALG_HANDLE; pbBuffer: PBYTE;
  cbBuffer: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

const
  STATUS_SUCCESS = 0; // NTSTATUS Success value


{ TWindowsCSPRNGProvider }

constructor TWindowsCSPRNGProvider.Create;
begin
  inherited Create;
  if BCryptOpenAlgorithmProvider(@FHandle, BCRYPT_RNG_ALGORITHM, nil, 0) <> STATUS_SUCCESS then
    raise Exception.Create('Failed to open BCrypt RNG provider');

  SeedFromEntropySource();
end;

destructor TWindowsCSPRNGProvider.Destroy;
begin
  BCryptCloseAlgorithmProvider(FHandle, 0);
  inherited;
end;

procedure TWindowsCSPRNGProvider.SeedFromEntropySource;
begin
  // Use the default system-provided entropy
  BCryptGenRandom(FHandle, nil, 0, 0);
end;

function TWindowsCSPRNGProvider.GetBytes(const Count: Integer): TBytes;
var
  pBytes: PByte;
begin
  SetLength(Result, Count);
  pBytes := PByte(Result);
  if BCryptGenRandom(FHandle, pBytes, Count, 0) <> STATUS_SUCCESS then
    raise Exception.Create('Failed to generate random bytes');
end;
{$ELSE}
implementation
{$ENDIF}

end.

