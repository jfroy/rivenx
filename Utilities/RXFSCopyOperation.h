//
//  RXFSCopyOperation.h
//  rivenx
//
//  Copyright 2005-2014 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

typedef NS_ENUM (NSUInteger, RXFSOperationState) {
  RXFSOperationStateReady = 1,
  RXFSOperationStatePreflight,
  RXFSOperationStateData,
  RXFSOperationStateExtendedAttribute,
  RXFSOperationStateDone
};

@interface RXFSCopyOperation : NSObject

// these properties can only be read race-free while executing the status callback and pertain to the operation
@property (readonly, nonatomic) RXFSOperationState state;
@property (readonly, nonatomic) off_t totalBytesCopied;
@property (readonly, nonatomic) NSError* error;
@property (readonly, nonatomic) BOOL cancelled;

// these properties can only be read race-free while executing the status callback and pertain to the item currently being copied
@property (readonly, nonatomic) NSString* item;
@property (readonly, nonatomic) off_t bytesCopied;
@property (readonly, nonatomic) NSString* extendedAttribute;

- (instancetype)initWithSource:(NSString*)source destination:(NSString*)destination;

- (void)setTargetQueue:(dispatch_queue_t)queue;

- (void)setStatusQueue:(dispatch_queue_t)queue callback:(dispatch_block_t)callback;

- (void)start;
- (void)cancel;

@end
