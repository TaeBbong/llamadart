cmake_minimum_required(VERSION 3.10)
project(llamadart_linux LANGUAGES C CXX)

# Include the central native build logic
add_subdirectory(../src/native ${CMAKE_CURRENT_BINARY_DIR}/native)
