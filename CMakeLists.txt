cmake_minimum_required(VERSION 3.16)


option(USE_CLANG "Compile with Clang C/C++ compiler" OFF)
if(USE_CLANG)
    set(CMAKE_C_COMPILER clang)
    set(CMAKE_CXX_COMPILER clang++)
    message(STATUS "Compiler set to Clang.")
else()
    message(STATUS "Using default system compiler.")
endif()


set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

project(geecodex_server LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(
    spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.15.3
)
FetchContent_MakeAvailable(spdlog)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBPQXX REQUIRED libpqxx)
message(STATUS "Building with PGSQL support")



list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")


include_directories(
    ${CMAKE_SOURCE_DIR}/include
)

add_subdirectory(src)
