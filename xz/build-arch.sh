#!/usr/bin/env bash

SYMROOT="`pwd`/symroot/$CURRENT_ARCH"
DSTROOT="`pwd`/dstroot/$CURRENT_ARCH"
PKGROOT="`pwd`/pkgroot/$CURRENT_ARCH"
MIN_VERSION='10.7'
SDKROOT="`xcodebuild -sdk macosx10.9 -version Path`"

export CC="clang"
export CFLAGS="-arch $CURRENT_ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_VERSION -Ofast"
export LDFLAGS="-arch $CURRENT_ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_VERSION"

rm -Rf "$SYMROOT"
rm -Rf "$DSTROOT"
rm -Rf "$PKGROOT"
mkdir -p "$SYMROOT"
mkdir -p "$DSTROOT"
mkdir -p "$PKGROOT"

make distclean
./configure \
    --prefix="$DSTROOT" \
    --enable-static --disable-shared \
    --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-lzma-links --disable-scripts

make -j 4
make install

cp -Rp "$DSTROOT/include/lzma.h" "$DSTROOT/include/lzma" "$PKGROOT/" 

