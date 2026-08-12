@echo off
REM build.cmd - 5EPlay NoBrandSplash dylib builder (Windows)
REM
REM Toolchain (verified on this machine):
REM   clang 20.1.8     D:\OPENCODE\tools\clang+llvm-20.1.8-x86_64-pc-windows-msvc\bin\clang.exe
REM   ld64.lld 20.1.8  same dir
REM   iPhoneOS16.5.sdk D:\OPENCODE\tools\iPhoneOS16.5.sdk
REM
REM Usage: build.cmd
REM Output: out\NoBrandSplash.dylib

setlocal
set "LLVM=D:\OPENCODE\tools\clang+llvm-20.1.8-x86_64-pc-windows-msvc\bin"
set "SDK=D:\OPENCODE\tools\iPhoneOS16.5.sdk"
set "SRC=src\hook.m"
set "OUT=out\NoBrandSplash.dylib"

if not exist out mkdir out

echo [*] Compiling %SRC% -^> %OUT% (arm64)

"%LLVM%\clang.exe" ^
  -target arm64-apple-ios16.5 ^
  -arch arm64 ^
  -isysroot "%SDK%" ^
  -fobjc-arc ^
  -fno-stack-protector ^
  -fvisibility=hidden ^
  -fuse-ld=lld ^
  -dynamiclib ^
  -undefined dynamic_lookup ^
  -o "%OUT%" ^
  "%SRC%"

if errorlevel 1 (
  echo [^!] clang failed
  exit /b 1
)

echo [*] Verifying Mach-O structure...
python "%~dp0tools\check_macho.py" "%OUT%"
if errorlevel 1 (
  echo [^!] Structure check FAILED - do NOT inject this dylib.
  exit /b 1
)

echo [*] OK: %OUT% ready for TrollFools injection
endlocal
