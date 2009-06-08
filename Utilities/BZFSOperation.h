//
//  BZFSOperation.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

enum {
    BZFSOperationCopyOperation = 1,
    BZFSOperationMoveOperation
};
typedef uint32_t BZFSOperationType;


@interface BZFSOperation : NSObject {   
@private
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

- (BOOL)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode error:(NSError**)error;
- (BOOL)start:(NSError**)error;
- (BOOL)cancel:(NSError**)error;

- (NSString*)item;
- (FSFileOperationStage)stage;
- (NSDictionary*)status;
- (NSError*)error;

@end
