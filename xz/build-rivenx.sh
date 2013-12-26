#!/usr/bin/env bash

CURRENT_ARCH="x86_64" ./build-arch.sh

DSTROOT="`pwd`/dstroot"
PKGROOT="`pwd`/pkgroot"

lipo "$DSTROOT/x86_64/lib/liblzma.a" -create -output "$PKGROOT/liblzma.a"
