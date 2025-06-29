include_guard(GLOBAL)

# include(${CMAKE_CURRENT_LIST_DIR}/PrettyPrint.cmake)


# 描述: 检查当前工具链是否支持 PCH(一般用在主CMakeLists中)
function(check_pch_support)
    if (CMAKE_VERSION VERSION_LESS "3.16")
        pretty_message(WARNING "CMake version < 3.16, PCH support disabled")
        set(PCH_SUPPORTED FALSE CACHE INTERNAL "PCH support status")
        return()
    endif()

    if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|MSVC|AppleClang")
        set(PCH_SUPPORTED TRUE CACHE INTERNAL "PCH support status")
        pretty_message(SUCCESS "PCH support enabled for ${CMAKE_CXX_COMPILER_ID}")
    else()
        set(PCH_SUPPORTED TRUE CACHE INTERNAL "PCH support status")
        pretty_message(WARNING "PCH not supported for compiler: ${CMAKE_CXX_COMPILER_ID}")
    endif()
endfunction()

# 描述: 启用PCH (一般用在主CMakeLists中)
# 用法: enable_pch(<target> [INTERFACE] [PRIVATE <headers>...] [PUBLIC <headers>...])
function(enable_pch TARGET_NAME)
    cmake_parse_arguments(ARG "INTERFACE" "" "PRIVATE;PUBLIC" ${ARGN})

    if (NOT PCH_SUPPORTED)
        return()
    endif()
    
    if (NOT TARGET ${TARGET_NAME})
        pretty_message(ERROR "Target '${TARGET_NAME}' does not exist")
        return()
    endif()

    if (NOT ARG_PRIVATE AND NOT ARG_PUBLIC)
        set(ARG_PRIVATE "${CMAKE_SOURCE_DIR}/include/pch.h")
    endif()

    if (ARG_INTERFACE)
        target_precompile_headers(${TARGET_NAME} INTERFACE ${ARG_PRIVATE} ${ARG_PUBLIC})
    else()
        if (ARG_PRIVATE)
            target_precompile_headers(${TARGET_NAME} PRIVATE ${ARG_PRIVATE})
        endif()
        if (ARG_PUBLIC)
            target_precompile_headers(${TARGET_NAME} PUBLIC ${ARG_PUBLIC})
        endif()
    endif()

    pretty_message(INFO "PCH enabled for target: ${TARGET_NAME}")

    if (ARG_PRIVATE)
        pretty_message(DEBUG "  Private PCH: ${ARG_PRIVATE}")
    endif()
    if(ARG_PUBLIC)
        pretty_message(DEBUG "  Public PCH: ${ARG_PUBLIC}")
    endif()
endfunction()

# 描述: 为目标启用分层 PCH
# 用法: enable_layered_pch(<target> [BASE_PCH <base_pch>] [MODULE_PCH <module_pch>])
function(enable_layered_pch TARGET_NAME)
    cmake_parse_arguments(ARG "" "BASE_PCH;MODULE_PCH" "" ${ARGN})

    if (NOT PCH_SUPPORTED)
        return()
    endif()

    if (NOT TARGET ${TARGET_NAME})
        pretty_message(ERROR "Target '${TARGET_NAME}' does not exist")
        return()
    endif()

    # 默认主 pch.h
    if (NOT ARG_BASE_PCH)
        set(ARG_BASE_PCH "${CMAKE_SOURCE_DIR}/include/pch.h")
    endif()

    # 为模块指定特定的 PCH
    if (ARG_MODULE_PCH AND EXISTS ${ARG_MODULE_PCH})
        target_precompile_headers(${TARGET_NAME} PRIVATE ${ARG_MODULE_PCH})
        pretty_message(INFO "Layered PCH enabled for target: ${TARGET_NAME}")
        pretty_message(DEBUG "  Module PCH: ${ARG_MODULE_PCH}")
    else()
        target_precompile_headers(${TARGET_NAME} PRIVATE ${ARG_BASE_PCH})
        pretty_message(INFO "Base PCH enabled for target: ${TARGET_NAME}")
        pretty_message(DEBUG "  Base PCH: ${ARG_BASE_PCH}")
    endif()
endfunction()

# 描述: 自动检测并启用分层 PCH
# 用法： auto_enable_pch(<target> <module_name>)
function(auto_enable_pch TARGET_NAME MODULE_NAME)
    if (NOT PCH_SUPPORTED)
        return()
    endif()

    set(module_pch_paths
        "${CMAKE_SOURCE_DIR}/include/${MODULE_NAME}/${MODULE_NAME}_pch.h"
        "${CMAKE_SOURCE_DIR}/include/${MODULE_NAME}/pch.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/pch.h"
    )

    set(module_pch_found FALSE)
    foreach(pch_pach ${module_pch_paths})
        if(EXISTS ${pch_path})
            enable_layered_pch(${TARGET_NAME} MODULE_PCH ${pch_path})
            set(module_Pch_found TRUE)
            break()
        endif()
    endforeach()

    if (NOT module_pch_found)
        enable_layered_pch(${TARGET_NAME})
    endif()

endfunction()

# 描述: 创建PCH目标
function(create_pch_target PCH_TARGET_NAME PCH_HEADER)
    if (NOT PCH_SUPPORTED)
        return()
    endif()

    add_library(${PCH_TARGET_NAME} INTERFACE)
    target_precompile_headers(${PCH_TARGET_NAME} INTERFACE ${PCH_HEADER})
    
    pretty_message(SUCCESS "Created reusable PCH target: ${PCH_TARGET_NAME}")
    pretty_message_kv(VINFO "PCH header" "${PCH_HEADER}")
endfunction()

# 构建项目PCH
function(setup_project_pch)
    cmake_parse_arguments(ARG "" "" "TARGETS" ${ARGN})

    check_pch_support()
    if (NOT PCH_SUPPORTED)
        return()
    endif()

    pretty_message(STATUS "Setting up Project PCH")
    
    set(PCH_HEADER "${CMAKE_SOURCE_DIR}/include/pch.h")
    if(NOT EXISTS ${PCH_HEADER})
        pretty_message(WARNING "PCH header not found: ${PCH_HEADER}")
        pretty_message(WARNING "PCH setup skipped")
        return()
    endif()

    create_pch_target(pch_global ${PCH_HEADER})

    if (ARG_TARGETS)
        foreach(target ${ARG_TARGETS})
            if (TARGET ${target})
                target_link_libraries(${target} PRIVATE pch_global)
                pretty_message(SUCCESS "PCH enabled for: ${target}")
            endif()
        endforeach()
    endif()


endfunction()

# 统计 PCH 信息
function(show_pch_stats)
    if(NOT PCH_SUPPORTED)
        pretty_message(INFO "PCH not supported on this platform")
        return()
    endif()

    pretty_message_kv(VINFO "CMake Version" "${CMAKE_VERSION}")
    pretty_message_kv(VINFO "Compiler"      "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
    pretty_message_kv(VINFO "PCH Supported" "YES")

    if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        pretty_message_kv(VINFO "PCH Extension" ".gch")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        pretty_message_kv(VINFO "PCH Extension" ".pch")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        pretty_message_kv(VINFO "PCH Extension" ".pch")
    endif()

    pretty_message(TIP "To use PCH in your targets: ")
    pretty_message(TIP "  target_link_libraries(your_target PRIVATE pch_global)")
    pretty_message(TIP "Or:")
    pretty_message(TIP "  enable_pch(your_target)")

    pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
    pretty_message(STATUS "")
endfunction()

# 配置 PCH
function(pch_configure)
    pretty_message(VINFO_BANNER "Configuring PCH" "=" ${BANNER_WIDTH})
    if (CMAKE_BUILD_TYPE MATCHES "[Dd]eb")
        option(USE_PCH_IN_DEBUG "Use PCH in Debug builds" ON)
        if (NOT USE_PCH_IN_DEBUG)
            set(PCH_SUPPORTED FALSE CACHE INTERNAL "PCH support status")
            pretty_message(INFO "PCH disabled in Debug mode")
            return()
        endif()
    endif()

    if (CMAKE_UNITY_BUILD)
        pretty_message(WARNING "Unity Build is enabled, PCH might not provide additional benefits")
    endif()

    if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-Winvalid-pch)
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        add_compile_options(/Zm200)
    endif()
endfunction()



