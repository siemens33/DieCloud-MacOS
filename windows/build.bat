@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo        DieCloud 5.0 (Windows Edition) Build Script
echo ========================================================
echo.

REM 1. Check for .NET SDK
where dotnet >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] .NET SDK 8.0+ not found in PATH!
    echo Please install .NET 8.0 SDK from https://dotnet.microsoft.com/download
    exit /b 1
)

REM 2. Prepare Xray-core for Windows
set "XRAY_DIR=resources"
set "XRAY_EXE=%XRAY_DIR%\xray-windows-64.exe"
if not exist "%XRAY_EXE%" (
    echo [INFO] Downloading Xray-core v26.3.27 for Windows...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-windows-64.zip' -OutFile 'resources\xray.zip'"
    powershell -Command "Expand-Archive -Path 'resources\xray.zip' -DestinationPath 'resources\xray_tmp' -Force"
    copy /Y "resources\xray_tmp\xray.exe" "%XRAY_EXE%" >nul
    rmdir /S /Q "resources\xray_tmp"
    del /Q "resources\xray.zip"
)

REM 3. Compile Single-File Executable
echo [INFO] Compiling DieCloud 5.0 (Release, win-x64, Self-Contained)...
dotnet publish DieCloud.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o build\

if %errorlevel% equ 0 (
    echo.
    echo ========================================================
    echo  [SUCCESS] DieCloud 5.0 built successfully!
    echo  Binary: build\DieCloud.exe
    echo ========================================================
) else (
    echo.
    echo [ERROR] Compilation failed. See logs above.
    exit /b 1
)
