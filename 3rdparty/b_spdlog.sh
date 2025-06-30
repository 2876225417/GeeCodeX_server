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

# 引入 NDK 工具链配置 export ANDROID_NDK_HOME
if [ -f "${SCRIPT_DIR_REALPATH}/common_env.sh" ]; then
    source "${SCRIPT_DIR_REALPATH}/common_env.sh"
else
    echo -e "${BRED}ERROR: NO ANDROID_NDK_HOME CONFIGURED.${NC}"
    echo -e "${BYELLOW}Tip: Try to export ANDROID_NDK_HOME="ANDROID NDK Dev Toolchain."${NC}"
    exit 1
fi

# 配置 spdlog 仓库
SPDLOG_VERSION_TAG="v1.x"
SPDLOG_REPO_URL="https://github.com/gabime/spdlog.git"

# 配置 spdlog 相关路径
SCRIPT_BASE_DIR="$(pwd)"
SPDLOG_SOURCE_DIR="${SCRIPT_BASE_DIR}/source/spdlog"
SPDLOG_BUILD_BASE_DIR="${SCRIPT_BASE_DIR}/build/spdlog"
SPDLOG_INSTALL_BASE_DIR="${SCRIPT_BASE_DIR}/spdlog"

# --- 准备源码 ---
echo -e "${YELLOW}--- Preparing spdlog source: ${SPDLOG_SOURCE_DIR} ---${NC}"
mkdir -p "$SPDLOG_SOURCE_DIR"
echo -e "${YELLOW}--- Handling spdlog Source Repository ---${NC}"
git_clone_or_update "$SPDLOG_REPO_URL" "$SPDLOG_SOURCE_DIR" "$SPDLOG_VERSION_TAG"

print_usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options: ${NC}"
    echo -e "   ${CYAN}--target_platform=<platform>         ${NC}       Specify the target platform."
    echo -e "   Supported Platforms: ${GREEN}android, linux${NC}"
}

TARGET_PLATFORM=""
for i in "$@"; do
    case $i in
        --target_platform=*)
        TARGET_PLATFORM="${i#*=}"
        shift
        ;;
        *)
        echo -e "${BRED}Error: Unknown option '$i'${NC}"
        print_usage
        exit 1
        ;;
    esac
done

if [ -z "$TARGET_PLATFORM" ]; then
    echo -e "${BRED}Error: Target platform must be specified.${NC}"
    print_usage
    exit 1
fi

build_spdlog_for_platform() {
    local abi="$1"
    local platform_version="$2"
    local extra_cmake_flags="$3"

    # 编译、安装和编译日志路径(删除再重新创建)
    SPDLOG_BUILD_DIR="${SPDLOG_BUILD_BASE_DIR}/spdlog_$abi"
    echo -e "${GREEN}--- Creating and cleaning spdlog build directory ---${NC}"
    rm -rf "$SPDLOG_BUILD_DIR"
    mkdir -p "$SPDLOG_BUILD_DIR"

    SPDLOG_INSTALL_PREFIX_DIR="${SPDLOG_INSTALL_BASE_DIR}/spdlog_$abi/spdlog"
    echo -e "${GREEN}--- Creating and cleaning spdlog install directory ---${NC}"
    rm -rf "$SPDLOG_INSTALL_PREFIX_DIR"
    mkdir -p "$SPDLOG_INSTALL_PREFIX_DIR"

    SPDLOG_LOG_DIR="${SCRIPT_BASE_DIR}/logs/spdlog"
    mkdir -p "$SPDLOG_LOG_DIR"
    SPDLOG_LOG_FILE="${SPDLOG_LOG_DIR}/spdlog_$abi.txt"

    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX"="${SPDLOG_INSTALL_PREFIX_DIR}"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DSPDLOG_BUILD_EXAMPLES=OFF"
        # "-DSPDLOG_BUILD_SHARED=OFF"
    )
    
    if [ "$TARGET_PLATFORM" = "android" ]; then
        CMAKE_ARGS+=(
            "-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=${abi}"
            "-DANDROID_PLATFORM=android-${platform_version}"
            "-DCMAKE_ANDROID_ARCH_ABI=${abi}"
            "-DCMAKE_EXE_LINKER_FLAGS=-llog" # 解决链接时的错误信息
        )
    fi

    if [ -n "$extra_cmake_flags" ]; then
        CMAKE_ARGS+=($extra_cmake_flags)
    fi

    cd "$SPDLOG_BUILD_DIR"
    echo -e "${YELLOW}--- Configuring spdlog for platform: $abi ---${NC}"

    echo "CMake Configurations:" > "$SPDLOG_LOG_FILE"
    echo "cmake -S \"$SPDLOG_SOURCE_DIR\" -B \"$SPDLOG_BUILD_DIR\" ${CMAKE_ARGS[*]}" >> "$SPDLOG_LOG_FILE"

    if cmake -S "$SPDLOG_SOURCE_DIR" -B "$SPDLOG_BUILD_DIR" "${CMAKE_ARGS[@]}" >> "$SPDLOG_LOG_FILE"; then
        CMAKE_CONFIG_EXIT_CODE=0
    else
        CMAKE_CONFIG_EXIT_CODE=$?
    fi

    if [ "$CMAKE_CONFIG_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to configure cmake for spdlog(platform: $abi), EXIT CODE: $CMAKE_CONFIG_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${SPDLOG_LOG_FILE}${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}--- Building spdlog for platform: $abi... --- ${NC}"
    if cmake --build "$SPDLOG_BUILD_DIR" --config Release --parallel $(nproc) >> "$SPDLOG_LOG_FILE"; then
        CMAKE_BUILD_EXIT_CODE=0
    else
        CMAKE_BUILD_EXIT_CODE=$?
    fi

    if [ "$CMAKE_BUILD_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to build spdlog for platform: $abi, EXIT CODE: $CMAKE_BUILD_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${SPDLOG_LOG_FILE} ${NC}" >&2
        return 1
    else
        echo -e "${GREEN}spdlog built for platform: $abi successfully${NC}"
        BUILD_SUCCESSFUL_FLAG=true
    fi

    if [ "$BUILD_SUCCESSFUL_FLAG" = true ]; then
        echo -e "${YELLOW}--- Installing spdlog for platform: $abi ---${NC}"
        if cmake --install . --config Release >> "$SPDLOG_LOG_FILE" 2>&1; then
            CMAKE_INSTALL_EXIT_CODE=0
        else
            CMAKE_INSTALL_EXIT_CODE=$?
        fi

        if [ "$CMAKE_INSTALL_EXIT_CODE" -ne 0 ]; then
            echo -e "${BRED}Error: Failed to install spdlog for platform: $abi, EXIT CODE: $CMAKE_INSTALL_EXIT_CODE ${NC}" >&2
            echo -e "${BRED}Please check detailed log: ${SPDLOG_LOG_FILE} ${NC}" >&2
            BUILD_SUCCESSFUL_FLAG=false
            return 1
        else
            echo -e "${YELLOW}--- spdlog for platform: $abi installed to $SPDLOG_INSTALL_PREFIX_DIR ${NC}"

            REPORT_FILE="${SPDLOG_INSTALL_PREFIX_DIR}/build_report_${abi}.txt"
            echo "spdlog Build Report" > "$REPORT_FILE"
            echo "========================================================"     >> "$REPORT_FILE"
            echo "Date: $(date)"                                                >> "$REPORT_FILE"
            echo "Platform: $abi"                                               >> "$REPORT_FILE"
            echo "spdlog Version (Git Tag/Branch): $SPDLOG_VERSION_TAG"         >> "$REPORT_FILE"
            if [ -d "$SPDLOG_SOURCE_DIR/.git" ]; then
                GIT_COMMIT_HASH=$(cd "$SPDLOG_SOURCE_DIR" && git rev-parse --short HEAD)
                echo "spdlog Git Commit: $GIT_COMMIT_HASH"                      >> "$REPORT_FILE"
            fi
            echo "Build Configuration: Release (via CMake)"                     >> "$REPORT_FILE"
            if [ "$abi" = "android" ]; then
                echo "NDK Path: $ANDROID_NDK_HOME"                              >> "$REPORT_FILE"
                echo "NDK Version (fom source.properties): $NDK_VERSION_STRING" >> "$REPORT_FILE"
                echo "CLANG_CXX_COMPILER: $CLANG_COMPILER_PATH"                 >> "$REPORT_FILE"
                echo "CLANG_C_COMPILER: $CLANG_C_COMPILER_PATH"                 >> "$REPORT_FILE"
                echo "Clang Version: $CLANG_VERSION_STRING"                     >> "$REPORT_FILE"
            else
                echo "HOST_GCC_PATH: $HOST_GCC_PATH"                            >> "$REPORT_FILE"
                echo "HOST_GXX_PATH: $HOST_GXX_PATH"                            >> "$REPORT_FILE"
                echo "HOST_GCC_VERSION: $HOST_GCC_VERSION"                      >> "$REPORT_FILE"
                echo "HOST_CLANG_PATH: $HOST_CLANG_PATH"                        >> "$REPORT_FILE"
                echo "HOST_CLANGXX_PATH: $HOST_CLANGXX_PATH"                    >> "$REPORT_FILE"
                echo "HOST_CLANG_VERSION: $HOST_CLANG_VERSION"                  >> "$REPORT_FILE"
            fi
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
    build_spdlog_for_platform "linux-x86_64"
elif [ "$TARGET_PLATFORM" == "android" ]; then
    echo -e "${YELLOW}Build target is android. All Android ABIS and 'linux-x86_64' will be built.${NC}"
    build_spdlog_for_platform "arm64-v8a"    "21" ""
    build_spdlog_for_platform "armeabi-v7a"  "19" ""
    build_spdlog_for_platform "x86_64"       "21" ""
    build_spdlog_for_platform "x86"          "19" ""
    build_spdlog_for_platform "linux-x86_64" 
else 
    echo -e "${BRED}Error: Unsupported target platform: '$TARGET_PLATFORM'.${NC}"
    print_usage
    exit 1
fi

echo ""
echo -e "${YELLOW}===========================================================${NC}"
echo -e "${YELLOW}spdlog has been installed: ${SPDLOG_INSTALL_BASE_DIR}${NC}"
ls -1 "$SPDLOG_INSTALL_BASE_DIR"
echo -e "${YELLOW}Now you can use find_package(spdlog) in cmake.${NC}"
echo -e "${YELLOW}===========================================================${NC}"


