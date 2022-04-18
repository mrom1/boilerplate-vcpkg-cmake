#######################################################################################
## MIT License                                                                       ## 
##                                                                                   ##
## Copyright (c) 2022 https://github.com/mrom1/boilerplate-vcpkg-cmake               ##
##                                                                                   ##
## Permission is hereby granted, free of charge, to any person obtaining a copy      ##
## of this software and associated documentation files (the "Software"), to deal     ##
## in the Software without restriction, including without limitation the rights      ##
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell         ##
## copies of the Software, and to permit persons to whom the Software is             ##
## furnished to do so, subject to the following conditions:                          ##
##                                                                                   ##
## The above copyright notice and this permission notice shall be included in all    ##
## copies or substantial portions of the Software.                                   ##
##                                                                                   ##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR        ##
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,          ##
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE       ##
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER            ##
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,     ##
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE     ##
## SOFTWARE.                                                                         ##
#######################################################################################


#######################################################################################
## Configuration Variables                                                           ##
##                                                                                   ##
## - VCPKG_VERSION: Defaults to "latest"                                             ##
##  - "latest": If chosen latest, the version will be the last tagged release.       ##
##  - "edge": If chosen edge, the version will be the last commit in master branch.  ##
## - VCPKG_INSTALL_DIR: If not set defaults to CMAKE_CURRENT_BINARY_DIR.             ##
## - VCPKG_NO_INSTALL: If set there will be no action triggered from this script.    ##
## - VCPKG_FORCE_INSTALL: If this variable is set the script will force cloning      ##
##                        and installing vcpkg each time you include this script.    ##
##                        Default behaviour is to disable this feature.              ##
#######################################################################################
cmake_minimum_required(VERSION 3.20)


set(VCPKG_REPO_URL "https://github.com/Microsoft/vcpkg.git")

#######################################################################################
## Git dependency                                                                    ##
#######################################################################################
find_package(Git REQUIRED)


#######################################################################################
## Function: vcpkg_install                                                           ##
##                                                                                   ##
## - Installs vcpkg if necessary.                                                    ##
#######################################################################################
function(vcpkg_install)
    if(NOT DEFINED VCPKG_VERSION OR VCPKG_VERSION EQUAL "")
        set(VCPKG_VERSION latest)
    endif()
    
    vcpkg_check_environment(VCPKG_ENVIRONMENT_OK)

    if(${VCPKG_ENVIRONMENT_OK})
        message(STATUS  "[vcpkg] Found VCPKG Executable: ${VCPKG_EXECUTABLE}")
        message(STATUS  "[vcpkg] Found VCPKG Version: ${VCPKG_INSTALLED_VERSION}")
    else()
        vcpkg_git_clone_repository()
        vcpkg_execute_bootstrap()
        vcpkg_set_environment()
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_install_package                                                   ##
##                                                                                   ##
## - Installs a package. Expects a package name as input parameter.                  ##
#######################################################################################
function(vcpkg_install_package PACKAGE_NAME)
    if (EXISTS VCPKG_EXECUTABLE)
        execute_process(
            COMMAND ${VCPKG_EXECUTABLE} --feature-flags=-manifests --disable-metrics 
            install "${PACKAGE_NAME}" 
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR} 
            RESULT_VARIABLE VCPKG_INSTALL_OK)
        if(NOT VCPKG_INSTALL_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Failed to install ${PACKAGE_NAME}")
        endif()
    else()
        message(FATAL_ERROR "[vcpkg] Failed to find the vcpkg executable.")
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_check_environment                                                 ##
##                                                                                   ##
## - Checks the environment.                                                         ##
##                                                                                   ##
## Args:                                                                             ##
##  - RESULT:                                                                        ##
##      'True': Successful installation found, can be used immediately.              ##
##      'False': No installation found, needs to be cloned.                          ##
#######################################################################################
function(vcpkg_check_environment RESULT)
    if(DEFINED VCPKG_FORCE_INSTALL)
        # Going to force installation anyway, nothing more to check.
        message(STATUS "[vcpkg] Force Installtion: ON")
        set(${RESULT} False PARENT_SCOPE)
        return()
    elseif(DEFINED ENV{VCPKG_ROOT} AND EXISTS $ENV{VCPKG_ROOT})
        # The environment variable VCPKG_ROOT gets defined by the vcpkg installer.
        # This script nerver sets this variable, i.e. if it is set that must mean
        # there is a known vcpkg installation already.
        message(STATUS 
            "[vcpkg] Environment variable VCPKG_ROOT defined: $ENV{VCPKG_ROOT}")
        set(VCPKG_ROOT_DIR $ENV{VCPKG_ROOT})
        set(VCPKG_ROOT_DIR $ENV{VCPKG_ROOT} PARENT_SCOPE)
    elseif(DEFINED VCPKG_ROOT_DIR AND EXISTS ${VCPKG_ROOT_DIR})
        set(VCPKG_ROOT_DIR ${VCPKG_ROOT_DIR} PARENT_SCOPE)
    else()
        message(STATUS "[vcpkg] No installation found.")
        set(${RESULT} False PARENT_SCOPE)
        return()
    endif()

    # Check if the git repository is reachable
    vcpkg_git_repository_reachable(VCPKG_GIT_REPOSITORY_REACHABLE_OK)
    if(NOT ${VCPKG_GIT_REPOSITORY_REACHABLE_OK})
        message(STATUS 
            "[vcpkg] Git repository not reachable, check your internet connection!")
        set(VCPKG_INSTALLED_VERSION ${VCPKG_INSTALLED_VERSION} PARENT_SCOPE)
        set(${RESULT} True PARENT_SCOPE)
        return()
    endif()

    # Check if the vcpkg version found is on the desired version or if corrupted.
    vcpkg_check_version(VCPKG_CHECK_VERSION_OK)
    if(NOT VCPKG_CHECK_VERSION_OK)
        message(STATUS "[vcpkg] Installed version needs to be updated!")
        set(${RESULT} False PARENT_SCOPE)
        return()
    endif()

    set(VCPKG_INSTALLED_VERSION ${VCPKG_INSTALLED_VERSION} PARENT_SCOPE)
    set(${RESULT} True PARENT_SCOPE)
endfunction()


#######################################################################################
## Function: vcpkg_check_version                                                     ##
##                                                                                   ##
## - Verify the found vcpkg version against the desired (configured) version.        ##
##                                                                                   ##
## Args:                                                                             ##
##  - RESULT:                                                                        ##
##      - 'True': Success. Version can be used.                                      ##
##      - 'False': Failure. VCPKG should be cloned / checked out again.              ##
#######################################################################################
function(vcpkg_check_version RESULT)
    message(STATUS "[vcpkg] Checking version of vcpkg...")  
    
    # Check vcpkg has already been bootstrapped
    if(WIN32)
        set(VCPKG_EXECUTABLE_NAME "vcpkg.exe")
    else()
        set(VCPKG_EXECUTABLE_NAME "vcpkg")
    endif()

    if(EXISTS "${VCPKG_ROOT_DIR}/${VCPKG_EXECUTABLE_NAME}")
        set(VCPKG_EXECUTABLE "${VCPKG_ROOT_DIR}/${VCPKG_EXECUTABLE_NAME}")
    else()
        set(${RESULT} False PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND ${VCPKG_EXECUTABLE} version 
        RESULT_VARIABLE VCPKG_TEST_RETVAL 
        OUTPUT_VARIABLE VCPKG_VERSION_OUTPUT
    )

    if(NOT (${VCPKG_TEST_RETVAL} EQUAL "0"))
        set(${RESULT} False PARENT_SCOPE)
        return()
    endif()

    string(REGEX MATCH "([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])-([0-9a-zA-Z]+)"
        VCPKG_INSTALLED_VERSION ${VCPKG_VERSION_OUTPUT})

    if(VCPKG_VERSION STREQUAL "edge")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} ls-remote ${VCPKG_REPO_URL} HEAD
            OUTPUT_VARIABLE VCPKG_LATEST_HEAD
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(SUBSTRING ${VCPKG_LATEST_HEAD} 0 40 VCPKG_MOST_RECENT_HASH)

    elseif(VCPKG_VERSION STREQUAL "latest")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} ls-remote --tags ${VCPKG_REPO_URL}
            OUTPUT_VARIABLE VCPKG_LATEST_TAGS_LIST
            OUTPUT_STRIP_TRAILING_WHITESPACE
            
        )
        string(FIND ${VCPKG_LATEST_TAGS_LIST} "\n" POSITION_LAST_NEWLINE REVERSE)
        string(LENGTH ${VCPKG_LATEST_TAGS_LIST} TAGS_LENGTH)
        math(EXPR OUTPUT_HASH_STARTBYTE "${POSITION_LAST_NEWLINE}+1")
        string(SUBSTRING ${VCPKG_LATEST_TAGS_LIST} ${OUTPUT_HASH_STARTBYTE} 40 VCPKG_MOST_RECENT_HASH)

    else()
        # Invalid version has been specificed
        message(FATAL_ERROR 
            "[vcpkg] Invalid version has been specified ('${VCPKG_VERSION}'). "
            "Please set the VCPKG_VERSION variable to either 'edge' or 'latest' "
            "before including the vcpkg.cmake file.")
    endif()

    vcpkg_git_execute_command(
        COMMAND rev-parse
        ARGS_LIST HEAD
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        OUTPUT VCPKG_CURRENT_ACTIVE_HASH
    )

    if(VCPKG_VERSION STREQUAL "latest")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} describe --tags --exact-match ${VCPKG_CURRENT_ACTIVE_HASH}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            RESULT_VARIABLE VCPKG_CURRENT_REVISION_IS_TAG
            OUTPUT_QUIET
        )
        if(NOT (VCPKG_CURRENT_REVISION_IS_TAG EQUAL 0))
            # Current version is not a tag.
            set(${RESULT} False PARENT_SCOPE)
            return()
        endif()
    endif()

    vcpkg_git_compare_timestamp(
        INPUT_VERSION ${VCPKG_CURRENT_ACTIVE_HASH}
        BASELINE_VERSION ${VCPKG_MOST_RECENT_HASH}
        RESULT GIT_COMPARE_TIMESTAMP_RESULT)

    if(GIT_COMPARE_TIMESTAMP_RESULT LESS 0)
        message(STATUS "[vcpkg] Version found at ${VCPKG_ROOT_DIR} is outdated!")
        set(${RESULT} False PARENT_SCOPE)
        return()
    endif()

    set(VCPKG_INSTALLED_VERSION ${VCPKG_INSTALLED_VERSION} PARENT_SCOPE)
    set(${RESULT} True PARENT_SCOPE)
endfunction()


#######################################################################################
## Function: vcpkg_git_clone_repository                                              ##
##                                                                                   ##
## - Clones the vcpkg repository.                                                    ##
#######################################################################################
function(vcpkg_git_clone_repository)
    # If no path has been specified for installing vcpkg, then use the build folder
    if(VCPKG_INSTALL_DIR EQUAL "" OR NOT DEFINED VCPKG_INSTALL_DIR)
        set(VCPKG_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/")
        set(VCPKG_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/" PARENT_SCOPE)
    endif()
    string(REGEX REPLACE "[/\\]$" "" VCPKG_INSTALL_DIR "${VCPKG_INSTALL_DIR}")

    if(VCPKG_ROOT_DIR EQUAL "" OR NOT DEFINED VCPKG_ROOT_DIR)
        set(VCPKG_ROOT_DIR "${VCPKG_INSTALL_DIR}/vcpkg")
        set(VCPKG_ROOT_DIR "${VCPKG_INSTALL_DIR}/vcpkg" PARENT_SCOPE)
    endif()

    if(EXISTS ${VCPKG_ROOT_DIR} AND DEFINED VCPKG_FORCE_INSTALL)
        vcpkg_is_path_in_project(PATH ${VCPKG_ROOT_DIR} RESULT IS_IN_PATH)
        if(${IS_IN_PATH})
            message(STATUS "[vcpkg] Forcing reinstall.. removing ${VCPKG_ROOT_DIR}")
            file(REMOVE_RECURSE ${VCPKG_ROOT_DIR})
        endif()
    endif()

    if(NOT EXISTS ${VCPKG_ROOT_DIR})
        message(STATUS "[vcpkg] Cloning repository...")
        vcpkg_git_execute_command(
            COMMAND clone 
            ARGS_LIST ${VCPKG_REPO_URL}
            WORKING_DIRECTORY ${VCPKG_INSTALL_DIR}
        )    
    endif()

    message(STATUS "[vcpkg] Fetching Updates ...")
    vcpkg_git_execute_command(
        COMMAND fetch
        ARGS_LIST origin
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
    )

    if(VCPKG_VERSION STREQUAL "edge")
        message(STATUS "[vcpkg] Updating vcpkg to version '${VCPKG_VERSION}' ...")
        vcpkg_git_execute_command(
            COMMAND reset
            ARGS_LIST --hard origin/master
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        )
    elseif(VCPKG_VERSION STREQUAL "latest")
        vcpkg_git_execute_command(
            COMMAND rev-list
            ARGS_LIST --tags --max-count=1
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT GIT_REVISION_VERSION
        )

        vcpkg_git_execute_command(
            COMMAND describe
            ARGS_LIST --tags ${GIT_REVISION_VERSION}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT GIT_LATEST_TAG_NAME
        )

        message(STATUS "[vcpkg] Checking out latest release tag '${GIT_LATEST_TAG_NAME}' ...")
        vcpkg_git_execute_command(
            COMMAND checkout
            ARGS_LIST ${GIT_LATEST_TAG_NAME}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        )

        vcpkg_read_builtin_baseline(VCPKG_BASELINE_VERSION)
        if(DEFINED VCPKG_BASELINE_VERSION AND NOT VCPKG_BASELINE_VERSION EQUAL "")
            vcpkg_git_compare_timestamp(
                INPUT_VERSION ${GIT_REVISION_VERSION}
                BASELINE_VERSION ${VCPKG_BASELINE_VERSION}
                RESULT GIT_COMPARE_TIMESTAMP_RESULT
            )
            if(GIT_COMPARE_TIMESTAMP_RESULT LESS 0)
                # Baseline version is newer than the last tagged version
                # Checking out specified baseline version.
                vcpkg_git_execute_command(
                    COMMAND checkout
                    ARGS_LIST ${VCPKG_BASELINE_VERSION}
                    WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
                )
            endif()
        endif()
    else()
        # Invalid version has been specificed
        message(FATAL_ERROR 
            "[vcpkg] Invalid version has been specified ('${VCPKG_VERSION}'). "
            "Please set the VCPKG_VERSION variable to either 'edge' or 'latest' "
            "before including the vcpkg.cmake file.")
    endif()
endfunction()



#######################################################################################
## Function: vcpkg_git_compare_timestamp                                             ##
##                                                                                   ##
## - Compare the timestamp of two given commits.                                     ##
##                                                                                   ##
## Args:                                                                             ##
##  - 'INPUT_VERSION': SHA1 hash of the version of the cloned repo.                  ##
##  - 'BASELINE_VERSION': SHA1 hash of the baseline version to be compared against.  ##
##  - 'RESULT': Output variable containing the result.                               ##
##      - '0':  Both timestamps are equal.                                           ##
##      - '1':  INPUT_VERSION is newer than BASELINE_VERSION.                        ##
##      - '-1': INPUT_VERSION is older than BASELINE_VERSION!                        ##
#######################################################################################
function(vcpkg_git_compare_timestamp)
    set(oneValueArgs INPUT_VERSION BASELINE_VERSION RESULT)
    cmake_parse_arguments(GIT_TIMESTAMP "" "${oneValueArgs}" "" ${ARGN})

    if(NOT DEFINED GIT_TIMESTAMP_INPUT_VERSION 
       OR GIT_TIMESTAMP_INPUT_VERSION EQUAL ""
       OR NOT DEFINED GIT_TIMESTAMP_BASELINE_VERSION 
       OR GIT_TIMESTAMP_BASELINE_VERSION EQUAL "")
        message(FATAL_ERROR 
            "[vcpkg] Error: Function 'vcpkg_git_compare_timestamp' called with "
            "invalid arugments. Missing required arguments.")
    endif()

    execute_process(
        # Check if baseline version is in the repository
        COMMAND ${GIT_EXECUTABLE} cat-file -e ${GIT_TIMESTAMP_BASELINE_VERSION}^{commit}
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        RESULT_VARIABLE BASELINE_VERSION_EXSISTS
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if(NOT BASELINE_VERSION_EXSISTS EQUAL "0")
        set(${GIT_TIMESTAMP_RESULT} -1 PARENT_SCOPE)
        return()
    endif()

    vcpkg_git_execute_command(
        COMMAND show
        ARGS_LIST --format=\"%ct\" -s ${GIT_TIMESTAMP_BASELINE_VERSION}
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        OUTPUT UNIX_TIMESTAMP_BASELINE_VERSION
    )

    vcpkg_git_execute_command(
        COMMAND show
        ARGS_LIST --format=\"%ct\" -s ${GIT_TIMESTAMP_INPUT_VERSION}
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        OUTPUT UNIX_TIMESTAMP_INPUT_VERSION
    )

    if(DEFINED UNIX_TIMESTAMP_BASELINE_VERSION AND DEFINED UNIX_TIMESTAMP_INPUT_VERSION)
        if(UNIX_TIMESTAMP_BASELINE_VERSION STREQUAL UNIX_TIMESTAMP_INPUT_VERSION)
            set(${GIT_TIMESTAMP_RESULT} 0 PARENT_SCOPE)
        elseif(UNIX_TIMESTAMP_BASELINE_VERSION STRGREATER UNIX_TIMESTAMP_INPUT_VERSION)
            set(${GIT_TIMESTAMP_RESULT} -1 PARENT_SCOPE)
        elseif(UNIX_TIMESTAMP_BASELINE_VERSION STRLESS UNIX_TIMESTAMP_INPUT_VERSION)
            set(${GIT_TIMESTAMP_RESULT} 1 PARENT_SCOPE)
        endif()
    else()
        set(${GIT_TIMESTAMP_RESULT} -1 PARENT)
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_git_repository_reachable                                          ##
##                                                                                   ##
## Args:                                                                             ##
##  - RESULT:                                                                        ##
##      'True': Reachable                                                            ##
##      'False': Not reachable                                                       ##
#######################################################################################
function(vcpkg_git_repository_reachable RESULT)
    if(EXISTS ${GIT_EXECUTABLE})
        execute_process(
            # git ls-remote --exit-code https://github.com/Microsoft/vcpkg.git
            COMMAND ${GIT_EXECUTABLE} ls-remote --exit-code ${VCPKG_REPO_URL}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            RESULT_VARIABLE RETURN_CODE
            OUTPUT_QUIET
        )
        if(NOT ${RETURN_CODE} EQUAL "0")
            set(${RESULT} False PARENT_SCOPE)
            return()
        endif()
    else()
        message(STATUS "[vcpkg] Git not found!")
        return()
        set(${RESULT} False PARENT_SCOPE)
    endif()

    set(${RESULT} True PARENT_SCOPE)
endfunction()


#######################################################################################
## Function: vcpkg_execute_bootstrap                                                 ##
##                                                                                   ##
## - Executes the bootstrap script inside the vcpkg folder                           ##
#######################################################################################
function(vcpkg_execute_bootstrap)
    message(STATUS "[vcpkg] Executing Bootstrap ...")

    if(WIN32)
        set(CMD_EXECUTABLE "cmd")
        get_filename_component(
            VCPKG_BOOTSTRAP_FILE
            "${VCPKG_ROOT_DIR}/bootstrap-vcpkg.bat"
            ABSOLUTE)
    else()
        set(CMD_EXECUTABLE "bash")
        get_filename_component(
            VCPKG_BOOTSTRAP_FILE
            "${VCPKG_ROOT_DIR}/bootstrap-vcpkg.sh"
            ABSOLUTE)
    endif()

    execute_process(
        COMMAND ${CMD_EXECUTABLE} ${VCPKG_BOOTSTRAP_FILE} -disableMetrics
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        OUTPUT_QUIET
        RESULT_VARIABLE VCPKG_BUILD_OK)
    
    if(NOT VCPKG_BUILD_OK EQUAL "0")
        message(FATAL_ERROR "[vcpkg] Bootstrapping VCPKG failed!")
    else()
        message(STATUS "[vcpkg] Installed VCPKG!")
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_set_environment                                                   ##
##                                                                                   ##
## - Sets environment and cache variables for next use.                              ##
#######################################################################################
function(vcpkg_set_environment)
    message(STATUS "[vcpkg] Setting VCPKG Environment...")
    if(WIN32)
        get_filename_component(
            VCPKG_EXECUTABLE
            "${VCPKG_ROOT_DIR}/vcpkg.exe"
            ABSOLUTE)
    else()
        get_filename_component(
            VCPKG_EXECUTABLE
            "${VCPKG_ROOT_DIR}/vcpkg"
            ABSOLUTE)
    endif()

    get_filename_component(
        VCPKG_TOOLCHAIN_FILE 
        "${VCPKG_ROOT_DIR}/scripts/buildsystems/vcpkg.cmake"
        ABSOLUTE)

    if(NOT EXISTS ${VCPKG_EXECUTABLE})
        message(FATAL_ERROR "[vcpkg] Unable to find VCPKG Executable!")
    endif()

    # Cache VCPKG Root Directory
    set(VCPKG_ROOT_DIR ${VCPKG_ROOT_DIR} CACHE STRING "VCPKG Root" FORCE)

    # Cache VCPKG_EXECUTABLE
    set(VCPKG_EXECUTABLE ${VCPKG_EXECUTABLE} PARENT_SCOPE)
    set(VCPKG_EXECUTABLE ${VCPKG_EXECUTABLE} CACHE STRING "VCPKG Executable" FORCE)

    # Setting CMAKE_TOOLCHAIN_FILE
    set(CMAKE_TOOLCHAIN_FILE "${VCPKG_TOOLCHAIN_FILE}")
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} PARENT_SCOPE)
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} CACHE STRING "")
endfunction()


#######################################################################################
## Function: vcpkg_git_execute_command                                               ##
##                                                                                   ##
## - Executes a git command.                                                         ##
##                                                                                   ##
## Args:                                                                             ##
##  - COMMAND: Input like 'checkout', 'clone' etc.                                   ## 
##  - WORKING_DIRECTORY: Directory of the git repository.                            ##
##  - OUTPUT: Output of the git command will be written to a passed variable.        ##
##  - RESULT: Return value of the git process. Returns '0' on success.               ##  
##  - ARGS_LIST: Input arguments to the git command. Expects a list.                 ##
##  - VERBOSE: If this option is set the output from the git call will be printed.   ##
#######################################################################################
function(vcpkg_git_execute_command)
    set(options VERBOSE)
    set(oneValueArgs COMMAND WORKING_DIRECTORY OUTPUT RESULT)
    set(multiValueArgs ARGS_LIST)
    cmake_parse_arguments(GIT_EXECUTE "${options}"
                          "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT DEFINED GIT_EXECUTABLE OR GIT_EXECUTABLE EQUAL "")
        message(FATAL_ERROR 
            "[vcpkg] Error: Git executable not found!")
    elseif(NOT DEFINED GIT_EXECUTE_COMMAND OR GIT_EXECUTE_COMMAND EQUAL "")
        message(FATAL_ERROR 
            "[vcpkg] Error: In 'vcpkg_git_execute_command' git command undefined.")
        return()
    elseif(GIT_EXECUTE_WORKING_DIRECTORY EQUAL "" 
           OR NOT DEFINED GIT_EXECUTE_WORKING_DIRECTORY)
        message(FATAL_ERROR 
            "[vcpkg] Error: In 'vcpkg_git_execute_command' git working directory undefined.")
        return()
    endif()

    if(${GIT_EXECUTE_VERBOSE})
        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${GIT_EXECUTE_COMMAND} ${GIT_EXECUTE_ARGS_LIST}
            WORKING_DIRECTORY ${GIT_EXECUTE_WORKING_DIRECTORY}
            OUTPUT_VARIABLE GIT_EXECUTE_OUTPUT_VALUE
            RESULT_VARIABLE GIT_EXECUTE_RESULT_VALUE
            OUTPUT_STRIP_TRAILING_WHITESPACE
            COMMAND_ERROR_IS_FATAL ANY
            COMMAND_ECHO STDOUT)
    else()
        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${GIT_EXECUTE_COMMAND} ${GIT_EXECUTE_ARGS_LIST}
            WORKING_DIRECTORY ${GIT_EXECUTE_WORKING_DIRECTORY}
            OUTPUT_VARIABLE GIT_EXECUTE_OUTPUT_VALUE
            RESULT_VARIABLE GIT_EXECUTE_RESULT_VALUE
            OUTPUT_STRIP_TRAILING_WHITESPACE
            COMMAND_ERROR_IS_FATAL ANY)
    endif()

    if(DEFINED GIT_EXECUTE_OUTPUT AND NOT GIT_EXECUTE_OUTPUT EQUAL "")
        set(${GIT_EXECUTE_OUTPUT} ${GIT_EXECUTE_OUTPUT_VALUE} PARENT_SCOPE)
    endif()
    if(DEFINED GIT_EXECUTE_RESULT AND NOT GIT_EXECUTE_RESULT EQUAL "")
        set(${GIT_EXECUTE_RESULT} ${GIT_EXECUTE_RESULT_VALUE} PARENT_SCOPE)
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_read_builtin_baseline                                             ##
##                                                                                   ##
## - Reads the builtin-version setting from the vcpkg.json manifest file             ##
##                                                                                   ##
## Args:                                                                             ##
##  'OUTPUT_VERSION': The builtin-version as a SHA1 string                           ##
#######################################################################################
function(vcpkg_read_builtin_baseline OUTPUT_VERSION)
    if(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg.json")
        file(READ "${CMAKE_SOURCE_DIR}/vcpkg.json" VCPKG_MANIFEST_JSON)
        string(JSON BUILTIN_BASELINE 
               ERROR_VARIABLE ERROR_MESSAGE
               GET ${VCPKG_MANIFEST_JSON} "builtin-baseline")
        if(ERROR_MESSAGE STREQUAL "" OR NOT DEFINED ERROR_MESSAGE)
            set(${OUTPUT_VERSION} ${BUILTIN_BASELINE} PARENT_SCOPE)
        endif()
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_is_path_in_project                                                ##
##                                                                                   ##
## - Checks if the given path is inside this project ('CMAKE_SOURCE_DIR')            ##
##                                                                                   ##
## Args:                                                                             ##
##  'PATH': Path to be checked against root of the project directory                 ##
##  'RESULT': True if inside the project, otherwise false                            ##
#######################################################################################
function(vcpkg_is_path_in_project)
    cmake_parse_arguments(PATH_CHECK "" "PATH;RESULT" "" ${ARGN})

    if(PATH_CHECK_PATH STREQUAL "" OR NOT DEFINED PATH_CHECK_PATH
       OR PATH_CHECK_RESULT STREQUAL "" OR NOT DEFINED PATH_CHECK_RESULT)
        message(FATAL_ERROR 
            "[vcpkg] Error: Called function 'vcpkg_is_path_in_project' "
            "with invalid arguments. Missing required arguments.")
    else()
        string(TOLOWER ${CMAKE_SOURCE_DIR} PROJECT_ROOT_LOWERCASE)
        string(TOLOWER ${PATH_CHECK_PATH} PATH_LOWERCASE)
        string(REGEX MATCH ${PROJECT_ROOT_LOWERCASE} TEST_PATH ${PATH_LOWERCASE})
        if(TEST_PATH STREQUAL "")
            set(${PATH_CHECK_RESULT} FALSE PARENT_SCOPE)
        else()
            set(${PATH_CHECK_RESULT} TRUE PARENT_SCOPE)
        endif()
    endif()
endfunction()


#######################################################################################
## Executing Script                                                                  ##
#######################################################################################
if (NOT VCPKG_NO_INSTALL)
    vcpkg_install()
endif()
