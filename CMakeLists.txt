# version
cmake_minimum_required( VERSION 3.0 )

# project name
project( chat_service )

# flags

# files

# include
include_directories ( ./include ./src )

# target
add_executable( client ./src/client.cpp )
add_executable( server ./src/server.cpp )
