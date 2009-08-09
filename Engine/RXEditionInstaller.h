//
//  RXEditionInstaller.h
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RXEdition.h"


//! RXEditionInstaller objects are one-shot edition installer objects. They support driving a modal install UI through a provided modal session.
@interface RXEditionInstaller : NSObject {
    RXEdition* edition;
    
    double progress;
    NSString* item;
    NSString* stage;
    CFTimeInterval remainingTime;
    
@private
    uint32_t _directiveCount;
    uint32_t _currentDirective;
    double _directiveProgress;
    BOOL _didRun;
    
    // for StackCopy
    uint32_t _discsToProcess;
    uint32_t _discsProcessed;
    uint64_t _totalBytesToCopy;
    uint64_t _totalBytesCopied;
}

- (id)initWithEdition:(RXEdition*)ed;

- (BOOL)fullUserInstallInModalSession:(NSModalSession)session error:(NSError**)error;

@end
