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
##                        Default behaviour is to not set the variable.              ##
#######################################################################################
cmake_minimum_required(VERSION 3.2)


#######################################################################################
## Git dependency                                                                    ##
#######################################################################################
find_package(Git REQUIRED)


#######################################################################################
## Function: vcpkg_install                                                           ##
##                                                                                   ##
## - Clones vcpkg from git repo and installs it to VCPKG_INSTALL_DIR                 ##
#######################################################################################
function(vcpkg_install)
    # If not specified which version to use, use the latest tagged release version.
    if (NOT DEFINED VCPKG_VERSION)
        set(VCPKG_VERSION "latest")
    endif()

    # Check if vcpkg is already installed
    if (NOT DEFINED VCPKG_EXECUTABLE 
        OR VCPKG_EXECUTABLE EQUAL "" 
        OR DEFINED VCPKG_FORCE_INSTALL)

        # If no path has been specified for vcpkg, then use the build folder
        if(VCPKG_INSTALL_DIR EQUAL "" OR NOT DEFINED VCPKG_INSTALL_DIR)
            set(VCPKG_INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/")
        endif()
        string(REGEX REPLACE "[/\\]$" "" VCPKG_INSTALL_DIR "${VCPKG_INSTALL_DIR}")

        message(STATUS "[vcpkg] Installing vcpkg at: ${VCPKG_INSTALL_DIR}")

        # Make sure git executable is defined and found.
        if (GIT_EXECUTABLE EQUAL "" OR NOT DEFINED GIT_EXECUTABLE)
            message(FATAL_ERROR 
                "[vcpkg] Git is necessary for downloading vcpkg! "
                "Unable to find git executable. Please make sure to "
                "have git installed and in your path.")
        else()
            message(STATUS "[vcpkg] Git found at: ${GIT_EXECUTABLE}")
        endif()

        set(VCPKG_ROOT_DIR "${VCPKG_INSTALL_DIR}/vcpkg")

        # Check if vcpkg needs to be cloned
        if (NOT EXISTS ${VCPKG_ROOT_DIR})
            vcpkg_clone_repository()
        endif()
        
        vcpkg_check_integrity(INTEGRITY_CHECK_OK)
        if(NOT INTEGRITY_CHECK_OK EQUAL "0")
            # The vcpkg folder which exists failed the integrity check.
            # Remove the folder and clone again.
            message(STATUS "[vcpkg] Removing ${VCPKG_ROOT_DIR}")
            file(REMOVE_RECURSE ${VCPKG_ROOT_DIR})
            vcpkg_clone_repository()
        endif()

        # At this point in the script we should have a working clone
        # of the vcpkg repository and can start bootstrapping
        vcpkg_execute_bootstrap()

        # Setting the vcpkg executable
        vcpkg_set_executable()
    else()
        message(STATUS "[vcpkg] Executable found at ${VCPKG_EXECUTABLE}")
    endif()

    # Cache VCPKG_EXECUTABLE
    set(VCPKG_EXECUTABLE ${VCPKG_EXECUTABLE} 
        CACHE STRING "vcpkg executable location" FORCE)

    # Setting CMAKE_TOOLCHAIN_FILE
    set(CMAKE_TOOLCHAIN_FILE "${VCPKG_TOOLCHAIN_FILE}")
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} PARENT_SCOPE)
    set(CMAKE_TOOLCHAIN_FILE ${CMAKE_TOOLCHAIN_FILE} CACHE STRING "")

endfunction()


#######################################################################################
## Function: vcpkg_set_executable                                                    ##
##                                                                                   ##
## - Sets the executable binary based on VCPKG_ROOT_DIR                              ##
#######################################################################################
function(vcpkg_set_executable)
    if (NOT EXISTS ${VCPKG_ROOT_DIR})
        message(FATAL_ERROR "[vcpkg] Unable to find vcpkg root directory!")
    endif()

    if(WIN32)
        if(EXISTS "${VCPKG_ROOT_DIR}/vcpkg.exe")
            set(VCPKG_EXECUTABLE "${VCPKG_ROOT_DIR}/vcpkg.exe" PARENT_SCOPE)
        endif()
    else()
        if(EXISTS "${VCPKG_ROOT_DIR}/vcpkg")
            set(VCPKG_EXECUTABLE "${VCPKG_ROOT_DIR}/vcpkg" PARENT_SCOPE)
        endif()
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_execute_bootstrap                                                 ##
##                                                                                   ##
## - Executes the bootstrap script inside the vcpkg folder                           ##
#######################################################################################
function(vcpkg_execute_bootstrap)
    message(STATUS "[vcpkg] Executing bootstrap script ...")

    if(NOT EXISTS ${VCPKG_BOOTSTRAP_FILE})
        message(FATAL_ERROR "[vcpkg] Bootstrap file not found!")
    endif()
    
    execute_process(
        COMMAND bash ${VCPKG_BOOTSTRAP_FILE} -disableMetrics
        WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
        OUTPUT_QUIET
        RESULT_VARIABLE VCPKG_BUILD_OK)
    
    if(NOT VCPKG_BUILD_OK EQUAL "0")
        message(FATAL_ERROR "[vcpkg] Bootstrapping VCPKG failed!")
    else()
        message(STATUS "[vcpkg] Built VCPKG successfully!")
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_clone_repository                                                  ##
##                                                                                   ##
## - Clones the repository inside VCPKG_INSTALL_DIR                                  ##
#######################################################################################
function(vcpkg_clone_repository)

    message(STATUS "[vcpkg] Cloning vcpkg version: '${VCPKG_VERSION}' ...")
    # Check for specified vcpkg version and start cloning the vcpkg repo
    if (VCPKG_VERSION STREQUAL "edge")
        # Clone the latest commit from the vcpkg repo using default branch (master)
        # Command: "git clone --depth 1 https://github.com/Microsoft/vcpkg.git"

        set(CLONE_ARGS "clone;\--depth;1;https://github.com/Microsoft/vcpkg.git")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${CLONE_ARGS}
            WORKING_DIRECTORY ${VCPKG_INSTALL_DIR}
            OUTPUT_QUIET
            RESULT_VARIABLE VCPKG_GIT_CLONE_OK)

        if(NOT VCPKG_GIT_CLONE_OK EQUAL "0")
            message(FATAL_ERROR "Cloning vcpkg repository failed!")
        endif()

    elseif (VCPKG_VERSION STREQUAL "latest")
        # Clone latest tagged release version from the vcpkg repo
        # Commands:
        #   git clone https://github.com/Microsoft/vcpkg.git
        #   latest_tag = $(git describe --tags `git rev-list --tags --max-count=1`)
        #   git checkout $latest_tag

        set(CLONE_ARGS "clone;https://github.com/Microsoft/vcpkg.git")
        set(REV_LIST_ARGS "rev-list;--tags;--max-count=1")
        set(DESCRIBE_ARGS "describe;--tags")

        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${CLONE_ARGS}
            WORKING_DIRECTORY ${VCPKG_INSTALL_DIR}
            OUTPUT_QUIET
            RESULT_VARIABLE VCPKG_GIT_CLONE_OK)

        if(NOT VCPKG_GIT_CLONE_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Cloning vcpkg repository failed!")
        endif()

        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${REV_LIST_ARGS}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT_VARIABLE VCPKG_GIT_TAG_SHA1_LATEST
            RESULT_VARIABLE VCPKG_GIT_TAG_LATEST_OK
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        
        if(NOT VCPKG_GIT_TAG_LATEST_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Getting vcpkg repository revision list failed!")
        endif()

        execute_process(
            COMMAND ${GIT_EXECUTABLE} ${DESCRIBE_ARGS} ${VCPKG_GIT_TAG_SHA1_LATEST}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT_VARIABLE VCPKG_GIT_TAG_NAME_LATEST
            RESULT_VARIABLE VCPKG_GIT_TAG_NAME_LATEST_OK)
        string(REGEX REPLACE "\n$" "" VCPKG_GIT_TAG_NAME_LATEST "${VCPKG_GIT_TAG_NAME_LATEST}")
        
        if(NOT VCPKG_GIT_TAG_NAME_LATEST_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Getting vcpkg latest tag failed!")
        endif()

        message(STATUS "[vcpkg] Checking out latest tag: ${VCPKG_GIT_TAG_NAME_LATEST}")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} checkout ${VCPKG_GIT_TAG_NAME_LATEST}
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT_QUIET
            ERROR_QUIET
            RESULT_VARIABLE VCPKG_GIT_CHECKOUT_OK)
        
        if(NOT VCPKG_GIT_CHECKOUT_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Checkout for tag ${VCPKG_GIT_TAG_NAME_LATEST} failed!")
        endif()

        execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
            WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
            OUTPUT_VARIABLE VCPKG_GIT_CURRENT_COMMIT_SHA1
            RESULT_VARIABLE VCPKG_GIT_CURRENT_COMMIT_SHA1_OK)

        if(NOT VCPKG_GIT_CURRENT_COMMIT_SHA1_OK EQUAL "0")
            message(FATAL_ERROR "[vcpkg] Getting vcpkg SHA1 revision failed!")
        endif()
    else()
        # no version or invalid version has been specificed
        message(FATAL_ERROR 
            "[vcpkg] Invalid version has been specified ('${VCPKG_VERSION}'). "
            "Please set the VCPKG_VERSION variable to either 'edge' or 'latest' "
            "before including the vcpkg.cmake file.")
    endif()
endfunction()


#######################################################################################
## Function: vcpkg_check_integrity                                                   ##
##                                                                                   ##
## - Checks if the cloned repository is compatible to the specified version.         ##
##                                                                                   ##
## Args:                                                                             ##
##  - OUTPUT_RESULT:                                                                 ##
##      - "SUCCESS": Indicates that the cloned repository can be used.               ##
##      - "FAILURE": Indicates that the repository should be cloned again.           ##
#######################################################################################
function(vcpkg_check_integrity OUTPUT_RESULT)
    get_filename_component(
        VCPKG_TOOLCHAIN_FILE 
        "${VCPKG_ROOT_DIR}/scripts/buildsystems/vcpkg.cmake"
        ABSOLUTE)

    if(WIN32)
        get_filename_component(
            VCPKG_BOOTSTRAP_FILE
            "${VCPKG_ROOT_DIR}/bootstrap-vcpkg.bat"
            ABSOLUTE)
    else()
        get_filename_component(
            VCPKG_BOOTSTRAP_FILE
            "${VCPKG_ROOT_DIR}/bootstrap-vcpkg.sh"
            ABSOLUTE)
    endif()

    if(NOT EXISTS ${VCPKG_TOOLCHAIN_FILE} OR NOT EXISTS ${VCPKG_BOOTSTRAP_FILE})
        message(WARNING 
            "[vcpkg] Cloned folder at ${VCPKG_ROOT_DIR} seems corrupted. "
            "Performing clean install...")
        set(${OUTPUT_RESULT} -1 PARENT_SCOPE)
        return()
    endif()

    set(VCPKG_BOOTSTRAP_FILE ${VCPKG_BOOTSTRAP_FILE} PARENT_SCOPE)
    set(VCPKG_TOOLCHAIN_FILE ${VCPKG_TOOLCHAIN_FILE} PARENT_SCOPE)
    set(${OUTPUT_RESULT} 0 PARENT_SCOPE)
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
## Executing Script                                                                  ##
#######################################################################################
if (NOT VCPKG_NO_INSTALL)
    vcpkg_install()
endif()
