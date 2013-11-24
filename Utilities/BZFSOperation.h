//
//  BZFSOperation.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <CoreServices/CoreServices.h>

@class NSRunLoop;

enum {
  BZFSOperationCopyOperation = 1,
  BZFSOperationMoveOperation
};
typedef uint32_t BZFSOperationType;

@interface BZFSOperation : NSObject {
  FSFileOperationRef _op;
  OptionBits _options;

  BZFSOperationType _type;

  NSString* _source;
  NSString* _destination;

  BOOL _cancelled;

  NSString* _item;
  FSFileOperationStage _stage;
  NSDictionary* _status;
  NSError* _error;
}

- (id)initCopyOperationWithSource:(NSString*)source destination:(NSString*)destination;

- (BOOL)allowOverwriting;
- (void)setAllowOverwriting:(BOOL)allow;

- (BOOL)scheduleInRunLoop:(NSRunLoop*)aRunLoop forMode:(NSString*)mode error:(NSError**)error;
- (BOOL)start:(NSError**)error;
- (BOOL)cancel:(NSError**)error;

- (NSString*)item;
- (FSFileOperationStage)stage;
- (NSDictionary*)status;
- (NSError*)error;
- (BOOL)cancelled;

@end
