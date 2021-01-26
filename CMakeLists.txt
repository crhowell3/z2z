# version
cmake_minimum_required( VERSION 3.5 )

# project name
project(chat_service LANGUAGES CXX )

set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(QT NAMES Qt6 Qt5 COMPONENTS Widgets REQUIRED)
find_package(Qt${QT_VERSION_MAJOR} COMPONENTS Widgets REQUIRED)

set(PROJECT_SOURCES
        ./src/main.cpp
        ./src/mainwindow.cpp
        ./src/mainwindow.h
        ./src/mainwindow.ui
)

if(${QT_VERSION_MAJOR} GREATER_EQUAL 6)
    qt_add_executable(chat_service
        ${PROJECT_SOURCES}
    )
else()
    if(ANDROID)
        add_library(chat_service SHARED
            ${PROJECT_SOURCES}
        )
    else()
        add_executable(chat_service
            ${PROJECT_SOURCES}
        )
    endif()
endif()

target_link_libraries(chat_service PRIVATE Qt${QT_VERSION_MAJOR}::Widgets)