#!/bin/sh

export CURRENT_ARCH="x84_64"
./build-arch.sh

DSTROOT="`pwd`/dstroot"
mkdir -p "$DSTROOT/staging"
mkdir -p "$DSTROOT/staging/x84_64"

cp -Rp "$DSTROOT/x84_64/include/libavcore" "$DSTROOT/staging/x84_64/"
cp -Rp "$DSTROOT/x84_64/include/libavutil" "$DSTROOT/staging/x84_64/"
cp -Rp "$DSTROOT/x84_64/include/libavcodec" "$DSTROOT/staging/x84_64/"

install_name_tool -id libavutil.dylib "$DSTROOT/x84_64/lib/libavutil.dylib"
install_name_tool -id libavcore.dylib "$DSTROOT/x84_64/lib/libavcore.dylib"
install_name_tool -id libavcodec.dylib "$DSTROOT/x84_64/lib/libavcodec.dylib"
install_name_tool -change "$DSTROOT/x84_64/lib/libavutil.dylib" @loader_path/libavutil.dylib "$DSTROOT/x84_64/lib/libavcore.dylib"
install_name_tool -change "$DSTROOT/x84_64/lib/libavutil.dylib" @loader_path/libavutil.dylib "$DSTROOT/x84_64/lib/libavcodec.dylib"
install_name_tool -change "$DSTROOT/x84_64/lib/libavcore.dylib" @loader_path/libavcore.dylib "$DSTROOT/x84_64/lib/libavcodec.dylib"

lipo "$DSTROOT/x84_64/lib/libavutil.dylib" -create -output "$DSTROOT/staging/libavutil.dylib"
lipo "$DSTROOT/x84_64/lib/libavcore.dylib" -create -output "$DSTROOT/staging/libavcore.dylib"
lipo "$DSTROOT/x84_64/lib/libavcodec.dylib" -create -output "$DSTROOT/staging/libavcodec.dylib"

#dsymutil "$DSTROOT/staging/libavutil.dylib"
#dsymutil "$DSTROOT/staging/libavcodec.dylib"

strip -x "$DSTROOT/staging/libavutil.dylib"
strip -x "$DSTROOT/staging/libavcore.dylib"
strip -x "$DSTROOT/staging/libavcodec.dylib"
