//
//  RXEditionProxy.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RXEdition.h"


@interface RXEditionProxy : NSObject <NSCopying> {
	RXEdition* edition;
}

- (id)initWithEdition:(RXEdition*)e;

@end
