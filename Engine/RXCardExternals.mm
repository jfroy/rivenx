//
//  RXCardExternals.m
//  rivenx
//
//  Created by Jean-Francois Roy on 21/09/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXCard.h"

#define DEFINE_COMMAND(NAME) - (void)_external_ ## NAME:(const uint16_t)argc arguments:(const uint16_t*)argv


@implementation RXCard (RXCardExternals)

#pragma mark setup

DEFINE_COMMAND(xasetupcomplete) {

}

#pragma mark journals

DEFINE_COMMAND(xaatrusopenbook) {

}

DEFINE_COMMAND(xaatrusbookback) {

}

DEFINE_COMMAND(xaatrusbookprevpage) {

}

DEFINE_COMMAND(xaatrusbooknextpage) {

}

@end
