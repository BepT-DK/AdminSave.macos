cmake_minimum_required(VERSION 3.20)

# Universal binary for macOS 11+, the same floor as Nextpad++ itself.
# Both must be set before project().
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "")

project(AdminSave VERSION 1.0.1 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# The plugin. The host loads plugins/<Folder>/<Folder>.dylib, so the file must
# be named exactly AdminSave.dylib.
add_library(AdminSave SHARED src/AdminSave.mm)
# vendor/ holds the host's plugin interface header, unmodified (see vendor/README.md).
target_include_directories(AdminSave PRIVATE vendor)
target_compile_definitions(AdminSave PRIVATE ADMINSAVE_VERSION="${PROJECT_VERSION}")
target_compile_options(AdminSave PRIVATE -Wall -Wextra -fvisibility=hidden -fobjc-arc)
target_link_libraries(AdminSave PRIVATE "-framework AppKit" "-framework Security")
set_target_properties(AdminSave PROPERTIES PREFIX "" SUFFIX ".dylib")
# Plugins Admin reads the installed version from the dylib's current_version.
target_link_options(AdminSave PRIVATE "-Wl,-current_version,${PROJECT_VERSION}")

# cmake --install build: copies the plugin into Nextpad++. Quit the editor first.
install(TARGETS AdminSave
        DESTINATION "$ENV{HOME}/Library/Application Support/Nextpad++/plugins/AdminSave")

# Self-check: the plugin loaded over a fake EditorView (test/test.mm).
#   ctest --test-dir build                  no prompts
#   cmake --build build --target test-auth  three admin prompts
enable_testing()
add_executable(adminsave-test test/test.mm)
target_include_directories(adminsave-test PRIVATE vendor)
target_compile_options(adminsave-test PRIVATE -Wall -Wextra -fobjc-arc)
target_link_libraries(adminsave-test PRIVATE "-framework Foundation")
add_test(NAME selfcheck COMMAND adminsave-test $<TARGET_FILE:AdminSave>)
add_custom_target(test-auth
    COMMAND adminsave-test $<TARGET_FILE:AdminSave> --auth
    USES_TERMINAL)

# cmake --build build --target zip: release archive in the layout Plugins Admin
# expects, AdminSave/AdminSave.dylib, written to build/zip/.
add_custom_target(zip
    COMMAND ${CMAKE_COMMAND} -E rm -rf zip
    COMMAND ${CMAKE_COMMAND} -E make_directory zip/AdminSave
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:AdminSave> zip/AdminSave/
    COMMAND ${CMAKE_COMMAND} -E chdir zip
            ${CMAKE_COMMAND} -E tar cf AdminSavev${PROJECT_VERSION}.zip --format=zip AdminSave
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
