
# 彩色输出 
option(USE_CMAKE_COLORED_MESSAGES   "Enable colored messages in CMake output for this project" ON)
option(USE_CPP_COLORED_DEBUG_OUTPUT "Enable colored messages in Debug output for this project" ON)
option(ENABLE_EXTERNAL_FMT          "Enable external {fmt} (even though std fmt is available)" ON)

# 使用 string(ASCII <n>) 生成字符以解决 “/0” 无效转义序列问题
string(ASCII 27 ESC) # ESC: 
                     #   ASCII Code: 27
                     #   HEX:        0x1B
                     #   OCT:        033

# --- ANSI 颜色代码定义 ----
if (USE_CMAKE_COLORED_MESSAGES AND (NOT WIN32 OR CMAKE_GENERATOR STREQUAL "Ninja" OR CMAKE_COLOR_MAKEFILE))
    set(C_RESET     "${ESC}[0m" )
    set(C_BLACK     "${ESC}[30m")
    set(C_RED       "${ESC}[31m")
    set(C_GREEN     "${ESC}[32m")
    set(C_YELLOW    "${ESC}[33m")
    set(C_BLUE      "${ESC}[34m")
    set(C_MAGENTA   "${ESC}[35m")
    set(C_CYAN      "${ESC}[36m")
    set(C_WHITE     "${ESC}[37m")

    # 粗体/高亮 Bold/Bright
    set(C_B_BLACK   "${ESC}[1;30m")
    set(C_B_RED     "${ESC}[1;31m")
    set(C_B_GREEN   "${ESC}[1;32m")
    set(C_B_YELLOW  "${ESC}[1;33m")
    set(C_B_BLUE    "${ESC}[1;34m")
    set(C_B_MAGENTA "${ESC}[1;35m")
    set(C_B_CYAN    "${ESC}[1;36m")
    set(C_B_WHITE   "${ESC}[1;37m")
else()
    # 如果环境不支持彩色输出
    set(C_RESET     "")
    set(C_BLACK     "")
    set(C_RED       "")
    set(C_GREEN     "")
    set(C_YELLOW    "")
    set(C_BLUE      "")
    set(C_MAGENTA   "")
    set(C_CYAN      "")
    set(C_WHITE     "")

    set(C_B_BLACK   "")
    set(C_B_RED     "")
    set(C_B_GREEN   "")
    set(C_B_YELLOW  "")
    set(C_B_BLUE    "")
    set(C_B_MAGENTA "")
    set(C_B_CYAN    "")
    set(C_B_WHITE   "")
endif()

# --- 自定义消息函数 ---
# 用法 pretty_message(<TYPE> "消息内容...")
# Defined Type:
#   STATUS      (蓝色粗体) -  常规状态, 比默认 message(STATUS) 更醒目
#   INFO        (青色)    -  提供参考信息
#   VINFO       (黄色)    -  CMake中的变量信息
#   SUCCESS     (绿色粗体) -  操作成功
#   WARNING     (黄色粗体) -  警告
#   ERROR       (红色粗体) -  非致命错误 (使用message(SEND_ERROR))
#   FATAL_ERROR (红色粗体) -  致命错误 (使用message(FATAL_ERROR))
#   DEBUG       (洋红色)   -  调试信息 (仅在 CMAKE_BUILD_TYPE 为 Debug 时输出)
#   IMPORTANT   (洋红粗体)  - 重要提示
#   DEFAULT     (无颜色)   -  使用 message(STATUS) 默认行为
function(pretty_message TYPE MESSAGE)
    set(PREFIX "")
    set(COLOR  "")
    set(MSG_CMD "STATUS")

    if (USE_CMAKE_COLORED_MESSAGES)
        if (${TYPE} STREQUAL "STATUS")
            set(PREFIX  "[STATUS] ")
            set(COLOR   "${C_B_BLUE}")
        elseif (${TYPE} STREQUAL "INFO")
            set(PREFIX  "[INFO] ")
            set(COLOR   "${C_CYAN}")
        elseif (${TYPE} STREQUAL "VINFO")
            set(PREFIX  "[VINFO]")
            set(COLOR   "${C_YELLOW}")
        elseif (${TYPE} STREQUAL "SUCCESS")
            set(PREFIX  "[SUCCESS] ")
            set(COLOR   "${C_B_GREEN}")
        elseif (${TYPE} STREQUAL "WARNING")
            set(PREFIX  "[WARNING] ")
            set(COLOR   "${C_B_YELLOW}")
            set(MSG_CMD "WARNING")
        elseif (${TYPE} STREQUAL "ERROR")
            set(PREFIX  "[ERROR] ")
            set(COLOR   "${C_B_RED}")
            set(MSG_CMD "SEND_ERROR")
        elseif (${TYPE} STREQUAL "FATAL_ERROR")
            set(PREFIX  "[FATAL] ")
            set(COLOR   "${C_B_RED}")
            set(MSG_CMD "FATAL_ERROR")
        elseif (${TYPE} STREQUAL "IMPORTANT")
            set(PREFIX  "[IMPORTANT] ")
            set(COLOR   "${C_B_MAGENTA}")
        elseif (${TYPE} STREQUAL "DEBUG")
            string(TOLOWER "${CMAKE_BUILD_TYPE}" _build_type_lower)
            if (NOT (_build_type_lower STREQUAL "debug" OR _build_type_lower STREQUAL "debug_mode"))
                return()
            endif()
            set(PREFIX  "[DEBUG] ")
            set(COLOR   "${C_MAGENTA}")
        else () # 没有定义的输出类型
            set(PREFIX  "[${TYPE}] ")
            set(COLOR   "")
        endif()
        message(${MSG_CMD} "${COLOR}${PREFIX}${MESSAGE}${C_RESET}")
    else()
        if (${TYPE} STREQUAL "FATAL_ERROR")
            message(FATAL_ERROR "[FATAL]   ${MESSAGE}")
        elseif (${TYPE} STREQUAL "ERROR")
            message(SEND_ERROR  "[ERROR]   ${MESSAGE}")
        elseif (${TYPE} STREQUAL "WARNING")
            message(WARNING     "[WARNING] ${MESSAGE}")
        elseif (${TYPE} STREQUAL "DEBUG")
            string(TOLOWER "${CMAKE_BUILD_TYPE}" _build_type_lower)
            if (_build_type_lower STREQUAL "debug" OR _build_type_lower STREQUAL "debug_mode")
                message(STATUS  "[DEBUG]   ${MESSAGE}")   
            endif()
        elseif (NOT ({$TYPE} STREQUAL "DEFAULT"))
            message(STATUS      "[${TYPE}] ${MESSAGE}")
        else ()
            message(STATUS      "${MESSAGE}")
        endif()
    endif()
endfunction()

if (CMAKE_CXX_STANDARD GREATER_EQUAL 20)
    include(CheckCXXSourceCompiles)
    set(STD_FORMAT_TEST
    "
    #include <format>
    #include <string>
    #if !defined(__cpp_lib_format) || __cpp_lib_format < 201907L
    #endif

    int main() {
        std::string s = std::format(\"Hello, {}!\", \"world\");
        (void)s;
        return 0;
    }
    "
    )
    # Store them in case of 'check_cxx_source_compiles's side effect 
    set(CMAKE_REQUIRED_FLAGS_     ${CMAKE_REQUIRED_FLAGS})
    set(CMAKE_REQUIRED_LIBRARIES_ ${CMAKE_REQUIRED_LIBRARIES})

    check_cxx_source_compiles("${STD_FORMAT_TEST}" _HAS_STD_FORMAT)

    # Restore
    set(CMAKE_REQUIRED_FLAGS      ${CMAKE_REQUIRED_FLAGS_})
    set(CMAKE_REQUIRED_LIBRARIES  ${CMAKE_REQUIRED_LIBRARIES_})


    if (_HAS_STD_FORMAT)    # Enable cpp std format 
        set(HAVE_STD_FORMAT ON CACHE INTERNAL "std::format is avaible")
    
    else() 
        set(HAVE_STD_FORMAT OFF CACHE INTERNAL "std::format is unavaible")
    endif()
endif()


if (HAVE_STD_FORMAT)
    if (ENABLE_EXTERNAL_FMT)
        add_compile_definitions(USE_EXTERNAL_FMT=1)
    else()
        add_compile_definitions(USE_STD_FMT=1)
    endif()
else()
    add_compile_definitions(USE_EXTERNAL_FMT=1)
endif()

if (USE_CPP_COLORED_DEBUG_OUTPUT)
    add_compile_definitions(USE_CPP_COLORED_DEBUG_OUTPUT=1)
endif()


# Debug
pretty_message(INFO  "PrettyPrint.cmake module loaded.")
pretty_message(VINFO "======================Pretty Message Info======================")
pretty_message(VINFO "  USE_CMAKE_COLORED_MESSAGES:     ${USE_CMAKE_COLORED_MESSAGES} ")
pretty_message(VINFO "  USE_CPP_COLORED_DEBUG_OUTPUT:   ${USE_CPP_COLORED_DEBUG_OUTPUT} ")
pretty_message(VINFO "  ENABLE_EXTERNAL_FMT:            ${ENABLE_EXTERNAL_FMT}")
if (NOT ENABLE_EXTERNAL_FMT)
pretty_message(VINFO "  HAVE_STD_FORMAT:                ${HAVE_STD_FORMAT}")
endif()
pretty_message(VINFO "===============================================================")