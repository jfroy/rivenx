import code
import sys
import objc
import warnings

import Foundation
import rivenx

import debug_notification


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
world = None
renderer = None
engine = None
edition_manager = None

load_notification_handler = None

def _load_globals():
    global world, renderer, engine, edition_manager, load_notification_handler
    world = objc.lookUpClass('RXWorld').sharedWorld()
    if world:
        renderer = world.cardRenderer()
    if renderer:
        engine = renderer.scriptEngine()
    edition_manager = objc.lookUpClass('RXEditionManager').sharedEditionManager()

    if load_notification_handler:
        del load_notification_handler

_load_globals()
if not renderer:
    load_notification_handler = debug_notification.OneShotNotificationHandler("RXStackDidLoadNotification")
    load_notification_handler.add_callable(_load_globals)

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

def cmd_reload(*args):
    fp = Foundation.NSBundle.mainBundle().pathForResource_ofType_("debug_init", "py")
    execfile(fp, globals())

def _find_missing_externals(card):
    card._loadHotspots()
    card._loadScripts()
    externals = set()

    scripts = card.scripts()
    for event in scripts.allKeys():
        for script in scripts[event]:
            externals.update(debug._findExternalCommands_card_(script, card))
    for hotspot in card.hotspots():
        scripts = hotspot.scripts()
        for event in scripts.allKeys():
            for script in scripts[event]:
                externals.update(debug._findExternalCommands_card_(script, card))

    return frozenset(a for a in externals if not hasattr(engine, '_external_' + a + '_arguments_'))

def cmd_missing_externals(*args):
    edition = edition_manager.currentEdition()
    stacks = edition.valueForKey_("stackDescriptors").allKeys()

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

def cmd_tcombo(*args):
    tcombo = world.gameState().unsigned32ForKey_("tCorrectOrder")
    print "telescope combination: %d %d %d %d %d" % tuple((tcombo >> (3 * i)) & 0x7 for i in xrange(5))

def cmd_dcombo(*args):
    dcombo = world.gameState().unsigned32ForKey_("aDomeCombo")
    def gen_dome_digit():
        for i in xrange(25):
            if (dcombo & (1 << (24 - i))):
                yield i + 1
    print "dome combination: %d %d %d %d %d" % tuple(gen_dome_digit())

OPCODES = {
    0: "invalid",
    1: "draw dynamic picture",
    2: "goto card",
    3: "activate synthesized SLST",
    4: "play sfx",
    5: "activate synthesized MLST",
    6: "unimplemented",
    7: "set variable",
    8: "branch",
    9: "enable hotspot",
    10: "disable hotspot",
    11: "invalid",
    12: "clear ambient sounds",
    13: "set cursor",
    14: "pause",
    15: "invalid",
    16: "invalid",
    17: "call external",
    18: "schedule transition",
    19: "reload",
    20: "disable screen updates",
    21: "enable screen updates",
    22: "invalid",
    23: "invalid",
    24: "increment var",
    25: "decrement var",
    26: "close all movies",
    27: "goto stack",
    28: "disable movie",
    29: "disable all movies",
    30: "set movie rate",
    31: "enable movie",
    32: "play movie and block",
    33: "play movie",
    34: "stop movie",
    35: "activate SFXE",
    36: "noop",
    37: "fade ambient sounds",
    38: "schedule movie command",
    39: "activate PLST",
    40: "activate SLST",
    41: "activate MLST and play movie",
    42: "noop",
    43: "activate BLST",
    44: "activate FLST",
    45: "do zip",
    46: "activate MLST",
    47: "activate SLST with volume",
}
