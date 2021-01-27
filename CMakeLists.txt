cmake_minimum_required(VERSION 3.8.2)

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
  )

add_project_meta(META_FILES_TO_INCLUDE)

set(RESOURCE_FILES example.qrc)

find_package(Qt5 COMPONENTS Widgets REQUIRED)

# Add a compiler flag
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")

add_executable(${PROJECT_NAME} ${OS_BUNDLE} # Expands to WIN32 or MACOS_BUNDLE depending on OS
    ${SOURCE_FILES} ${META_FILES_TO_INCLUDE} ${RESOURCE_FILES}
)

target_link_libraries(${PROJECT_NAME} Qt5::Widgets)