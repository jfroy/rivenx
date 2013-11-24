//
//  RXSingleton.h
//  rivenx
//
//  Created by Jean-Francois Roy on 27/08/2005.
//  Verbatim copy of FTSWAbstractSingleton, but using RX's namespace
//  Copyright 2005 MacStorm. All rights reserved.
//

@interface RXSingleton : NSObject {
}

+ (id)singleton;
+ (id)singletonWithZone:(NSZone*)zone;

- (id)initSingleton;
- (void)secondStageInitSingleton;

@end
