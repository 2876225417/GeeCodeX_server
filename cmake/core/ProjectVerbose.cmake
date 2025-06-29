include_guard(GLOBAL)

option(DEPRECATED_INFO "Enable deprecated info in project" ON)

if (DEPRECATED_INFO)
    add_compile_definitions(_DEPRECATED_INFO_=1)
endif()