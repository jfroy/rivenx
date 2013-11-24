//
//  RXLogCenter.h
//  rivenx
//
//  Created by Jean-Francois Roy on 26/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"
#import <pthread.h>

@interface RXLogCenter : NSObject {
@private
  BOOL _toreDown;
  BOOL _didInit;

  NSString* _logsBase;

  int _genericLogFD;

  pthread_mutex_t _facilityFDMapMutex;
  NSMutableDictionary* _facilityFDMap;

  uint32_t _levelFilter;
}

+ (RXLogCenter*)sharedLogCenter;

- (void)tearDown;

- (void)log:(NSString*)message facility:(NSString*)facility level:(int)level;

@end
