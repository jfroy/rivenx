import code
import sys
import objc
import warnings

import Foundation
import rivenx

# ignore all warnings
warnings.simplefilter("ignore")

# get a number of native classes
RXCardDescriptor = objc.lookUpClass('RXCardDescriptor')
RXCard = objc.lookUpClass('RXCard')
RXScriptOpcodeStream = objc.lookUpClass('RXScriptOpcodeStream')

# intercept stderr and stdout
class StdoutCatcher(object):
    def write(self, str):
        rivenx.CaptureStdout(str)
class StderrCatcher(object):
    def write(self, str):
        rivenx.CaptureStderr(str)
sys.stdout = StdoutCatcher()
sys.stderr = StderrCatcher()

# interactive console
console = code.InteractiveConsole(globals())

# get the debug window controller
debug = objc.lookUpClass('RXDebugWindowController').globalDebugWindowController()

# get a number of useful global objects
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

# register for stack did load notifications because some global objects do not exist until then
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
        try:
            cmd_func(*cmd_parts[1:])
        except Exception, e:
            print str(e)
    except KeyError:
        console.push(cmd)
    except Exception, e:
        print str(e)

# greet the user
print "Riven X debug shell v4.\n"

def cmd_help(*args):
    for a in sorted(globals()):
        if a.startswith('cmd_') and callable(globals()[a]):
            print a[4:]

def _find_missing_externals(card):
    card._loadHotspots()
    card._loadScripts()
    externals = set()

    scripts = card.scripts()
    for event in scripts.allKeys():
        #print event
        for script in scripts[event]:
            externals.update(debug._findExternalCommands_card_(script, card))
    for hotspot in card.hotspots():
        #print hotspot.name()
        scripts = hotspot.scripts()
        for event in scripts.allKeys():
            #print event
            for script in scripts[event]:
                externals.update(debug._findExternalCommands_card_(script, card))

    return frozenset(a for a in externals if not hasattr(engine, '_external_' + a + '_arguments_'))

def cmd_missing_externals(*args):
    edition = edition_manager.currentEdition()
    stacks = edition.valueForKey_("stackDescriptors").allKeys()

    stack = edition_manager.loadStackWithKey_('bspit')
    desc = RXCardDescriptor.alloc().initWithStack_ID_(stack, 284)
    card = RXCard.alloc().initWithCardDescriptor_(desc)
    _find_missing_externals(card)

    for stack_key in sorted(stacks):
        stack = edition_manager.loadStackWithKey_(stack_key)
        if not stack:
            continue
        print "missing externals for %s" % stack_key

        external_card_map = {}

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
            if not card:
                continue

            new_externals = _find_missing_externals(card)
            for external in new_externals:
                external_cards = external_card_map.get(external, None)
                if external_cards is None:
                    external_cards = []
                    external_card_map[external] = external_cards
                external_cards.append(card.name())

        print ('    ' if len(external_card_map) else '') + '\n    '.join('%s - %s' % (e, str(external_card_map[e])) for e in external_card_map)
