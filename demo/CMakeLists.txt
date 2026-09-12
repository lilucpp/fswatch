cmake_minimum_required(VERSION 3.14)
project(fswatch_cpp_demo CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (NOT FSWATCH_ROOT)
    set(FSWATCH_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../dist/shared")
endif ()

message(STATUS "Using FSWATCH_ROOT: ${FSWATCH_ROOT}")

# Include directory containing <libfswatch/c/libfswatch.h>
include_directories("${FSWATCH_ROOT}/include")

# Find the import library (supports .lib for MSVC and .dll.a for MinGW)
find_library(LIBFSWATCH_IMPLIB
    NAMES libfswatch liblibfswatch fswatch
    PATHS "${FSWATCH_ROOT}/lib" "${FSWATCH_ROOT}/bin"
    NO_DEFAULT_PATH
    REQUIRED
)

message(STATUS "Found libfswatch import library: ${LIBFSWATCH_IMPLIB}")

add_executable(fswatch_cpp_demo main.cpp)
target_link_libraries(fswatch_cpp_demo PRIVATE ${LIBFSWATCH_IMPLIB})

# If MSVC, set UTF-8 source charset and sensible warnings
if (MSVC)
    target_compile_options(fswatch_cpp_demo PRIVATE /utf-8 /W3)
    if (CMAKE_SIZEOF_VOID_P EQUAL 4)
        # 32-bit MSVC linking against 32-bit MinGW import library requires /SAFESEH:NO
        target_link_options(fswatch_cpp_demo PRIVATE /SAFESEH:NO)
    endif ()
endif ()
