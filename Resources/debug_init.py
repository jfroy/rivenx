import sys
import objc

import rivenx

# intercept stderr and stdout
class StdoutCatcher:
    def write(self, str):
        rivenx.CaptureStdout(str)

class StderrCatcher:
    def write(self, str):
        rivenx.CaptureStderr(str)

sys.stdout = StdoutCatcher()
sys.stderr = StderrCatcher()

# get the debug window controller
debug = objc.lookUpClass('RXDebugWindowController').globalDebugWindowController()

# get RXWorld
world = objc.lookUpClass('RXWorld').sharedWorld()

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
    # ok, if may be a "simple command" of the formd <command> <foo> <bar>
    cmd_parts = cmd.split(' ')
    try:
        cmd_func = globals()[cmd_parts[0]]
        cmd_func(*cmd_parts[1:])
    except KeyError:
        exec cmd in globals()

# greet the user
print "Riven X debug shell v4. Type help for commands. Type a command for usage information.\n"
