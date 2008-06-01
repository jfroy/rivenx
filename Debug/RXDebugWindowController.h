//
//	RXDebugWindowController.h
//	rivenx
//
//	Created by Jean-Francois Roy on 27/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//


@class CLIView;

@interface RXDebugWindowController : NSWindowController {
	IBOutlet CLIView* cli;
	
	uint16_t _trip;
}

@end
