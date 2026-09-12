#!/usr/bin/env bash
# ==============================================================================
# fswatch Windows MSYS2 (UCRT64) Compilation & SDK Packaging Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_TYPE="${1:-Release}"
INSTALL_DIR="${SCRIPT_DIR}/dist"
SDK_PKG_DIR="${INSTALL_DIR}/libfswatch-sdk"

echo "=== 1. Checking Environment ==="
echo "MSYSTEM: ${MSYSTEM:-unknown}"
if [[ "${MSYSTEM:-}" != "UCRT64" && "${MSYSTEM:-}" != "MINGW64" && "${MSYSTEM:-}" != "CLANG64" ]]; then
    echo "[WARNING] It is recommended to run this in MSYS2 UCRT64 environment."
fi

command -v gcc >/dev/null 2>&1 || { echo "[ERROR] gcc not found. Run: pacman -S mingw-w64-ucrt-x86_64-gcc"; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "[ERROR] cmake not found. Run: pacman -S mingw-w64-ucrt-x86_64-cmake"; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "[ERROR] ninja not found. Run: pacman -S mingw-w64-ucrt-x86_64-ninja"; exit 1; }

# Check and apply Windows compatibility patch if needed
if [[ -f "patches/01-windows-signal-handler.patch" ]] && git apply --check patches/01-windows-signal-handler.patch >/dev/null 2>&1; then
    echo "[INFO] Applying Windows signal compatibility patch..."
    git apply patches/01-windows-signal-handler.patch
fi

echo "=== 2. Configuring and Building Standalone Static Executable ==="
cmake -B build-standalone -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_EXE_LINKER_FLAGS="-static" \
    -DUSE_NLS=OFF \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/standalone"

cmake --build build-standalone
cmake --install build-standalone

echo "=== 3. Configuring and Building Shared Library (DLL) ==="
cmake -B build-shared -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/shared"

cmake --build build-shared
cmake --install build-shared

echo "=== 4. Configuring and Building Static Library (.a) ==="
cmake -B build-static -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}/static"

cmake --build build-static
cmake --install build-static

echo "=== 5. Generating MSVC Import Library (.lib) ==="
cd "${INSTALL_DIR}/shared"
gendef bin/libfswatch.dll
dlltool -d libfswatch.def -l lib/libfswatch.lib -D libfswatch.dll
cd "$SCRIPT_DIR"

echo "=== 6. Packaging libfswatch SDK (bin/ lib/ include/) ==="
rm -rf "${SDK_PKG_DIR}"
mkdir -p "${SDK_PKG_DIR}/bin" "${SDK_PKG_DIR}/lib" "${SDK_PKG_DIR}/include"

# 1. Copy headers to include/
cp -rf "${INSTALL_DIR}/shared/include/"* "${SDK_PKG_DIR}/include/"

# 2. Copy libraries to lib/
cp -f "${INSTALL_DIR}/shared/lib/libfswatch.lib" "${SDK_PKG_DIR}/lib/"
cp -f "${INSTALL_DIR}/shared/lib/liblibfswatch.dll.a" "${SDK_PKG_DIR}/lib/"
cp -f "${INSTALL_DIR}/static/lib/libfswatch.a" "${SDK_PKG_DIR}/lib/"
if [[ -d "${INSTALL_DIR}/shared/lib/cmake" ]]; then
    cp -rf "${INSTALL_DIR}/shared/lib/cmake" "${SDK_PKG_DIR}/lib/"
fi

# 3. Copy binaries and DLL dependencies to bin/
cp -f "${INSTALL_DIR}/shared/bin/libfswatch.dll" "${SDK_PKG_DIR}/bin/"
cp -f "${INSTALL_DIR}/standalone/bin/fswatch.exe" "${SDK_PKG_DIR}/bin/"

# Copy runtime DLLs from toolchain if present
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll libintl-8.dll libiconv-2.dll; do
    if [[ -f "/ucrt64/bin/${dll}" ]]; then
        cp -f "/ucrt64/bin/${dll}" "${SDK_PKG_DIR}/bin/"
    elif [[ -f "/mingw64/bin/${dll}" ]]; then
        cp -f "/mingw64/bin/${dll}" "${SDK_PKG_DIR}/bin/"
    fi
done

echo "=== 7. Verifying Output ==="
"${SDK_PKG_DIR}/bin/fswatch.exe" --version
"${SDK_PKG_DIR}/bin/fswatch.exe" -M

echo ""
echo "=============================================================================="
echo "  libfswatch SDK Package Successfully Created at: ${SDK_PKG_DIR}"
echo "=============================================================================="
echo "Package directory layout:"
ls -lh "${SDK_PKG_DIR}/bin"
ls -lh "${SDK_PKG_DIR}/lib"
ls -lh "${SDK_PKG_DIR}/include"
