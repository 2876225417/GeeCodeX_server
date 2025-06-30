#!/bin/bash
set -e

SCRIPT_DIR_REALPATH=$(dirname "$(realpath "$0")")

# 引入颜色输出配置
if [ -f "${SCRIPT_DIR_REALPATH}/common_color.sh" ]; then
    source "${SCRIPT_DIR_REALPATH}/common_color.sh"
else
    echo "Warning: NOT FOUND common_color.sh, the output will be without color." >&2
    NC='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE=''
    BBLACK='' BRED='' BGREEN='' BYELLOW='' BBLUE='' BPURPLE='' BCYAN='' BWHITE=''
fi

# 引入 GIT 配置
COMMON_GIT_SCRIPT="${SCRIPT_DIR_REALPATH}/common_git.sh"
if [ -f "$COMMON_GIT_SCRIPT" ]; then
    source "$COMMON_GIT_SCRIPT"
else
    echo -e "${RED}Error: NOT FOUND common_git.sh under ${COMMON_GIT_SCRIPT}${NC}" >&2 
    exit 1
fi

# 检查 libpqxx 依赖
if ! command -v pg_config &> /dev/null; then
    echo -e "${BRED}Error: 'pg_config' command not found.${NC}" >&2
    echo -e "${YELLOW}libpqxx requires the PostgreSQL client development library (libpq).${NC}" >&2
    echo -e "${YELLOW}Please install it first. On Debian/Ubuntu: ${GREEN}sudo apt-get install libpq-dev${NC}"
    echo -e "${YELLOW}On REHL/CentOS/Fedora: ${GREEN}sudo dnf install libpq-devel${NC}" >&2
    exit 1
fi
LIBPQ_VERSION=$(pg_config --version)
echo -e "${GREEN}Found dependency: ${LIBPQ_VERSION}${NC}"

# 配置 libpqxx 仓库
LIBPQXX_VERSION_TAG="master"
LIBPQXX_REPO_URL="https://github.com/jtv/libpqxx.git"

# 配置 libpqxx 相关路径
SCRIPT_BASE_DIR="$(pwd)"
LIBPQXX_SOURCE_DIR="${SCRIPT_BASE_DIR}/source/libpqxx"
LIBPQXX_BUILD_BASE_DIR="${SCRIPT_BASE_DIR}/build/libpqxx"
LIBPQXX_INSTALL_BASE_DIR="${SCRIPT_BASE_DIR}/libpqxx"

# --- 准备源码 ---
echo -e "${YELLOW}--- Preparing libpqxx source: ${LIBPQXX_SOURCE_DIR} ---${NC}"
mkdir -p "$LIBPQXX_SOURCE_DIR"
echo -e "${YELLOW}--- Handling libpqxx Source Repository ---${NC}"
git_clone_or_update "$LIBPQXX_REPO_URL" "$LIBPQXX_SOURCE_DIR" "$LIBPQXX_VERSION_TAG"

TARGET_PLATFORM="linux"

build_libpqxx() {
    platform="linux"
    # 编译、安装和编译日志路径(删除再重新创建)
    LIBPQXX_BUILD_DIR="${LIBPQXX_BUILD_BASE_DIR}/libpqxx_$platform"
    echo -e "${GREEN}--- Creating and cleaning libpqxx build directory ---${NC}"
    rm -rf "$LIBPQXX_BUILD_DIR"
    mkdir -p "$LIBPQXX_BUILD_DIR"

    LIBPQXX_INSTALL_PREFIX_DIR="${LIBPQXX_INSTALL_BASE_DIR}/libpqxx_$platform/libpqxx"
    echo -e "${GREEN}--- Creating and cleaning libpqxx install directory ---${NC}"
    rm -rf "$LIBPQXX_INSTALL_PREFIX_DIR"
    mkdir -p "$LIBPQXX_INSTALL_PREFIX_DIR"

    LIBPQXX_LOG_DIR="${SCRIPT_BASE_DIR}/logs/libpqxx"
    mkdir -p "$LIBPQXX_LOG_DIR"
    LIBPQXX_LOG_FILE="${LIBPQXX_LOG_DIR}/libpqxx_$platform.txt"

    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX"="${LIBPQXX_INSTALL_PREFIX_DIR}"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DBUILD_SHARED_LIBS=OFF"
        "-DSKIP_BUILD_TEST=ON"
        "-DBUILD_DOC=OFF"
        "-DINSTALL_TEST=OFF"
    )
    
    cd "$LIBPQXX_BUILD_DIR"
    echo -e "${YELLOW}--- Configuring libpqxx for platform: $platform ---${NC}"

    echo "CMake Configurations:" > "$LIBPQXX_LOG_FILE"
    echo "cmake -S \"$LIBPQXX_SOURCE_DIR\" -B \"$LIBPQXX_BUILD_DIR\" ${CMAKE_ARGS[*]}" >> "$LIBPQXX_LOG_FILE"

    if cmake -S "$LIBPQXX_SOURCE_DIR" -B "$LIBPQXX_BUILD_DIR" "${CMAKE_ARGS[@]}" >> "$LIBPQXX_LOG_FILE"; then
        CMAKE_CONFIG_EXIT_CODE=0
    else
        CMAKE_CONFIG_EXIT_CODE=$?
    fi

    if [ "$CMAKE_CONFIG_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to configure cmake for libpqxx(platform: $platform), EXIT CODE: $CMAKE_CONFIG_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${LIBPQXX_LOG_FILE}${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}--- Building libpqxx for platform: $platform... --- ${NC}"
    if cmake --build "$LIBPQXX_BUILD_DIR" --config Release --parallel $(nproc) >> "$LIBPQXX_LOG_FILE"; then
        CMAKE_BUILD_EXIT_CODE=0
    else
        CMAKE_BUILD_EXIT_CODE=$?
    fi

    if [ "$CMAKE_BUILD_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to build libpqxx for platform: $platform, EXIT CODE: $CMAKE_BUILD_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${LIBPQXX_LOG_FILE} ${NC}" >&2
        return 1
    else
        echo -e "${GREEN}libpqxx built for platform: $platform successfully${NC}"
        BUILD_SUCCESSFUL_FLAG=true
    fi

    if [ "$BUILD_SUCCESSFUL_FLAG" = true ]; then
        echo -e "${YELLOW}--- Installing libpqxx for platform: $platform ---${NC}"
        if cmake --install . --config Release >> "$LIBPQXX_LOG_FILE" 2>&1; then
            CMAKE_INSTALL_EXIT_CODE=0
        else
            CMAKE_INSTALL_EXIT_CODE=$?
        fi

        if [ "$CMAKE_INSTALL_EXIT_CODE" -ne 0 ]; then
            echo -e "${BRED}Error: Failed to install libpqxx for platform: $platform, EXIT CODE: $CMAKE_INSTALL_EXIT_CODE ${NC}" >&2
            echo -e "${BRED}Please check detailed log: ${LIBPQXX_LOG_FILE} ${NC}" >&2
            BUILD_SUCCESSFUL_FLAG=false
            return 1
        else
            echo -e "${YELLOW}--- libpqxx for platform: $platform installed to $LIBPQXX_INSTALL_PREFIX_DIR ${NC}"

            REPORT_FILE="${LIBPQXX_INSTALL_PREFIX_DIR}/build_report_${platform}.txt"
            echo "libpqxx Build Report" > "$REPORT_FILE"
            echo "========================================================"     >> "$REPORT_FILE"
            echo "Date: $(date)"                                                >> "$REPORT_FILE"
            echo "Platform: $platform"                                          >> "$REPORT_FILE"
            echo "libpqxx Version (Git Tag/Branch): $LIBPQXX_VERSION_TAG"       >> "$REPORT_FILE"
            if [ -d "$LIBPQXX_SOURCE_DIR/.git" ]; then
                GIT_COMMIT_HASH=$(cd "$LIBPQXX_SOURCE_DIR" && git rev-parse --short HEAD)
                echo "libpqxx Git Commit: $GIT_COMMIT_HASH"                     >> "$REPORT_FILE"
            fi
            echo "Build Configuration: Release (via CMake)"                     >> "$REPORT_FILE"
            echo "HOST_GCC_PATH: $HOST_GCC_PATH"                            >> "$REPORT_FILE"
            echo "HOST_GXX_PATH: $HOST_GXX_PATH"                            >> "$REPORT_FILE"
            echo "HOST_GCC_VERSION: $HOST_GCC_VERSION"                      >> "$REPORT_FILE"
            echo "HOST_CLANG_PATH: $HOST_CLANG_PATH"                        >> "$REPORT_FILE"
            echo "HOST_CLANGXX_PATH: $HOST_CLANGXX_PATH"                    >> "$REPORT_FILE"
            echo "HOST_CLANG_VERSION: $HOST_CLANG_VERSION"                  >> "$REPORT_FILE"
            echo ""                                                             >> "$REPORT_FILE"
            echo "CMake Arguments Used: "                                       >> "$REPORT_FILE"
            printf "    %s\n" "${CMAKE_ARGS[@]}"                                >> "$REPORT_FILE"
            echo ""                                                             >> "$REPORT_FILE"
            echo -e "${GREEN}Build Report Generated: ${REPORT_FILE}${NC}"    
        fi
    fi
    cd "${SCRIPT_BASE_DIR}"
}

echo -e "${GREEN}Target platform set to: ${CYAN}$TARGET_PLATFORM${NC}"
if [ "$TARGET_PLATFORM" == "linux" ]; then
    echo -e "${YELLOW}Build target is linux. Only 'linux-x86_64' will be built.${NC}"
    build_libpqxx "linux-x86_64"
fi

echo ""
echo -e "${YELLOW}===========================================================${NC}"
echo -e "${YELLOW}libpqxx has been installed: ${LIBPQXX_INSTALL_BASE_DIR}${NC}"
ls -1 "$LIBPQXX_INSTALL_BASE_DIR"
echo -e "${YELLOW}Now you can use find_package(libpqxx) in cmake.${NC}"
echo -e "${YELLOW}===========================================================${NC}"


