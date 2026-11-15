# DieCloud 5.0 (Windows Edition) Build Script
$ErrorActionPreference = "Stop"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "       DieCloud 5.0 (Windows Edition) Build Script      " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Check for .NET SDK
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error ".NET SDK 8.0+ not found! Please install it from https://dotnet.microsoft.com/download"
    exit 1
}

# 2. Prepare Xray-core
$xrayExe = Join-Path "resources" "xray-windows-64.exe"
if (-not (Test-Path $xrayExe)) {
    Write-Host "[INFO] Downloading Xray-core v26.3.27 for Windows..." -ForegroundColor Yellow
    $zipPath = "resources\xray.zip"
    $tmpDir = "resources\xray_tmp"
    Invoke-WebRequest -Uri "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-windows-64.zip" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
    Copy-Item -Path "$tmpDir\xray.exe" -Destination $xrayExe -Force
    Remove-Item -Recurse -Force $tmpDir
    Remove-Item -Force $zipPath
}

# 3. Compile Single-File Executable
Write-Host "[INFO] Publishing DieCloud 5.0 (win-x64, Self-Contained)..." -ForegroundColor Green
dotnet publish DieCloud.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o build\

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [SUCCESS] DieCloud 5.0 built: build\DieCloud.exe" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
