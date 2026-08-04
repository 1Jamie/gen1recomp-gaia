cmake_minimum_required(VERSION 3.24)
project(Gen1RecompUWP LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "Configure with a WindowsStore preset.")
endif()

get_filename_component(GAME_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(THIRD_PARTY_ROOT "${CMAKE_CURRENT_LIST_DIR}/third_party")
set(LOVE_ROOT "${THIRD_PARTY_ROOT}/love")
set(SDL2_ROOT "${THIRD_PARTY_ROOT}/sdl2")
set(ANGLE_ROOT "${THIRD_PARTY_ROOT}/angle")
set(RUNTIME_ROOT "${THIRD_PARTY_ROOT}/runtime")

set(REQUIRED_FILES
    "${THIRD_PARTY_ROOT}/manifest.json"
    "${LOVE_ROOT}/lib/lovestatic.lib"
    "${LOVE_ROOT}/lib/liblove.lib"
    "${LOVE_ROOT}/lib/lua51.lib"
    "${LOVE_ROOT}/bin/love.dll"
    "${LOVE_ROOT}/bin/lua51.dll"
    "${SDL2_ROOT}/include/SDL2/SDL.h"
    "${SDL2_ROOT}/lib/SDL2.lib"
    "${SDL2_ROOT}/bin/SDL2.dll"
    "${ANGLE_ROOT}/bin/libEGL.dll"
    "${ANGLE_ROOT}/bin/libGLESv2.dll"
    "${ANGLE_ROOT}/bin/d3dcompiler_47.dll"
)
foreach(path IN LISTS REQUIRED_FILES)
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Missing UWP dependency: ${path}")
    endif()
endforeach()

set(GAME_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/gen1recomp.love")
set_source_files_properties("${GAME_ARCHIVE}" PROPERTIES GENERATED TRUE)
add_custom_target(gen1recomp_love ALL
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
        "${CMAKE_CURRENT_LIST_DIR}/scripts/package-game.ps1"
        -SourceRoot "${GAME_ROOT}" -Output "${GAME_ARCHIVE}"
    BYPRODUCTS "${GAME_ARCHIVE}"
    VERBATIM
)

add_custom_target(verify_uwp_dependencies
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File
        "${CMAKE_CURRENT_LIST_DIR}/scripts/verify-dependencies.ps1"
    VERBATIM
)

add_executable(${PROJECT_NAME} WIN32 "app/main.cpp")
add_dependencies(${PROJECT_NAME} gen1recomp_love verify_uwp_dependencies)
set_target_properties(${PROJECT_NAME} PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    VS_SDK_REFERENCES "Microsoft.VCLibs, Version=14.0"
)
target_include_directories(${PROJECT_NAME} PRIVATE "${SDL2_ROOT}/include/SDL2")
target_link_libraries(${PROJECT_NAME} PRIVATE
    "${LOVE_ROOT}/lib/lovestatic.lib"
    "${LOVE_ROOT}/lib/liblove.lib"
    "${SDL2_ROOT}/lib/SDL2.lib"
    "${LOVE_ROOT}/lib/lua51.lib"
    WindowsApp.lib
)

set(PACKAGE_ROOT_FILES
    "${CMAKE_CURRENT_LIST_DIR}/Package.appxmanifest"
    "${GAME_ARCHIVE}"
    "${LOVE_ROOT}/bin/love.dll"
    "${LOVE_ROOT}/bin/lua51.dll"
    "${SDL2_ROOT}/bin/SDL2.dll"
    "${ANGLE_ROOT}/bin/libEGL.dll"
    "${ANGLE_ROOT}/bin/libGLESv2.dll"
    "${ANGLE_ROOT}/bin/d3dcompiler_47.dll"
)

set(RUNTIME_NAMES
    brotlicommon.dll brotlidec.dll bz2.dll fmt.dll freetype.dll libpng16.dll
    OpenAL32.dll theora.dll theoradec.dll vorbis.dll vorbisfile.dll ogg.dll z.dll
)
foreach(name IN LISTS RUNTIME_NAMES)
    set(runtime "${RUNTIME_ROOT}/bin/${name}")
    if(NOT EXISTS "${runtime}")
        message(FATAL_ERROR "Missing UWP runtime DLL: ${name}")
    endif()
    list(APPEND PACKAGE_ROOT_FILES "${runtime}")
endforeach()

set_source_files_properties(${PACKAGE_ROOT_FILES} PROPERTIES
    VS_COPY_TO_OUT_DIR Always
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "."
)

file(GLOB PACKAGE_ASSETS CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/Assets/*.png")
set_source_files_properties(${PACKAGE_ASSETS} PROPERTIES
    VS_DEPLOYMENT_CONTENT TRUE
    VS_DEPLOYMENT_LOCATION "Assets"
)
target_sources(${PROJECT_NAME} PRIVATE ${PACKAGE_ROOT_FILES} ${PACKAGE_ASSETS})
