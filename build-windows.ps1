# ==============================================================================
# fswatch Windows Build Helper (PowerShell)
# Invokes MSYS2 UCRT64 environment to run build-windows.sh
# ==============================================================================
param(
    [string]$MsysRoot = "C:\msys64",
    [string]$BuildType = "Release"
)

$ErrorActionPreference = "Stop"

$bashPath = Join-Path $MsysRoot "usr\bin\bash.exe"
if (-not (Test-Path $bashPath)) {
    Write-Error "MSYS2 bash not found at $bashPath. Please check -MsysRoot parameter."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPosix = "/" + ($scriptDir -replace "\\", "/").Replace(":", "")

Write-Host "Starting fswatch build via MSYS2 UCRT64..." -ForegroundColor Cyan
& (Join-Path $MsysRoot "usr\bin\env.exe") MSYSTEM=UCRT64 CHERE_INVOKING=1 $bashPath -lc "$scriptPosix/build-windows.sh $BuildType"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild succeeded! Artifacts are in $scriptDir\dist\" -ForegroundColor Green
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
}
