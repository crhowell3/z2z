cmake_minimum_required(VERSION 3.8.2)
set(QT_MINIMUM_VERSION 5.15.2)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

# Include the Qt functions in the cmake folder
include(QtCommon)

# Set additional project information
set(COMPANY "Cameron")
set(COPYRIGHT "Copyright (c) 2021 Cameron Howell. All rights reserved.")
set(IDENTIFIER "com.cameron.Cameron")

set(CLIENT_SOURCE_FILES
  src/client/ClientGui.cpp
  src/client/ClientThread.cpp
  src/client/ClientWindow.ui
  )

set(SERVER_SOURCE_FILES
  src/server/ServerGui.cpp
  src/server/ServerThread.cpp
  src/server/ServerWindow.ui
 )

set(RESOURCE_FILES example.qrc)

# Find the necessary Qt5 modules
find_package(Qt5Core REQUIRED)
find_package(Qt5Gui REQUIRED)
find_package(Qt5Widgets REQUIRED)

set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
set(THREADS_PREFER_PTHREAD_FLAG TRUE)

find_package(Threads REQUIRED)

# Add a compiler flag
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)

list(APPEND LIBRARIES
Qt5::Core
Qt5::Gui
Qt5::Widgets
Threads::Threads
)

list(REMOVE_DUPLICATES LIBRARIES)

add_executable(chat_client ${OS_BUNDLE} # Expands to WIN32 or MACOS_BUNDLE depending on OS
    ${CLIENT_SOURCE_FILES} ${RESOURCE_FILES}
)
target_link_libraries(chat_client ${LIBRARIES} ws2_32 mswsock advapi32)
set_target_properties(chat_client PROPERTIES INSTALL_RPATH_USE_LINK_PATH TRUE)

add_executable(chat_server ${OS_BUNDLE} # Expands to WIN32 or MACOS_BUNDLE depending on OS
    ${SERVER_SOURCE_FILES} ${RESOURCE_FILES}
)
target_link_libraries(chat_server ${LIBRARIES} ws2_32 mswsock advapi32)
set_target_properties(chat_server PROPERTIES INSTALL_RPATH_USE_LINK_PATH TRUE)

INSTALL(TARGETS chat_client chat_server RUNTIME DESTINATION bin)
INCLUDE(InstallRequiredSystemLibraries)

if(WIN32)
  find_program(WINDEPLOYQT_EXECUTABLE NAMES windeployqt HINTS ${QTDIR} ENV QTDIR PATH_SUFFIXES bin)
  add_custom_command(TARGET chat_client POST_BUILD
  COMMAND ${WINDEPLOYQT_EXECUTABLE} $<TARGET_FILE:chat_client>)

  install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Release/
                  RUNTIME DESTINATION bin
                  FILES_MATCHING
                  PATTERN "_CPack*" EXCLUDE
                  PATTERN "*.dll"
                  )
endif()

if(WIN32)
  find_program(WINDEPLOYQT_EXECUTABLE NAMES windeployqt HINTS ${QTDIR} ENV QTDIR PATH_SUFFIXES bin)
  add_custom_command(TARGET chat_server POST_BUILD
  COMMAND ${WINDEPLOYQT_EXECUTABLE} $<TARGET_FILE:chat_server>)

  install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Release/
                  RUNTIME DESTINATION bin
                  FILES_MATCHING
                  PATTERN "_CPack*" EXCLUDE
                  PATTERN "*.dll"
                  )
endif()