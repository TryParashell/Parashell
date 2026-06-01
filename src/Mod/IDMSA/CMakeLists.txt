# SPDX-License-Identifier: LGPL-2.1-or-later

file(GLOB IDMSA_Binaries CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.pyd"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.so"
)

if(NOT IDMSA_Binaries)
    message(FATAL_ERROR "No compiled IDMSA extensions (*.pyd/*.so) found in ${CMAKE_CURRENT_SOURCE_DIR}. "
                        "Run the Build Cython Modules workflow and sync the output before building.")
endif()

SET(IDMSA_SRCS
    Init.py
    InitGui.py
    IDMSA_prompts.py
)

SET(IDMSA_ALL ${IDMSA_SRCS} ${IDMSA_Binaries})
SOURCE_GROUP("" FILES ${IDMSA_ALL})

ADD_CUSTOM_TARGET(IDMSA ALL
    SOURCES ${IDMSA_ALL}
)

fc_copy_sources(IDMSA "${CMAKE_BINARY_DIR}/Mod/IDMSA" ${IDMSA_ALL})

INSTALL(
    FILES
        ${IDMSA_ALL}
    DESTINATION
        Mod/IDMSA
)
