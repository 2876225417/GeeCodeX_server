include_guard(GLOBAL)

set(BOOST_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/boost/boost_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/boost/build"
    "${DEPENDENCY_ROOT_DIR}/boost/install"
    "${DEPENDENCY_ROOT_DIR}/boost"
)

foreach(path ${BOOST_POSSIBLE_PATHS})
    set(config_path "${path}/lib/cmake/Boost-1.88.0")
    if (EXISTS "${config_path}/BoostConfig.cmake")
        pretty_message_kv(SUCCESS "Found Boost config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(Boost QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (Boost_FOUND)
            pretty_message_kv(SUCCESS "Boost loaded from" "${path}")
            pretty_message_kv(SUCCESS "Boost version" "${Boost_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT Boost_FOUND)
    pretty_message(OPTIONAL "Boost not found in local paths")
endif()

