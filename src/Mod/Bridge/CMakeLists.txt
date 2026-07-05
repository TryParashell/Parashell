# SPDX-License-Identifier: LGPL-2.1-or-later

file(GLOB_RECURSE Bridge_Binaries CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.pyd"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.so"
)

if(NOT Bridge_Binaries)
    message(FATAL_ERROR "No compiled Bridge extensions (*.pyd/*.so) found in ${CMAKE_CURRENT_SOURCE_DIR}. "
                        "Run the Build Cython Modules workflow and sync the output before building.")
endif()

SET(Bridge_SRCS
    Init.py
    InitGui.py
    acs.py
)

SET(Bridge_ALL ${Bridge_SRCS} ${Bridge_Binaries})
SOURCE_GROUP("" FILES ${Bridge_ALL})

ADD_CUSTOM_TARGET(Bridge ALL
    SOURCES ${Bridge_ALL}
)

fc_copy_sources(Bridge "${CMAKE_BINARY_DIR}/Mod/Bridge" ${Bridge_ALL})

foreach(_bridge_file IN LISTS Bridge_ALL)
    get_filename_component(_bridge_dir "${_bridge_file}" DIRECTORY)
    if(_bridge_dir)
        install(FILES "${_bridge_file}" DESTINATION "Mod/Bridge/${_bridge_dir}")
    else()
        install(FILES "${_bridge_file}" DESTINATION Mod/Bridge)
    endif()
endforeach()
