//
//  RXGOGSetupInstaller.h
//  rivenx
//
//  Created by Jean-François Roy on 30/12/2011.
//  Copyright (c) 2011 MacStorm. All rights reserved.
//

#import "RXInstaller.h"


@interface RXGOGSetupInstaller : RXInstaller
{
@private
    NSURL* _gogSetupURL;
    uint32_t _filesUnpacked;
    uint32_t _filesToUnpack;
}

- (id)initWithGOGSetupURL:(NSURL*)url;

@end
