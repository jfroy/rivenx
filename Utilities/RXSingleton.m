//
//  RXSingleton.m
//  rivenx
//
//  Created by Jean-Francois Roy on 27/08/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "RXSingleton.h"

@implementation RXSingleton

static NSMutableDictionary* RX_singletons = nil;

+ (void)initialize
{
  @synchronized([RXSingleton class])
  {
    if (RX_singletons == nil)
      RX_singletons = [[NSMutableDictionary alloc] init];
  }
}

// Should be considered private to the abstract singleton class, wrap with a "sharedXxx" class method
+ (id)singleton { return [self singletonWithZone:[self zone]]; }

// Should be considered private to the abstract singleton class
+ (id)singletonWithZone:(NSZone*)zone
{
  id singleton = nil;
  Class class = [self class];

  if (class == [RXSingleton class]) {
    [NSException raise:NSInternalInconsistencyException format:@"Not valid to request the abstract singleton."];
  }

  @synchronized(class)
  {
    singleton = [RX_singletons objectForKey:class];
    if (singleton == nil) {
      singleton = NSAllocateObject(class, 0U, zone);
      if ((singleton = [singleton initSingleton]) != nil) {
        [RX_singletons setObject:singleton forKey:class];
        [singleton secondStageInitSingleton];
      }
    }
  }

  return singleton;
}

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly { return NO; }

// Designated initializer for instances. If subclasses override they must call this implementation.
- (id)initSingleton { return [super init]; }

- (void)secondStageInitSingleton { return; }

// Disallow the normal default initializer for instances.
- (id)init
{
  [self doesNotRecognizeSelector:_cmd]; // optional
  [self release];
  return nil;
}

// ------------------------------------------------------------------------------
// The following overrides attempt to enforce singleton behavior.

+ (id) new { return [self singleton]; }

+ (id)allocWithZone:(NSZone*)zone { return [self singletonWithZone:zone]; }

+ (id)alloc { return [self singleton]; }

- (id)copy
{
  [self doesNotRecognizeSelector:_cmd]; // optional
  return self;
}

- (id)copyWithZone:(NSZone*)zone
{
  [self doesNotRecognizeSelector:_cmd]; // optional
  return self;
}

- (id)mutableCopy
{
  [self doesNotRecognizeSelector:_cmd]; // optional
  return self;
}

- (id)mutableCopyWithZone:(NSZone*)zone
{
  [self doesNotRecognizeSelector:_cmd]; // optional
  return self;
}

- (unsigned)retainCount { return UINT_MAX; }

- (oneway void)release {}

- (id)retain { return self; }

- (id)autorelease { return self; }

- (void)dealloc
{
  //[self doesNotRecognizeSelector:_cmd];  // optional
  [super dealloc];
}
// ------------------------------------------------------------------------------

@end
