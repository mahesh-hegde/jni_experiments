# CMAKE generated file: DO NOT EDIT!
# Generated by "Unix Makefiles" Generator, CMake Version 3.18

# Delete rule output on recipe failure.
.DELETE_ON_ERROR:


#=============================================================================
# Special targets provided by cmake.

# Disable implicit rules so canonical targets will work.
.SUFFIXES:


# Disable VCS-based implicit rules.
% : %,v


# Disable VCS-based implicit rules.
% : RCS/%


# Disable VCS-based implicit rules.
% : RCS/%,v


# Disable VCS-based implicit rules.
% : SCCS/s.%


# Disable VCS-based implicit rules.
% : s.%


.SUFFIXES: .hpux_make_needs_suffix_list


# Command-line flag to silence nested $(MAKE).
$(VERBOSE)MAKESILENT = -s

#Suppress display of executed commands.
$(VERBOSE).SILENT:

# A target that is always out of date.
cmake_force:

.PHONY : cmake_force

#=============================================================================
# Set environment variables for the build.

# The shell in which to execute make rules.
SHELL = /bin/sh

# The CMake executable.
CMAKE_COMMAND = /usr/bin/cmake

# The command to remove a file.
RM = /usr/bin/cmake -E rm -f

# Escaping for special characters.
EQUALS = =

# The top-level source directory on which CMake was run.
CMAKE_SOURCE_DIR = /home/mahesh/Code/Flutter/jnigen/jni/src

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /home/mahesh/Code/Flutter/jnigen/jni/src

# Include any dependencies generated for this target.
include CMakeFiles/jni.dir/depend.make

# Include the progress variables for this target.
include CMakeFiles/jni.dir/progress.make

# Include the compile flags for this target's objects.
include CMakeFiles/jni.dir/flags.make

CMakeFiles/jni.dir/dartjni.c.o: CMakeFiles/jni.dir/flags.make
CMakeFiles/jni.dir/dartjni.c.o: dartjni.c
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/home/mahesh/Code/Flutter/jnigen/jni/src/CMakeFiles --progress-num=$(CMAKE_PROGRESS_1) "Building C object CMakeFiles/jni.dir/dartjni.c.o"
	/usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -o CMakeFiles/jni.dir/dartjni.c.o -c /home/mahesh/Code/Flutter/jnigen/jni/src/dartjni.c

CMakeFiles/jni.dir/dartjni.c.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing C source to CMakeFiles/jni.dir/dartjni.c.i"
	/usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -E /home/mahesh/Code/Flutter/jnigen/jni/src/dartjni.c > CMakeFiles/jni.dir/dartjni.c.i

CMakeFiles/jni.dir/dartjni.c.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling C source to assembly CMakeFiles/jni.dir/dartjni.c.s"
	/usr/bin/cc $(C_DEFINES) $(C_INCLUDES) $(C_FLAGS) -S /home/mahesh/Code/Flutter/jnigen/jni/src/dartjni.c -o CMakeFiles/jni.dir/dartjni.c.s

# Object files for target jni
jni_OBJECTS = \
"CMakeFiles/jni.dir/dartjni.c.o"

# External object files for target jni
jni_EXTERNAL_OBJECTS =

libdartjni.so: CMakeFiles/jni.dir/dartjni.c.o
libdartjni.so: CMakeFiles/jni.dir/build.make
libdartjni.so: /usr/lib/jvm/default-java/lib/libjawt.so
libdartjni.so: /usr/lib/jvm/default-java/lib/server/libjvm.so
libdartjni.so: CMakeFiles/jni.dir/link.txt
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --bold --progress-dir=/home/mahesh/Code/Flutter/jnigen/jni/src/CMakeFiles --progress-num=$(CMAKE_PROGRESS_2) "Linking C shared library libdartjni.so"
	$(CMAKE_COMMAND) -E cmake_link_script CMakeFiles/jni.dir/link.txt --verbose=$(VERBOSE)

# Rule to build all files generated by this target.
CMakeFiles/jni.dir/build: libdartjni.so

.PHONY : CMakeFiles/jni.dir/build

CMakeFiles/jni.dir/clean:
	$(CMAKE_COMMAND) -P CMakeFiles/jni.dir/cmake_clean.cmake
.PHONY : CMakeFiles/jni.dir/clean

CMakeFiles/jni.dir/depend:
	cd /home/mahesh/Code/Flutter/jnigen/jni/src && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /home/mahesh/Code/Flutter/jnigen/jni/src /home/mahesh/Code/Flutter/jnigen/jni/src /home/mahesh/Code/Flutter/jnigen/jni/src /home/mahesh/Code/Flutter/jnigen/jni/src /home/mahesh/Code/Flutter/jnigen/jni/src/CMakeFiles/jni.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : CMakeFiles/jni.dir/depend
