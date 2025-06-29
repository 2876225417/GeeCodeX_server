include_guard(GLOBAL)


include(${CMAKE_CURRENT_LIST_DIR}/PrettyPrint.cmake)

function(show_qt_info)
    set(options DETAILED)
    cmake_parse_arguments(ARG "${options}" "" "" ${ARGN})

    if (NOT Qt6_FOUND AND NOT Qt5_FOUND)
        pretty_message(OPTION "Qt not found, skipping Qt info display")
        return()
    endif()

    pretty_message(VINFO_BANNER "Configuring Qt" "=" ${BANNER_WIDTH})

    if (Qt6_FOUND)
        set(QT_VERSION_MAJOR "6")
        set(QT_PREFIX "Qt6")
    elseif(Qt5_FOUND)
        set(QT_VERSION_MAJOR "5")
        set(QT_PREFIX "Qt5")
    endif()

    if (DEFINED ${QT_PREFIX}_VERSION)
        pretty_message_kv(VINFO "Qt Version" "${${QT_PREFIX}_VERSION}")
    elseif (DEFINED QT_VERSION)
        pretty_message_kv(VINFO "Qt Version" "${QT_VERSION}")
    else()
        if (DEFINED ${QT_PREFIX}Core_VERSION)
            pretty_message(VINFO "Qt Version" "${${QT_PREFIX}Core_VERSION}")
        else()
            pretty_message(VINFO "Qt Version" "Unknown")
        endif()
    endif()

    pretty_message_kv(VINFO "Qt Major Version" "${QT_VERSION_MAJOR}")

    if (DEFINED ${QT_PREFIX}_VERSION_MAJOR)
        pretty_message_kv(DEBUG "Major" "${${QT_PREFIX}_VERSION_MAJOR}")
    endif()
    if (DEFINED ${QT_PREFIX}_VERSION_MINOR)
        pretty_message_kv(DEBUG "Major" "${${QT_PREFIX}_VERSION_MINOR}")
    endif()
    if (DEFINED ${QT_PREFIX}_VERSION_PATCH)
        pretty_message_kv(DEBUG "Major" "${${QT_PREFIX}_VERSION_PATCH}")
    endif()

    if (DEFINED ${QT_PREFIX}_DIR)
        pretty_message_kv(VINFO "Qt Directory" "${${QT_PREFIX}_DIR}")
    endif()

    if (DEFINED QT_INSTALL_PREFIX)
        pretty_message_kv(VINFO "Qt Install Prefix" "${QT_INSTALL_PREFIX}")
    elseif (DEFINED ${QT_PREFIX}_INSTALL_PREFIX)
        pretty_message_kv(VINFO "Qt Install Prefix" "${${QT_PREFIX}_INSTALL_PREFIX}")
    else()
        if (TARGET ${QT_PREFIX}::qmake)
            get_target_property(QMAKE_LOCATION ${QT_PREFIX}::qmake LOCATION)
            if (QMAKE_LOCATION)
                get_filename_component(QT_BIN_DIR "${QMAKE_LOCATION}" DIRECTORY)
                get_filename_component(QT_INSTALL_PREFIX "${QT_BIN_DIR}" DIRECTORY)
                pretty_message_kv(VINFO "Qt Install Prefix" "${QT_INSTALL_PREFIX}")
            endif()
        endif()
    endif()

    pretty_message(INFO "Qt Components Found:")
    _show_qt_components(${QT_PREFIX})

    if (ARG_DETAILED)
        pretty_message(INFO "")
        pretty_message(INFO "Detailed Qt Information:")
        _show_qt_detailed_info(${QT_PREFIX})
    endif()

    pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
endfunction()

function(_show_qt_components QT_PREFIX)
    set(QT_COMMON_COMPONENTS
        Core
        Gui
        Widgets
        Network
        Sql
        Xml
        Concurrent
        PrintSupport
        OpenGL
        Svg
        Test
        Designer
        Help
        LinguistTools
        UiTools
        Quick
        QuickWidgets
        Qml
        QmlModels
        WebEngineCore
        WebEngineWidgets
        Charts
        DataVisualization
        3DCore
        3DRender
        3DInput
        3DLogic
        3DExtras
        SerialPort
        Multimedia
        MultimediaWidgets
        Positioning
        Location
        Sensors
        WebSockets
        WebChannel
        Bluetooth
        Nfc
    )

    set(FOUND_COMPONENTS "")
    set(MISSING_COMPONENTS "")
    
    foreach(component ${QT_COMMON_COMPONENTS})
        if(TARGET ${QT_PREFIX}::${component})
            list(APPEND FOUND_COMPONENTS ${component})
        else()
            list(APPEND MISSING_COMPONENTS ${component})
        endif()
    endforeach()

    foreach(component ${FOUND_COMPONENTS})
        if (TARGET ${QT_PREFIX}::${component})
            get_target_property(comp_version ${QT_PREFIX}::${component} VERSION)
            if (comp_version)
                pretty_message(SUCCESS "  ✓ ${component} (${comp_version})")
            else()
                pretty_message(SUCCESS "  ✓ ${component}")
            endif()
        endif()
    endforeach()
    
    list(LENGTH MISSING_COMPONENTS MISSING_COUNT)
    if(MISSING_COUNT GREATER 0)
        pretty_message(DEBUG "Components not found: ${MISSING_COUNT}")
        foreach(component ${MISSING_COMPONENTS})
            pretty_message(DEBUG "  ○ ${component}")
        endforeach()
    endif()
endfunction()

function(_show_qt_detailed_info QT_PREFIX)
    pretty_message(INFO "Qt Build Configuration:")
    
    if (DEFINED QT_IS_STATIC)
        if (QT_IS_STATIC)
            pretty_message(INFO "  Build Type: Static")
        else()
            pretty_message(INFO "  Build Type: Shared")
        endif()
    endif()

    pretty_message(INFO "Qt Tools: ")
    set(QT_TOOLS moc rcc uic qmake lupdate lrelease)
    foreach(tool ${QT_TOOLS})
        string(TOUPPER ${tool} TOOL_UPPER)
        if (DEFINED QT_${TOOL_UPPER}_EXECUTABLE OR DEFINED ${QT_PREFIX}_${TOOL_UPPER}_EXECUTABLE)
            if (DEFINED ${QT_PREFIX}_${TOOL_UPPER}_EXECUTABLE)
                set(tool_path ${${QT_PREFIX}_${TOOL_UPPER}_EXECUTABLE})
            else()
                set(tool_path ${QT_${TOOL_UPPER}_EXECUTABLE})
            endif()

            if (EXISTS ${tool_path})
                pretty_message(SUCCESS  "  ✓ ${tool}: ${tool_path}")
            else()
                pretty_message(OPTIONAL "  ? ${tool}: ${tool_path} (not found)")
            endif()
        endif()
    endforeach()

    if (DEFINED QT_PLUGINS_DIR OR DEFINED ${QT_PREFIX}_PLUGINS_DIR)
        if (DEFINED ${QT_PREFIX}_PLUGINS_DIR)
            pretty_message(INFO     "Qt Plugins Directory: ${${QT_PREFIX}_PLUGINS_DIR}")
        else()
            pretty_message(OPTIONAL "Qt Plugins Directory: ${QT_PLUGINS_DIR}")
        endif()
    endif()
    
    if (DEFINED QT_QML_DIR OR DEFINED ${QT_PREFIX}_QML_DIR)
        if (DEFINED ${QT_PREFIX}_QML_DIR)
            pretty_message(INFO     "Qt QML Directory: ${${QT_PREFIX}_QML_DIR}")
        else()
            pretty_message(OPTIONAL "Qt QML Directory: ${QT_QML_DIR}")
        endif()
    endif()
endfunction()

function(show_qt_deploy_info TARGET_NAME)
    if (NOT TARGET ${TARGET_NAME})
        pretty_message(ERROR "Target '${TARGET_NAME}' does not exist")
        return()
    endif()

    pretty_message(INFO "Qt Deployment Info for ${TARGET_NAME}:")
    
    get_target_property(link_libs ${TARGET_NAME} LINK_LIBRARIES)
    if (link_libs)
        set(qt_libs "")
        foreach(lib ${link_libs})
            if (lib MATCHES "^Qt[0-9]+::")
                list(APPEND qt_libs ${lib})
            endif()
        endforeach()

        if (qt_libs)
            pretty_message(INFO "  Qt Libraries Used:")
            foreach(lib ${qt_libs})
                pretty_message(INFO "   - ${lib}")
            endforeach()
        endif()
    endif()

    if (WIN32)
        pretty_message(INFO "  Deployment Tool: windeployqt")
    elseif (APPLE)
        pretty_message(INFO "  Deployment Tool: macdeployqt")
    else()
        pretty_message(INFO "  Deployment: Manual or use linuxdeployqt")
    endif()
endfunction()

function(setup_qt_target TARGET_NAME)
    if (NOT TARGET ${TARGET_NAME})
        return()
    endif()

    set_target_properties(${TARGET_NAME} PROPERTIES
        AUTOMOC ON
        AUTOUIC ON 
        AUTORCC ON
    )

    target_compile_features(${TARGET_NAME} PUBLIC cxx_std_17)

    if (WIN32)
        set_target_properties(${TARGET_NAME} PROPERTIES
            WIN32_EXECUTABLE TRUE
        )
    endif()

    pretty_message(INFO "Qt target '${TARGET_NAME}' configured with AUTOMOC, AUTOUIC, AUTORCC")
endfunction()
