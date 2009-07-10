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

class DebugNotificationHandler(Foundation.NSObject):
    
    def _handleStackDidLoad_(self, notification):
        global renderer
        global engine
        renderer = world.cardRenderState()
        engine = renderer.scriptEngine()
        
        print "Global objects initialized:\n    world=%s\n    renderer=%s\n    engine=%s" % (world, renderer, engine)

notification_handler = DebugNotificationHandler.alloc().init()
Foundation.NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
    notification_handler, '_handleStackDidLoad:', "RXStackDidLoadNotification", None)

# alias native debug commands
try:
    _methods = dir(debug.pyobjc_instanceMethods)
    for m in _methods:
        if m.startswith('cmd_'):
            cmd_name = m[4:].split('_', 1)[0]
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
        cmd_func = globals()[cmd_parts[0]]
        cmd_func(*cmd_parts[1:])
    except KeyError:
        exec cmd in globals()

# greet the user
print "Riven X debug shell v4.\n"
