//
//	MHKArchiveWAVAdditions.m
//	MHKKit
//
//	Created by Jean-Francois Roy on 06/25/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "mohawk_wave.h"

#import "MHKArchive.h"
#import "MHKADPCMDecompressor.h"
#import "MHKMP2Decompressor.h"
#import "MHKErrors.h"
#import "PHSErrorMacros.h"


@interface MHKFileHandle (Private)
- (id)_initWithArchive:(MHKArchive *)archive fork:(SInt16)fork soundDescriptor:(NSDictionary *)sdesc;
@end


@implementation MHKArchive (MHKArchiveWAVAdditions)

- (NSDictionary *)soundDescriptorWithID:(uint16_t)soundID error:(NSError **)errorPtr {
	OSStatus err = noErr;
	ByteCount bytes_read = 0;
	SInt64 file_offset;
	NSNumber *soundIDNumber = [NSNumber numberWithUnsignedShort:soundID];
	
	// check for a cached value
	pthread_rwlock_rdlock(&__cached_sound_descriptors_rwlock);
	NSDictionary *soundDescriptor = [__cached_sound_descriptors objectForKey:soundIDNumber];
	if (soundDescriptor) {
		pthread_rwlock_unlock(&__cached_sound_descriptors_rwlock);
		ReturnValueWithNoError(soundDescriptor, errorPtr)
	}
	pthread_rwlock_unlock(&__cached_sound_descriptors_rwlock);
	
	// get the wave resource descriptor
	NSDictionary *descriptor = [self resourceDescriptorWithResourceType:@"tWAV" ID:soundID];
	if (!descriptor) ReturnNULLWithError(MHKErrorDomain, errUnknownID, nil, errorPtr)
	
	// seek to the tWAV resource then seek to the data chunk
	SInt64 resource_offset = [[descriptor objectForKey:@"Offset"] longLongValue];
	file_offset = resource_offset;
	
#if defined(VERBOSE)
	printf("offset: 0x%qx\n", resource_offset);
#endif
	
	// standard chunk header
	MHK_chunk_header chunk_header;
	
	// we need to have a standard MHWK chunk first
	err = FSReadFork(forkRef, fsFromStart, file_offset, sizeof(MHK_chunk_header), &chunk_header, &bytes_read);
	if (err) ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
	file_offset += bytes_read;
	
	// handle byte order and check header
	MHK_chunk_header_fton(&chunk_header);
	if (*(uint32_t *)chunk_header.signature != MHK_MHWK_signature_integer) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
	
	// since resource lengths are computed in the archive, we need to do some checking here
	UInt32 resource_length = chunk_header.content_length + sizeof(MHK_chunk_header);
	UInt32 resource_length_from_archive = [[descriptor objectForKey:@"Length"] unsignedLongValue];
	if (resource_length != resource_length_from_archive) {
#if defined(VERBOSE)
		printf("read length: 0x%x, computed length: 0x%x, difference = 0x%x\n", resource_length, resource_length_from_archive, resource_length_from_archive - resource_length);
#endif
		
		// if the resource length is greater than the one from the archive, take the one from the archive since it was computed to be the biggest size possible w/o resource overlap
		if (resource_length > resource_length_from_archive) resource_length = resource_length_from_archive;
	}
	
	// must have the WAVE signature next
	uint32_t wave_signature = 0;
	err = FSReadFork(forkRef, fsFromStart, file_offset, sizeof(uint32_t), &wave_signature, &bytes_read);
	if (err) ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
	file_offset += bytes_read;
	if (wave_signature != MHK_WAVE_signature_integer) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
	
	// compute the resource limit
	SInt64 resource_eof = resource_offset + chunk_header.content_length + sizeof(MHK_chunk_header);
	
	// loop until we find the Data chunk of we exceed the limits of this resource
	do {
		// read a chunk header structure
		err = FSReadFork(forkRef, fsFromStart, file_offset, sizeof(MHK_chunk_header), &chunk_header, &bytes_read);
		if (err) ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
		file_offset += bytes_read;
		MHK_chunk_header_fton(&chunk_header);
		
		// do we have a winner?
		if (*(uint32_t *)chunk_header.signature == MHK_Data_signature_integer) break;
		
		// advance the position to the next chunk
		file_offset += chunk_header.content_length;
	} while (resource_offset < resource_eof);
	
	// did we score?
	if (*(uint32_t *)chunk_header.signature != MHK_Data_signature_integer) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
	
	// read the Data chunk content header
	MHK_WAVE_Data_chunk_header data_header;
	err = FSReadFork(forkRef, fsFromStart, file_offset, sizeof(MHK_WAVE_Data_chunk_header), &data_header, &bytes_read);
	if (err) ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
	file_offset += bytes_read;
	MHK_WAVE_Data_chunk_header_fton(&data_header);
	
	// just like a lot of other things in MHK files, we have to compute lengths because the numbers in the archive are unreliable
	uint32_t headers_length = (uint32_t)(file_offset - resource_offset);
	uint32_t samples_length = resource_length - headers_length;
	
	// if the file is ADPCM, we can actually compute exactly how many bytes we need
	if (data_header.compression_type == MHK_WAVE_ADPCM) {
		uint32_t required_bytes_for_adpcm = data_header.frame_count * data_header.channel_count / 2;
		
		// from my observations, ADPCM files always need 0x18 more bytes :| but let's do the math anyways
		if (required_bytes_for_adpcm > samples_length) {
			uint32_t extra_bytes_required = required_bytes_for_adpcm - samples_length;
			uint32_t available_gap_bytes = (uint32_t)(resource_offset + resource_length_from_archive);
			available_gap_bytes = available_gap_bytes - (uint32_t)(file_offset + samples_length);
			
			// we need to have extra bytes in order to fudge the number
			if (available_gap_bytes > 0) {
				samples_length += (extra_bytes_required > available_gap_bytes) ? available_gap_bytes : extra_bytes_required;
			}
		}
	} else if(data_header.compression_type == MHK_WAVE_MP2) {
		// let's verify if it's a proper MP2 file by checking the first packet
		uint32_t mpeg_header = 0;
		unsigned char packet_index = 0;
		for (; packet_index < 3; packet_index++) {
			err = FSReadFork(forkRef, fsFromStart, file_offset, sizeof(uint32_t), &mpeg_header, NULL);
			if (err) ReturnNULLWithError(NSOSStatusErrorDomain, err, nil, errorPtr)
			// WE OMIT TO UPDATE file_offset ON PURPOSE SO THAT IT STILL POINTS AT THE BEGINNING OF THE FIRST MPEG FRAME
			
			// byte swap the header
			mpeg_header = CFSwapInt32BigToHost(mpeg_header);
			
			// first 11 bits have to be 1s (MPEG packet sync)
			if ((mpeg_header & 0xFFE00000) != 0xFFE00000) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
			
			// 2 bits - type must be 10 for MPEG v2
			if ((mpeg_header & 0x00180000) != 0x00100000) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
			
			// 2 bits - layer must be 10 for layer II
			if ((mpeg_header & 0x00060000) != 0x00040000) ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
		}
	} else {
		ReturnNULLWithError(MHKErrorDomain, errDamagedResource, nil, errorPtr)
		return nil;
	}
	
#if defined(VERBOSE)
	printf("samples offset: 0x%qx\n", file_offset);
	printf("sample rate: %u, samples: %u, bit depth: %d, channels: %d, compression: %u\n", 
		data_header.sampling_rate, 
		data_header.frame_count, 
		data_header.bit_depth, 
		data_header.channel_count, 
		data_header.compression_type);
	printf("headers length: 0x%x\n", headers_length);
	printf("computed resource length without headers: 0x%x\n", samples_length);
	if(data_header.compression_type == MHK_WAVE_ADPCM) {
		uint32_t required_bytes_for_adpcm = data_header.frame_count * data_header.channel_count / 2;
		printf("required bytes for compressed samples (using ADPCM): 0x%x\n", required_bytes_for_adpcm);
		printf("difference: 0x%x\n", required_bytes_for_adpcm - samples_length);
	}
	printf("\n");
#endif
	
	soundDescriptor = [NSDictionary dictionaryWithObjectsAndKeys:@"tWAV", @"Type", 
		[NSNumber numberWithLongLong:file_offset], @"Samples Absolute Offset", 
		[NSNumber numberWithUnsignedLong:samples_length], @"Samples Length", 
		[NSNumber numberWithUnsignedShort:data_header.sampling_rate], @"Sampling Rate", 
		[NSNumber numberWithUnsignedLong:data_header.frame_count], @"Frame Count", 
		[NSNumber numberWithUnsignedChar:data_header.bit_depth], @"Bit Depth", 
		[NSNumber numberWithUnsignedChar:data_header.channel_count], @"Channel Count", 
		[NSNumber numberWithUnsignedShort:data_header.compression_type], @"Compression Type", 
		nil];
	
	pthread_rwlock_wrlock(&__cached_sound_descriptors_rwlock);
	[__cached_sound_descriptors setObject:soundDescriptor forKey:soundIDNumber];
	pthread_rwlock_unlock(&__cached_sound_descriptors_rwlock);
	
	ReturnValueWithNoError(soundDescriptor, errorPtr)
}

- (MHKFileHandle *)openSoundWithID:(uint16_t)soundID error:(NSError **)errorPtr {
	NSDictionary *soundDescriptor = [self soundDescriptorWithID:soundID error:errorPtr];
	if (!soundDescriptor) return nil;
	
	MHKFileHandle *fh = [[MHKFileHandle alloc] _initWithArchive:self fork:forkRef soundDescriptor:soundDescriptor];
	if (fh) [self performSelector:@selector(_fileDidAlloc)];
	
	ReturnValueWithNoError([fh autorelease], errorPtr)
}

- (id <MHKAudioDecompression>)decompressorWithSoundID:(uint16_t)soundID error:(NSError **)errorPtr {
	NSDictionary *soundDescriptor = [self soundDescriptorWithID:soundID error:errorPtr];
	if (!soundDescriptor) return nil;
	
	uint16_t compression_type = [[soundDescriptor objectForKey:@"Compression Type"] unsignedShortValue];
	UInt32 channels = [[soundDescriptor objectForKey:@"Channel Count"] unsignedLongValue];
	SInt64 frames = [[soundDescriptor objectForKey:@"Frame Count"] longLongValue];
	double sr = [[soundDescriptor objectForKey:@"Sampling Rate"] doubleValue];
	
	// open a MHK file handle for the decompressor
	MHKFileHandle *fh = [self openSoundWithID:soundID error:errorPtr];
	if(!fh) return nil;
	
	// what decompressor class do we need
	Class decompressor_class = NULL;
	if (compression_type == MHK_WAVE_ADPCM) decompressor_class = [MHKADPCMDecompressor class];
	else if (compression_type == MHK_WAVE_MP2) decompressor_class = [MHKMP2Decompressor class];
	else ReturnNILWithError(MHKErrorDomain, errInvalidSoundDescriptor, nil, errorPtr)
		
	// return a decompressor
	return [[[decompressor_class alloc] initWithChannelCount:channels frameCount:frames samplingRate:sr fileHandle:fh error:errorPtr] autorelease];
}

@end
