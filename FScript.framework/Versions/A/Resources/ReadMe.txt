JGAdditions for the FScript-Distribution
====================================
Added 
  servicesProvider=[[FSServicesProvider alloc] initWithFScriptInterpreterViewProvider:self];
  [servicesProvider registerExports];
to method in FScriptAppController (Application fs)
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;
Added - (id)interpreterView; to FScriptAppController

FSServicesProvider is the main entrance point for services provided to other applications. 3 different Service-handlers are used by example:

DistributedObject connections are enabled by
- (void)registerServerConnection:(NSString *)connectionName;

Service-Menu services are enabled by
- (void)registerServicesProvider;
- (void)putCommand:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
- (void)execute:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
and by NSServices entry in Info.plist (Expert-Mode in Application Settings Tab in ProjectBuilder)

Apple-Script events are enabled by FSEvalCommand.m and the Entries in fs.scriptSuite,fs.scriptTerminology and the NSAppleScriptEnabled setting in Info.plist

KV-Browser Extension for FScript:
====================================
FSKVCoding: Extensions to the standard Key-Value-Coding protocol (e.g. used for Arrays, Dictionaries...)
FSKVBrowserBase: Delegate Class for Browser in FSKVBrowser.nib
FSKVBrowser: Controller Class (owner) for FSKVBrowser.nib
FSKVBrowserExample: Additions for the Flight-Tutorial
FSKVBrowser.nib: User Interface.

The KV-Browser is invoked by typing: sys browserKV 
or by typing: sys browserKV:anObject
The Method-Browser is invoked by typing: sys browse
or by typing: sys browse:anObject
Within the Method-Browser there is a Button for getting a KV-Browser and vice-versa.
 
Buttons, Switches and sliders: 
---------------------
Buttons with Bold fonts are more dangerous than the other ones.
Buttons Workspace, SetName, Inspect are analog to BigBrowserView. Only: SetName will take the name from the TextField below.
Button SetValue will take a fscript-Expression from the TextField below and set that Object at the selected Position. Because this may be harmful for a program, which works with the object graph, this button is considered dangerous.
Button Methods will give a BigBrowserView for the selected Object. (Dangerous for the same reason.)
NewBrowser will give a new Key-Value Browser for the selected Object.
Button Update Now tries to reconstruct the selected path from the root Object or Workspace for the actual state of the root object. Below is an interface for triggering automatic updates. 0.0 means: no automatic update.
If Switch Description is on, we send -description to the selected Object, so this might be dangerous, if it is implemented recursive. The result is either (in Drawer-Switch) displayed in another View of the Spitview (keeps the window the same size), or in a Drawer (keeps the other views the same size).
The left slider is to resize the width of a Browser-Column. So this can effect the number of visable columns.
If the Browse Attributes Switch is on, Attributes will also be displayed within the Relationship-Browser, so one can choose to set the size of the Attribute-Table minimal to have a larger Relationship-Browser.
The Attribute-Table sends -description to attribute-Values.


Extensions that have few to do with FScript, but with my Projects:
========================================================================

FSTask is a wrapper for input-output based command line programs. Makes those programs easily available in FScript-Browser and through apple events for Programs, that run in the classic box. 

Macintosh Common Lisp (MCL) can call FScript through (send-eval "command" "fs") after loading apple-event-toolkit.lisp. (MCL can be obtained as a demo version from digitool.com) There is a graphical user interface to lisp from ircam.fr called OpenMusic. (Now with FScript it can do Cocoa!)

FSPropertyLisp2Lisp is a Class which transforms possibly cyclic property lists into function calls, that build the equivalent lisp structure. Lisp usage: (eval (read-from-string (send-eval "FSPropertyLisp2Lisp stringFromPropertyList:aPlist" "fs")))
This class can be augmented to transform any Object with attributeKeys,toOneRelationshipKey, toManyRelationshipKey. Needs some checking with [obj valueForKey:toManyRelationshipKey], because Arrays can be constructed for each call. But entries in the array should be again checkable for cyclic occourances. I will do this. (jg)
