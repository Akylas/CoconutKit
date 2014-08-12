#!/bin/bash

set -e

IOSSDK_VER="7.0"

# xcodebuild -showsdks
PROJECT_NAME="CoconutKit"
TARGET_NAME="CoconutKitAnimation"

cd CoconutKit
xcodebuild -project ${PROJECT_NAME}.xcodeproj -target ${TARGET_NAME}  -sdk iphoneos -configuration Release clean build
xcodebuild -project ${PROJECT_NAME}.xcodeproj -target ${TARGET_NAME} -sdk iphonesimulator -configuration Release clean build

cd Build

LIBNAME="lib${TARGET_NAME}"
# for the fat lib file
LIB_DIR="../Release-iphone"

mkdir -p ../Release-iphone/lib
xcrun -sdk iphoneos lipo -create Release-iphoneos/${LIBNAME}.a Release-iphonesimulator/${LIBNAME}.a -output ${LIB_DIR}/${LIBNAME}.a
xcrun -sdk iphoneos lipo -info ${LIB_DIR}/${LIBNAME}.a
# for header files
mkdir -p ${LIB_DIR}/${TARGET_NAME}
cp Release-iphoneos/${TARGET_NAME}/*.h ${LIB_DIR}/${TARGET_NAME}
