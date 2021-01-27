cmake_minimum_required(VERSION 3.8.2)
set(QT_MINIMUM_VERSION 5.15.2)

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

# Include the Qt functions in the cmake folder
include(QtCommon)

project(chat_service VERSION 1.0.0)

fix_project_version()

# Set additional project information
set(COMPANY "Cameron")
set(COPYRIGHT "Copyright (c) 2021 Cameron Howell. All rights reserved.")
set(IDENTIFIER "com.cameron.Cameron")

set(SOURCE_FILES
  src/main.cpp
  src/mainwindow.cpp
  src/client.cpp
  )

add_project_meta(META_FILES_TO_INCLUDE)

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

add_executable(${PROJECT_NAME} ${OS_BUNDLE} # Expands to WIN32 or MACOS_BUNDLE depending on OS
    ${SOURCE_FILES} ${META_FILES_TO_INCLUDE} ${RESOURCE_FILES}
)

target_link_libraries(${PROJECT_NAME} ${LIBRARIES})

set_target_properties(${PROJECT_NAME} PROPERTIES INSTALL_RPATH_USE_LINK_PATH TRUE)

INSTALL(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION bin)
INCLUDE(InstallRequiredSystemLibraries)

if(WIN32)
  find_program(WINDEPLOYQT_EXECUTABLE NAMES windeployqt HINTS ${QTDIR} ENV QTDIR PATH_SUFFIXES bin)
  add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
  COMMAND ${WINDEPLOYQT_EXECUTABLE} $<TARGET_FILE:${PROJECT_NAME}>)

  install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Release/
                  RUNTIME DESTINATION bin
                  FILES_MATCHING
                  PATTERN "_CPack*" EXCLUDE
                  PATTERN "*.dll"
                  )
endif()