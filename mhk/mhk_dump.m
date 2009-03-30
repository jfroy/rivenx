//
//	main.m
//	foo
//
//	Created by Jean-Francois Roy on 10/04/2005.
//	Copyright MacStorm 2005. All rights reserved.
//

#import <ApplicationServices/ApplicationServices.h>
#import <AudioToolbox/CAFFile.h>

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>

#import "mhk_dump_cmd.h"


static void texture_provider_data_release(void *info, const void *data, size_t size) {
	free((void *)data);
}

static void dump_bitmaps(MHKArchive *archive) {
	NSError *error = nil;
	NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dump_folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Temporary/mhk_bitmap_dump"];
	[fm createDirectoryAtPath:dump_folder attributes:nil];
	
	dump_folder = [dump_folder stringByAppendingPathComponent:[[[archive url] path] lastPathComponent]];
	[fm createDirectoryAtPath:dump_folder attributes:nil];
	
	NSArray *bmpResources = [archive valueForKey:@"tBMP"];
	NSEnumerator *bmpEnumerator = [bmpResources objectEnumerator];
	NSDictionary *resourceDescriptor = nil;
	while ((resourceDescriptor = [bmpEnumerator nextObject])) {
		NSNumber *bmp_id = [resourceDescriptor objectForKey:@"ID"];
		uint16_t bmp_id_native = [bmp_id unsignedShortValue];
		
		NSDictionary *bmpDescriptor = [archive bitmapDescriptorWithID:bmp_id_native error:&error];
		if (!bmpDescriptor || error) {
			NSLog(@"An error in the %@ domain with code %d (%@) has occured.", [error domain], [error code], UTCreateStringForOSType([error code]));
			continue;
		}
		
		uint16_t width = [[bmpDescriptor valueForKey:@"Width"] unsignedShortValue];
		uint16_t height = [[bmpDescriptor valueForKey:@"Height"] unsignedShortValue];
		
		uint32_t texture_length = width * height * 4;
		void *texture_buffer = malloc(texture_length);
		[archive loadBitmapWithID:bmp_id_native buffer:texture_buffer format:MHK_ARGB_UNSIGNED_BYTE_PACKED error:&error];
		if (error) {
			NSLog(@"An error in the %@ domain with code %d (%@) has occured.", [error domain], [error code], UTCreateStringForOSType([error code]));
			free(texture_buffer);
			continue;
		}
		
		NSString *bmp_path_base = [dump_folder stringByAppendingPathComponent:[bmp_id stringValue]];
		NSString *bmp_name = [resourceDescriptor objectForKey:@"Name"];
		if(bmp_name) bmp_path_base = [bmp_path_base stringByAppendingFormat:@" - %@", bmp_name];
		
		bmp_path_base = [bmp_path_base stringByAppendingPathExtension:@"tiff"];
		NSURL *bmp_url = [NSURL fileURLWithPath:bmp_path_base];
		if (!bmp_url) {
			NSLog(@"The output URL failed to allocate!");
			free(texture_buffer);
			continue;
		}
		
		CGImageDestinationRef imageDestRef = CGImageDestinationCreateWithURL((CFURLRef)bmp_url, kUTTypeTIFF, 1, NULL);
		if (!imageDestRef) {
			NSLog(@"Failed to create a CGImageDestinationRef from output URL!");
			free(texture_buffer);
			continue;
		}
		
		CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(NULL, texture_buffer, texture_length, &texture_provider_data_release);
		CGColorSpaceRef genericRGBColorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		CGImageRef textureImageRef = CGImageCreate(width, height, 8, 32, width * 4, genericRGBColorSpaceRef, kCGImageAlphaFirst, dataProviderRef, NULL, 0, kCGRenderingIntentDefault);
		
		CFRelease(genericRGBColorSpaceRef);
		CFRelease(dataProviderRef);
		
		CGImageDestinationAddImage(imageDestRef, textureImageRef, NULL);
		CGImageDestinationFinalize(imageDestRef);
		
		CFRelease(imageDestRef);
		CFRelease(textureImageRef);
	}
	
	[p release];
}

static void dump_sounds(MHKArchive *archive, int first_pkt_only) {
	NSError *error = nil;
	NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dump_folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Temporary/mhk_sound_dump"];
	[fm createDirectoryAtPath:dump_folder attributes:nil];
	
	dump_folder = [dump_folder stringByAppendingPathComponent:[[[archive url] path] lastPathComponent]];
	[fm createDirectoryAtPath:dump_folder attributes:nil];
	
	NSArray *wavResources = [archive valueForKey:@"tWAV"];
	NSEnumerator *wavEnumerator = [wavResources objectEnumerator];
	NSDictionary *wavDescriptor = nil;
	while ((wavDescriptor = [wavEnumerator nextObject])) {
		NSNumber *sound_id = [wavDescriptor objectForKey:@"ID"];
		printf("    %03d (%s)\n", [sound_id intValue], [[wavDescriptor objectForKey:@"Name"] UTF8String]);
		
		NSDictionary *soundDescriptor = [archive soundDescriptorWithID:[sound_id unsignedShortValue] error:&error];
		if (!soundDescriptor) {
			uint32_t code = (uint32_t)[error code];
			fprintf(stderr, "an error in the %s domain with code %d (%c%c%c%c) has occured\n", [[error domain] UTF8String], code, ((char*)&code)[0], ((char*)&code)[1], ((char*)&code)[2], ((char*)&code)[3]);
			continue;
		}
		
		NSString *sound_path_base = [dump_folder stringByAppendingPathComponent:[sound_id stringValue]];
		
		// get a decompressor object for the sound
		id <MHKAudioDecompression> decomp = [archive decompressorWithSoundID:[sound_id unsignedShortValue] error:&error];
		if (!decomp) {
			uint32_t code = (uint32_t)[error code];
			fprintf(stderr, "an error in the %s domain with code %d (%c%c%c%c) has occured\n", [[error domain] UTF8String], code, ((char*)&code)[0], ((char*)&code)[1], ((char*)&code)[2], ((char*)&code)[3]);
			continue;
		}
		
		// ask the decompressor for a frame count and its output ABSD
		SInt64 frame_count = [decomp frameCount];
		AudioStreamBasicDescription absd = [decomp outputFormat];
		
		// handle first packet option
		if (first_pkt_only && [decomp isMemberOfClass:NSClassFromString(@"MHKMP2Decompressor")]) {
			frame_count = 1152;
		}
		
		// allocate samples buffer
		size_t samples_size = frame_count * absd.mBytesPerFrame;
		UInt8 *samples = (UInt8*)malloc(samples_size);
		
		// setup a buffer list structure
		AudioBufferList abl;
		abl.mNumberBuffers = 1;
		abl.mBuffers[0].mData = samples;
		abl.mBuffers[0].mNumberChannels = absd.mChannelsPerFrame;
		abl.mBuffers[0].mDataByteSize = samples_size;
		
		// decompress all the samples
		[decomp fillAudioBufferList:&abl];
		
		// create a caf file
		int fd = open([[sound_path_base stringByAppendingPathExtension:@"caf"] UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0600);
		
		// caf header
		CAFFileHeader ch = {kCAF_FileType, kCAF_FileVersion_Initial, 0};
		ch.mFileType = CFSwapInt32HostToBig(ch.mFileType);
		ch.mFileVersion = CFSwapInt16HostToBig(ch.mFileVersion);
		ch.mFileFlags = CFSwapInt16HostToBig(ch.mFileFlags);
		write(fd, &ch, sizeof(CAFFileHeader));
		
		// audio description chunk
		CAFChunkHeader cch;
		cch.mChunkType = CFSwapInt32HostToBig(kCAF_StreamDescriptionChunkID);
		cch.mChunkSize = (SInt64)CFSwapInt64HostToBig(sizeof(CAFAudioDescription));
		write(fd, &cch.mChunkType, sizeof(cch.mChunkType));
		write(fd, &cch.mChunkSize, sizeof(cch.mChunkSize));
		
		// CAFAudioDescription
		CAFAudioDescription cad;
		CFSwappedFloat64 swapped_sr = CFConvertFloat64HostToSwapped(absd.mSampleRate);
		cad.mSampleRate = *((Float64 *)(&swapped_sr.v));
		cad.mFormatID = CFSwapInt32HostToBig(absd.mFormatID);
		cad.mFormatFlags = 0;
		if (absd.mFormatFlags & kAudioFormatFlagIsFloat)
			cad.mFormatFlags |= kCAFLinearPCMFormatFlagIsFloat;
		if (!(absd.mFormatFlags & kAudioFormatFlagIsBigEndian))
			cad.mFormatFlags |= kCAFLinearPCMFormatFlagIsLittleEndian;
#if defined(__LITTLE_ENDIAN__)
		cad.mFormatFlags = CFSwapInt32HostToBig(cad.mFormatFlags);
#endif
		cad.mBytesPerPacket = CFSwapInt32HostToBig(absd.mBytesPerPacket);
		cad.mFramesPerPacket = CFSwapInt32HostToBig(absd.mFramesPerPacket);
		cad.mChannelsPerFrame = CFSwapInt32HostToBig(absd.mChannelsPerFrame);
		cad.mBitsPerChannel = CFSwapInt32HostToBig(absd.mBitsPerChannel);
		write(fd, &cad, sizeof(CAFAudioDescription));
		
		// audio data chunk
		cch.mChunkType = CFSwapInt32HostToBig(kCAF_AudioDataChunkID);
		cch.mChunkSize = (SInt64)CFSwapInt64HostToBig(samples_size);
		write(fd, &cch.mChunkType, sizeof(cch.mChunkType));
		write(fd, &cch.mChunkSize, sizeof(cch.mChunkSize));
		
		// audio data
		UInt32 edit_count = 0;
		write(fd, &edit_count, sizeof(UInt32));
		write(fd, samples, samples_size);
		
		// flush to disk
		close(fd);
		
		// free the samples buffer
		free(samples);
	}
	
	[p release];
}

int main(int argc, char *argv[]) {
	NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
	
	struct gengetopt_args_info arguments;
	if (cmdline_parser(argc, argv, &arguments)) {
		exit(1);
	}
	
	if (arguments.inputs_num < 1) {
		printf("no archive was provided");
		exit(1);
	}
	
	NSError *error = nil;
	int archive_index = 0;
	for (; archive_index < arguments.inputs_num; archive_index++) {
		printf("processing %s\n", arguments.inputs[archive_index]);
		
		MHKArchive *archive = [[MHKArchive alloc] initWithPath:[NSString stringWithUTF8String:arguments.inputs[archive_index]] error:&error];
		if (!archive) {
			fprintf(stderr, "failed to open archive: %s", [[error description] UTF8String]);
			continue;
		}
		
		printf("--> dumping bitmaps\n");
		dump_bitmaps(archive);
		
		printf("--> dumping sounds\n");
		dump_sounds(archive, arguments.first_mpeg_pkt_only_flag);
		
		[archive release];
	}
	
	cmdline_parser_free(&arguments);
	[p release];
	return 0;
}
