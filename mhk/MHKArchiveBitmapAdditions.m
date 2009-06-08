//
//	MHKArchiveBitmapAdditions.m
//	MHKKit
//
//	Created by Jean-Francois Roy on 02/07/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <stdlib.h>

#import "mohawk_bitmap.h"

#import "MHKArchive.h"
#import "MHKErrors.h"
#import "PHSErrorMacros.h"


@implementation MHKArchive (MHKArchiveBitmapAdditions)

- (NSDictionary*)bitmapDescriptorWithID:(uint16_t)bitmapID error:(NSError**)errorPtr {
	// get a resource descriptor
	NSDictionary* descriptor = [self resourceDescriptorWithResourceType:@"tBMP" ID:bitmapID];
	if (!descriptor)
		ReturnNULLWithError(MHKErrorDomain, errResourceNotFound, nil, errorPtr);
	
	// seek to the tBMP resource
	SInt64 resource_offset = [[descriptor objectForKey:@"Offset"] longLongValue];
	
	// read the bitmap header
	MHK_BITMAP_header bitmap_header;
	ByteCount bytes_read = 0;
	OSStatus err = FSReadFork(forkRef, fsFromStart, resource_offset, sizeof(MHK_BITMAP_header), &bitmap_header, &bytes_read);
	if (err)
		ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr);
	MHK_BITMAP_header_fton(&bitmap_header);
	
	// make the bitmap descriptor
	NSDictionary* bitmapDescriptor = [NSDictionary dictionaryWithObjectsAndKeys:@"tBMP", @"Type", 
		[NSNumber numberWithUnsignedShort:bitmap_header.width], @"Width", 
		[NSNumber numberWithUnsignedShort:bitmap_header.height], @"Height", 
		nil];
		
	return bitmapDescriptor;
}

- (BOOL)loadBitmapWithID:(uint16_t)bitmapID buffer:(void*)pixels format:(MHK_BITMAP_FORMAT)format error:(NSError**)errorPtr {
	// get a resource descriptor
	NSDictionary *descriptor = [self resourceDescriptorWithResourceType:@"tBMP" ID:bitmapID];
	if (!descriptor)
		ReturnValueWithError(NO, MHKErrorDomain, errResourceNotFound, nil, errorPtr);
	
	// seek to the tBMP resource
	SInt64 resource_offset = [[descriptor objectForKey:@"Offset"] longLongValue];
	
	// read the bitmap header
	MHK_BITMAP_header bitmap_header;
	ByteCount bytes_read = 0;
	OSStatus err = FSReadFork(forkRef, fsFromStart, resource_offset, sizeof(MHK_BITMAP_header), &bitmap_header, &bytes_read);
	if (err)
		ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, errorPtr);
	MHK_BITMAP_header_fton(&bitmap_header);
	
	if (bitmap_header.truecolor_flag == 4) {
		err = read_raw_bgr_pixels(forkRef, resource_offset + bytes_read, &bitmap_header, pixels, format);
		if (err)
			ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, errorPtr);
		return YES;
	}
	
	// move the offset past the header and skip 2 shorts
	resource_offset += bytes_read + 4;
	
	// process the pixels
	if (bitmap_header.compression_flag == MHK_BITMAP_PLAIN)
		err = read_raw_indexed_pixels(forkRef, resource_offset, &bitmap_header, pixels, format);
	else if (bitmap_header.compression_flag == MHK_BITMAP_COMPRESSED)
		err = read_compressed_indexed_pixels(forkRef, resource_offset, &bitmap_header, pixels, format);
	else
		ReturnValueWithError(NO, MHKErrorDomain, errInvalidBitmapCompression, nil, errorPtr);
	if (err)
		ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, errorPtr);
	
	// we're done
	return YES;
}

@end
