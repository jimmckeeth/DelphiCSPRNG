unit Holon.CSRNG.Interfaces;

interface

uses SysUtils;

type
  /// <summary>
  /// Raised for CSPRNG-specific errors, such as the platform's random number source
  /// failing or an invalid parameter (e.g. a negative byte count). Catch this instead of
  /// the generic Exception to distinguish CSPRNG failures from unrelated errors.
  /// </summary>
  ECSPRNGError = class(Exception);

  /// <summary>
  /// Cross-platform interface to a cryptographically secure pseudo-random number generator.
  /// Obtain an instance via Holon.CSRNG.GetCSPRNGProvider, which selects the correct
  /// platform-specific implementation (Windows CNG, /dev/urandom or getrandom(2) on
  /// Linux/Android, or the Security framework on macOS/iOS) at compile time.
  /// </summary>
  ICSPRNGProvider = interface
    /// <summary>
    /// Generates the specified number of cryptographically secure random bytes.
    /// </summary>
    function GetBytes(const Count: Integer): TBytes;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 32-bit integer in the
    /// range [0, max].
    /// </summary>
    function GetUInt32(const max: UInt32 = High(UInt32)): UInt32;

    /// <summary>
    /// Generates a cryptographically secure random 32-bit integer in the range [0, max].
    /// Note that despite the "signed" type, this never returns a negative value; max
    /// must be zero or greater.
    /// </summary>
    function GetInt32(const max: Int32 = High(Int32)): Int32;

    /// <summary>
    /// Generates a cryptographically secure random 64-bit integer in the range [0, max].
    /// Note that despite the "signed" type, this never returns a negative value; max
    /// must be zero or greater.
    /// </summary>
    function GetInt64(const max: Int64 = High(Int64)): Int64;

    /// <summary>
    /// Generates a cryptographically secure random unsigned 64-bit integer in the
    /// range [0, max].
    /// </summary>
    function GetUInt64(const max: UInt64 = High(UInt64)): UInt64;

    /// <summary>
    /// Generates a cryptographically secure random Double in the range [0, 1).
    /// </summary>
    function GetFloat: Double;

    /// <summary>
    /// Generates len cryptographically secure random bytes and returns them
    /// Base64-encoded. Note that len is the number of source bytes, not the length
    /// of the resulting string.
    /// </summary>
    function GetBase64(const len: Integer = 1024): String;
  end;


implementation

end.
