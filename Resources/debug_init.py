import sys
import objc

import Foundation
import rivenx

# intercept stderr and stdout
class StdoutCatcher(object):
    def write(self, str):
        rivenx.CaptureStdout(str)

class StderrCatcher(object):
    def write(self, str):
        rivenx.CaptureStderr(str)

sys.stdout = StdoutCatcher()
sys.stderr = StderrCatcher()

# get the debug window controller
debug = objc.lookUpClass('RXDebugWindowController').globalDebugWindowController()

# get RXWorld
world = objc.lookUpClass('RXWorld').sharedWorld()
renderer = None
engine = None
edition_manager = None

class DebugNotificationHandler(Foundation.NSObject):
    
    def _handleStackDidLoad_(self, notification):
        global renderer
        global engine
        global edition_manager
        renderer = world.cardRenderState()
        engine = renderer.scriptEngine()
        edition_manager = objc.lookUpClass('RXEditionManager').sharedEditionManager()
        
        print "Global objects initialized:\n    world=%s\n    renderer=%s\n    engine=%s" % (world, renderer, engine)
        Foundation.NSNotificationCenter.defaultCenter().removeObserver_(self)

notification_handler = DebugNotificationHandler.alloc().init()
Foundation.NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
    notification_handler, '_handleStackDidLoad:', "RXStackDidLoadNotification", None)

# alias native debug commands
try:
    _methods = dir(debug.pyobjc_instanceMethods)
    for m in _methods:
        if m.startswith('cmd_'):
            cmd_name = 'cmd_' + m[4:].split('_', 1)[0]
            def make_cmd():
                cmd = getattr(debug, m)
                def g(*args):
                    cmd(args)
                g.__name__ = cmd_name
                return g
            globals()[cmd_name] = make_cmd()
except Exception, e:
    print str(e)

def exec_cmd(cmd):
    # ok, it may be a "simple command" of the formd <command> <foo> <bar>
    cmd_parts = cmd.split(' ')
    try:
        cmd_func = globals()['cmd_' + cmd_parts[0]]
        cmd_func(*cmd_parts[1:])
    except KeyError:
        exec cmd in globals()
    except Exception, e:
        print str(e)

# greet the user
print "Riven X debug shell v4.\n"

def cmd_help(*args):
    for a in sorted(globals()):
        if a.startswith('cmd_') and callable(globals()[a]):
            print a[4:]

def cmd_missing_externals(*args):
    RXCardDescriptor = objc.lookUpClass('RXCardDescriptor')
    RXCard = objc.lookUpClass('RXCard')
    RXScriptOpcodeStream = objc.lookUpClass('RXScriptOpcodeStream')

    edition = edition_manager.currentEdition()
    stacks = edition.valueForKey_("stackDescriptors").allKeys()
    print stacks
    for stack_key in sorted(stacks)[:2]:
        stack = edition_manager.loadStackWithKey_(stack_key)
        card_i = 0
        card_id = 1
        card_count = stack.cardCount()
        while card_i < card_count:
            desc = RXCardDescriptor.alloc().initWithStack_ID_(stack, card_id)
            card_id += 1
            if not desc:
                continue

            card_i += 1
            card = RXCard.alloc().initWithCardDescriptor_(desc)
            print card
