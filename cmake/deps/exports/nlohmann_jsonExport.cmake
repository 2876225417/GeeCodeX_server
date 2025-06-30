include_guard(GLOBAL)

set(NLOHMANN_JSON_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/nlohmann_json/nlohmann_json_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/nlohmann_json/build"
    "${DEPENDENCY_ROOT_DIR}/nlohmann_json/install"
    "${DEPENDENCY_ROOT_DIR}/nlohmann_json"
)

foreach(path ${NLOHMANN_JSON_POSSIBLE_PATHS})
    set(config_path "${path}/nlohmann_json/share/cmake/nlohmann_json")
    if (EXISTS "${config_path}/nlohmann_jsonConfig.cmake")
        pretty_message_kv(SUCCESS "Found nlohmann_json config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(nlohmann_json QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (nlohmann_json_FOUND)
            pretty_message_kv(SUCCESS "nlohmann_json loaded from" "${path}")
            pretty_message_kv(SUCCESS "nlohmann_json version" "${nlohmann_json_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT nlohmann_json_FOUND)
    pretty_message(OPTIONAL "nlohmann_json not found in local paths")
endif()

