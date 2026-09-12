@echo off
setlocal enabledelayedexpansion

echo ==============================================================================
echo   fswatch C++ Demo Build Script (MSVC v142 Toolset)
echo ==============================================================================

set "FULL_DIR=%~dp0"
set "SCRIPT_DIR=%FULL_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "MSYS_ROOT=C:\msys64"
set "FSWATCH_ROOT=%ROOT_DIR%\dist\shared"
set "OUTPUT_BIN_DIR=%SCRIPT_DIR%\bin"
set "BUILD_DIR=%SCRIPT_DIR%\build-msvc"

:: -----------------------------------------------------------------------------
:: Step 1: Ensure libfswatch.dll and libfswatch.lib exist
:: -----------------------------------------------------------------------------
if not exist "%FSWATCH_ROOT%\bin\libfswatch.dll" (
    echo [INFO] libfswatch.dll not found. Building libfswatch via MSYS2 UCRT64...
    if not exist "%MSYS_ROOT%\usr\bin\bash.exe" (
        echo [ERROR] MSYS2 bash not found at %MSYS_ROOT%\usr\bin\bash.exe
        exit /b 1
    )
    "%MSYS_ROOT%\usr\bin\env.exe" MSYSTEM=UCRT64 CHERE_INVOKING=1 "%MSYS_ROOT%\usr\bin\bash.exe" -lc "./build-windows.sh Release"
)

if not exist "%FSWATCH_ROOT%\lib\libfswatch.lib" (
    echo [INFO] Generating MSVC import library libfswatch.lib via gendef and dlltool...
    "%MSYS_ROOT%\usr\bin\env.exe" MSYSTEM=UCRT64 CHERE_INVOKING=1 "%MSYS_ROOT%\usr\bin\bash.exe" -lc "cd dist/shared && gendef bin/libfswatch.dll && dlltool -d libfswatch.def -l lib/libfswatch.lib -D libfswatch.dll"
)

if not exist "%FSWATCH_ROOT%\lib\libfswatch.lib" (
    echo [ERROR] Failed to locate or generate %FSWATCH_ROOT%\lib\libfswatch.lib
    exit /b 1
)

echo [OK] Found libfswatch import library: %FSWATCH_ROOT%\lib\libfswatch.lib

:: -----------------------------------------------------------------------------
:: Step 2: Configure and build Demo with CMake specifying v142 toolset
:: -----------------------------------------------------------------------------
echo.
echo [INFO] Configuring CMake with MSVC v142 toolset (-T v142)...

set "CMAKE_GEN=Visual Studio 16 2019"
set "VSWHERE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if exist "%VSWHERE_EXE%" (
    for /f "usebackq tokens=*" %%i in (`^""%VSWHERE_EXE%" -version "[16.0,17.0)" -property installationPath^"`) do (
        set "VS2019_PATH=%%i"
    )
    if not defined VS2019_PATH (
        for /f "usebackq tokens=*" %%i in (`^""%VSWHERE_EXE%" -version "[17.0,18.0)" -property installationPath^"`) do (
            set "VS2022_PATH=%%i"
        )
        if defined VS2022_PATH (
            echo [INFO] Detected VS2022, targeting v142 toolset.
            set "CMAKE_GEN=Visual Studio 17 2022"
        )
    )
)

echo [INFO] Using CMake Generator: %CMAKE_GEN% with toolset: v142

cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" -G "%CMAKE_GEN%" -A x64 -T v142 -DFSWATCH_ROOT="%FSWATCH_ROOT%"
if errorlevel 1 (
    echo [ERROR] CMake configuration failed.
    exit /b 1
)

echo.
echo [INFO] Building Release configuration...
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)

:: -----------------------------------------------------------------------------
:: Step 3: Collect Executable and all runtime DLL dependencies
:: -----------------------------------------------------------------------------
echo.
echo [INFO] Collecting binary and runtime DLL dependencies into bin/...

if not exist "%OUTPUT_BIN_DIR%" mkdir "%OUTPUT_BIN_DIR%"

:: Copy compiled demo executable
if exist "%BUILD_DIR%\Release\fswatch_cpp_demo.exe" (
    copy /Y "%BUILD_DIR%\Release\fswatch_cpp_demo.exe" "%OUTPUT_BIN_DIR%\" >nul
) else if exist "%BUILD_DIR%\fswatch_cpp_demo.exe" (
    copy /Y "%BUILD_DIR%\fswatch_cpp_demo.exe" "%OUTPUT_BIN_DIR%\" >nul
)

:: Copy libfswatch.dll
copy /Y "%FSWATCH_ROOT%\bin\libfswatch.dll" "%OUTPUT_BIN_DIR%\" >nul

:: Copy runtime DLLs from MSYS2 UCRT64
set "UCRT_BIN=%MSYS_ROOT%\ucrt64\bin"
copy /Y "%UCRT_BIN%\libgcc_s_seh-1.dll" "%OUTPUT_BIN_DIR%\" >nul 2>&1
copy /Y "%UCRT_BIN%\libstdc++-6.dll" "%OUTPUT_BIN_DIR%\" >nul 2>&1
copy /Y "%UCRT_BIN%\libwinpthread-1.dll" "%OUTPUT_BIN_DIR%\" >nul 2>&1
copy /Y "%UCRT_BIN%\libintl-8.dll" "%OUTPUT_BIN_DIR%\" >nul 2>&1
copy /Y "%UCRT_BIN%\libiconv-2.dll" "%OUTPUT_BIN_DIR%\" >nul 2>&1

echo.
echo ==============================================================================
echo   Build and Dependency Collection Succeeded!
echo ==============================================================================
echo Output directory: %OUTPUT_BIN_DIR%
echo.
dir /B "%OUTPUT_BIN_DIR%"
echo.
echo Run the demo with:
echo   "%OUTPUT_BIN_DIR%\fswatch_cpp_demo.exe" .
echo ==============================================================================
