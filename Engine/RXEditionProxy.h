//
//  RXEditionProxy.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RXEdition.h"


@interface RXEditionProxy : NSObject <NSCopying> {
    RXEdition* edition;
}

- (id)initWithEdition:(RXEdition*)e;

@end
