//
//  RXDebugWindowController.m
//  rivenx
//
//  Created by Jean-Francois Roy on 27/01/2006.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <Python/Python.h>

#import "Debug/RXDebugWindowController.h"

#import "Engine/RXWorldProtocol.h"
#import "Engine/RXScriptCompiler.h"
#import "Engine/RXScriptCommandAliases.h"
#import "Engine/RXScriptDecoding.h"

#import "States/RXCardState.h"

#import "Utilities/GTMSystemVersion.h"


PyAPI_FUNC(void) Py_InitializeEx(int) __attribute__((weak_import));

@interface RXDebugWindowController (RXDebugConsolePythonIO)
- (IBAction)runPythonCmd:(id)sender;
- (void)pythonOut:(NSString*)string;

- (void)print:(NSString*)msg;
@end

// pointer to python controller
static RXDebugWindowController* rx_debug_window_controller;

PyObject* rivenx_CaptureStdout(PyObject* self, PyObject* pArgs) {
    char* log_string = NULL;
    if (!PyArg_ParseTuple(pArgs, "s", &log_string))
        return NULL;
    
    [rx_debug_window_controller pythonOut:[NSString stringWithCString:log_string encoding:NSASCIIStringEncoding]];
    
    Py_RETURN_NONE;
}

PyObject* rivenx_CaptureStderr(PyObject* self, PyObject* pArgs) {
    char* log_string = NULL;
    if (!PyArg_ParseTuple(pArgs, "s", &log_string))
        return NULL;

    [rx_debug_window_controller pythonOut:[NSString stringWithCString:log_string encoding:NSASCIIStringEncoding]];

    Py_RETURN_NONE;
}

// methods for the 'rivenx' module
static PyMethodDef rivenx_methods[] = {
    {"CaptureStdout", rivenx_CaptureStdout, METH_VARARGS, "Logs stdout"},
    {"CaptureStderr", rivenx_CaptureStderr, METH_VARARGS, "Logs stderr"},
    {NULL, NULL, 0, NULL}
};


@interface NSObject (CLIViewPrivate)

@end


@implementation RXDebugWindowController

+ (RXDebugWindowController*)globalDebugWindowController {
    return rx_debug_window_controller;
}

- (void)awakeFromNib {
    [consoleView setRichText: NO];
    _consoleFont = [NSFont fontWithName:@"Menlo" size:11];
    if (!_consoleFont)
        _consoleFont = [NSFont fontWithName:@"Monaco" size:11];
    [consoleView setFont:_consoleFont];
    [_consoleFont retain];
    
    // Python is weakly linked because Tiger only has 2.3 and we don't support that version
    if (!&Py_InitializeEx || [GTMSystemVersion isTiger]) {
        [self pythonOut:@"Debug shell not supported in Mac OS X 10.4."];
        return;
    }
    
    // set ourselves as the global debug window controller
    rx_debug_window_controller = self;
    
    // add the resources directory to the Python path
    setenv("PYTHONPATH", [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation], 1);
    
    // initialize Python (skipping signal initialization)
    Py_InitializeEx(0);
    
    // add a log module with the log functions
    Py_InitModule("rivenx", rivenx_methods);
    
    // initialize the debug console
    NSString* init_file = [[NSBundle mainBundle] pathForResource:@"debug_init" ofType:@"py"];
    FILE* fp = fopen([init_file fileSystemRepresentation], "r");
    PyRun_SimpleFileEx(fp, [[init_file lastPathComponent] cStringUsingEncoding:NSASCIIStringEncoding], 1);
    
    // get the main module
    PyObject* main_mod = PyImport_AddModule("__main__");
    assert(main_mod);
}

- (NSString*)windowFrameAutosaveName {
    return @"DebugConsoleFrame";
}

- (IBAction)runPythonCmd:(id)sender {
    if (!rx_debug_window_controller)
        return;
    
    NSFont* bold_console_font = [[NSFontManager sharedFontManager] convertFont:_consoleFont toHaveTrait:NSBoldFontMask];
    NSAttributedString* attr_str = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@">> %@\n", [sender stringValue]]
                                                                   attributes:[NSDictionary dictionaryWithObject:bold_console_font forKey:NSFontAttributeName]];
    [[consoleView textStorage] beginEditing];
    [[consoleView textStorage] appendAttributedString:attr_str];
    [[consoleView textStorage] endEditing];
    [attr_str release];

    PyObject* main_module = PyImport_AddModule("__main__");
    PyObject* global_dict = PyModule_GetDict(main_module);
    PyObject* exec_cmd_f = PyDict_GetItemString(global_dict, "exec_cmd");
    PyObject_CallFunction(exec_cmd_f, (char*)"s", [[sender stringValue] cStringUsingEncoding:NSASCIIStringEncoding]);
    [sender setStringValue:@""];
}

- (void)print:(NSString*)msg {
    [self pythonOut:[msg stringByAppendingString:@"\n"]];
}

- (void)pythonOut:(NSString*)str {
    NSAttributedString* attr_str = [[NSAttributedString alloc] initWithString:str
                                                                   attributes:[NSDictionary dictionaryWithObject:_consoleFont forKey:NSFontAttributeName]];
    [[consoleView textStorage] beginEditing];
    [[consoleView textStorage] appendAttributedString:attr_str];
    [[consoleView textStorage] endEditing];
    [attr_str release];
    
#if defined(DEBUG)
    fprintf(stderr, "%s", [str UTF8String]);
#endif
}

#pragma mark debug commands

- (NSMutableSet*)_findExternalCommands:(NSDictionary*)script card:(RXCard*)card {
    RXScriptOpcodeStream* opstream = [[RXScriptOpcodeStream alloc] initWithScript:script];
    NSMutableSet* command_names = [NSMutableSet set];
    rx_opcode_t* opcode;
    while ((opcode = [opstream nextOpcode])) {
        if (opcode->command != RX_COMMAND_CALL_EXTERNAL)
            continue;
        
        uint16_t external_id = opcode->arguments[0];
        NSString* external_name = [[[[card descriptor] parent] externalNameAtIndex:external_id] lowercaseString];
        if (!external_name)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"INVALID EXTERNAL COMMAND ID" userInfo:nil];
        [command_names addObject:external_name];
    }
    
    [opstream release];
    return command_names;
}

- (void)cmd_card:(NSArray*)arguments {
    if ([arguments count] < 2)
        @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

    RXCardState* renderingState = (RXCardState*)[g_world cardRenderer];

    NSString* stackKey = [arguments objectAtIndex:0];
    NSString* cardStringID = [arguments objectAtIndex:1];

    int cardID;
    BOOL foundID = [[NSScanner scannerWithString:cardStringID] scanInt:&cardID];
    if (!foundID)
        @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"card [stack] [ID]" userInfo:nil];

    RXOLog2(kRXLoggingBase, kRXLoggingLevelDebug, @"changing active card to %@ %d", stackKey, cardID);
    [renderingState setActiveCardWithStack:stackKey ID:cardID waitUntilDone:NO];
}

- (void)cmd_refresh:(NSArray*)arguments {
    RXSimpleCardDescriptor* current_card = [[g_world gameState] currentCard];
    RXCardState* renderingState = (RXCardState*)[g_world cardRenderer];
    [renderingState setActiveCardWithStack:current_card->stackKey ID:current_card->cardID waitUntilDone:NO];
}

- (void)_activateSLST:(NSNumber*)index {
    RXCardState* renderingState = (RXCardState*)[g_world cardRenderer];
    uint16_t args = (uint16_t)[index intValue];
    [[renderingState valueForKey:@"sengine"] performSelector:@selector(_opcode_activateSLST:arguments:) withObject:(id)1 withObject:(id)&args];
}

- (void)cmd_slst:(NSArray*)arguments {
    if ([arguments count] < 1)
        @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"slst [1-based index]" userInfo:nil];
    [self performSelector:@selector(_activateSLST:) withObject:[arguments objectAtIndex:0] inThread:[g_world scriptThread] waitUntilDone:YES];
}

- (void)cmd_get:(NSArray*)arguments {
    if ([arguments count] < 1)
        @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"get [variable]" userInfo:nil];
    NSString* path = [arguments objectAtIndex:0];
    
    if ([[g_world gameState] isKeySet:path])
        [self print:[NSString stringWithFormat:@"%d", [[g_world gameState] signed32ForKey:path]]];
    else {
        @try {
            [self print:[NSString stringWithFormat:@"%@", [[g_world valueForKeyPath:path] stringValue]]];
        } @catch (NSException* e) {
            [self print:@"undefined variable"];
        }
    }
}

- (void)cmd_set:(NSArray*)arguments {
    if ([arguments count] < 2)
        @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"set [variable] [value]" userInfo:nil];
    
    NSString* path = [arguments objectAtIndex:0];
    NSString* valueString = [arguments objectAtIndex:1];
    NSScanner* valueScanner = [NSScanner scannerWithString:valueString];
    id value;
    
    // scan away
    BOOL valueFound = NO;
    double doubleValue;
    int intValue;
    
    valueFound = [valueScanner scanDouble:&doubleValue];
    if (valueFound)
        value = [NSNumber numberWithDouble:doubleValue];
    else {
        valueFound = [valueScanner scanInt:&intValue];
        if (valueFound)
            value = [NSNumber numberWithInt:intValue];
        else {
            if ([valueString isEqualToString:@"yes"] || [valueString isEqualToString:@"YES"])
                valueFound = YES;
            
            if (valueFound)
                value = [NSNumber numberWithBool:YES];
            else {
                if ([valueString isEqualToString:@"no"] || [valueString isEqualToString:@"NO"])
                    valueFound = YES;
                
                if (valueFound)
                    value = [NSNumber numberWithBool:NO];
                else
                    value = valueString;
            }
        }
    }
    
    if ([[g_world gameState] isKeySet:path]) {
        if (![value isKindOfClass:[NSNumber class]])
            @throw [NSException exceptionWithName:@"RXCommandArgumentsException" reason:@"game variables can only be set to integer values" userInfo:nil];
        else {
            [[g_world gameState] setSigned32:[value intValue] forKey:path];
        }
    } else
        [g_world setValue:value forEngineVariable:path];
}

- (void)cmd_dump:(NSArray*)arguments {
    [[g_world cardRenderer] performSelector:@selector(exportCompositeFramebuffer)];
}

- (void)_nextJspitCard:(NSNotification*)notification {
    _trip++;
    if (_trip > 800) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"RXActiveCardDidChange" object:nil];
        return;
    }
    
    RXStack* jspit = [g_world activeStackWithKey:@"jspit"];
    RXCardDescriptor* d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
    while (!d) {
        _trip++;
        d = [RXCardDescriptor descriptorWithStack:jspit ID:_trip];
    }
    
    RXCardState* renderingState = (RXCardState *)[g_world cardRenderer];
    [renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)cmd_jtrip:(NSArray*)arguments {
    RXCardState* renderingState = (RXCardState*)[g_world cardRenderer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_nextJspitCard:) name:@"RXActiveCardDidChange" object:nil];
    _trip = 1;
    [renderingState setActiveCardWithStack:@"jspit" ID:_trip waitUntilDone:NO];
}

- (void)cmd_recompile:(NSArray*)args {
    RXCard* card = [[(RXCardState*)[g_world cardRenderer] scriptEngine] card];
    NSDictionary* scripts = [card scripts];
    
    NSEnumerator* iter_k = [scripts keyEnumerator];
    NSString* k;
    while ((k = [iter_k nextObject])) {
        if ([[scripts objectForKey:k] count] == 0)
            continue;
        
        [self print:[NSString stringWithFormat:@"recompiling %@", k]];
                
        RXScriptCompiler* comp = [[RXScriptCompiler alloc] initWithCompiledScript:[[scripts objectForKey:k] objectAtIndex:0]];
        NSMutableArray* decompiled_script = [comp decompiledScript];
        
        [comp setDecompiledScript:decompiled_script];
        NSDictionary* compiled_script = [comp compiledScript];
        
        [comp release];
        
        if (![compiled_script isEqual:[[scripts objectForKey:k] objectAtIndex:0]]) {
            [self print:@"re-compiled script not equal to origial script!"];
            [[[[scripts objectForKey:k] objectAtIndex:0] objectForKey:RXScriptProgramKey] writeToFile:@"original.rxscript" options:0 error:NULL];
            [[compiled_script objectForKey:RXScriptProgramKey] writeToFile:@"recompiled.rxscript" options:0 error:NULL];
            break;
        }
    }
}

@end
