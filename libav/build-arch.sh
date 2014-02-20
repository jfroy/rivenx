#!/usr/bin/env bash

SYMROOT="`pwd`/symroot/$CURRENT_ARCH"
DSTROOT="`pwd`/dstroot/$CURRENT_ARCH"
PKGROOT="`pwd`/pkgroot/$CURRENT_ARCH"

SDKROOT="`xcodebuild -sdk macosx -version Path`"
MIN_VERSION="10.8"

rm -Rf "$SYMROOT"
rm -Rf "$DSTROOT"
rm -Rf "$PKGROOT"
mkdir -p "$SYMROOT"
mkdir -p "$DSTROOT"
mkdir -p "$PKGROOT"

make distclean
./configure --prefix="$DSTROOT" --target-path="$SYMROOT" \
    --cc=clang \
    --extra-cflags="-arch $CURRENT_ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_VERSION -Ofast" \
    --extra-ldflags="-arch $CURRENT_ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_VERSION" \
    --disable-static --enable-shared \
    --enable-runtime-cpudetect \
    --disable-all --enable-avcodec --enable-avformat --enable-avutil \
    --disable-debug \
    --enable-decoder=mp2 --enable-decoder=cinepak --enable-decoder=adpcm_ima_qt \
    --enable-parser=mpegaudio --enable-demuxer=mov

make -j 4
make install

cp -Rp "$DSTROOT/include/libavutil" "$PKGROOT/"
cp -Rp "$DSTROOT/include/libavcodec" "$PKGROOT/"
cp -Rp "$DSTROOT/include/libavformat" "$PKGROOT/"

install_name_tool -id libavutil.dylib "$DSTROOT/lib/libavutil.dylib"
install_name_tool -id libavcodec.dylib "$DSTROOT/lib/libavcodec.dylib"
install_name_tool -id libavformat.dylib "$DSTROOT/lib/libavformat.dylib"

LIB_PATH=`otool -L "$DSTROOT/lib/libavcodec.dylib" | egrep -o "$DSTROOT/lib/libavutil.[[[:digit:]].]*.dylib"`
install_name_tool -change "$LIB_PATH" @loader_path/libavutil.dylib "$DSTROOT/lib/libavcodec.dylib"

LIB_PATH=`otool -L "$DSTROOT/lib/libavformat.dylib" | egrep -o "$DSTROOT/lib/libavutil.[[[:digit:]].]*.dylib"`
install_name_tool -change "$LIB_PATH" @loader_path/libavutil.dylib "$DSTROOT/lib/libavformat.dylib"
LIB_PATH=`otool -L "$DSTROOT/lib/libavformat.dylib" | egrep -o "$DSTROOT/lib/libavcodec.[[[:digit:]].]*.dylib"`
install_name_tool -change "$LIB_PATH" @loader_path/libavcodec.dylib "$DSTROOT/lib/libavformat.dylib"

strip -x "$DSTROOT/lib/libavutil.dylib"
strip -x "$DSTROOT/lib/libavcodec.dylib"
strip -x "$DSTROOT/lib/libavformat.dylib"
