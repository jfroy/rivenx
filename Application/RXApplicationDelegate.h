//
//	RXApplicationDelegate.h
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface RXApplicationDelegate : NSObject {
#if defined(DEBUG)
	NSWindowController* _debugConsoleWC;
	NSWindowController* _engineVariableEditorWC;
	NSWindowController* _gameVariableEditorWC;
#endif
	
	IBOutlet NSWindow* aboutBox_;
	IBOutlet NSTextField* versionField_;
	IBOutlet NSTextField* copyrightField_;
	
	
}

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

@end
