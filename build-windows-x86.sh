#!/usr/bin/env bash
# ==============================================================================
# fswatch Windows 32-bit (x86 / Win32) Compilation & SDK Packaging Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_TYPE="${1:-Release}"
INSTALL_DIR="${SCRIPT_DIR}/dist"
SDK_PKG_DIR="${INSTALL_DIR}/libfswatch-sdk-x86"

echo "=== 1. Checking Environment ==="
echo "MSYSTEM: ${MSYSTEM:-unknown}"
if [[ "${MSYSTEM:-}" != "MINGW32" ]]; then
    echo "[WARNING] It is recommended to run this in MSYS2 MINGW32 environment."
fi

command -v gcc >/dev/null 2>&1 || { echo "[ERROR] gcc not found. Run: pacman -S mingw-w64-i686-gcc"; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "[ERROR] cmake not found. Run: pacman -S mingw-w64-i686-cmake"; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "[ERROR] ninja not found. Run: pacman -S mingw-w64-i686-ninja"; exit 1; }

# Check and apply Windows compatibility patches
if [[ -f "patches/01-windows-signal-handler.patch" ]] && git apply --check patches/01-windows-signal-handler.patch >/dev/null 2>&1; then
    echo "[INFO] Applying Windows signal compatibility patch..."
    git apply patches/01-windows-signal-handler.patch
fi

if [[ -f "patches/02-win32-msvcrt-quick-exit.patch" ]] && git apply --check patches/02-win32-msvcrt-quick-exit.patch >/dev/null 2>&1; then
    echo "[INFO] Applying 32-bit quick_exit compatibility patch..."
    git apply patches/02-win32-msvcrt-quick-exit.patch
fi

echo "=== 2. Configuring and Building 32-bit Shared Library (DLL) ==="
cmake -B build-win32-shared -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/win32-shared"

cmake --build build-win32-shared
cmake --install build-win32-shared

echo "=== 3. Configuring and Building 32-bit Static Library (.a) ==="
cmake -B build-win32-static -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/win32-static"

cmake --build build-win32-static
cmake --install build-win32-static

echo "=== 4. Generating 32-bit MSVC Import Library (.lib) ==="
cd "${INSTALL_DIR}/win32-shared"
gendef bin/libfswatch.dll
dlltool -m i386 -d libfswatch.def -l lib/libfswatch.lib -D libfswatch.dll
cd "$SCRIPT_DIR"

echo "=== 5. Packaging 32-bit libfswatch SDK (bin/ lib/ include/) ==="
rm -rf "${SDK_PKG_DIR}"
mkdir -p "${SDK_PKG_DIR}/bin" "${SDK_PKG_DIR}/lib" "${SDK_PKG_DIR}/include"

# 1. Copy headers to include/
cp -rf "${INSTALL_DIR}/win32-shared/include/"* "${SDK_PKG_DIR}/include/"

# 2. Copy libraries to lib/
cp -f "${INSTALL_DIR}/win32-shared/lib/libfswatch.lib" "${SDK_PKG_DIR}/lib/"
cp -f "${INSTALL_DIR}/win32-shared/lib/liblibfswatch.dll.a" "${SDK_PKG_DIR}/lib/"
cp -f "${INSTALL_DIR}/win32-static/lib/libfswatch.a" "${SDK_PKG_DIR}/lib/"
if [[ -d "${INSTALL_DIR}/win32-shared/lib/cmake" ]]; then
    cp -rf "${INSTALL_DIR}/win32-shared/lib/cmake" "${SDK_PKG_DIR}/lib/"
fi

# 3. Copy binaries and DLL dependencies to bin/
cp -f "${INSTALL_DIR}/win32-shared/bin/libfswatch.dll" "${SDK_PKG_DIR}/bin/"
cp -f "${INSTALL_DIR}/win32-shared/bin/fswatch.exe" "${SDK_PKG_DIR}/bin/"

# Copy 32-bit runtime DLLs from mingw32/bin if present
for dll in libgcc_s_dw2-1.dll libgcc_s_sjlj-1.dll libstdc++-6.dll libwinpthread-1.dll libintl-8.dll libiconv-2.dll; do
    if [[ -f "/mingw32/bin/${dll}" ]]; then
        cp -f "/mingw32/bin/${dll}" "${SDK_PKG_DIR}/bin/"
    fi
done

echo ""
echo "=============================================================================="
echo "  32-bit libfswatch SDK Package Successfully Created at: ${SDK_PKG_DIR}"
echo "=============================================================================="
ls -lh "${SDK_PKG_DIR}/bin"
ls -lh "${SDK_PKG_DIR}/lib"
ls -lh "${SDK_PKG_DIR}/include"
