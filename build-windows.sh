#!/usr/bin/env bash
# ==============================================================================
# fswatch Windows MSYS2 (UCRT64) Compilation Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_TYPE="${1:-Release}"
INSTALL_DIR="${SCRIPT_DIR}/dist"

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
# -static: Links libstdc++ and libgcc statically so the .exe has zero non-system DLL dependencies.
# -DUSE_NLS=OFF: Avoids dynamic libintl-8.dll / libiconv-2.dll dependency for standalone CLI.
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

echo "=== 5. Verifying Output ==="
echo "Testing standalone executable:"
"${INSTALL_DIR}/standalone/bin/fswatch.exe" --version
echo "Available monitors:"
"${INSTALL_DIR}/standalone/bin/fswatch.exe" -M

echo "=== Build Completed Successfully! ==="
echo "Output directories:"
echo " - Standalone CLI : ${INSTALL_DIR}/standalone/bin/fswatch.exe"
echo " - Shared Lib/DLL : ${INSTALL_DIR}/shared/"
echo " - Static Lib     : ${INSTALL_DIR}/static/"
