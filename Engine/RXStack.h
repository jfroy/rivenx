//
//	RXStack.h
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <MHKKit/MHKAudioDecompression.h>


@interface RXStack : NSObject {
@private
	NSString* _key;
	
	NSMutableArray* _dataArchives;
	NSMutableArray* _soundArchives;
	
	// global stack data
	NSArray* _cardNames;
	NSArray* _hotspotNames;
	NSArray* _externalNames;
	NSArray* _varNames;
	NSArray* _stackNames;
	NSData* _rmapData;
	
	// card descriptors
	uint32_t _cardCount;
	
	// card storage
	uint16_t _entryCardID;
}

- (id)initWithStackDescriptor:(NSDictionary*)descriptor key:(NSString*)key error:(NSError**)error;

- (NSString*)key;
- (uint16_t)entryCardID;

- (NSString*)cardNameAtIndex:(uint32_t)index;
- (NSString*)hotspotNameAtIndex:(uint32_t)index;
- (NSString*)externalNameAtIndex:(uint32_t)index;
- (NSString*)varNameAtIndex:(uint32_t)index;
- (NSString*)stackNameAtIndex:(uint32_t)index;

- (uint16_t)cardIDFromRMAPCode:(uint32_t)code;

- (id <MHKAudioDecompression>)audioDecompressorWithID:(uint16_t)soundID;
- (id <MHKAudioDecompression>)audioDecompressorWithDataID:(uint16_t)soundID;

@end
