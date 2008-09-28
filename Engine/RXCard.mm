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

#import <OpenGL/CGLMacro.h>

#import "RXAtomic.h"
#import "RXWorldProtocol.h"
#import "RXCard.h"
#import "RXTransition.h"

#import "RXMovieProxy.h"

static const GLuint kDynamicPictureSlots = 10;

static const NSTimeInterval kInsideHotspotPeriodicEventPeriod = 0.1;

static const float kSoundGainDivisor = 255.0f;
static const float kMovieGainDivisor = 500.0f;

static const NSString* k_eventSelectors[] = {
	@"mouseDown",
	@"mouseDown2",
	@"mouseUp",
	@"mouseDownOrUpOrMoved",
	@"mouseTrack",
	@"mouseExited",
	@"loading",
	@"leaving",
	@"UNKNOWN - TYPE 8",
	@"rendering",
	@"priming"
};

struct _RXCardPictureRecord {
	float width;
	float height;
};

struct _RXCardDynamicPicture {
	GLuint texture;
	GLuint buffer;
};

#pragma options align=packed
struct _RXPLSTRecord {
	uint16_t index;
	uint16_t bitmap_id;
	uint16_t left;
	uint16_t top;
	uint16_t right;
	uint16_t bottom;
};

struct _RXMLSTRecord {
	uint16_t index;
	uint16_t movie_id;
	uint16_t code;
	uint16_t left;
	uint16_t top;
	uint16_t u0[3];
	uint16_t loop;
	uint16_t volume;
	uint16_t u1;
};

struct _RXSLSTRecord1 {
	uint16_t index;
	uint16_t sound_count;
};

struct _RXSLSTRecord2 {
	uint16_t fade_flags;
	uint16_t global_volume;
	uint16_t u0;
	uint16_t u1;
};

struct _RXHSPTRecord {
	uint16_t blst_id;
	int16_t name_rec;
	int16_t left;
	int16_t top;
	int16_t right;
	int16_t bottom;
	uint16_t u0;
	uint16_t mouse_cursor;
	uint16_t index;
	int16_t u1;
	uint16_t zip;
};

struct _RXBLSTRecord {
	uint16_t index;
	uint16_t enabled;
	uint16_t hotspot_id;
};

struct _RXFLSTRecord {
	uint16_t index;
	uint16_t sfxe_id;
	uint16_t u0;
};

struct _RXSFXERecord {
	uint16_t magic;
	uint16_t frame_count;
	uint32_t offset_table;
	uint16_t left;
	uint16_t top;
	uint16_t right;
	uint16_t bottom;
	uint16_t fps;
	uint16_t u0;
	uint16_t alt_top;
	uint16_t alt_left;
	uint16_t alt_bottom;
	uint16_t alt_right;
	uint16_t u1;
	uint16_t alt_frame_count;
	uint32_t u2;
	uint32_t u3;
	uint32_t u4;
	uint32_t u5;
	uint32_t u6;
};
#pragma options align=reset

typedef void (*RXOpcodeImplementor)(id, SEL, const uint16_t, const uint16_t *);
static SEL _rivenOpcodeSelectors[47];
static RXOpcodeImplementor _rivenOpcodeImplementations[47];

static NSMutableString* _scriptLogPrefix;

CF_INLINE NSPoint RXMakeNSPointFromPoint(uint16_t x, uint16_t y) {
	return NSMakePoint((float)x, (float)y);
}

CF_INLINE NSRect RXMakeNSRect(uint16_t left, uint16_t top, uint16_t right, uint16_t bottom) {
	return NSMakeRect((float)left, (float)(kRXCardViewportSize.height - bottom), (float)(right - left), (float)(bottom - top));
}

static size_t _computeRivenScriptLength(const void* script, uint16_t commandCount, bool byte_swap) {
	size_t scriptOffset = 0;
	
	uint16_t currentCommandIndex = 0;
	for (; currentCommandIndex < commandCount; currentCommandIndex++) {
		// command, argument count, arguments (all shorts)
		uint16_t commandNumber = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
		if (byte_swap) commandNumber = CFSwapInt16BigToHost(commandNumber);
		scriptOffset += 2;
		
		uint16_t argumentCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
		if (byte_swap) argumentCount = CFSwapInt16BigToHost(argumentCount);
		size_t argumentsOffset = 2 * (argumentCount + 1);
		scriptOffset += argumentsOffset;
		
		// need to do extra processing for command 8
		if (commandNumber == 8) {
			// arg 0 is the variable, arg 1 is the number of cases
			uint16_t caseCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset - argumentsOffset + 4);
			if (byte_swap) caseCount = CFSwapInt16BigToHost(caseCount);
			
			uint16_t currentCaseIndex = 0;
			for (; currentCaseIndex < caseCount; currentCaseIndex++) {
				// case variable value
				scriptOffset += 2;
				
				uint16_t caseCommandCount = *(const uint16_t*)BUFFER_OFFSET(script, scriptOffset);
				if (byte_swap) caseCommandCount = CFSwapInt16BigToHost(caseCommandCount);
				scriptOffset += 2;
				
				size_t caseCommandListLength = _computeRivenScriptLength(BUFFER_OFFSET(script, scriptOffset), caseCommandCount, byte_swap);
				scriptOffset += caseCommandListLength;
			}
		}
	}
	
	return scriptOffset;
}

static NSDictionary* _decodeRivenScript(const void* script, uint32_t* scriptLength) {
	// WARNING: THIS METHOD ASSUMES THE INPUT SCRIPT IS IN BIG ENDIAN
	
	// a script is composed of several events
	uint16_t eventCount = CFSwapInt16BigToHost(*(const uint16_t *)script);
	uint32_t scriptOffset = 2;
	
	// one array of Riven programs per event type
	uint32_t eventTypeCount = sizeof(k_eventSelectors) / sizeof(NSString *);
	uint16_t currentEventIndex = 0;
	NSMutableArray** eventProgramsPerType = (NSMutableArray**)malloc(sizeof(NSMutableArray*) * eventTypeCount);
	for (; currentEventIndex < eventTypeCount; currentEventIndex++) eventProgramsPerType[currentEventIndex] = [[NSMutableArray alloc] initWithCapacity:eventCount];
	
	// process the programs
	for (currentEventIndex = 0; currentEventIndex < eventCount; currentEventIndex++) {
		// event type, command count
		uint16_t eventCode = CFSwapInt16BigToHost(*(const uint16_t *)BUFFER_OFFSET(script, scriptOffset));
		scriptOffset += 2;
		uint16_t commandCount = CFSwapInt16BigToHost(*(const uint16_t *)BUFFER_OFFSET(script, scriptOffset));
		scriptOffset += 2;
		
		// program length
		size_t programLength = _computeRivenScriptLength(BUFFER_OFFSET(script, scriptOffset), commandCount, true);
		
		// allocate a storage buffer for the program and swap it if needed
		uint16_t* programStore = (uint16_t*)malloc(programLength);
		memcpy(programStore, BUFFER_OFFSET(script, scriptOffset), programLength);
#if defined(__LITTLE_ENDIAN__)
		uint32_t shortCount = programLength / 2;
		while (shortCount > 0) {
			programStore[shortCount - 1] = CFSwapInt16BigToHost(programStore[shortCount - 1]);
			shortCount--;
		}
#endif
		
		// store the program in an NSData object
		NSData* program = [[NSData alloc] initWithBytesNoCopy:programStore length:programLength freeWhenDone:YES];
		scriptOffset += programLength;
		
		// program descriptor
		NSDictionary* programDescriptor = [[NSDictionary alloc] initWithObjectsAndKeys:program, @"program", 
			[NSNumber numberWithUnsignedShort:commandCount], @"opcodeCount", 
			nil];
		assert(eventCode < eventTypeCount);
		[eventProgramsPerType[eventCode] addObject:programDescriptor];
		
		[program release];
		[programDescriptor release];
	}
	
	// each event key holds an array of programs
	NSDictionary* scriptDictionary = [[NSDictionary alloc] initWithObjects:eventProgramsPerType forKeys:k_eventSelectors count:eventTypeCount];
	
	// release the program arrays now that they're in the dictionary
	for (currentEventIndex = 0; currentEventIndex < eventTypeCount; currentEventIndex++) [eventProgramsPerType[currentEventIndex] release];
	
	// release the program array array.
	free(eventProgramsPerType);
	
	// return total script length and script dictionary
	if (scriptLength) *scriptLength = scriptOffset;
	return scriptDictionary;
}

#pragma mark -

@interface RXCard (RXCardPrivate)
- (RXSoundGroup *)_createSoundGroupWithSLSTRecord:(const uint16_t *)slstRecord soundCount:(uint16_t)soundCount swapBytes:(BOOL)swapBytes;
- (size_t)_executeRivenProgram:(const void *)program count:(uint16_t)opcodeCount;
- (void)_swapRenderState;
- (void)_swapMovieRenderState;
@end

@interface RXCard (RXCardRivenScriptOpcodes)
- (void)_opcode_activateMLST:(const uint16_t)argc arguments:(const uint16_t *)argv;
@end

@implementation RXCard

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

+ (void)initialize {
	if (self == [RXCard class]) {
		_scriptLogPrefix = [NSMutableString new];
		
		_rivenOpcodeSelectors[0] = @selector(_invalid_opcode:arguments:);
		_rivenOpcodeSelectors[1] = @selector(_opcode_drawDynamicPicture:arguments:);
		_rivenOpcodeSelectors[2] = @selector(_opcode_goToCard:arguments:);
		_rivenOpcodeSelectors[3] = @selector(_opcode_enableSynthesizedSLST:arguments:);
		_rivenOpcodeSelectors[4] = @selector(_opcode_playLocalSound:arguments:);
		_rivenOpcodeSelectors[5] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[6] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[7] = @selector(_setVariable:arguments:);
		_rivenOpcodeSelectors[8] = @selector(_invalid_opcode:arguments:);
		_rivenOpcodeSelectors[9] = @selector(_opcode_enableHotspot:arguments:);
		_rivenOpcodeSelectors[10] = @selector(_opcode_disableHotspot:arguments:);
		_rivenOpcodeSelectors[11] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[12] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[13] = @selector(_opcode_setCursor:arguments:);
		_rivenOpcodeSelectors[14] = @selector(_opcode_pause:arguments:);
		_rivenOpcodeSelectors[15] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[16] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[17] = @selector(_callExternal:arguments:);
		_rivenOpcodeSelectors[18] = @selector(_scheduleTransition:arguments:);
		_rivenOpcodeSelectors[19] = @selector(_reloadCard:arguments:);
		_rivenOpcodeSelectors[20] = @selector(_disableAutomaticSwaps:arguments:);
		_rivenOpcodeSelectors[21] = @selector(_enableAutomaticSwaps:arguments:);
		_rivenOpcodeSelectors[22] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[23] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[24] = @selector(_incrementVariable:arguments:);
		_rivenOpcodeSelectors[25] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[26] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[27] = @selector(_goToStack:arguments:);
		_rivenOpcodeSelectors[28] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[29] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[30] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[31] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[32] = @selector(_opcode_startMovieAndWaitUntilDone:arguments:);
		_rivenOpcodeSelectors[33] = @selector(_opcode_startMovie:arguments:);
		_rivenOpcodeSelectors[34] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[35] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[36] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[37] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[38] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[39] = @selector(_opcode_activatePLST:arguments:);
		_rivenOpcodeSelectors[40] = @selector(_opcode_activateSLST:arguments:);
		_rivenOpcodeSelectors[41] = @selector(_opcode_prepareMLST:arguments:);
		_rivenOpcodeSelectors[42] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[43] = @selector(_opcode_activateBLST:arguments:);
		_rivenOpcodeSelectors[44] = @selector(_opcode_activateFLST:arguments:);
		_rivenOpcodeSelectors[45] = @selector(_opcode_noop:arguments:);
		_rivenOpcodeSelectors[46] = @selector(_opcode_activateMLST:arguments:);
		
		unsigned char selectorIndex = 0;
		for (; selectorIndex < 47; selectorIndex++) _rivenOpcodeImplementations[selectorIndex] = (RXOpcodeImplementor)[self instanceMethodForSelector:_rivenOpcodeSelectors[selectorIndex]];
	}
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithCardDescriptor:(RXCardDescriptor *)cardDescriptor {
	self = [super init];
	if (!self) return nil;
	
	_scriptHandler = nil;
	
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
	RXOLog(@"initializing card");
#endif
	kern_return_t kerr;
	NSError* error;
	
	// movie playback semaphore
	kerr = semaphore_create(mach_task_self(), &_moviePlaybackSemaphore, SYNC_POLICY_FIFO, 0);
	if (kerr != 0) {
		[self release];
		error = [NSError errorWithDomain:NSMachErrorDomain code:kerr userInfo:nil];
		@throw [NSException exceptionWithName:@"RXSystemResourceException" reason:@"Could not create the movie playback semaphore." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	}
	
	// movie load semaphore
	kerr = semaphore_create(mach_task_self(), &_movieLoadSemaphore, SYNC_POLICY_FIFO, 0);
	if (kerr != 0) {
		[self release];
		error = [NSError errorWithDomain:NSMachErrorDomain code:kerr userInfo:nil];
		@throw [NSException exceptionWithName:@"RXSystemResourceException" reason:@"Could not create the movie load semaphore." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	}
	
	// active hotspots lock
	_activeHotspotsLock = OS_SPINLOCK_INIT;
	
	NSData* cardData = [cardDescriptor valueForKey:@"data"];
	_archive = [cardDescriptor valueForKey:@"archive"];
	uint16_t resourceID = [[cardDescriptor valueForKey:@"ID"] unsignedShortValue];
	
	// basic CARD information
	/*int16_t nameIndex = (int16_t)CFSwapInt16BigToHost(*(const int16_t *)[cardData bytes]);
	NSString* cardName = (nameIndex > -1) ? [_cardNames objectAtIndex:nameIndex] : nil;*/
	
	/*uint16_t zipCard = CFSwapInt16BigToHost(*(const uint16_t *)([cardData bytes] + 2));
	NSNumber* zipCardNumber = [NSNumber numberWithBool:(zipCard) ? YES : NO];*/
	
	// card events
	_cardEvents = _decodeRivenScript(BUFFER_OFFSET([cardData bytes], 4), NULL);
	
	// list resources
	MHKFileHandle* fh = nil;
	void* listData = NULL;
	size_t listDataLength = 0;
	uint16_t currentListIndex = 0;
	
#pragma mark MLST
	// movies need to be loaded on the main thread because of QuickTime limitations
	[self performSelectorOnMainThread:@selector(_loadMovies) withObject:nil waitUntilDone:NO];
	
#pragma mark HSPT
	fh = [_archive openResourceWithResourceType:@"HSPT" ID:resourceID];
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding HSPT resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:listData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding HSPT ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many hotspots do we have?
	uint16_t hotspotCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	uint8_t* hsptRecordPointer = (uint8_t*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	_hotspots = [[NSMutableArray alloc] initWithCapacity:hotspotCount];
	
	_hotspotsIDMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, hotspotCount);
	_activeHotspots = [[NSMutableArray alloc] initWithCapacity:hotspotCount];
	
	// load the hotspots
	for (currentListIndex = 0; currentListIndex < hotspotCount; currentListIndex++) {
		struct _RXHSPTRecord* hspt_record = (struct _RXHSPTRecord*)hsptRecordPointer;
		hsptRecordPointer += sizeof(struct _RXHSPTRecord);
		
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
		uint32_t scriptLength = 0;
		NSDictionary* hotspotScript = _decodeRivenScript(hsptRecordPointer, &scriptLength);
		hsptRecordPointer += scriptLength;
		
		// if this is a zip hotspot, skip it if Zip mode is disabled
		// FIXME: Zip mode is always disabled currently
		if (hspt_record->zip == 1) continue;
		
		// allocate the hotspot object
		RXHotspot* hs = [[RXHotspot alloc] initWithIndex:hspt_record->index ID:hspt_record->blst_id frame:RXMakeNSRect(hspt_record->left, hspt_record->top, hspt_record->right, hspt_record->bottom) cursorID:hspt_record->mouse_cursor script:hotspotScript];
		
		uintptr_t key = hspt_record->blst_id;
		NSMapInsert(_hotspotsIDMap, (void*)key, hs);
		[_hotspots addObject:hs];
		
		[hs release];
		[hotspotScript release];
	}
	
	// don't need the HSPT data anymore
	free(listData); listData = NULL;
	
#pragma mark BLST
	fh = [_archive openResourceWithResourceType:@"BLST" ID:resourceID];
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding BLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	_blstData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:_blstData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding BLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	_hotspotControlRecords = BUFFER_OFFSET(_blstData, sizeof(uint16_t));
	
	// byte order (and debug)
#if defined(__LITTLE_ENDIAN__) || defined(DEBUG)
	uint16_t blstCount = CFSwapInt16BigToHost(*(uint16_t*)_blstData);
	for (currentListIndex = 0; currentListIndex < blstCount; currentListIndex++) {
		struct _RXBLSTRecord* record = (struct _RXBLSTRecord*)_hotspotControlRecords + currentListIndex;
		
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
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding PLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:listData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding PLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many pictures do we have?
	_pictureCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	struct _RXPLSTRecord* plstRecords = (struct _RXPLSTRecord*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	
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
	struct _RXCardPictureRecord* pictureRecords = new struct _RXCardPictureRecord[_pictureCount];
	
	// precompute the total texture storage to hint OpenGL
	size_t textureStorageSize = 0;
	for (currentListIndex = 0; currentListIndex < _pictureCount; currentListIndex++) {
		NSDictionary* pictureDescriptor = [_archive bitmapDescriptorWithID:plstRecords[currentListIndex].bitmap_id error:&error];
		if (!pictureDescriptor) @throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not get a picture resource's picture descriptor." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		pictureRecords[currentListIndex].width = [[pictureDescriptor valueForKey:@"Width"] floatValue];
		pictureRecords[currentListIndex].height = [[pictureDescriptor valueForKey:@"Height"] floatValue];
		
		// we'll be using MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
		textureStorageSize += pictureRecords[currentListIndex].width * pictureRecords[currentListIndex].height * 4;
	}
	
	// allocate one big chunk of memory for all the textures
	_pictureTextureStorage = malloc(textureStorageSize);
	
	// get the load context
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	// VAO and VBO for card pictures
	glGenBuffers(1, &_pictureVertexArrayBuffer); glReportError();
	glGenVertexArraysAPPLE(1, &_pictureVAO); glReportError();
	
	// bind the card picture VAO and VBO
	glBindVertexArrayAPPLE(_pictureVAO); glReportError();
	glBindBuffer(GL_ARRAY_BUFFER, _pictureVertexArrayBuffer); glReportError();
	
	// 4 vertices per picture [<position.x position.y> <texcoord0.s texcoord0.t>], floats
	glBufferData(GL_ARRAY_BUFFER, (_pictureCount + kDynamicPictureSlots) * 16 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
	
	// VM map the buffer object and cache some useful pointers
	GLfloat* vertex_attributes = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	
	// allocate the texture object ID array
	_pictureTextures = new GLuint[_pictureCount + kDynamicPictureSlots];
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
	
	// unmap and flush the VBO
	glUnmapBuffer(GL_ARRAY_BUFFER); glReportError();
	
	// configure VAs
	glEnableClientState(GL_VERTEX_ARRAY); glReportError();
	glVertexPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 0)); glReportError();
	
	glClientActiveTexture(GL_TEXTURE0);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY); glReportError();
	glTexCoordPointer(2, GL_FLOAT, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
	
	// bind 0 to ARRAY_BUFFER
	glBindBuffer(GL_ARRAY_BUFFER, 0); glReportError();
	
	// bind 0 to the current VAO
	glBindVertexArrayAPPLE(0); glReportError();
	
	// we don't need the picture records and the PLST data anymore
	delete[] pictureRecords;
	free(listData); listData = NULL;
	
#pragma mark FLST
	fh = [_archive openResourceWithResourceType:@"FLST" ID:resourceID];
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding FLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:listData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding FLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	_sfxeCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	_sfxes = new _rx_card_sfxe[_sfxeCount];
	
	struct _RXFLSTRecord* flstRecordPointer = reinterpret_cast<struct _RXFLSTRecord*>(BUFFER_OFFSET(listData, sizeof(uint16_t)));
	for (currentListIndex = 0; currentListIndex < _sfxeCount; currentListIndex++) {
		struct _RXFLSTRecord* record = flstRecordPointer + currentListIndex;
		
#if defined(__LITTLE_ENDIAN__)
		record->index = CFSwapInt16(record->index);
		record->sfxe_id = CFSwapInt16(record->sfxe_id);
		record->u0 = CFSwapInt16(record->u0);
#endif

		MHKFileHandle* sfxeHandle = [_archive openResourceWithResourceType:@"SFXE" ID:record->sfxe_id];
		if (!sfxeHandle) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open a required SFXE resource." userInfo:nil];
		
		size_t sfxeLength = (size_t)[sfxeHandle length];
		assert(sfxeLength >= sizeof(struct _RXSFXERecord*));
		void* sfxeData = malloc(sfxeLength);
		
		// read the data from the archive
		[sfxeHandle readDataToEndOfFileInBuffer:sfxeData error:&error];
		if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read a required SFXE resource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		struct _RXSFXERecord* sfxeRecord = reinterpret_cast<struct _RXSFXERecord*>(sfxeData);
#if defined(__LITTLE_ENDIAN__)
		sfxeRecord->magic = CFSwapInt16(sfxeRecord->magic);
		sfxeRecord->frame_count = CFSwapInt16(sfxeRecord->frame_count);
		sfxeRecord->offset_table = CFSwapInt32(sfxeRecord->offset_table);
		sfxeRecord->left = CFSwapInt16(sfxeRecord->left);
		sfxeRecord->top = CFSwapInt16(sfxeRecord->top);
		sfxeRecord->right = CFSwapInt16(sfxeRecord->right);
		sfxeRecord->bottom = CFSwapInt16(sfxeRecord->bottom);
		sfxeRecord->fps = CFSwapInt16(sfxeRecord->fps);
		sfxeRecord->u0 = CFSwapInt16(sfxeRecord->u0);
		sfxeRecord->alt_top = CFSwapInt16(sfxeRecord->alt_top);
		sfxeRecord->alt_left = CFSwapInt16(sfxeRecord->alt_left);
		sfxeRecord->alt_bottom = CFSwapInt16(sfxeRecord->alt_bottom);
		sfxeRecord->alt_right = CFSwapInt16(sfxeRecord->alt_right);
		sfxeRecord->u1 = CFSwapInt16(sfxeRecord->u1);
		sfxeRecord->alt_frame_count = CFSwapInt16(sfxeRecord->alt_frame_count);
		sfxeRecord->u2 = CFSwapInt32(sfxeRecord->u2);
		sfxeRecord->u3 = CFSwapInt32(sfxeRecord->u3);
		sfxeRecord->u4 = CFSwapInt32(sfxeRecord->u4);
		sfxeRecord->u5 = CFSwapInt32(sfxeRecord->u5);
		sfxeRecord->u6 = CFSwapInt32(sfxeRecord->u6);
#endif
		
		// prepare the rx special effect structure
		struct _rx_card_sfxe* sfxe = _sfxes + currentListIndex;
		
		// fill in some general information
		sfxe->nframes = sfxeRecord->frame_count;
		sfxe->frames = new GLuint[sfxe->nframes];
		sfxe->fps = static_cast<double>(sfxeRecord->fps);
		sfxe->roi = RXMakeNSRect(sfxeRecord->left, sfxeRecord->top, sfxeRecord->right, sfxeRecord->bottom);
		
		glGenTextures(sfxe->nframes, sfxe->frames);
		size_t frame_size = kRXCardViewportSize.width * kRXCardViewportSize.height * sizeof(uint32_t);
		sfxe->frame_storage = malloc(frame_size * sfxe->nframes);
		
		uint32_t* offset_table = reinterpret_cast<uint32_t*>(BUFFER_OFFSET(sfxeData, sfxeRecord->offset_table));
		for (uint32_t frame = 0; frame < sfxeRecord->frame_count; frame++) {
			uint16_t* sfxeProgram = reinterpret_cast<uint16_t*> (BUFFER_OFFSET(sfxeData, CFSwapInt32BigToHost(offset_table[frame])));
			uint8_t* frame_texture = reinterpret_cast<uint8_t*> (BUFFER_OFFSET(sfxe->frame_storage, frame_size * frame));
			
			// BGRA
			frame_texture[0] = 0;
			frame_texture[1] = INT8_MAX;
			frame_texture[2] = INT8_MAX;
			frame_texture[3] = 0;
			for (GLsizei i = 4; i < (kRXCardViewportSize.width << 2); i+=4) {
				frame_texture[i] = frame_texture[0];
				frame_texture[i + 1] = frame_texture[1];
				frame_texture[i + 2] = frame_texture[2];
				frame_texture[i + 3] = frame_texture[3];
			}
			GLint currentRow = 1;
			GLsizei rowsAvailable = 1;
			GLsizei rowsToCopy = kRXCardViewportSize.height - 1;
			while (rowsToCopy > 0) {
				rowsAvailable = MIN(rowsAvailable, rowsToCopy);
				memcpy(frame_texture + ((currentRow * kRXCardViewportSize.width) << 2), frame_texture, (rowsAvailable * kRXCardViewportSize.width) << 2);
				rowsToCopy -= rowsAvailable;
				currentRow += rowsAvailable;
				rowsAvailable <<= 1;
			}
#if defined(DEBUG)
			for (GLint y = 0; y < kRXCardViewportSize.height; y++) {
				for (GLint x = 0; x < kRXCardViewportSize.width; x++) {
					size_t p = (y*kRXCardViewportSize.width + x) << 2;
					assert(frame_texture[p] == 0);
					assert(frame_texture[p + 1] == INT8_MAX);
					assert(frame_texture[p + 2] == INT8_MAX);
					assert(frame_texture[p + 3] == 0);
				}
			}
#endif
			
			int16_t dy = static_cast<int16_t>(kRXCardViewportSize.height - sfxeRecord->top - 1);
			uint16_t command = CFSwapInt16BigToHost(*sfxeProgram);
			while (command != 4) {
				if (command == 1) dy--;
				else if (command == 3) {
					int16_t dx = static_cast<int16_t>(CFSwapInt16BigToHost(*(sfxeProgram + 1)));
					int16_t sx = static_cast<int16_t>(CFSwapInt16BigToHost(*(sfxeProgram + 2)));
					int16_t sy = static_cast<int16_t>(kRXCardViewportSize.height - CFSwapInt16BigToHost(*(sfxeProgram + 3)) - 1);
					int16_t rows = static_cast<int16_t>(CFSwapInt16BigToHost(*(sfxeProgram + 4)));
					sfxeProgram += 4;
					
					assert(sx >= 0);
					assert(sx < kRXCardViewportSize.width);
					assert(sy >= 0);
					assert(sy < kRXCardViewportSize.height);
					
					assert(dx >= 0);
					assert(dx < kRXCardViewportSize.width);
					assert(dy >= 0);
					assert(dy < kRXCardViewportSize.height);
					assert((dx + rows) <= kRXCardViewportSize.width);
					
					int16_t delta_y = sy - dy;
					int16_t delta_x = sx - dx;
					
					assert(delta_x <= INT8_MAX);
					assert(delta_x > INT8_MIN);
					
					assert(delta_y <= INT8_MAX);
					assert(delta_y > INT8_MIN);
					
					size_t row_p = dy*kRXCardViewportSize.width;
					for (int16_t r = dx; r < dx + rows; r++) {
						size_t p = (row_p + r) << 2;
#if defined(__LITTLE_ENDIAN__)
						assert(frame_texture[p + 3] == 0);
						assert(frame_texture[p + 2] == INT8_MAX);
						assert(frame_texture[p + 1] == INT8_MAX);
						
						frame_texture[p + 3] = UINT8_MAX;
						frame_texture[p + 2] = static_cast<uint8_t>(delta_x + INT8_MAX);
						frame_texture[p + 1] = static_cast<uint8_t>(delta_y + INT8_MAX);
#else
						assert(frame_texture[p] == 0);
						assert(frame_texture[p + 1] == INT8_MAX);
						assert(frame_texture[p + 2] == INT8_MAX);
						
						frame_texture[p] = UINT8_MAX;
						frame_texture[p + 1] = static_cast<uint8_t>(delta_x + INT8_MAX);
						frame_texture[p + 2] = static_cast<uint8_t>(delta_y + INT8_MAX);
#endif
					}
				} else abort();
				
				sfxeProgram++;
				command = CFSwapInt16BigToHost(*sfxeProgram);
			}
			
			// bind the corresponding texture object
			glBindTexture(GL_TEXTURE_RECTANGLE_ARB, sfxe->frames[frame]); glReportError();
			
			// texture parameters
			glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_SHARED_APPLE);
			glReportError();
			
			glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXCardViewportSize.width, kRXCardViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, frame_texture); glReportError();
		}
		
		free(sfxeData);
	}
	
	// don't need the FLST data anymore
	free(listData); listData = NULL;
	
	// new textures, buffer and program objects
	glFlush();
	
	// done with the GL context
	CGLUnlockContext(cgl_ctx);
	
#pragma mark SLST
	fh = [_archive openResourceWithResourceType:@"SLST" ID:resourceID];
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding SLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:listData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding SLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
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
		RXSoundGroup* group = [self _createSoundGroupWithSLSTRecord:slstRecordPointer soundCount:soundCount swapBytes:YES];
		if (group) [_soundGroups addObject:group];
		[group release];
		
		// move on to the next record's sound_count field
		slstRecordPointer = slstRecordPointer + (4 * soundCount) + 6;
	}
	
	// don't need the SLST data anymore
	free(listData); listData = NULL;
	
	// end of list records loading
	
#pragma mark rendering
	// now that we know how many renderable graphic objects there are, allocate the render state objects
	_renderState1.pictures = [NSMutableArray new];
	_renderState1.movies = [NSMutableArray new];
	_renderState2.pictures = [_renderState1.pictures mutableCopy];
	_renderState2.movies = [_renderState1.movies mutableCopy];
	
	_frontRenderStatePtr = &_renderState1;
	_backRenderStatePtr = &_renderState2;
	
	// render state swaps are disabled by default
	_renderStateSwapsEnabled = NO;
	
	// map from tBMP resource to texture ID for dynamic pictures
	_dynamicPictureMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSOwnedPointerMapValueCallBacks, 0);
	_dynamicPictureCount = 0;
	
	// wait for movies
	semaphore_wait(_movieLoadSemaphore);
	
	// we're done preparing the card
#if defined(DEBUG)
	RXOLog(@"initialized card");
#endif
	return self;
}

- (RXCardDescriptor*)descriptor {
	return _descriptor;
}

- (void)setRivenScriptHandler:(id <RXRivenScriptProtocol>)handler {
	if (![handler conformsToProtocol:@protocol(RXRivenScriptProtocol)]) {
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"OBJECT DOES NOT CONFORM TO RXRivenScriptProtocol" userInfo:nil];
	}
	
	_scriptHandler = handler;
}

- (void)_loadMovies {
	NSError* error;
	MHKFileHandle* fh;
	void* listData;
	size_t listDataLength;
	uint16_t currentListIndex;
	
	uint16_t resourceID = [[_descriptor valueForKey:@"ID"] unsignedShortValue];
	
	fh = [_archive openResourceWithResourceType:@"MLST" ID:resourceID];
	if (!fh) @throw [NSException exceptionWithName:@"RXMissingResourceException" reason:@"Could not open the card's corresponding MLST resource." userInfo:nil];
	
	listDataLength = (size_t)[fh length];
	listData = malloc(listDataLength);
	
	// read the data from the archive
	[fh readDataToEndOfFileInBuffer:listData error:&error];
	if (error) [NSException exceptionWithName:@"RXRessourceIOException" reason:@"Could not read the card's corresponding MLST ressource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// how many movies do we have?
	uint16_t movieCount = CFSwapInt16BigToHost(*(uint16_t*)listData);
	struct _RXMLSTRecord* mlstRecords = (struct _RXMLSTRecord*)BUFFER_OFFSET(listData, sizeof(uint16_t));
	
	// allocate movie management objects
	_movies = [NSMutableArray new];
	_mlstCodes = new uint16_t[movieCount];
	_codeToMovieMap = NSCreateMapTable(NSIntMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 0);
	
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
#if defined(DEBUG) && DEBUG > 1
		RXOLog(@"loading mlst entry: {movie ID: %hu, code: %hu, left: %hu, top: %hu, loop: %hu, volume: %hu}",
			mlstRecords[currentListIndex].movie_id,
			mlstRecords[currentListIndex].code,
			mlstRecords[currentListIndex].left,
			mlstRecords[currentListIndex].top,
			mlstRecords[currentListIndex].loop,
			mlstRecords[currentListIndex].volume);
#endif
		
		// load the movie up
		CGPoint origin = CGPointMake(mlstRecords[currentListIndex].left, kRXCardViewportSize.height - mlstRecords[currentListIndex].top);
		RXMovieProxy* movieProxy = [[RXMovieProxy alloc] initWithArchive:_archive ID:mlstRecords[currentListIndex].movie_id origin:origin loop:(mlstRecords[currentListIndex].loop == 1) ? YES : NO];
		
		// add the movie to the movies array
		[_movies addObject:movieProxy];
		[movieProxy release];
		
		// set the movie code in the mlst to code array
		_mlstCodes[currentListIndex] = mlstRecords[currentListIndex].code;
	}
	
	// don't need the MLST data anymore
	free(listData); listData = NULL;
	
	// signal that we're done loading the movies
	semaphore_signal(_movieLoadSemaphore);
}

- (RXSoundGroup *)_createSoundGroupWithSLSTRecord:(const uint16_t *)slstRecord soundCount:(uint16_t)soundCount swapBytes:(BOOL)swapBytes {
	RXSoundGroup* group = [[RXSoundGroup alloc] init];
	RXStack* parent = [_descriptor valueForKey:@"parent"];
	
	// some useful pointers
	const uint16_t* groupParameters = slstRecord + soundCount;
	const uint16_t* sourceGains = groupParameters + 5;
	const uint16_t* sourcePans = sourceGains + soundCount;
	
	// fade flags
	uint16_t fade_flags = *groupParameters;
	if (swapBytes) fade_flags = CFSwapInt16BigToHost(fade_flags);
	[group setValue:[NSNumber numberWithBool:(fade_flags & 0x0001) ? YES : NO] forKey:@"fadeOutActiveGroupBeforeActivating"];
	[group setValue:[NSNumber numberWithBool:(fade_flags & 0x0002) ? YES : NO] forKey:@"fadeInOnActivation"];
	
	// loop flag
	uint16_t loop = *(groupParameters + 1);
	if (swapBytes) loop = CFSwapInt16BigToHost(loop);
	[group setValue:[NSNumber numberWithBool:(loop) ? YES : NO] forKey:@"loop"];
	
	// group gain
	uint16_t integerGain = *(groupParameters + 2);
	if (swapBytes) integerGain = CFSwapInt16BigToHost(integerGain);
	float gain = (float)integerGain / kSoundGainDivisor;
	[group setValue:[NSNumber numberWithFloat:gain] forKey:@"gain"];
	
	uint16_t soundIndex = 0;
	for (; soundIndex < soundCount; soundIndex++) {
		uint16_t soundID = *(slstRecord + soundIndex);
		if (swapBytes) soundID = CFSwapInt16BigToHost(soundID);
		
		uint16_t sourceIntegerGain = *(sourceGains + soundIndex);
		if (swapBytes) sourceIntegerGain = CFSwapInt16BigToHost(sourceIntegerGain);
		float sourceGain = (float)sourceIntegerGain / kSoundGainDivisor;
		
		int16_t sourceIntegerPan = *((int16_t*)(sourcePans + soundIndex));
		if (swapBytes) sourceIntegerPan = (int16_t)CFSwapInt16BigToHost(sourceIntegerPan);
		float sourcePan = 0.5f + ((float)sourceIntegerPan / 127.0f);
		
		[group addSoundWithStack:parent ID:soundID gain:sourceGain pan:sourcePan];
	}
	
#if defined(DEBUG) && DEBUG > 1
	RXOLog(@"created sound group: %@", group);
#endif
	return group;
}

#pragma mark -

- (void)_handleMovieRateChange:(NSNotification *)notification {
	// WARNING: MUST RUN ON MAIN THREAD
	float rate = [[[notification userInfo] objectForKey:QTMovieRateDidChangeNotificationParameter] floatValue];
	if (rate < 0.001f) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"%@ has stopped playing", [notification object]);
#endif
		
		// FIXME: slow way to find the matching RXMovie object, should use a map, but there won't ever be a million movies, so
//		uint32_t movieIndex = 0;
//		for (; movieIndex < [_backRenderStatePtr->movies count]; movieIndex++) if ([(RXMovie*)[_backRenderStatePtr->movies objectAtIndex:movieIndex] movie] == [notification object]) break;
//		if (movieIndex == [_backRenderStatePtr->movies count]) RXOLog2(kRXLoggingRendering, kRXLoggingLevelError, @"failed to find matching RXMovie object after movie %@ finished playing", [notification object]);
//		else [_backRenderStatePtr->movies removeObjectAtIndex:movieIndex];
		
		[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieRateDidChangeNotification object:[notification object]];
	}
}

- (void)_handleBlockingMovieRateChange:(NSNotification *)notification {
	// WARNING: MUST RUN ON MAIN THREAD
	float rate = [[[notification userInfo] objectForKey:QTMovieRateDidChangeNotificationParameter] floatValue];
	if (rate < 0.001f) {
		[self _handleMovieRateChange:notification];
		
#if defined(DEBUG)
		RXOLog2(kRXLoggingRendering, kRXLoggingLevelDebug, @"resuming script execution after blocking movie %@ playback", [notification object]);
#endif
		
		// inform the script handler script execution is no longer blocked
		[_scriptHandler setExecutingBlockingAction:NO];
		
		// signal the movie playback semaphore to unblock the script thread
		semaphore_signal(_moviePlaybackSemaphore);
	}
}

- (void)_reallyDoPlayMovie:(RXMovie*)glMovie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// do nothing if the movie is already playing
	if ([[glMovie movie] rate] > 0.001f) return;
	
	// put the movie at its beginning
	if (![glMovie looping]) [glMovie gotoBeginning];
	
	// add the movie to the render state
	uint32_t movieIndex = [_backRenderStatePtr->movies indexOfObject:glMovie];
	if (movieIndex != NSNotFound) [_backRenderStatePtr->movies removeObjectAtIndex:movieIndex];
	[_backRenderStatePtr->movies addObject:glMovie];
	
	// begin playback
	[[glMovie movie] play];
	
	// swap render states (it is safe to do so because the script thread always waits for _playMovie to be done before continuing)
	[self _swapMovieRenderState];
}

- (void)_playMovie:(RXMovie*)glMovie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// register for rate notifications on the non-blocking movie handler
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleMovieRateChange:) name:QTMovieRateDidChangeNotification object:[glMovie movie]];
	
	// play
	[self _reallyDoPlayMovie:glMovie];
}

- (void)_playBlockingMovie:(RXMovie*)glMovie {
	// WARNING: MUST RUN ON MAIN THREAD
	
	// register for rate notifications on the blocking movie handler
	[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieRateDidChangeNotification object:[glMovie movie]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleBlockingMovieRateChange:) name:QTMovieRateDidChangeNotification object:[glMovie movie]];
	
	// inform the script handler script execution is now blocked
	[_scriptHandler setExecutingBlockingAction:YES];
	
	// start playing the movie (this may be a no-op if the movie was already started)
	[self _reallyDoPlayMovie:glMovie];
}


- (void)_stopAllMovies {
	// WARNING: MUST RUN ON MAIN THREAD
	NSEnumerator* movies = [_backRenderStatePtr->movies objectEnumerator];
	RXMovie* movie;
	while ((movie = [movies nextObject])) [[movie movie] stop];
}

#pragma mark -

- (void)_invalid_opcode:(const uint16_t)argc arguments:(const uint16_t *)argv {
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"INVALID RIVEN SCRIPT OPCODE EXECUTED: %d", argv[-2]] userInfo:nil];
}

- (void)_opcode_noop:(const uint16_t)argc arguments:(const uint16_t *)argv {
	uint16_t argi = 0;
	NSString* formatString;
	if (argv) formatString = [NSString stringWithFormat:@"WARNING: opcode %hu not implemented. arguments: {", *(argv - 2)];
	else formatString = [NSString stringWithFormat:@"WARNING: unknown opcode called (most likely the _enableAutomaticSwaps hack) {"];
	if (argc > 1) for (; argi < argc - 1; argi++) formatString = [formatString stringByAppendingFormat:@"%hu, ", argv[argi]];
	
	if (argc > 0) formatString = [formatString stringByAppendingFormat:@"%hu", argv[argi]];
	formatString = [formatString stringByAppendingString:@"}"];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", _scriptLogPrefix, formatString);
}

- (void)_opcode_drawDynamicPicture:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 9) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	if (_dynamicPictureCount >= kDynamicPictureSlots) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"OUT OF DYNAMIC PICTURE SLOTS" userInfo:nil];
	NSRect field_display_rect = RXMakeNSRect(argv[1], argv[2], argv[3], argv[4]);
	
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@drawing dynamic picture ID %hu in rect {{%f, %f}, {%f, %f}}", _scriptLogPrefix, argv[0], field_display_rect.origin.x, field_display_rect.origin.y, field_display_rect.size.width, field_display_rect.size.height);
#endif
	
	// get the resource descriptor for the tBMP resource
	NSError* error;
	NSDictionary* pictureDescriptor = [_archive bitmapDescriptorWithID:argv[0] error:&error];
	if (!pictureDescriptor) @throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not get a picture resource's picture descriptor." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
	
	// compute the size of the buffer needed to store the texture; we'll be using MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED as the texture format, which is 4 bytes per pixel
	GLsizeiptr pictureSize = [[pictureDescriptor valueForKey:@"Width"] integerValue] * [[pictureDescriptor valueForKey:@"Height"] integerValue] * 4;
	
	// get the load context
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	
	// check if we have a cache for the tBMP ID; create a dynamic picture structure otherwise and map it to the tBMP ID
	uintptr_t dynamicPictureKey = argv[0];
	struct _RXCardDynamicPicture* dynamicPicture = (struct _RXCardDynamicPicture*)NSMapGet(_dynamicPictureMap, (const void*)dynamicPictureKey);
	if (dynamicPicture == NULL) {
		dynamicPicture = reinterpret_cast<struct _RXCardDynamicPicture*>(malloc(sizeof(struct _RXCardDynamicPicture*)));
		
		// create a buffer object in which to decompress the tBMP resource
		glGenBuffers(1, &(dynamicPicture->buffer)); glReportError();
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, dynamicPicture->buffer); glReportError();
		
		// allocate the buffer object and map it
		glBufferData(GL_PIXEL_UNPACK_BUFFER, pictureSize, NULL, GL_STATIC_DRAW);
		GLvoid* pictureBuffer = glMapBuffer(GL_PIXEL_UNPACK_BUFFER, GL_WRITE_ONLY); glReportError();
		
		// load the picture in the mapped picture buffer
		[_archive loadBitmapWithID:argv[0] buffer:pictureBuffer format:MHK_BGRA_UNSIGNED_INT_8_8_8_8_REV_PACKED error:&error];
		if (error) @throw [NSException exceptionWithName:@"RXPictureLoadException" reason:@"Could not load a picture resource." userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
		
		// unmap the buffer
		glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER); glReportError();
		
		// create a texture object and bind it
		glGenTextures(1, &(dynamicPicture->texture)); glReportError();
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, dynamicPicture->texture); glReportError();
		
		// texture parameters
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glReportError();
		
		// client storage is not compatible with PBO texture unpack
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
		
		// unpack the texture
		glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, [[pictureDescriptor valueForKey:@"Width"] intValue], [[pictureDescriptor valueForKey:@"Height"] intValue], 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, BUFFER_OFFSET(NULL, 0)); glReportError();
		
		// reset the unpack buffer state and re-enable client storage
		glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE); glReportError();
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0); glReportError();
		
		// map the tBMP ID to the dynamic picture
		NSMapInsert(_dynamicPictureMap, (void*)dynamicPictureKey, dynamicPicture);
	}
	
	// if the front render state says we're done refreshing the static content and the back render state has not been modified, we can reset the dynamic picture count
	if (_frontRenderStatePtr->refresh_static == NO && _backRenderStatePtr->refresh_static == NO) _dynamicPictureCount = 0;
	
	// compute common vertex values
	float vertex_left_x = field_display_rect.origin.x;
	float vertex_right_x = vertex_left_x + field_display_rect.size.width;
	float vertex_bottom_y = field_display_rect.origin.y;
	float vertex_top_y = field_display_rect.origin.y + field_display_rect.size.height;
	
	// bind the the picture VBO 
	glBindBuffer(GL_ARRAY_BUFFER, _pictureVertexArrayBuffer); glReportError();
	if (GLEE_APPLE_client_storage) glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
	
	// map the picture VBO and move to the correct offset
	GLfloat* vertex_attributes = reinterpret_cast<GLfloat*>(glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)); glReportError();
	vertex_attributes = vertex_attributes + ((_pictureCount + _dynamicPictureCount) * 16); // 8 vectors, 2 component per vector
	
	// specify rectangle vertex and tex coords counter-clockwise from (0, 0)
	// vertex 1
	vertex_attributes[0] = vertex_left_x;
	vertex_attributes[1] = vertex_bottom_y;
	
	vertex_attributes[2] = 0.0f;
	vertex_attributes[3] = [[pictureDescriptor valueForKey:@"Height"] floatValue];
	
	// vertex 2
	vertex_attributes[4] = vertex_right_x;
	vertex_attributes[5] = vertex_bottom_y;
	
	vertex_attributes[6] = [[pictureDescriptor valueForKey:@"Width"] floatValue];
	vertex_attributes[7] = [[pictureDescriptor valueForKey:@"Height"] floatValue];
	
	// vertex 3
	vertex_attributes[8] = vertex_right_x;
	vertex_attributes[9] = vertex_top_y;
	
	vertex_attributes[10] = [[pictureDescriptor valueForKey:@"Width"] floatValue];
	vertex_attributes[11] = 0.0f;
	
	// vertex 4
	vertex_attributes[12] = vertex_left_x;
	vertex_attributes[13] = vertex_top_y;
	
	vertex_attributes[14] = 0.0f;
	vertex_attributes[15] = 0.0f;
	
	// unmap the picture VBO and restore the array buffer state
	if (GLEE_APPLE_flush_buffer_range) glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, (_pictureCount + _dynamicPictureCount) * 16, 16);
	glUnmapBuffer(GL_ARRAY_BUFFER);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	
	// flush new objects
	glFlush();
	
	CGLUnlockContext(cgl_ctx);
	
	// add the dynamic picture index to the picture render array
	[_backRenderStatePtr->pictures addObject:[NSNumber numberWithUnsignedInt:_pictureCount + _dynamicPictureCount]];
	_pictureTextures[_pictureCount + _dynamicPictureCount] = dynamicPicture->texture;
	
	// one more dynamic picture
	_dynamicPictureCount++;
	
	// opcode 1 triggers a render state swap
	[self _swapRenderState];
}

// 2
- (void)_opcode_goToCard:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to card ID %hu", _scriptLogPrefix, argv[0]);
#endif

	RXStack* parent = [_descriptor valueForKey:@"parent"];
	[_scriptHandler setActiveCardWithStack:[parent key] ID:argv[0] waitUntilDone:YES];
}

// 3
- (void)_opcode_enableSynthesizedSLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling a synthesized slst record", _scriptLogPrefix);
#endif

	RXSoundGroup* oldSoundGroup = _synthesizedSoundGroup;

	// argv + 1 is suitable for _createSoundGroupWithSLSTRecord
	uint16_t soundCount = argv[0];
	_synthesizedSoundGroup = [self _createSoundGroupWithSLSTRecord:(argv + 1) soundCount:soundCount swapBytes:NO];
	
	[_scriptHandler activateSoundGroup:_synthesizedSoundGroup];
	[oldSoundGroup release];
}

// 4
- (void)_opcode_playLocalSound:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 3) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@playing local sound resource with id %hu", _scriptLogPrefix, argv[0]);
#endif
	
	RXDataSound* sound = [RXDataSound new];
	sound->parent = [_descriptor valueForKey:@"parent"];
	sound->ID = argv[0];
	sound->gain = 1.0f;
	sound->pan = 0.5f;
	
	[_scriptHandler playDataSound:sound];
	[sound release];
}

// 7
- (void)_setVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	RXStack* parent = [_descriptor valueForKey:@"parent"];
	NSString* name = [parent varNameAtIndex:argv[0]];
	if (!name) name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting variable %@ to %hu", _scriptLogPrefix, name, argv[1]);
#endif
	
	[[g_world gameState] setUnsignedShort:argv[1] forKey:name];
}

// 9
- (void)_opcode_enableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling hotspot %hu", _scriptLogPrefix, argv[0]);
#endif
	
	uint32_t key = argv[0];
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void*)key));
	assert(hotspot);
	
	if (!hotspot->enabled) {
		hotspot->enabled = YES;
		
		OSSpinLockLock(&_activeHotspotsLock);
		[_activeHotspots addObject:hotspot];
		[_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
		OSSpinLockUnlock(&_activeHotspotsLock);
		
		[_insideHotspotEventTimer invalidate];
		_insideHotspotEventTimer = nil;
		
		[_scriptHandler resetHotspotState];
	}
}

// 10
- (void)_opcode_disableHotspot:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling hotspot %hu", _scriptLogPrefix, argv[0]);
#endif
	
	uint32_t key = argv[0];
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void *)key));
	if (!hotspot) abort();
	
	if (hotspot->enabled) {
		hotspot->enabled = NO;
		
		OSSpinLockLock(&_activeHotspotsLock);
		[_activeHotspots removeObject:hotspot];
		[_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
		OSSpinLockUnlock(&_activeHotspotsLock);
		
		[_insideHotspotEventTimer invalidate];
		_insideHotspotEventTimer = nil;
		
		[_scriptHandler resetHotspotState];
	}
}

// 13
- (void)_opcode_setCursor:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@setting cursor to %hu", _scriptLogPrefix, argv[0]);
#endif

	[g_worldView performSelectorOnMainThread:@selector(setCursor:) withObject:[g_world cursorForID:argv[0]] waitUntilDone:NO];
}

// 14
- (void)_opcode_pause:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@pausing for %d msec", _scriptLogPrefix, argv[0]);
#endif
	
	[_scriptHandler setExecutingBlockingAction:YES];
	usleep(argv[0] * 1000);
	[_scriptHandler setExecutingBlockingAction:NO];
}

// 17
- (void)_callExternal:(const uint16_t)argc arguments:(const uint16_t*)argv {
	// FIXME: implement externals
	uint16_t argi = 0;
	uint16_t externalID = argv[0];
	uint16_t extarnalArgc = argv[1];
	
	NSString* externalName = [[_descriptor valueForKey:@"_parent"] externalNameAtIndex:externalID];
	if (!externalName) externalName = @"UNKNOWN_EXTERNAL";
	NSString* formatString = [NSString stringWithFormat:@"WARNING: calling external %hu (%@) not implemented. arguments: {", externalID, externalName];
	if (extarnalArgc > 1) for (; argi < extarnalArgc - 1; argi++) formatString = [formatString stringByAppendingFormat:@"%hu, ", argv[2 + argi]];
	
	if (extarnalArgc > 0) formatString = [formatString stringByAppendingFormat:@"%hu", argv[2 + argi]];
	formatString = [formatString stringByAppendingString:@"}"];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@%@", _scriptLogPrefix, formatString);
}

// 18
- (void)_scheduleTransition:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc != 1 && argc != 5) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	uint16_t code = argv[0];	
	NSRect rect;
	if (argc > 1) rect = RXMakeNSRect(argv[1], argv[2], argv[3], argv[4]);
	else rect = NSMakeRect(0, 0, kRXCardViewportSize.width, kRXCardViewportSize.height);
	
	RXTransition* transition = [[RXTransition alloc] initWithCode:code region:rect];

#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@scheduling transition %@", _scriptLogPrefix, transition);
#endif
	
	// queue the transition
	if (transition->type == RXTransitionDissolve && _lastExecutedProgramOpcode == 18 && _queuedAPushTransition) RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"WARNING: dropping dissolve transition because last command queued a push transition");
	else [_scriptHandler queueTransition:transition];
	
	// transition is now owned by the transitionq queue
	[transition release];
	
	// leave a note if we queued a push transition
	if (transition->type == RXTransitionSlide) _queuedAPushTransition = YES;
	else _queuedAPushTransition = NO;
}

// 19
- (void)_reloadCard:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@reloading card", _scriptLogPrefix);
#endif
	
	RXStack* parent = [_descriptor valueForKey:@"parent"];
	[_scriptHandler setActiveCardWithStack:[parent key] ID:[[_descriptor valueForKey:@"ID"] unsignedShortValue] waitUntilDone:YES];
}

// 20
- (void)_disableAutomaticSwaps:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (argv != NULL) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling render state swaps", _scriptLogPrefix);
	else RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@disabling render state swaps before prepareForRendering execution", _scriptLogPrefix);
#endif
	_renderStateSwapsEnabled = NO;
}

// 21
- (void)_enableAutomaticSwaps:(const uint16_t)argc arguments:(const uint16_t*)argv {
#if defined(DEBUG)
	if (!_disableScriptLogging) {
		if (argv != NULL) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling render state swaps", _scriptLogPrefix);
		else RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@enabling render state swaps after prepareForRendering execution", _scriptLogPrefix);
	}
#endif
	
	// swap
	_renderStateSwapsEnabled = YES;
	[self _swapRenderState];
}

// 24
- (void)_incrementVariable:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	RXStack* parent = [_descriptor valueForKey:@"parent"];
	NSString* name = [parent varNameAtIndex:argv[0]];
	if (!name) name = [NSString stringWithFormat:@"%@%hu", [parent key], argv[0]];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@incrementing variable %@ by %hu", _scriptLogPrefix, name, argv[1]);
#endif
	
	uint16_t v = [[g_world gameState] unsignedShortForKey:name];
	[[g_world gameState] setUnsignedShort:(v + argv[1]) forKey:name];
}

// 27
- (void)_goToStack:(const uint16_t)argc arguments:(const uint16_t*) argv {
	if (argc < 3) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
	
	NSString* stackKey = [(RXStack*)[_descriptor valueForKey:@"parent"] stackNameAtIndex:argv[0]];
	// FIXME: we need to be smarter about stack management. For now, we try to load the stack once. And it stays loaded. Forver
	// make sure the requested stack has been loaded
	RXStack* stack = [g_world activeStackWithKey:stackKey];
	if (!stack) [g_world loadStackWithKey:stackKey waitUntilDone:YES];
	stack = [g_world activeStackWithKey:stackKey];
	
	uint32_t card_rmap = (argv[1] << 16) | argv[2];
	uint16_t card_id = [stack cardIDFromRMAPCode:card_rmap];
	
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@going to stack %@ on card ID %hu", _scriptLogPrefix, stackKey, card_id);
#endif
	
	[_scriptHandler setActiveCardWithStack:stackKey ID:card_id waitUntilDone:YES];
}

// 32
- (void)_opcode_startMovieAndWaitUntilDone:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu and waiting until done", _scriptLogPrefix, argv[0]);
#endif
	
	// get the movie object
	uintptr_t k = argv[0];
	RXMovie* glMovie = reinterpret_cast<RXMovie*>(NSMapGet(_codeToMovieMap, (const void*)k));
	assert(glMovie);
	
	// start the movie and register for rate change notifications
	[self performSelectorOnMainThread:@selector(_playBlockingMovie:) withObject:glMovie waitUntilDone:YES];
	
	// wait until the movie is done playing
	semaphore_wait(_moviePlaybackSemaphore);
}

// 33
- (void)_opcode_startMovie:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting movie with code %hu", _scriptLogPrefix, argv[0]);
#endif
	
	// get the movie object
	uintptr_t k = argv[0];
	RXMovie* glMovie = reinterpret_cast<RXMovie*>(NSMapGet(_codeToMovieMap, (const void*)k));
	assert(glMovie);
	
	// start the movie
	[self performSelectorOnMainThread:@selector(_playMovie:) withObject:glMovie waitUntilDone:YES];
}

// 39
- (void)_opcode_activatePLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating plst record at index %hu", _scriptLogPrefix, argv[0]);
#endif
	
	// FIXME: check for duplicates
	[_backRenderStatePtr->pictures addObject:[NSNumber numberWithUnsignedShort:argv[0] - 1]];
	
	// opcode 39 triggers a render state swap
	[self _swapRenderState];
	
	// indicate that an PLST record has been activated (to manage the automatic activation of PLST record 1 if none has been)
	_didActivatePLST = YES;
}

// 40
- (void)_opcode_activateSLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating slst record at index %hu", _scriptLogPrefix, argv[0]);
#endif
	
	// the script handler is responsible for this
	[_scriptHandler activateSoundGroup:[_soundGroups objectAtIndex:argv[0] - 1]];
	
	// indicate that an SLST record has been activated (to manage the automatic activation of SLST record 1 if none has been)
	_didActivateSLST = YES;
}

// 41
- (void)_opcode_prepareMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelMessage, @"%@WARNING: executing unknown opcode 41, implicit activation of mlst record at index %hu", _scriptLogPrefix, argv[0]);
#endif
	
	uint16_t opcode_buffer[] = {argv[0], 0};
	[self _opcode_activateMLST:2 arguments:opcode_buffer];
}

// 43
- (void)_opcode_activateBLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating blst record at index %hu", _scriptLogPrefix, argv[0]);
#endif
	
	struct _RXBLSTRecord* record = (struct _RXBLSTRecord *)_hotspotControlRecords + (argv[0] - 1);
	uint32_t key = record->hotspot_id;
	
	RXHotspot* hotspot = reinterpret_cast<RXHotspot*>(NSMapGet(_hotspotsIDMap, (void *)key));
	assert(hotspot);
	
	OSSpinLockLock(&_activeHotspotsLock);
	if (record->enabled == 1 && !hotspot->enabled) [_activeHotspots addObject:hotspot];
	else if (record->enabled == 0 && hotspot->enabled) [_activeHotspots removeObject:hotspot];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	hotspot->enabled = record->enabled;
	
	OSSpinLockLock(&_activeHotspotsLock);
	[_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	[_insideHotspotEventTimer invalidate];
	_insideHotspotEventTimer = nil;
	
	[_scriptHandler resetHotspotState];
}

// 44
- (void)_opcode_activateFLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 1) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating flst record at index %hu", _scriptLogPrefix, argv[0]);
#endif
	
	_backRenderStatePtr->water_fx.current_frame = 0;
	_backRenderStatePtr->water_fx.sfxe = _sfxes + (argv[0] - 1);
}

// 46
- (void)_opcode_activateMLST:(const uint16_t)argc arguments:(const uint16_t*)argv {
	if (argc < 2) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
#if defined(DEBUG)
	if (!_disableScriptLogging) RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@activating mlst record at index %hu with u0=%hu", _scriptLogPrefix, argv[0], argv[1]);
#endif
	
	// update the code to movie map
	uintptr_t k = _mlstCodes[argv[0] - 1];
	RXMovie* glMovie = [_movies objectAtIndex:argv[0] - 1];
	NSMapInsert(_codeToMovieMap, (const void*)k, glMovie);
}

#pragma mark -

- (void)prepareForRendering {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@preparing for rendering {", _scriptLogPrefix);
	[_scriptLogPrefix appendString:@"    "];
#endif

	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// prepare for rendering "blocks" script execution, aka hides the cursor
	[_scriptHandler setExecutingBlockingAction:YES];

	// disable automatic updates by faking an execution of opcode 20
	_rivenOpcodeImplementations[20](self, _rivenOpcodeSelectors[20], 0, NULL);
	 
	// stop all playing movies (this will probably only ever include looping movies or non-blocking movies)
	[self performSelectorOnMainThread:@selector(_stopAllMovies) withObject:nil waitUntilDone:YES];
	
	// reset card state
	[_backRenderStatePtr->pictures removeAllObjects];
	[_backRenderStatePtr->movies removeAllObjects];
	
	OSSpinLockLock(&_activeHotspotsLock);
	[_activeHotspots removeAllObjects];
	[_activeHotspots addObjectsFromArray:_hotspots];
	[_activeHotspots makeObjectsPerformSelector:@selector(makeEnabled)];
	[_activeHotspots sortUsingSelector:@selector(compareByIndex:)];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	// reset auto-activation states
	_didActivatePLST = NO;
	_didActivateSLST = NO;
	
	// reset the transition queue flag
	_queuedAPushTransition = NO;
	
	// execute loading programs (index 6)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[6]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for(; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// activate the first picture if none has been enabled already
	if (_pictureCount > 0 && !_didActivatePLST) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first plst record", _scriptLogPrefix);
#endif
		[_backRenderStatePtr->pictures addObject:[NSNumber numberWithUnsignedShort:0]];
		[self _swapRenderState];
	}
	_didActivatePLST = YES;
	
	// swap render buffers (by faking an execution of command 21 -- _enableAutomaticSwaps)
	 _rivenOpcodeImplementations[21](self, _rivenOpcodeSelectors[21], 0, NULL);
	 
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif
	
	// mark script execution as being unblocked
	[_scriptHandler setExecutingBlockingAction:NO];
	
	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

- (void)startRendering {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@starting rendering {", _scriptLogPrefix);
	[_scriptLogPrefix appendString:@"    "];
#endif

	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// execute rendering programs (index 9)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[9]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// activate the first sound group if none has been enabled already
	if ([_soundGroups count] > 0 && !_didActivateSLST) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@automatically activating first slst record", _scriptLogPrefix);
#endif
		[_scriptHandler activateSoundGroup:[_soundGroups objectAtIndex:0]];
	}
	_didActivateSLST = YES;
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

- (void)stopRendering {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@stopping rendering {", _scriptLogPrefix);
	[_scriptLogPrefix appendString:@"    "];
#endif

	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// execute leaving programs (index 7)
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[7]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// stop all playing movies (this will probably only ever include looping movies or non-blocking movies)
	[self performSelectorOnMainThread:@selector(_stopAllMovies) withObject:nil waitUntilDone:YES];
	
	// invalidate the "inside hotspot" timer
	[_insideHotspotEventTimer invalidate];
	_insideHotspotEventTimer = nil;
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

#pragma mark -

- (NSArray*)activeHotspots {
	// WARNING: WILL BE CALLED BY THE MAIN THREAD
	
	OSSpinLockLock(&_activeHotspotsLock);
	NSArray* hotspots = [[_activeHotspots copy] autorelease];
	OSSpinLockUnlock(&_activeHotspotsLock);
	
	return hotspots;
}

- (void)_mouseInsideHotspot:(NSTimer*)timer {
	RXHotspot* hotspot = [timer userInfo];

#if defined(DEBUG)
//	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouseInside %@ {", _scriptLogPrefix, hotspot);
//	[_scriptLogPrefix appendString:@"    "];
	_disableScriptLogging = YES;
#endif
	
	// we don't disable UI event processing for mouse inside programs; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[self retain];
	}
	
	// execute mouse moved programs (index 4)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[4]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	_disableScriptLogging = NO;
//	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
//	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// release the card to match the retain above
	if (_programExecutionDepth == 0) {
		[self release];
	}
}

- (void)mouseEnteredHotspot:(RXHotspot*)hotspot {
	// it's possible to receive nil for hotspot, which means we're not over any hotspot; in that case, set the default cursor
	if (!hotspot) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse entered no hotspot", _scriptLogPrefix);
#endif
		[g_worldView performSelectorOnMainThread:@selector(setCursor:) withObject:[g_world defaultCursor] waitUntilDone:NO];
		return;
	}
	
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouse entered %@", _scriptLogPrefix, hotspot);
#endif
	
	// set the cursor associated with this hotspot
	[g_worldView performSelectorOnMainThread:@selector(setCursor:) withObject:[g_world cursorForID:[hotspot cursorID]] waitUntilDone:NO];
	
	// schedule periodic execution of the "inside hotspot" programs
	[_insideHotspotEventTimer invalidate];
	_insideHotspotEventTimer = [NSTimer scheduledTimerWithTimeInterval:kInsideHotspotPeriodicEventPeriod target:self selector:@selector(_mouseInsideHotspot:) userInfo:hotspot repeats:YES];
	
	// immediatly run the "inside hotspot" program
	[self _mouseInsideHotspot:_insideHotspotEventTimer];
}

- (void)mouseExitedHotspot:(RXHotspot*)hotspot {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouseExited %@ {", _scriptLogPrefix, hotspot);
	[_scriptLogPrefix appendString:@"    "];
#endif
	
	// stop periodic "inside hotspot" events
	[_insideHotspotEventTimer invalidate];
	_insideHotspotEventTimer = nil;
	
	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// execute mouse leave programs (index 5)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[5]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

- (void)mouseDownInHotspot:(RXHotspot*)hotspot {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouseDown in %@ {", _scriptLogPrefix, hotspot);
	[_scriptLogPrefix appendString:@"    "];
#endif

	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// execute mouse down programs (index 0)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[0]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

- (void)mouseUpInHotspot:(RXHotspot*)hotspot {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@mouseUp in %@ {", _scriptLogPrefix, hotspot);
	[_scriptLogPrefix appendString:@"    "];
#endif

	// disable UI event processing while a program executes; retain the card while a program executes
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:NO];
		[self retain];
	}
	
	// execute mouse up programs (index 2)
	NSArray* programs = [[hotspot script] objectForKey:k_eventSelectors[2]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif

	// enable UI event processing when we're done executing the top-level program; release the card as well
	if (_programExecutionDepth == 0) {
		[_scriptHandler setProcessUIEvents:YES];
		[self release];
	}
}

#pragma mark -

- (size_t)_executeRivenProgram:(const void *)program count:(uint16_t)opcodeCount {
	if (!_scriptHandler) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"NO RIVEN SCRIPT HANDLER" userInfo:nil];
	
	RXStack* parent = [_descriptor valueForKey:@"parent"];
	
	// bump the execution depth
	_programExecutionDepth++;
	
	size_t programOffset = 0;
	const uint16_t* shortedProgram = (uint16_t *)program;
	
	uint16_t pc = 0;
	for (; pc < opcodeCount; pc++) {
		if (*shortedProgram == 8) {
			// parameters for the conditional branch opcode
			uint16_t argc = *(shortedProgram + 1);
			uint16_t varID = *(shortedProgram + 2);
			uint16_t caseCount = *(shortedProgram + 3);
			
			// adjust the shorted program
			programOffset += 8;
			shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
			
			// argc should always be 2 for a conditional branch
			if (argc != 2) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID NUMBER OF ARGUMENTS" userInfo:nil];
			
			// get the variable from the game state
			NSString* name = [parent varNameAtIndex:varID];
			if (!name) name = [NSString stringWithFormat:@"%@%hu", [parent key], varID];
			uint16_t varValue = [[g_world gameState] unsignedShortForKey:name];
			
#if defined(DEBUG)
			RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@switch statement on variable %@=%hu", _scriptLogPrefix, name, varValue);
#endif
			
			// evaluate each branch
			uint16_t caseIndex = 0;
			uint16_t caseValue;
			size_t defaultCaseOffset = 0;
			for (; caseIndex < caseCount; caseIndex++) {
				caseValue = *shortedProgram;
				
				// record the address of the default case in case we need to execute it if we don't find a matching case
				if (caseValue == 0xffff) defaultCaseOffset = programOffset;
				
				// matching case
				if (caseValue == varValue) {
#if defined(DEBUG)
					RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@executing matching case {", _scriptLogPrefix);
					[_scriptLogPrefix appendString:@"    "];
#endif
					
					// execute the switch statement program
					programOffset += [self _executeRivenProgram:(shortedProgram + 2) count:*(shortedProgram + 1)];
					
#if defined(DEBUG)
					[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
					RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif
				} else programOffset += _computeRivenScriptLength((shortedProgram + 2), *(shortedProgram + 1), false); // skip over the case
				
				// adjust the shorted program
				programOffset += 4; // account for the case value and case instruction count
				shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
				
				// bail out if we executed a matching case
				if (caseValue == varValue) break;
			}
			
			// if we didn't match any case, execute the default case
			if (caseIndex == caseCount && defaultCaseOffset != 0) {
#if defined(DEBUG)
				RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@no case matched variable value, executing default case {", _scriptLogPrefix);
				[_scriptLogPrefix appendString:@"    "];
#endif
				
				// execute the switch statement program
				[self _executeRivenProgram:((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 2 count:*(((uint16_t*)BUFFER_OFFSET(program, defaultCaseOffset)) + 1)];
				
#if defined(DEBUG)
				[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
				RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif
			} else {
				// skip over the instructions of the remaining cases
				caseIndex++;
				for (; caseIndex < caseCount; caseIndex++) {
					programOffset += _computeRivenScriptLength((shortedProgram + 2), *(shortedProgram + 1), false) + 4;
					shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
				}
			}
		} else {
			// execute the opcode
			_rivenOpcodeImplementations[*shortedProgram](self, _rivenOpcodeSelectors[*shortedProgram], *(shortedProgram + 1), shortedProgram + 2);
			_lastExecutedProgramOpcode = *shortedProgram;
			
			// adjust the shorted program
			programOffset += 4 + (*(shortedProgram + 1) * sizeof(uint16_t));
			shortedProgram = (uint16_t*)BUFFER_OFFSET(program, programOffset);
		}
	}
	
	// bump down the execution depth
#if defined(DEBUG)
	assert(_programExecutionDepth > 0);
#endif
	_programExecutionDepth--;
	
	return programOffset;
}

- (void)_runScreenUpdatePrograms {
#if defined(DEBUG)
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@screen update {", _scriptLogPrefix);
	[_scriptLogPrefix appendString:@"    "];
#endif
	
	// this is a bit of a hack, but disable automatic render state swaps while running screen update programs
	_renderStateSwapsEnabled = NO;
	
	NSArray* programs = [_cardEvents objectForKey:k_eventSelectors[10]];
	uint32_t programCount = [programs count];
	uint32_t programIndex = 0;
	for (; programIndex < programCount; programIndex++) {
		NSDictionary* program = [programs objectAtIndex:programIndex];
		[self _executeRivenProgram:[[program objectForKey:@"program"] bytes] count:[[program objectForKey:@"opcodeCount"] unsignedShortValue]];
	}
	
	// re-enable render state swaps (they must be enabled if we just ran screen update programs)
	_renderStateSwapsEnabled = YES;
	
#if defined(DEBUG)
	[_scriptLogPrefix deleteCharactersInRange:NSMakeRange([_scriptLogPrefix length] - 4, 4)];
	RXOLog2(kRXLoggingScript, kRXLoggingLevelDebug, @"%@}", _scriptLogPrefix);
#endif
}

- (void)_swapRenderState {
	// WARNING: THIS IS NOT THREAD SAFE, BUT WILL NOT INTERFERE WITH THE RENDER THREAD NEGATIVELY
	
	// leave a note for the renderer and also indicate the back render state has been modified
	_backRenderStatePtr->refresh_static = YES;
	
	// if swaps are disabled, return immediatly
	if (!_renderStateSwapsEnabled) {
#if defined(DEBUG)
		RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render state swap request ignored because swapping is disabled");
#endif
		return;
	}	
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"swapping render state");
#endif

	// run screen update programs
	[self _runScreenUpdatePrograms];
	
	// the script handler will set our front render state to our back render state at the appropriate moment; when this returns, the swap has occured (front == back)
	[_scriptHandler swapRenderState:self];
}

- (void)finalizeRenderStateSwap {
	// release memory of the old card render state
	[_backRenderStatePtr->pictures release];
	[_backRenderStatePtr->movies release];
	
	// copy the non-volatile front card render state members to the back card render state
	_backRenderStatePtr->pictures = [NSMutableArray new];
	_backRenderStatePtr->movies = [_frontRenderStatePtr->movies mutableCopy];
}

- (void)_swapMovieRenderState {
	// movies are not included in the original engine's picture swapping mechanism, so this method is a little bit different
#if defined(DEBUG)
	RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"swapping movie render state");
#endif
	
	// the script handler will set our front render state to our back render state at the appropriate moment; when this returns, the swap has occured (front == back)
	[_scriptHandler swapMovieRenderState:self];
}

- (void)finalizeMovieRenderStateSwap {
	// release memory of the old card render state
	[_backRenderStatePtr->movies release];
	
	// copy the non-volatile front card render state members to the back card render state
	_backRenderStatePtr->movies = [_frontRenderStatePtr->movies mutableCopy];
}

#pragma mark -

- (void)_dealloc_movies {
	// WARNING: this method can only run on the main thread
	if (!pthread_main_np()) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"_dealloc_movies: MAIN THREAD ONLY" userInfo:nil];
	
	// stop all movies (because we really want them to be stopped by the time the card is tearing down...)
	[self _stopAllMovies];
	
	if (_codeToMovieMap) NSFreeMapTable(_codeToMovieMap);
	[_movies release];
	
	[_frontRenderStatePtr->movies release];
	[_backRenderStatePtr->movies release];
}

- (void)dealloc {
#if defined(DEBUG)
	RXOLog(@"deallocating");
#endif

	// stop receiving notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// picture rendering
	[_frontRenderStatePtr->pictures release];
	[_backRenderStatePtr->pictures release];

	// lock the GL context and clean up textures and GL buffers
	CGLContextObj cgl_ctx = [RXGetWorldView() loadContext];
	CGLLockContext(cgl_ctx);
	{
		if (_pictureVertexArrayBuffer != 0) glDeleteBuffers(1, &_pictureVertexArrayBuffer);
		if (_pictureTextures) glDeleteTextures(_pictureCount, _pictureTextures);
#if defined(GPU_WATER)
		if (_sfxes) for (uint16_t i = 0; i < _sfxeCount; i++) glDeleteTextures(_sfxes[i].nframes, _sfxes[i].frames);
#endif
		if (_dynamicPictureMap) {
			NSMapEnumerator dynamicPictureEnum = NSEnumerateMapTable(_dynamicPictureMap);
			uintptr_t key;
			struct _RXCardDynamicPicture* value;
			while (NSNextMapEnumeratorPair(&dynamicPictureEnum, (void**)&key, (void**)&value)) {
				glDeleteTextures(1, &(value->texture));
				glDeleteBuffers(1, &(value->buffer));
			}
		}

		// objects have gone away, so we flush
		glFlush();
	}
	CGLUnlockContext(cgl_ctx);
	
	// movies
	[self performSelectorOnMainThread:@selector(_dealloc_movies) withObject:nil waitUntilDone:YES];
	if (_mlstCodes) delete[] _mlstCodes;
	semaphore_destroy(mach_task_self(), _moviePlaybackSemaphore);
	semaphore_destroy(mach_task_self(), _movieLoadSemaphore);
	
	// pictures
	if (_pictureTextures) delete[] _pictureTextures;
	if (_pictureTextureStorage) free(_pictureTextureStorage);
	if (_dynamicPictureMap) NSFreeMapTable(_dynamicPictureMap);
	
	// sounds
	[_soundGroups release];
	[_synthesizedSoundGroup release];
	
	// hotspots
	[_insideHotspotEventTimer invalidate];
	[_activeHotspots release];
	if (_hotspotsIDMap) NSFreeMapTable(_hotspotsIDMap);
	[_hotspots release];
	
	// sfxe
	if (_sfxes) {
#if defined(LLVM_WATER)
		for (uint16_t i = 0; i < _sfxeCount; i++) [_sfxes[i].frames release];
#elif defined(GPU_WATER)
		for (uint16_t i = 0; i < _sfxeCount; i++) {
			delete[] _sfxes[i].frames;
			free(_sfxes[i].frame_storage);
		}
#endif
		delete[] _sfxes;
	}
	
	// misc resources
	if (_blstData) free(_blstData);
	[_cardEvents release];
	[_descriptor release];
	
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat: @"%@ {%@}", [super description], [_descriptor description]];
}

@end
