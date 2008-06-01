#!/bin/sh

xcodebuild -target "Riven X" -configuration "$1" build SYMROOT="`pwd`/build"
