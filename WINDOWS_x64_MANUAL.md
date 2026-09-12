# fswatch Windows 64位 (x64) 开发与集成手册

本文档为 **64位 Windows (x64)** 环境下编译、集成和使用 **fswatch 1.22.0** 及 **libfswatch** 动态库/静态库的专用手册。

---

## 目录
1. [64位环境要求与依赖安装 (UCRT64)](#1-64位环境要求与依赖安装-ucrt64)
2. [源码补丁应用说明](#2-源码补丁应用说明)
3. [64位 libfswatch 编译与 MSVC 导入库生成](#3-64位-libfswatch-编译与-msvc-导入库生成)
4. [Windows 下使用 libfswatch C 接口的注意事项](#4-windows-下使用-libfswatch-c-接口的注意事项)
5. [为什么 MSVC 项目不能直接使用 MinGW 编译的 C++ 库](#5-为什么-msvc-项目不能直接使用-mingw-编译的-c-库)
6. [在 64位 MSVC (v142) 项目中集成与构建 Demo](#6-在-64位-msvc-v142-项目中集成与构建-demo)
7. [64位运行时 DLL 依赖清单与发布建议](#7-64位运行时-dll-依赖清单与发布建议)

---

## 1. 64位环境要求与依赖安装 (UCRT64)

在 MSYS2 (`C:\msys64`) 中推荐使用 **UCRT64** 子环境：
- **C 运行时 (CRT)**：`ucrtbase.dll` (Microsoft Universal CRT)，与 MSVC (VS 2015-VS 2022) 采用相同的标准运行时。
- **编译器**：64位 MinGW-w64 GCC。

### 安装依赖命令（在 MSYS2 UCRT64 终端中运行）
```bash
pacman -S --needed \
    mingw-w64-ucrt-x86_64-gcc \
    mingw-w64-ucrt-x86_64-cmake \
    mingw-w64-ucrt-x86_64-ninja \
    mingw-w64-ucrt-x86_64-gettext \
    mingw-w64-ucrt-x86_64-tools
```

---

## 2. 源码补丁应用说明

`fswatch 1.22.0` 在 `fswatch/src/fswatch.cpp` 中无条件调用了 POSIX 信号处理函数 `sigaction`，而 Windows CRT 仅支持 `std::signal`。

在编译前，在项目根目录下执行以下命令打上补丁即可（不污染其他原始文件）：

```bash
# 应用 64 位所需的信号处理补丁
git apply patches/01-windows-signal-handler.patch
```

> **撤销补丁命令**：
> ```bash
> git apply -R patches/01-windows-signal-handler.patch
> ```

---

## 3. 64位 libfswatch 编译与 MSVC 导入库生成

在 **MSYS2 UCRT64** 终端中执行：

```bash
# 1. 编译 64 位动态库并安装至 dist/shared
cmake -B build-x64 -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX=./dist/shared

cmake --build build-x64
cmake --install build-x64

# 2. 生成 64 位 MSVC 原生导入库 libfswatch.lib
cd dist/shared
gendef bin/libfswatch.dll
dlltool -d libfswatch.def -l lib/libfswatch.lib -D libfswatch.dll
```

产物说明：
- `dist/shared/bin/libfswatch.dll`：64位核心动态链接库。
- `dist/shared/lib/libfswatch.lib`：供 64位 MSVC 链接器使用的导入库。
- `dist/shared/include/libfswatch/`：头文件。

---

## 4. Windows 下使用 libfswatch C 接口的注意事项

1. **必须调用 C 接口**：包含 `#include <libfswatch/c/libfswatch.h>`。
2. **生命周期规范**：
   - 程序初始化时必须调用 `fsw_init_library()`。
   - 退出前调用 `fsw_destroy_session(handle)` 释放句柄与内核监听资源。
3. **监控模式选择 (Monitor Type)**：
   - `windows_monitor_type`（或 `system_default_monitor_type`）：基于 Win32 API `ReadDirectoryChangesW` 实现，内核事件驱动，实时高效，**强烈推荐**。
   - `poll_monitor_type`：基于 `stat()` 定时轮询目录树，开销大，仅在不支持 Win32 通知的文件系统上使用。
4. **控制台防乱码**：在 `main()` 开头调用 `SetConsoleOutputCP(CP_UTF8)` 保证 UTF-8 中文正常输出。

---

## 5. 为什么 MSVC 项目不能直接使用 MinGW 编译的 C++ 库

| 维度 | MinGW GCC 14 (x64) | MSVC (v142 / x64) | 冲突影响 |
| :--- | :--- | :--- | :--- |
| **C++ 符号修饰 (Name Mangling)** | Itanium ABI (`_ZN3fsw...`) | Microsoft ABI (`?create_monitor@...`) | MSVC 链接器报 `LNK2019: 无法解析的外部符号`。 |
| **标准库实现 (STL Layout)** | GNU `libstdc++-6` | Microsoft STL | `std::string`/`std::vector` 内部内存结构与对齐不同，跨库调用会引发**内存破坏与程序崩溃**。 |
| **虚表 (vtable) 与 RTTI** | Itanium 规范 | Microsoft 规范 | 多态调用时虚表偏移寻址错误。 |
| **异常处理机制** | GCC SEH / DWARF | MSVC 结构化异常 (SEH) | 跨编译器抛出的 `std::exception` 无法捕获。 |

> **规避方案**：通过标准 C 接口（`extern "C"`）进行跨编译器调用，基础数据类型无 ABI 差异，安全稳定。

---

## 6. 在 64位 MSVC (v142) 项目中集成与构建 Demo

已提供基于 MSVC v142 的 64位 C++ 示例工程（位于 `demo/` 目录）。

### 6.1 CMakeLists.txt 配置
```cmake
cmake_minimum_required(VERSION 3.14)
project(fswatch_cpp_demo CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(FSWATCH_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../dist/shared")
include_directories("${FSWATCH_ROOT}/include")

find_library(LIBFSWATCH_IMPLIB
    NAMES libfswatch
    PATHS "${FSWATCH_ROOT}/lib"
    NO_DEFAULT_PATH
    REQUIRED
)

add_executable(fswatch_cpp_demo main.cpp)
target_link_libraries(fswatch_cpp_demo PRIVATE ${LIBFSWATCH_IMPLIB})

if (MSVC)
    target_compile_options(fswatch_cpp_demo PRIVATE /utf-8 /W3)
endif ()
```

### 6.2 一键编译 64位 Demo
在 Windows CMD / PowerShell 中运行根目录的：
```cmd
build_demo.bat
```
脚本底层执行的 CMake 指令为：
```cmd
cmake -S demo -B demo/build-msvc -G "Visual Studio 16 2019" -A x64 -T v142 -DFSWATCH_ROOT="%cd%\dist\shared"
cmake --build demo/build-msvc --config Release
```

---

## 7. 64位运行时 DLL 依赖清单与发布建议

当 MSVC 编译的 64位程序发布时，需将以下 64位 DLL 放置在 `.exe` 相同目录下：

| DLL 文件名 | 来源 | 说明 |
| :--- | :--- | :--- |
| `fswatch_cpp_demo.exe` | MSVC 生成 | 64位应用程序主程序 |
| `libfswatch.dll` | `dist/shared/bin/` | 64位 fswatch 核心库 |
| `libgcc_s_seh-1.dll` | `C:\msys64\ucrt64\bin\` | GCC 64位运行时支持 |
| `libstdc++-6.dll` | `C:\msys64\ucrt64\bin\` | GCC 64位 C++ 标准库 |
| `libwinpthread-1.dll`| `C:\msys64\ucrt64\bin\` | POSIX 线程支持 |
| `libintl-8.dll` | `C:\msys64\ucrt64\bin\` | gettext 国际化支持 |
| `libiconv-2.dll` | `C:\msys64\ucrt64\bin\` | 字符编码转换支持 |
