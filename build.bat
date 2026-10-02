@echo off
rem Builds filedirs.exe (Win32) with Free Pascal 3.2.2.
setlocal
cd /d "%~dp0"
if not exist build mkdir build
fpc -Twin32 -Pi386 -O2 -Xs -XX -CX -FUbuild -FE. filedirs.pas
