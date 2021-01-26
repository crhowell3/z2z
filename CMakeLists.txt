# version
cmake_minimum_required( VERSION 3.8.0 FATAL_ERROR )

# project name
project(chat_service VERSION 1.0.0 LANGUAGES CXX )

# flags
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

# packages
find_package(Qt5 COMPONENTS Widgets REQUIRED)

# add executable
add_executable(chat_service ./src/main.cpp)

target_link_libraries(chat_service Qt5::Widgets)