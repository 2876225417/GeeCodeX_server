include_guard(GLOBAL)

set(DEPENDENCY_FIND_STRATEGIES
    "MANUAL" # 手动指定
    "LOCAL"  # 项目本地的 3rdparty
    "SYSTEM" # 系统安装的库
)

set(DEPENDENCY_ROOT_DIR "${CMAKE_SOURCE_DIR}/3rdparty")
set(DEPENDENCY_EXPORTS_DIR "${CMAKE_CURRENT_LIST_DIR}/exports")

set(DEFAULT_FIND_STRATEGY "LOCAL" CACHE STRING "Default dependency find strategy")
set_property(CACHE DEFAULT_FIND_STRATEGY PROPERTY STRINGS ${DEPENDENCY_FIND_STRATEGIES})

set_property(GLOBAL PROPERTY FOUND_DEPENDENCIES "")

function(dependency_manager_init)
    pretty_message(VINFO_BANNER "Configuring Dependency Manager" "=" ${BANNER_WIDTH})
    pretty_message_kv(VINFO "Default strategy"  "${DEFAULT_FIND_STRATEGY}")
    pretty_message_kv(VINFO "3rdparty root"     "${DEPENDENCY_ROOT_DIR}")
    pretty_message_kv(VINFO "Export directory"  "${DEPENDENCY_EXPORTS_DIR}")
    pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
    pretty_message(STATUS "")
    _create_dependency_cache_variables()
endfunction()

function(_create_dependency_cache_variables)
    file(GLOB export_files "${DEPENDENCY_EXPORTS_DIR}/*Export.cmake")
    foreach(export_file ${export_files})
        get_filename_component(dep_name ${export_file} NAME_WE)
        string(REGEX REPLACE "Export$" "" dep_name ${dep_name})
        string(TOUPPER ${dep_name} dep_upper)
        
        set(${dep_upper}_FIND_STRATEGY "${DEFAULT_FIND_STRATEGY}" CACHE STRING "Find strategy for ${dep_name}")
        set_property(CACHE ${dep_upper}_FIND_STRATEGY PROPERTY STRINGS ${DEPENDENCY_FIND_STRATEGIES})

        set(${dep_upper}_ROOT "" CACHE PATH "Manual specified root path for ${dep_name}")
    endforeach()
endfunction()

function(find_dependency dep_name)
    cmake_parse_arguments(FIND_DEP
        "REQUIRED;QUIET"
        "VERSION;STRATEGY"
        "COMPONENTS"
        ${ARGN}
    )

    string(TOUPPER ${dep_name} dep_upper)

    if (FIND_DEP_STRATEGY)
        set(strategy ${FIND_DEP_STRATEGY})
    elseif(DEFINED ${dep_upper}_FIND_STRATEGY)
        set(strategy ${${dep_upper}_FIND_STRATEGY})
    else()
        set(strategy ${DEFAULT_FIND_STRATEGY})
    endif()
    
    pretty_message(VINFO_BANNER "Configuring ${dep_name}" "=" ${BANNER_WIDTH})

    pretty_message_kv(VINFO "Finding ${dep_name} using strategy" "${strategy}")

    get_property(found_deps GLOBAL PROPERTY FOUND_DEPENDENCIES)
    if (${dep_name} IN_LIST found_deps)
        pretty_message(STATUS "${dep_name} already found, skipping")
        return()
    endif()

    set(found FALSE)
    if (strategy STREQUAL "MANUAL")
        _find_dependency_manual(${dep_name} found)
    elseif (strategy STREQUAL "LOCAL")
        _find_dependency_local(${dep_name} found)
    elseif (strategy STREQUAL "SYSTEM")
        _find_dependency_system(${dep_name} found)
    else()
        pretty_message(ERROR "Unknown find strategy: ${strategy}")
    endif()

    if (NOT found)
        pretty_message(OPTIONAL "${strategy} strategy failed, trying fallback strategies")
        foreach(fallback_strategy ${DEPENDENCY_FIND_STRATEGIES})
            if (NOT fallback_strategy STREQUAL strategy)    
                pretty_message(INFO "Trying fallback strategy: ${fallback_strategy}")
                if (fallback_strategy STREQUAL "LOCAL")
                    _find_dependency_local(${dep_name} found)
                elseif (fallback_strategy STREQUAL "SYSTEM")
                    _find_dependency_system(${dep_name} found)
                elseif (fallback_strategy STREQUAL "MANUAL")
                    _find_dependency_manual(${dep_name} found)
                endif()

                if (found)
                    break()
                endif()
            endif()
        endforeach()
    endif()

    if (found) 
        set_property(GLOBAL APPEND PROPERTY FOUND_DEPENDENCIES ${dep_name})
        pretty_message(SUCCESS "  ✓ ${dep_name} found successfully")
        pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
        pretty_message(STATUS "")
    else()
        if (FIND_DEP_REQUIRED)
            pretty_message(FATAL_ERROR "Required dependency ${dep_name} not found")
            pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
            pretty_message(VINFO "")
        else()
            pretty_message(OPTIONAL    "Optional dependency ${dep_name} not found")
            pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
            pretty_message(VINFO "")
        endif()
    endif()
endfunction()

# 手动路径查找
function(_find_dependency_manual dep_name out_found)
    string(TOUPPER ${dep_name} dep_upper)

    if (NOT DEFINED ${dep_upper}_ROOT OR "${${dep_upper}_ROOT}" STREQUAL "")
        pretty_message(OPTIONAL "No manual path specified for ${dep_name}")
        set(${out_found} FALSE PARENT_SCOPE)
        return()
    endif()

    set(manual_path ${${dep_upper}_ROOT})
    pretty_message_kv(VINFO "Using manual path for ${dep_name}" "${manual_path}")
    
    find_package(${dep_name} QUIET CONFIG PATHS ${manual_path} NO_DEFAULT_PATH)

    if (${dep_name}_FOUND)
        pretty_message(SUCCESS "Found ${dep_name} via manual path")
        set(${out_found} TRUE PARENT_SCOPE)
    else()
        pretty_message(OPTIONAL "Failed to find ${dep_name} via manual path")
        set(${out_found} FALSE PARENT_SCOPE)
    endif()
endfunction()


# 本地 3rdparty 中查找
function(_find_dependency_local dep_name out_found)
    set(export_file "${DEPENDENCY_EXPORTS_DIR}/${dep_name}Export.cmake")
    if (EXISTS ${export_file})
        pretty_message_kv(VINFO "Using export file" "${export_file}")
        include(${export_file})

        if (${dep_name}_FOUND)
            set(${out_found} TRUE PARENT_SCOPE)
            return()
        endif()
    endif()

    set(possible_paths
        "${DEPENDENCY_ROOT_DIR}/${dep_name}"
        "${DEPENDENCY_ROOT_DIR}/${dep_name}/${dep_name}_linux-x86_64"
        "${DEPENDENCY_ROOT_DIR}/${dep_name}/linux-x86_64"
        "${DEPENDENCY_ROOT_DIR}/${dep_name}/build"
        "${DEPENDENCY_ROOT_DIR}/${dep_name}/install"
    )

    foreach(path ${possible_paths})
        if (EXISTS ${path})
            pretty_message(INFO "Trying local path: ${path}")
            find_package(${dep_name} QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
            if (${dep_name}_FOUND)
                pretty_message(SUCCESS "Found ${dep_name} in local path: ${path}")
                set(${out_found} TRUE PARENT_SCOPE)
                return()
            endif()
        endif()
    endforeach()
    
    set(${out_found} FALSE PARENT_SCOPE)
endfunction()

# 在系统中进行查找
function(_find_dependency_system dep_name out_found)
    pretty_message(INFO "Searching for ${dep_name} in system")
    find_package(${dep_name} QUIET CONFIG)
    
    if (${dep_name}_FOUND)
        pretty_message(SUCCESS "Found ${dep_name} in system")
        set(${out_found} TRUE PARENT_SCOPE)
    else()
        set(${out_found} FALSE PARENT_SCOPE)
    endif()
endfunction()

# 批量查找依赖
function(find_dependencies)
    cmake_parse_arguments(FIND_DEPS
        ""
        ""
        "DEPENDENCIES"
        ${ARGN}
    )

    foreach(dep ${FIND_DEPS_DEPENDENCIES})
        find_dependency(${dep})
    endforeach()
endfunction()

function(print_dependency_summary)
    get_property(found_deps GLOBAL PROPERTY FOUND_DEPENDENCIES)    
    
    pretty_message(IMPORTANT "╔════════════════════════════════════════════════════════════════════╗")
    pretty_message(IMPORTANT "║                        Dependency   Summary                        ║")
    pretty_message(IMPORTANT "╚════════════════════════════════════════════════════════════════════╝")

    if (found_deps)
        foreach (dep ${found_deps})
            pretty_message(VINFO "  ✓ ${dep}")
        endforeach()
    else()
        pretty_message(OPTIONAL "  No dependencies found")
    endif()

    pretty_message(IMPORTANT "══════════════════════════════════════════════════════════════════════")
endfunction()
