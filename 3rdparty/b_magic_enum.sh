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

# 配置 magic_enum 仓库
MAGIC_ENUM_VERSION_TAG="master"
MAGIC_ENUM_REPO_URL="https://github.com/Neargye/magic_enum.git"

# 配置 magic_enum 相关路径
SCRIPT_BASE_DIR="$(pwd)"
MAGIC_ENUM_SOURCE_DIR="${SCRIPT_BASE_DIR}/source/magic_enum"
MAGIC_ENUM_BUILD_BASE_DIR="${SCRIPT_BASE_DIR}/build/magic_enum"
MAGIC_ENUM_INSTALL_BASE_DIR="${SCRIPT_BASE_DIR}/magic_enum"

# 配置 Android NDK 工具链(不影响)
ANDROID_ABI_FOR_MAGIC_ENUM_CONFIG="arm64-v8a"
ANDROID_PLATFORM_FOR_MAGIC_ENUM_CONFIG="android-24"

# --- 准备源码 ---
echo -e "${YELLOW}--- Preparing magic_enum source: ${MAGIC_ENUM_SOURCE_DIR} ---${NC}"
mkdir -p "$MAGIC_ENUM_SOURCE_DIR"
echo -e "${YELLOW}--- Handling magic_enum Source Repository ---${NC}"
git_clone_or_update "$MAGIC_ENUM_REPO_URL" "$MAGIC_ENUM_SOURCE_DIR" "$MAGIC_ENUM_VERSION_TAG"

print_usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options: ${NC}"
    echo -e "   ${CYAN}--target_platform=<platform>         ${NC}       Specify the target platform."
    echo -e "   Supported Platforms: ${GREEN}android, linux${NC}"
}

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




build_magic_enum_for_platform() {
    local platform="$1"

    # 编译、安装和编译日志路径(删除再重新创建)
    MAGIC_ENUM_BUILD_DIR="${MAGIC_ENUM_BUILD_BASE_DIR}/magic_enum_$platform"
    echo -e "${GREEN}--- Creating and cleaning magic_enum build directory ---${NC}"
    rm -rf "$MAGIC_ENUM_BUILD_DIR"
    mkdir -p "$MAGIC_ENUM_BUILD_DIR"

    MAGIC_ENUM_INSTALL_PREFIX_DIR="${MAGIC_ENUM_INSTALL_BASE_DIR}/magic_enum_$platform/magic_enum"
    echo -e "${GREEN}--- Creating and cleaning magic_enum install directory ---${NC}"
    rm -rf "$MAGIC_ENUM_INSTALL_PREFIX_DIR"
    mkdir -p "$MAGIC_ENUM_INSTALL_PREFIX_DIR"

    MAGIC_ENUM_LOG_DIR="${SCRIPT_BASE_DIR}/logs/magic_enum"
    mkdir -p "$MAGIC_ENUM_LOG_DIR"
    MAGIC_ENUM_LOG_FILE="${MAGIC_ENUM_LOG_DIR}/magic_enum_$platform.txt"

    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX"="${MAGIC_ENUM_INSTALL_PREFIX_DIR}"
        "-DCMAKE_BUILD_TYPE=Release"
    )
    
    if [ "$platform" = "android" ]; then
        CMAKE_ARGS+=(
            "-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=${ANDROID_ABI_FOR_MAGIC_ENUM_CONFIG}"
            "-DANDROID_PLATFORM=${ANDROID_PLATFORM_FOR_MAGIC_ENUM_CONFIG}" 
            "-DCMAKE_EXE_LINKER_FLAGS=-llog" # 解决链接时的错误信息
        )
    fi

    cd "$MAGIC_ENUM_BUILD_DIR"
    echo -e "${YELLOW}--- Configuring magic_enum for platform: $platform ---${NC}"

    echo "CMake Configurations:" > "$MAGIC_ENUM_LOG_FILE"
    echo "cmake -S \"$MAGIC_ENUM_SOURCE_DIR\" -B \"$MAGIC_ENUM_BUILD_DIR\" ${CMAKE_ARGS[*]}" >> "$MAGIC_ENUM_LOG_FILE"

    if cmake -S "$MAGIC_ENUM_SOURCE_DIR" -B "$MAGIC_ENUM_BUILD_DIR" "${CMAKE_ARGS[@]}" >> "$MAGIC_ENUM_LOG_FILE"; then
        CMAKE_CONFIG_EXIT_CODE=0
    else
        CMAKE_CONFIG_EXIT_CODE=$?
    fi

    if [ "$CMAKE_CONFIG_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to configure cmake for magic_enum(platform: $platform), EXIT CODE: $CMAKE_CONFIG_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${MAGIC_ENUM_LOG_FILE}${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}--- Building magic_enum for platform: $platform... --- ${NC}"
    if cmake --build "$MAGIC_ENUM_BUILD_DIR" --config Release --parallel $(nproc) >> "$MAGIC_ENUM_LOG_FILE"; then
        CMAKE_BUILD_EXIT_CODE=0
    else
        CMAKE_BUILD_EXIT_CODE=$?
    fi

    if [ "$CMAKE_BUILD_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to build magic_enum for platform: $platform, EXIT CODE: $CMAKE_BUILD_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${MAGIC_ENUM_LOG_FILE} ${NC}" >&2
        return 1
    else
        echo -e "${GREEN}magic_enum built for platform: $platform successfully${NC}"
        BUILD_SUCCESSFUL_FLAG=true
    fi

    if [ "$BUILD_SUCCESSFUL_FLAG" = true ]; then
        echo -e "${YELLOW}--- Installing magic_enum for platform: $platform ---${NC}"
        if cmake --install . --config Release >> "$MAGIC_ENUM_LOG_FILE" 2>&1; then
            CMAKE_INSTALL_EXIT_CODE=0
        else
            CMAKE_INSTALL_EXIT_CODE=$?
        fi

        if [ "$CMAKE_INSTALL_EXIT_CODE" -ne 0 ]; then
            echo -e "${BRED}Error: Failed to install magic_enum for platform: $platform, EXIT CODE: $CMAKE_INSTALL_EXIT_CODE ${NC}" >&2
            echo -e "${BRED}Please check detailed log: ${MAGIC_ENUM_LOG_FILE} ${NC}" >&2
            BUILD_SUCCESSFUL_FLAG=false
            return 1
        else
            echo -e "${YELLOW}--- magic_enum for platform: $platform installed to $MAGIC_ENUM_INSTALL_PREFIX_DIR ${NC}"

            REPORT_FILE="${MAGIC_ENUM_INSTALL_PREFIX_DIR}/build_report_${platform}.txt"
            echo "magic_enum Build Report" > "$REPORT_FILE"
            echo "========================================================"     >> "$REPORT_FILE"
            echo "Date: $(date)"                                                >> "$REPORT_FILE"
            echo "Platform: $platform"                                          >> "$REPORT_FILE"
            echo "magic_enum Version (Git Tag/Branch): $MAGIC_ENUM_VERSION_TAG" >> "$REPORT_FILE"
            if [ -d "$MAGIC_ENUM_SOURCE_DIR/.git" ]; then
                GIT_COMMIT_HASH=$(cd "$MAGIC_ENUM_SOURCE_DIR" && git rev-parse --short HEAD)
                echo "magic_enum Git Commit: $GIT_COMMIT_HASH"                  >> "$REPORT_FILE"
            fi
            echo "Build Configuration: Release (via CMake)"                     >> "$REPORT_FILE"
            if [ "$platform" = "android" ]; then
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
    build_magic_enum_for_platform "linux-x86_64"
elif [ "$TARGET_PLATFORM" == "android" ]; then
    echo -e "${YELLOW}Build target is android. All Android ABIS and 'linux-x86_64' will be built.${NC}"
    build_magic_enum_for_platform "android"
    build_magic_enum_for_platform "linux-x86_64"
else 
    echo -e "${BRED}Error: Unsupported target platform: '$TARGET_PLATFORM'.${NC}"
    print_usage
    exit 1
fi

echo ""
echo -e "${YELLOW}===========================================================${NC}"
echo -e "${YELLOW}magic_enum has been installed: ${MAGIC_ENUM_INSTALL_BASE_DIR}${NC}"
ls -1 "$MAGIC_ENUM_INSTALL_BASE_DIR"
echo -e "${YELLOW}Now you can use find_package(magic_enum) in cmake.${NC}"
echo -e "${YELLOW}===========================================================${NC}"


