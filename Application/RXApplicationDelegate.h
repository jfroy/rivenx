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
	
	IBOutlet NSWindow* _aboutBox;
	IBOutlet NSTextField* _versionField;
	IBOutlet NSTextField* _copyrightField;
	
	BOOL _saveFlag;
	BOOL _canSave;
}

- (IBAction)orderFrontAboutWindow:(id)sender;
- (IBAction)showAcknowledgments:(id)sender;

- (IBAction)openDocument:(id)sender;
- (IBAction)saveGame:(id)sender;
- (IBAction)saveGameAs:(id)sender;

- (BOOL)isSavingEnabled;
- (void)setSavingEnabled:(BOOL)flag;

@end
