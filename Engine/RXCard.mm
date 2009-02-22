//
//	RXCard.m
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <assert.h>
#import <limits.h>
#import <stdbool.h>
#import <unistd.h>

#import <mach/task.h>
#import <mach/thread_act.h>
#import <mach/thread_policy.h>

#import <OpenGL/CGLMacro.h>

#import "Base/RXAtomic.h"

#import "Engine/RXCard.h"
#import "Engine/RXScriptDecoding.h"
#import "Engine/RXScriptCommandAliases.h"

#import "Rendering/Graphics/RXTransition.h"
#import "Rendering/Graphics/RXPicture.h"
#import "Rendering/Graphics/RXDynamicPicture.h"
#import "Rendering/Graphics/RXMovieProxy.h"

struct rx_card_picture_record {
	float width;
	float height;
};


@implementation RXCard

+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (void)_loadMovies {
	NSError* error;
	MHKFileHandle* fh;
	void* listData;
	size_t listDataLength;
	uint16_t currentListIndex;
	
	uint16_t resourceID = [_descriptor ID];
	
	fh = [_archive openResourceWithResourceType:@"MLST" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding MLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:listData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding MLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many movies do we have?
	uint16_t movieCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	struct rx_mlst_record* mlstRecords = (struct rx_mlst_record*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	
	// allocate movie management objects
	_movies = [NSMutableArray new];
	_mlstCodes = new uint16_t[movieCount];
	
	// swap the records if needed
#if defined(__LITTLE_ENDIAN__)
	for (currentListIndex = 0; currentListIndex < movieCount; currentListIndex++) {
		mlstRecords[currentListIndex].index = CFSwapInt16(mlstRecords[currentListIndex].index);
		mlstRecords[currentListIndex].movie_id = CFSwapInt16(mlstRecords[currentListIndex].movie_id);
		mlstRecords[currentListIndex].code = CFSwapInt16(mlstRecords[currentListIndex].code);
		mlstRecords[currentListIndex].left = CFSwapInt16(mlstRecords[currentListIndex].left);
		mlstRecords[currentListIndex].top = CFSwapInt16(mlstRecords[currentListIndex].top);
		mlstRecords[currentListIndex].u0[0] = CFSwapInt16(mlstRecords[currentListIndex].u0[0]);
		mlstRecords[currentListIndex].u0[1] = CFSwapInt16(mlstRecords[currentListIndex].u0[1]);
		mlstRecords[currentListIndex].u0[2] = CFSwapInt16(mlstRecords[currentListIndex].u0[2]);
		mlstRecords[currentListIndex].loop = CFSwapInt16(mlstRecords[currentListIndex].loop);
		mlstRecords[currentListIndex].volume = CFSwapInt16(mlstRecords[currentListIndex].volume);
		mlstRecords[currentListIndex].u1 = CFSwapInt16(mlstRecords[currentListIndex].u1);
	}
#endif
	
	for (currentListIndex = 0; currentListIndex < movieCount; currentListIndex++) {
#if defined(DEBUG)
		RXOLog(@"loading mlst entry: {movie ID: %hu, code: %hu, left: %hu, top: %hu, loop: %hu, volume: %hu}",
			mlstRecords[currentListIndex].movie_id,
			mlstRecords[currentListIndex].code,
			mlstRecords[currentListIndex].left,
			mlstRecords[currentListIndex].top,
			mlstRecords[currentListIndex].loop,
			mlstRecords[currentListIndex].volume);
#endif
		
		// FIXME: sometimes volume > 256...
		if (mlstRecords[currentListIndex].volume > 256)
			mlstRecords[currentListIndex].volume = 256;
		
		// load the movie up
		CGPoint origin = CGPointMake(mlstRecords[currentListIndex].left, kRXCardViewportSize.height - mlstRecords[currentListIndex].top);
		RXMovieProxy* movieProxy = [[RXMovieProxy alloc] initWithArchive:_archive ID:mlstRecords[currentListIndex].movie_id origin:origin volume:mlstRecords[currentListIndex].volume / 256.0f loop:((mlstRecords[currentListIndex].loop == 1) ? YES : NO) owner:self];
		
		// add the movie to the movies array
		[_movies addObject:movieProxy];
		[movieProxy release];
		
		// set the movie code in the mlst to code array
		_mlstCodes[currentListIndex] = mlstRecords[currentListIndex].code;
	}
	
	// don't need the MLST data anymore
	free(listData);
}

- (RXSoundGroup*)createSoundGroupWithSLSTRecord:(const uint16_t*)slstRecord soundCount:(uint16_t)soundCount swapBytes:(BOOL)swapBytes {
	RXSoundGroup* group = [RXSoundGroup new];
	RXStack* parent = [_descriptor parent];
	
	// some useful pointers
	const uint16_t* groupParameters = slstRecord + soundCount;
	const uint16_t* sourceGains = groupParameters + 5;
	const uint16_t* sourcePans = sourceGains + soundCount;
	
	// fade flags
	uint16_t fade_flags = *groupParameters;
	if (swapBytes)
		fade_flags = CFSwapInt16BigToHost(fade_flags);
	group->fadeOutActiveGroupBeforeActivating = (fade_flags & 0x0001) ? YES : NO;
	group->fadeInOnActivation = (fade_flags & 0x0002) ? YES : NO;
	
	// loop flag
	uint16_t loop = *(groupParameters + 1);
	if (swapBytes)
		loop = CFSwapInt16BigToHost(loop);
	group->loop = (loop) ? YES : NO;
	
	// group gain
	uint16_t integerGain = *(groupParameters + 2);
	if (swapBytes)
		integerGain = CFSwapInt16BigToHost(integerGain);
	float gain = (float)integerGain / kRXSoundGainDivisor;
	group->gain = gain;
	
	uint16_t soundIndex = 0;
	for (; soundIndex < soundCount; soundIndex++) {
		uint16_t soundID = *(slstRecord + soundIndex);
		if (swapBytes)
			soundID = CFSwapInt16BigToHost(soundID);
		
		uint16_t sourceIntegerGain = *(sourceGains + soundIndex);
		if (swapBytes)
			sourceIntegerGain = CFSwapInt16BigToHost(sourceIntegerGain);
		float sourceGain = (float)sourceIntegerGain / kRXSoundGainDivisor;
		
		int16_t sourceIntegerPan = *((int16_t*)(sourcePans + soundIndex));
		if (swapBytes)
			sourceIntegerPan = (int16_t)CFSwapInt16BigToHost(sourceIntegerPan);
		float sourcePan = 0.5f + ((float)sourceIntegerPan / 127.0f);
		
		[group addSoundWithStack:parent ID:soundID gain:sourceGain pan:sourcePan];
	}
	
#if defined(DEBUG) && DEBUG > 1
	RXOLog(@"created sound group: %@", group);
#endif
	return group;
}

- (id)initWithCardDescriptor:(RXCardDescriptor*)cardDescriptor {
	self = [super init];
	if (!self)
		return nil;
	
	// check that the descriptor is "valid"
	if (!cardDescriptor || ![cardDescriptor isKindOfClass:[RXCardDescriptor class]]) { 
		[self release];
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Card descriptor object is nil or of the wrong type." userInfo:nil];
	}
	
	// WARNING: Stack descriptors belong to cards initialized with them, and to the object that initialized the descriptor.
	// WARNING: Consequently, if the object that initialized the descriptor owns the corresponding card, it can release the descriptor.
	// keep the descriptor around
	_descriptor = [cardDescriptor retain];
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"initializing card");
#endif
	NSError* error;
	
	NSData* cardData = [cardDescriptor valueForKey:@"data"];
	_archive = [cardDescriptor valueForKey:@"archive"];
	uint16_t resourceID = [cardDescriptor ID];
	
	// basic CARD information
	/*int16_t nameIndex = (int16_t)CFSwapInt16BigToHost(*(const int16_t *)[cardData bytes]);
	NSString* cardName = (nameIndex > -1) ? [_cardNames objectAtIndex:nameIndex] : nil;*/
	
	/*uint16_t zipCard = CFSwapInt16BigToHost(*(const uint16_t *)([cardData bytes] + 2));
	NSNumber* zipCardNumber = [NSNumber numberWithBool:(zipCard) ? YES : NO];*/
	
	// card events
	_cardEvents = rx_decode_riven_script(BUFFER_OFFSET([cardData bytes], 4), NULL);
	
	// list resources
	MHKFileHandle* fh = nil;
	void* listData = NULL;
	size_t listDataLength = 0;
	uint16_t currentListIndex = 0;
	
#pragma mark MLST

	// we don't need to load movies on the main thread anymore since we actually create movie proxies
	[self _loadMovies];
	
#pragma mark HSPT
	
	fh = [_archive openResourceWithResourceType:@"HSPT" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding HSPT resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:listData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding HSPT ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many hotspots do we have?
	uint16_t hotspotCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	uint8_t* hsptRecordPointer = (uint8_t*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	_hotspots = [[NSMutableArray alloc] initWithCapacity:hotspotCount];
	
	_hotspotsIDMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, hotspotCount);
	
	// load the hotspots
	for (currentListIndex = 0; currentListIndex < hotspotCount; currentListIndex++) {
		struct rx_hspt_record* hspt_record = (struct rx_hspt_record*)hsptRecordPointer;
		hsptRecordPointer += sizeof(struct rx_hspt_record);
		
		// byte order swap if needed
#if defined(__LITTLE_ENDIAN__)
		hspt_record->blst_id = CFSwapInt16(hspt_record->blst_id);
		hspt_record->name_rec = (int16_t)CFSwapInt16(hspt_record->name_rec);
		hspt_record->left = (int16_t)CFSwapInt16(hspt_record->left);
		hspt_record->top = (int16_t)CFSwapInt16(hspt_record->top);
		hspt_record->right = (int16_t)CFSwapInt16(hspt_record->right);
		hspt_record->bottom = (int16_t)CFSwapInt16(hspt_record->bottom);
		hspt_record->u0 = CFSwapInt16(hspt_record->u0);
		hspt_record->mouse_cursor = CFSwapInt16(hspt_record->mouse_cursor);
		hspt_record->index = CFSwapInt16(hspt_record->index);
		hspt_record->u1 = (int16_t)CFSwapInt16(hspt_record->u1);
		hspt_record->zip = CFSwapInt16(hspt_record->zip);
#endif

#if defined(DEBUG) && DEBUG > 1
		RXOLog(@"hotspot record %u: index=%hd, blst_id=%hd, zip=%hu", currentListIndex, hspt_record->index, hspt_record->blst_id, hspt_record->zip);
#endif
		
		// decode the hotspot's script
		uint32_t script_size = 0;
		NSDictionary* hotspot_script = rx_decode_riven_script(hsptRecordPointer, &script_size);
		hsptRecordPointer += script_size;
		
		// if this is a zip hotspot, skip it if Zip mode is disabled
		// FIXME: Zip mode is always disabled currently
		if (hspt_record->zip == 1)
			continue;
		
		// WORKAROUND: there is a legitimate bug in aspit's "start new game" hotspot; it executes a command 12 at the very end, which kills ambient sound after the introduction sequence; we remove that command here
		if ([_descriptor ID] == 1 && [[[_descriptor parent] key] isEqualToString:@"aspit"] && hspt_record->blst_id == 16) {
			NSDictionary* mouse_down_program = [[hotspot_script objectForKey:RXMouseDownScriptKey] objectAtIndex:0];
			
			uint16_t opcode_count = [[mouse_down_program objectForKey:RXScriptOpcodeCountKey] unsignedShortValue];
			if (opcode_count > 0 && rx_get_riven_script_opcode([[mouse_down_program objectForKey:RXScriptProgramKey] bytes] , opcode_count, opcode_count - 1) == RX_COMMAND_CLEAR_SLST) {
				NSDictionary* original_script = mouse_down_program;
				mouse_down_program = [[NSDictionary alloc] initWithObjectsAndKeys:[original_script objectForKey:RXScriptProgramKey], RXScriptProgramKey, [NSNumber numberWithUnsignedShort:opcode_count - 1], RXScriptOpcodeCountKey, nil];
				
				NSMutableDictionary* mutable_script = [hotspot_script mutableCopy];
				[mutable_script setObject:[NSArray arrayWithObject:mouse_down_program] forKey:RXMouseDownScriptKey];
				[mouse_down_program release];
				
				[hotspot_script release];
				hotspot_script = mutable_script;
			}
		}
		
		// allocate the hotspot object
		RXHotspot* hs = [[RXHotspot alloc] initWithIndex:hspt_record->index ID:hspt_record->blst_id frame:RXMakeNSRect(hspt_record->left, hspt_record->top, hspt_record->right, hspt_record->bottom) cursorID:hspt_record->mouse_cursor script:hotspot_script];
		
		uintptr_t key = hspt_record->blst_id;
		NSMapInsert(_hotspotsIDMap, (void*)key, hs);
		[_hotspots addObject:hs];
		
		[hs release];
		[hotspot_script release];
	}
	
	// don't need the HSPT data anymore
	free(listData);
	
#pragma mark BLST
	
	fh = [_archive openResourceWithResourceType:@"BLST" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding BLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	_blstData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:_blstData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding BLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	_hotspotControlRecords = (struct rx_blst_record*)BUFFER_OFFSET(_blstData, sizeof(uint16_t));
	
	// byte order (and debug)
#if defined(__LITTLE_ENDIAN__) || (defined(DEBUG) && DEBUG > 1)
	uint16_t blstCount = CFSwapInt16BigToHost(*(uint16_t*)_blstData);
	for (currentListIndex = 0; currentListIndex < blstCount; currentListIndex++) {
		struct rx_blst_record* record = _hotspotControlRecords + currentListIndex;
		
#if defined(__LITTLE_ENDIAN__)
		record->index = CFSwapInt16(record->index);
		record->enabled = CFSwapInt16(record->enabled);
		record->hotspot_id = CFSwapInt16(record->hotspot_id);
#endif // defined(__LITTLE_ENDIAN__)
		
#if defined(DEBUG) && DEBUG > 1
		RXOLog(@"blst record %u: index=%hd, enabled=%hd, hotspot_id=%hd", currentListIndex, record->index, record->enabled, record->hotspot_id);
#endif // defined(DEBUG)
	}
#endif // defined(__LITTLE_ENDIAN__) || defined(DEBUG)
	
#pragma mark PLST
	
	fh = [_archive openResourceWithResourceType:@"PLST" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding PLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:listData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding PLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many pictures do we have?
	_pictureCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	struct rx_plst_record* plstRecords = (struct rx_plst_record*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	
	// swap the records if needed
#if defined(__LITTLE_ENDIAN__)
	for (currentListIndex = 0; currentListIndex < _pictureCount; currentListIndex++) {
		plstRecords[currentListIndex].index = CFSwapInt16(plstRecords[currentListIndex].index);
		plstRecords[currentListIndex].bitmap_id = CFSwapInt16(plstRecords[currentListIndex].bitmap_id);
		plstRecords[currentListIndex].left = CFSwapInt16(plstRecords[currentListIndex].left);
		plstRecords[currentListIndex].top = CFSwapInt16(plstRecords[currentListIndex].top);
		plstRecords[currentListIndex].right = CFSwapInt16(plstRecords[currentListIndex].right);
		plstRecords[currentListIndex].bottom = CFSwapInt16(plstRecords[currentListIndex].bottom);
	}
#endif
	
	// temporary storage for picture resource IDs and dimensions
	struct rx_card_picture_record* pictureRecords = new struct rx_card_picture_record[_pictureCount];
	
	// precompute the total texture storage to hint OpenGL
	size_t textureStorageSize = 0;
	for (currentListIndex = 0; currentListIndex < _pictureCount; currentListIndex++) {
		NSDictionary* pictureDescriptor = [_archive bitmapDescriptorWithID:plstRecords[currentListIndex].bitmap_id error:&error];
		if (!pictureDescriptor)
			@throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not get a picture resource's picture descriptor." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		pictureRecords[currentListIndex].width = [[pictureDescriptor objectForKey:@"Width"] floatValue];
		pictureRecords[currentListIndex].height = [[pictureDescriptor objectForKey:@"Height"] floatValue];
		
		// we'll be using MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
		textureStorageSize += pictureRecords[currentListIndex].width * pictureRecords[currentListIndex].height * 4;
	}
	
	// allocate one big chunk of memory for all the textures
	_pictureTextureStorage = malloc(textureStorageSize);
	
	// get the load context
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	NSObject<RXOpenGLStateProtocol>* gl_state = g_loadContextState;
	
	// VAO and VBO for card pictures
	glGenBuffers(1, &_pictureVertexArrayBuffer); glReportError();
	glGenVertexArraysAPPLE(1, &_pictureVAO); glReportError();
	
	// bind the card picture VAO and VBO
	[gl_state bindVertexArrayObject:_pictureVAO];
	glBindBuffer(GL_ARRAY_BUFFER, _pictureVertexArrayBuffer); glReportError();
	
	// enable sub-range flushing if available
	if (GLEE_APPLE_flush_buffer_range)
		glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
	
	// 4 vertices per picture [<position.x position.y> <texcoord0.s texcoord0.t>], floats
	glBufferData(GL_ARRAY_BUFFER, _pictureCount * 16 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
	
	// VM map the buffer object and cache some useful pointers
	GLfloat* vertex_attributes = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	
	// allocate the texture object ID array
	_pictureTextures = new GLuint[_pictureCount];
	glGenTextures(_pictureCount, _pictureTextures); glReportError();
	
	// for each PLST entry, load and upload the picture, compute needed coords
	size_t textureStorageOffset = 0;
	for (currentListIndex = 0; currentListIndex < _pictureCount; currentListIndex++) {
		NSRect field_display_rect = RXMakeNSRect(plstRecords[currentListIndex].left, plstRecords[currentListIndex].top, plstRecords[currentListIndex].right, plstRecords[currentListIndex].bottom);
		if (![_archive loadBitmapWithID:plstRecords[currentListIndex].bitmap_id buffer:BUFFER_OFFSET(_pictureTextureStorage, textureStorageOffset) format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error])
			@throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not load a picture resource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		// bind the corresponding texture object, configure it and upload the picture
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _pictureTextures[currentListIndex]); glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
		glReportError();
		
		// specify the texture storage buffer as a texture range to encourage the framework to make a single mapping for the entire buffer
		glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_ARB, textureStorageSize, _pictureTextureStorage);
		
		// upload the texture
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, pictureRecords[currentListIndex].width, pictureRecords[currentListIndex].height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, BUFFER_OFFSET(_pictureTextureStorage, textureStorageOffset)); glReportError();
		
		// compute common vertex values
		float vertex_left_x = field_display_rect.origin.x;
		float vertex_right_x = vertex_left_x + field_display_rect.size.width;
		float vertex_bottom_y = field_display_rect.origin.y;
		float vertex_top_y = field_display_rect.origin.y + field_display_rect.size.height;
		
		// vertex 1
		vertex_attributes[0] = vertex_left_x;
		vertex_attributes[1] = vertex_bottom_y;
		
		vertex_attributes[2] = 0.0f;
		vertex_attributes[3] = pictureRecords[currentListIndex].height;
		
		// vertex 2
		vertex_attributes[4] = vertex_right_x;
		vertex_attributes[5] = vertex_bottom_y;
		
		vertex_attributes[6] = pictureRecords[currentListIndex].width;
		vertex_attributes[7] = pictureRecords[currentListIndex].height;
		
		// vertex 3
		vertex_attributes[8] = vertex_left_x;
		vertex_attributes[9] = vertex_top_y;
		
		vertex_attributes[10] = 0.0f;
		vertex_attributes[11] = 0.0f;
		
		// vertex 4
		vertex_attributes[12] = vertex_right_x;
		vertex_attributes[13] = vertex_top_y;
		
		vertex_attributes[14] = pictureRecords[currentListIndex].width;
		vertex_attributes[15] = 0.0f;
		
		// move along
		textureStorageOffset += pictureRecords[currentListIndex].width * pictureRecords[currentListIndex].height * 4;
		vertex_attributes += 16;
	}
	
	// unmap and flush the picture vertex buffer
	if (GLEE_APPLE_flush_buffer_range)
		glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, _pictureCount * 16 * sizeof(GLfloat));
	glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
	
	// configure VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 0)); glReportError();
	
	glClientActiveTexture(GL_TEXTURE0);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY); glReportError();
	glTexCoordPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), (void*)BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
	// bind 0 to the current VAO
	[gl_state bindVertexArrayObject:0];
	
	// we don't need the picture records and the PLST data anymore
	delete[] pictureRecords;
	free(listData);
	
#pragma mark FLST
	
	fh = [_archive openResourceWithResourceType:@"FLST" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding FLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:listData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding FLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	_sfxeCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	_sfxes = (rx_card_sfxe*)malloc(sizeof(rx_card_sfxe) * _sfxeCount);
	
	struct rx_flst_record* flstRecordPointer = reinterpret_cast<struct rx_flst_record*>(BUFFER_OFFSET(listData, sizeof(uint16_t)));
	for (currentListIndex = 0; currentListIndex < _sfxeCount; currentListIndex++) {
		struct rx_flst_record* record = flstRecordPointer + currentListIndex;
		
#if defined(__LITTLE_ENDIAN__)
		record->index = CFSwapInt16(record->index);
		record->sfxe_id = CFSwapInt16(record->sfxe_id);
		record->u0 = CFSwapInt16(record->u0);
#endif
		
		// open the corresponding SFXE resource
		MHKFileHandle* sfxeHandle = [_archive openResourceWithResourceType:@"SFXE" ID:record->sfxe_id];
		if (!sfxeHandle)
			@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open a required SFXE resource." userInfo:nil];
		
		// get the size of the SFXE resource and allocate the sfxe's record buffer
		size_t sfxeLength = (size_t)[sfxeHandle length];
		assert(sfxeLength >= sizeof(struct rx_sfxe_record*));
		
		rx_card_sfxe* sfxe = _sfxes + currentListIndex;
		sfxe->record = (struct rx_sfxe_record*)malloc(sfxeLength);
		
		// read the data from the archive
		if ([sfxeHandle readDataToEndOfFileInBuffer:(void*)sfxe->record error:&error] == -1)
			@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read a required SFXE resource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
#if defined(__LITTLE_ENDIAN__)
		// byte swap on litle endian architectures
		sfxe->record->magic = CFSwapInt16(sfxe->record->magic);
		sfxe->record->frame_count = CFSwapInt16(sfxe->record->frame_count);
		sfxe->record->offset_table = CFSwapInt32(sfxe->record->offset_table);
		sfxe->record->left = CFSwapInt16(sfxe->record->left);
		sfxe->record->top = CFSwapInt16(sfxe->record->top);
		sfxe->record->right = CFSwapInt16(sfxe->record->right);
		sfxe->record->bottom = CFSwapInt16(sfxe->record->bottom);
		sfxe->record->fps = CFSwapInt16(sfxe->record->fps);
		sfxe->record->u0 = CFSwapInt16(sfxe->record->u0);
		sfxe->record->alt_top = CFSwapInt16(sfxe->record->alt_top);
		sfxe->record->alt_left = CFSwapInt16(sfxe->record->alt_left);
		sfxe->record->alt_bottom = CFSwapInt16(sfxe->record->alt_bottom);
		sfxe->record->alt_right = CFSwapInt16(sfxe->record->alt_right);
		sfxe->record->u1 = CFSwapInt16(sfxe->record->u1);
		sfxe->record->alt_frame_count = CFSwapInt16(sfxe->record->alt_frame_count);
		sfxe->record->u2 = CFSwapInt32(sfxe->record->u2);
		sfxe->record->u3 = CFSwapInt32(sfxe->record->u3);
		sfxe->record->u4 = CFSwapInt32(sfxe->record->u4);
		sfxe->record->u5 = CFSwapInt32(sfxe->record->u5);
		sfxe->record->u6 = CFSwapInt32(sfxe->record->u6);
#endif
		
		// alias the offset table for convenience
		sfxe->offsets = (uint32_t*)BUFFER_OFFSET(sfxe->record, sfxe->record->offset_table);

#if defined(__LITTLE_ENDIAN__)
		// byte swap the offsets and the program
		for (uint16_t fi = 0; fi < sfxe->record->frame_count; fi++) {
			sfxe->offsets[fi] = CFSwapInt32(sfxe->offsets[fi]);
			
			uint16_t* mp = (uint16_t*)BUFFER_OFFSET(sfxe->record, sfxe->offsets[fi]);
			*mp = CFSwapInt16(*mp);
			while (*mp != 4) {
				if (*mp == 3) {
					mp[1] = CFSwapInt16(mp[1]);
					mp[2] = CFSwapInt16(mp[2]);
					mp[3] = CFSwapInt16(mp[3]);
					mp[4] = CFSwapInt16(mp[4]);
					mp += 4;
				} else if (*mp != 1)
					abort();
				
				mp++;
				*mp = CFSwapInt16(*mp);
			}
			
			assert(mp <= (uint16_t*)BUFFER_OFFSET(sfxe->record, sfxeLength));
		}
#endif
	}
	
	// don't need the FLST data anymore
	free(listData);
	
	// new textures, buffer and program objects
	glFlush();
	
	// done with the GL context
	CGLUnlockContext(cgl_ctx);
	
#pragma mark SLST
	
	fh = [_archive openResourceWithResourceType:@"SLST" ID:resourceID];
	if (!fh)
		@throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding SLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	if ([fh readDataToEndOfFileInBuffer:listData error:&error] == -1)
		@throw [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding SLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many sound groups do we have?
	uint16_t soundGroupCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	uint16_t* slstRecordPointer = (uint16_t*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	_soundGroups = [[NSMutableArray alloc] initWithCapacity:soundGroupCount];
	
	// skip over index of first record (for loop takes care of skipping it afterwards)
	slstRecordPointer++;
	
	// load the sound groups
	for (currentListIndex = 0; currentListIndex < soundGroupCount; currentListIndex++) {
		uint16_t soundCount = CFSwapInt16BigToHost(*slstRecordPointer);
		slstRecordPointer++;
		
		// create a sound group for the record
		RXSoundGroup* group = [self createSoundGroupWithSLSTRecord:slstRecordPointer soundCount:soundCount swapBytes:YES];
		if (group)
			[_soundGroups addObject:group];
		[group release];
		
		// move on to the next record's sound_count field
		slstRecordPointer = slstRecordPointer + (4 * soundCount) + 6;
	}
	
	// don't need the SLST data anymore
	free(listData);
	
	// end of list records loading
	
	// we're done preparing the card
#if defined(DEBUG)
	RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"initialized card");
#endif
	return self;
}

- (RXCardDescriptor*)descriptor {
	return _descriptor;
}

- (MHKArchive*)archive {
	return _archive;
}

- (GLuint)pictureCount {
	return _pictureCount;
}

- (GLuint)pictureVAO {
	return _pictureVAO;
}

- (GLuint*)pictureTextures {
	return _pictureTextures;
}

- (NSDictionary*)events {
	return _cardEvents;
}

- (NSArray*)hotspots {
	return _hotspots;
}

- (NSMapTable*)hotspotsIDMap {
	return _hotspotsIDMap;
}

- (struct rx_blst_record*)hotspotControlRecords {
	return _hotspotControlRecords;
}

- (NSArray*)movies {
	return _movies;
}

- (uint16_t*)movieCodes {
	return _mlstCodes;
}

- (NSArray*)soundGroups {
	return _soundGroups;
}

- (rx_card_sfxe*)sfxes {
	return _sfxes;
}

- (void)dealloc {
#if defined(DEBUG)
	RXOLog(@"deallocating");
#endif

	// stop receiving notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	// lock the GL context and clean up textures and GL buffers
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	{
		if (_pictureVertexArrayBuffer != 0)
			glDeleteBuffers(1, &_pictureVertexArrayBuffer);
		if (_pictureTextures)
			glDeleteTextures(_pictureCount, _pictureTextures);

		// objects have gone away, so we flush
		glFlush();
	}
	CGLUnlockContext(cgl_ctx);
	
	// movies
	[_movies release];
	if (_mlstCodes)
		delete[] _mlstCodes;
	
	// pictures
	if (_pictureTextures)
		delete[] _pictureTextures;
	if (_pictureTextureStorage)
		free(_pictureTextureStorage);
	
	// sounds
	[_soundGroups release];
	
	// hotspots
	if (_hotspotsIDMap)
		NSFreeMapTable(_hotspotsIDMap);
	[_hotspots release];
	
	// sfxe
	if (_sfxes) {
		for (uint16_t i = 0; i < _sfxeCount; i++) {
			free(_sfxes[i].record);
		}
		free(_sfxes);
	}
	
	// misc resources
	if (_blstData)
		free(_blstData);
	[_cardEvents release];
	[_descriptor release];
	
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat: @"%@ {%@}", [super description], [_descriptor description]];
}

@end
