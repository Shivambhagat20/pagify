cmake_minimum_required(VERSION 3.14)
project(WindowsRunner)

# --- Apply MSVC flags globally (affects plugins too) ---
if (MSVC)
  # Do NOT treat warnings as errors across the whole solution.
  add_compile_options(/WX-)
  # Silence 'strncpy' deprecation warnings that Firebase C++ headers trigger.
  add_compile_options(/wd4996)
  # Allow legacy CRT funcs without warnings in third-party deps.
  add_definitions(-D_CRT_SECURE_NO_WARNINGS)
endif()

# Flutter-managed build rules for Windows.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# This pulls in the Flutter tool build pieces (defines apply_standard_settings, etc).
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Your app runner target lives here.
add_subdirectory(runner)
