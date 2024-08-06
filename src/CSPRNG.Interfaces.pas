unit CSPRNG.Interfaces;

interface

uses SysUtils;

type
  ICSPRNGProvider = interface
    /// <summary>
    /// Seeds the CSPRNG using the provided byte array.
    /// </summary>
    procedure SeedFromBytes(const SeedData: TBytes); overload;

    /// <summary>
    /// Seeds the CSPRNG using an entropy source (e.g., RDRAND, RDSEED, or platform-specific sources).
    /// </summary>
    procedure SeedFromEntropySource; overload;

    /// <summary>
    /// Generates a specified number of cryptographically secure random bytes.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 32-bit integer.
    /// </summary>
    function GetUInt32(max: UInt32 = High(UInt32)): UInt32;

    /// <summary>
    /// Generates a cryptographically secure random signed 32-bit integer.
    /// </summary>
    function GetInt32(max: Int32 = High(Int32)): Int32;

    /// <summary>
    /// Generates a cryptographically secure random signed 64-bit integer.
    /// </summary>
    function GetInt64(max: Int64 = High(Int64)): Int64;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 64-bit integer.
    /// </summary>
    function GetUInt64(max: UInt64 = High(UInt64)): UInt64;

    /// <summary>
    /// Generates a cryptographically secure random float between 0 and 1
    /// </summary>
    function GetFloat: Double;

    function GetBase64(len: Integer = 1024): String;
  end;


implementation

end.
