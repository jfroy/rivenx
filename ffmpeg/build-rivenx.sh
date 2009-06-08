#!/bin/sh

export CURRENT_ARCH="i386"
./build-arch.sh

export CURRENT_ARCH="ppc"
./build-arch.sh

DSTROOT="`pwd`/dstroot"
mkdir -p "$DSTROOT/staging"
mkdir -p "$DSTROOT/staging/i386"
mkdir -p "$DSTROOT/staging/ppc"

cp -Rp "$DSTROOT/i386/include/libavutil" "$DSTROOT/staging/i386/"
cp -Rp "$DSTROOT/ppc/include/libavutil" "$DSTROOT/staging/ppc/"

cp -Rp "$DSTROOT/i386/include/libavcodec" "$DSTROOT/staging/i386/"
cp -Rp "$DSTROOT/ppc/include/libavcodec" "$DSTROOT/staging/ppc/"

install_name_tool -id libavutil.dylib "$DSTROOT/i386/lib/libavutil.dylib"
install_name_tool -id libavcodec.dylib "$DSTROOT/i386/lib/libavcodec.dylib"
install_name_tool -change "$DSTROOT/i386/lib/libavutil.dylib" @loader_path/libavutil.dylib "$DSTROOT/i386/lib/libavcodec.dylib"

lipo "$DSTROOT/i386/lib/libavutil.dylib" "$DSTROOT/ppc/lib/libavutil.dylib" -create -output "$DSTROOT/staging/libavutil.dylib"
lipo "$DSTROOT/i386/lib/libavcodec.dylib" "$DSTROOT/ppc/lib/libavcodec.dylib" -create -output "$DSTROOT/staging/libavcodec.dylib"

#dsymutil "$DSTROOT/staging/libavutil.dylib"
#dsymutil "$DSTROOT/staging/libavcodec.dylib"

strip -x "$DSTROOT/staging/libavutil.dylib"
strip -x "$DSTROOT/staging/libavcodec.dylib"
