#!/bin/sh

SYMROOT="`pwd`/symroot/$CURRENT_ARCH"
DSTROOT="`pwd`/dstroot/$CURRENT_ARCH"

rm -Rf "$SYMROOT"
rm -Rf "$DSTROOT"
mkdir -p "$SYMROOT"
mkdir -p "$DSTROOT"

make distclean
./configure --prefix="$DSTROOT" --arch=$CURRENT_ARCH --extra-cflags="-arch $CURRENT_ARCH" --extra-ldflags="-arch $CURRENT_ARCH" --target-path="$SYMROOT" \
	--disable-static --enable-shared --disable-stripping \
	--disable-ffmpeg --disable-ffplay --disable-ffserver \
	--enable-pthreads --disable-network \
	--disable-encoders --disable-decoders --enable-decoder=mp2 \
	--disable-muxers --disable-demuxers \
	--disable-parsers --enable-parser=mpegaudio \
	--disable-bsfs --disable-protocols --disable-devices --disable-filters

make -j 4
make install
make clean
