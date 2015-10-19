#!/usr/bin/env bash

CURRENT_ARCH="x86_64" ./build-arch.sh

DSTROOT="`pwd`/dstroot"
PKGROOT="`pwd`/pkgroot"

lipo "$DSTROOT/x86_64/lib/libavutil.dylib" -create -output "$PKGROOT/libavutil.dylib"
lipo "$DSTROOT/x86_64/lib/libavcodec.dylib" -create -output "$PKGROOT/libavcodec.dylib"
lipo "$DSTROOT/x86_64/lib/libavformat.dylib" -create -output "$PKGROOT/libavformat.dylib"
