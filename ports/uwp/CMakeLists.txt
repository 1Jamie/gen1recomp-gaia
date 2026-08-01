cmake_minimum_required(VERSION 3.24)
project(Gen1RecompUWP LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    message(FATAL_ERROR "Configure with a WindowsStore preset.")
endif()

foreach(required_env LOVE_UWP_ROOT UWP_SDL2_ANGLE_ROOT VCPKG_ROOT)
    if(NOT DEFINED ENV{${required_env}} OR "$ENV{${required_env}}" STREQUAL "")
        message(FATAL_ERROR "Set ${required_env} before configuring.")
    endif()
endforeach()

file(TO_CMAKE_PATH "$ENV{LOVE_UWP_ROOT}" LOVE_UWP_ROOT)
file(TO_CMAKE_PATH "$ENV{UWP_SDL2_ANGLE_ROOT}" UWP_SDL2_ANGLE_ROOT)
file(TO_CMAKE_PATH "$ENV{VCPKG_ROOT}" VCPKG_ROOT)
get_filename_component(GAME_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(ANGLE_RUNTIME_ROOT "${CMAKE_CURRENT_LIST_DIR}/third_party/angle")

set(LOVE_BUILD_ROOT "${LOVE_UWP_ROOT}/build/uwp-x64-angle" CACHE PATH "LÖVE UWP build directory")
set(LOVE_CONFIG "RelWithDebInfo" CACHE STRING "Configuration used for the LÖVE UWP backend")
set(LOVE_OUTPUT_ROOT "${LOVE_BUILD_ROOT}/${LOVE_CONFIG}")
if(LOVE_CONFIG STREQUAL "Release" OR LOVE_CONFIG STREQUAL "Debug")
    set(LOVE_LIBRARY "${LOVE_OUTPUT_ROOT}/liblove.lib")
    set(LOVE_RUNTIME "${LOVE_OUTPUT_ROOT}/love.dll")
else()
    set(LOVE_LIBRARY "${LOVE_OUTPUT_ROOT}/libliblove.lib")
    set(LOVE_RUNTIME "${LOVE_OUTPUT_ROOT}/liblove.dll")
endif()

set(REQUIRED_FILES
    "${LOVE_OUTPUT_ROOT}/lovestatic.lib"
    "${LOVE_LIBRARY}"
    "${LOVE_RUNTIME}"
    "${LOVE_OUTPUT_ROOT}/lua51.lib"
    "${LOVE_OUTPUT_ROOT}/lua51.dll"
    "${UWP_SDL2_ANGLE_ROOT}/include/SDL2/SDL.h"
    "${UWP_SDL2_ANGLE_ROOT}/lib/SDL2.lib"
    "${UWP_SDL2_ANGLE_ROOT}/bin/SDL2.dll"
    "${ANGLE_RUNTIME_ROOT}/libEGL.dll"
    "${ANGLE_RUNTIME_ROOT}/libGLESv2.dll"
    "${ANGLE_RUNTIME_ROOT}/d3dcompiler_47.dll"
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

add_executable(${PROJECT_NAME} WIN32 "app/main.cpp")
add_dependencies(${PROJECT_NAME} gen1recomp_love)
set_target_properties(${PROJECT_NAME} PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    VS_SDK_REFERENCES "Microsoft.VCLibs, Version=14.0"
)
target_include_directories(${PROJECT_NAME} PRIVATE "${UWP_SDL2_ANGLE_ROOT}/include/SDL2")
target_link_libraries(${PROJECT_NAME} PRIVATE
    "${LOVE_OUTPUT_ROOT}/lovestatic.lib"
    "${LOVE_LIBRARY}"
    "${UWP_SDL2_ANGLE_ROOT}/lib/SDL2.lib"
    "${LOVE_OUTPUT_ROOT}/lua51.lib"
    WindowsApp.lib
)

set(PACKAGE_ROOT_FILES
    "${CMAKE_CURRENT_LIST_DIR}/Package.appxmanifest"
    "${GAME_ARCHIVE}"
    "${LOVE_RUNTIME}"
    "${LOVE_OUTPUT_ROOT}/lua51.dll"
    "${UWP_SDL2_ANGLE_ROOT}/bin/SDL2.dll"
    "${ANGLE_RUNTIME_ROOT}/libEGL.dll"
    "${ANGLE_RUNTIME_ROOT}/libGLESv2.dll"
    "${ANGLE_RUNTIME_ROOT}/d3dcompiler_47.dll"
)

set(VCPKG_RUNTIME_NAMES
    brotlicommon.dll brotlidec.dll bz2.dll fmt.dll freetype.dll libpng16.dll
    OpenAL32.dll theora.dll theoradec.dll vorbis.dll vorbisfile.dll ogg.dll z.dll
)
foreach(name IN LISTS VCPKG_RUNTIME_NAMES)
    set(runtime "${VCPKG_ROOT}/installed/x64-uwp/bin/${name}")
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
