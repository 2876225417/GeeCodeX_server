include_guard(GLOBAL)

option(EXPORT_PROJ_INFO  "Export project info into source"    ON)
set(PROJ_INFO_INPUT      "${CMAKE_SOURCE_DIR}/include/proj_config.h.in" CACHE STRING "Project info configurations input file")
set(PROJ_INFO_HEADER     "${CMAKE_BINARY_DIR}/include/proj_config.h" CACHE STRING "Project info generated configurations output file")
string(TIMESTAMP BUILD_TIMESTAMP "%Y-%m-%d %H:%M:%S")

if (EXPORT_PROJ_INFO)
    if (EXISTS ${PROJ_INFO_INPUT})
        pretty_message(SUCCESS "Found project info files: ${PROJ_INFO_INPUT}")
        configure_file(
            "${PROJ_INFO_INPUT}"
            "${PROJ_INFO_HEADER}"
            @ONLY
        )

        add_compile_definitions(EXPORT_PROJ_INFO=1)
        add_library(proj_config INTERFACE)
        target_include_directories(proj_config 
            INTERFACE
            $<BUILD_INTERFACE:${CMAKE_BINARY_DIR}/include>
            $<INSTALL_INTERFACE:include>
        )
    else ()
        pretty_message(ERROR "Not exist project info files: ${PROJ_INFO_INPUT}")
    endif()
endif()

function(print_project_info_debug_info)
    pretty_message(DEBUG "ProjectInfo.cmake module loaded.")
    pretty_message(VINFO_BANNER "ProjectInfo Configuration" "=" ${BANNER_WIDTH})
    pretty_message_kv(VINFO "EXPORT_PROJ_INFO"      "${EXPORT_PROJ_INFO} ")
    pretty_message_kv(VINFO "_DEPRECATED_INFO_"      "${_DEPRECATED_INFO_} ")
    pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
endfunction()