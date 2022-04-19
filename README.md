# CMake vcpkg project boilerplate

[![CMake Template](https://img.shields.io/badge/CMake%20Template-Vcpkg%20Integration-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAM6wAADOsB5dZE0gAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAERSURBVCiRhZG/SsMxFEZPfsVJ61jbxaF0cRQRcRJ9hlYn30IHN/+9iquDCOIsblIrOjqKgy5aKoJQj4O3EEtbPwhJbr6Te28CmdSKeqzeqr0YbfVIrTBKakvtOl5dtTkK+v4HfA9PEyBFCY9AGVgCBLaBp1jPAyfAJ/AAdIEG0dNAiyP7+K1qIfMdonZic6+WJoBJvQlvuwDqcXadUuqPA1NKAlexbRTAIMvMOCjTbMwl1LtI/6KWJ5Q6rT6Ht1MA58AX8Apcqqt5r2qhrgAXQC3CZ6i1+KMd9TRu3MvA3aH/fFPnBodb6oe6HM8+lYHrGdRXW8M9bMZtPXUji69lmf5Cmamq7quNLFZXD9Rq7v0Bpc1o/tp0fisAAAAASUVORK5CYII=)](https://github.com/mrom1/boilerplate-vcpkg-cmake)
![Integration Test Windows](https://github.com/mrom1/boilerplate-vcpkg-cmake/actions/workflows/integration_windows.yml/badge.svg)
![Integration Test Linux](https://github.com/mrom1/boilerplate-vcpkg-cmake/actions/workflows/integration_linux.yml/badge.svg)

This repository is a template repository acting as boilerplate code for a empty C++ project using [vcpkg](https://github.com/microsoft/vcpkg) with CMake.

It automatically detects if vcpkg is already installed on the system and will download, update and install vcpkg for you if necessary. All done through a simple ``include(cmake/vcpkg.cmake)`` inside your root CMakeLists.txt before you define your project!

To add your external dependencies through vcpkg you have two options:
- Use a Manifest file [vcpkg.json](vcpkg.json) (For more information see [Manifest file Documentation](https://vcpkg.io/en/docs/maintainers/manifest-files.html)).
- Use the CMake function ``vcpkg_install_package(package_name)`` from the [vcpkg.cmake](cmake/vcpkg.cmake) script.

