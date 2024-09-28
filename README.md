# [DelphiCSPRNG](https://github.com/jimmckeeth/DelphiCSPRNG)
_A cross-platform Cryptographically-Secure Pseudo-Random Number Generator for Delphi_

I wanted an easy to use cross-platform random number generator that was more reliable than the built in Random. It is modular so you can just include the parts you want. Makes use of the platform secure random provider for each platform, with a common provider interface. I've only tested it on Win32, Win64, Android64, and Linux64. 

There are some basic tests and a sample app. Open to feedback, [issues](https://github.com/jimmckeeth/DelphiCSPRNG/issue) reports, and [pull requests](https://github.com/jimmckeeth/DelphiCSPRNG/fork). Especially if you want to test it on Apple hardware.

**Disclaimer**: _Make sure you understand any code before using it for anything important._ Just because I am calling this "Cryptographically-Secure" doesn't necessarily mean it is secure or suitable for cryptography.  

## Basic usage

```Delphi
uses CSPRNG, CSPRNG.Interfaces;

///
var rng: ICSPRNGProvider :=  GetCSPRNGProvider;
Writeln(rng.GetFloat);
Writeln(rng.GetUInt64);
Writeln(rng.GetBase64); 
```

## The provider interface

```Delphi
type 
  ICSPRNGProvider = interface
    // Generates a specified number of cryptographically secure random bytes.
    function GetBytes(const Count: Integer): TBytes;

    // Generates a cryptographically secure random unsigned 32-bit integer.
    function GetUInt32(const max: UInt32 = High(UInt32)): UInt32;

    // Generates a cryptographically secure random signed 32-bit integer.
    function GetInt32(const max: Int32 = High(Int32)): Int32;

    // Generates a cryptographically secure random signed 64-bit integer.
    function GetInt64(const max: Int64 = High(Int64)): Int64;

    // Generates a cryptographically secure random unsigned 64-bit integer.
    function GetUInt64(const max: UInt64 = High(UInt64)): UInt64;

    // Generates a cryptographically secure random float between 0 and 1
    function GetFloat: Double;

    // Generates a BASE64 encoded random string
    function GetBase64(const len: Integer = 1024): String;
  end;
```

Most of the functionality comes from the base implementation, with the platform specific implementation providing the **`GetBytes`** function.
