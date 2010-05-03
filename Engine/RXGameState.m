//
//  RXGameState.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/11/2007.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import "Engine/RXGameState.h"
#import "Engine/RXWorldProtocol.h"


static const int RX_GAME_STATE_CURRENT_VERSION = 4;

// 1-2-3-4-5
static const uint32_t domecombo_bad1 = (1 << 24) | (1 << 23) | (1 << 22) | (1 << 21) | (1 << 20);


@implementation RXGameState

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

+ (RXGameState*)gameStateWithURL:(NSURL*)url error:(NSError**)error {
    // read the data in
    NSData* archive = [NSData dataWithContentsOfURL:url options:(NSMappedRead | NSUncachedRead) error:error];
    if (!archive) {
        [self release];
        return nil;
    }
    
    // use a keyed unarchiver to unfreeze a new game state object
    RXGameState* gameState = nil;
    @try {
        gameState = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
        if (!gameState)
            ReturnNILWithError(RXErrorDomain,
                               0,
                               ([NSDictionary dictionaryWithObject:@"Riven X does not understand the save file. It may be corrupted or may not be a Riven X save file at all."
                                                            forKey:NSLocalizedDescriptionKey]),
                               error);
        
        // set the write URL on the game state to indicate it has an existing location on the file system
        gameState->_URL = [url retain];
    } @catch (NSException* e) {
        if (error) {
            if ([[e userInfo] objectForKey:NSUnderlyingErrorKey])
                *error = [[[[e userInfo] objectForKey:NSUnderlyingErrorKey] retain] autorelease];
            else if ([[e userInfo] objectForKey:@"RXErrorString"])
                *error = [RXError errorWithDomain:RXErrorDomain
                                             code:0
                                         userInfo:[NSDictionary dictionaryWithObject:[[e userInfo] objectForKey:@"RXErrorString"] forKey:NSLocalizedDescriptionKey]];
            else
                *error = [RXError errorWithDomain:RXErrorDomain
                                             code:0
                                         userInfo:[NSDictionary dictionaryWithObject:[e reason] forKey:NSLocalizedDescriptionKey]];
        }
    }
    
    return gameState;
}

- (uint32_t)_generateDomeCombination {
    uint8_t domecombo1 = random() % 25;
    
    uint8_t domecombo2 = random() % 25;
    while (domecombo2 == domecombo1)
        domecombo2 = random() % 25;
    
    uint8_t domecombo3 = random() % 25;
    while (domecombo3 == domecombo1 || domecombo3 == domecombo2)
        domecombo3 = random() % 25;
    
    uint8_t domecombo4 = random() % 25;
    while (domecombo4 == domecombo1 || domecombo4 == domecombo2 || domecombo4 == domecombo3)
        domecombo4 = random() % 25;
    
    uint8_t domecombo5 = random() % 25;
    while (domecombo5 == domecombo1 || domecombo5 == domecombo2 || domecombo5 == domecombo3 || domecombo5 == domecombo4)
        domecombo5 = random() % 25;
    
    return (1 << (24 - domecombo1)) | (1 << (24 - domecombo2)) | (1 << (24 - domecombo3)) | (1 << (24 - domecombo4)) | (1 << (24 - domecombo5));
}

- (uint32_t)_generateTelescopeCombination {
    // first digit of the combination is stored in the lsb (3 bits per number)
    uint32_t combo = (random() % 5) + 1;
    combo = (combo << 3) | ((random() % 5) + 1);
    combo = (combo << 3) | ((random() % 5) + 1);
    combo = (combo << 3) | ((random() % 5) + 1);
    combo = (combo << 3) | ((random() % 5) + 1);
    return combo;
}

- (uint32_t)_generatePrisonCombination {
    // first digit of the combination is stored in the lsb (2 bits per number)
    uint32_t combo = (random() % 3) + 1;
    combo = (combo << 2) | ((random() % 3) + 1);
    combo = (combo << 2) | ((random() % 3) + 1);
    combo = (combo << 2) | ((random() % 3) + 1);
    combo = (combo << 2) | ((random() % 3) + 1);
    return combo;
}

- (void)_generateCombinations {
    // generate a dome combination (we need to try until we get a valid one)
    uint32_t domecombo = 0;
    while (1) {
        domecombo = [self _generateDomeCombination];
        
        // disallow a certain number of "bad combinations"
        if (domecombo == domecombo_bad1)
            continue;
        
        // valid combination, break out
        break;
    }
    [self setUnsigned32:domecombo forKey:@"adomecombo"];
    
    // set the rebel icon order variable (always the same value)
    [self setUnsigned32:12068577 forKey:@"jiconcorrectorder"];
    
    // generate a prison combination
    [self setUnsigned32:[self _generatePrisonCombination] forKey:@"pcorrectorder"];
    
    // generate a telescope combination
    [self setUnsigned32:[self _generateTelescopeCombination] forKey:@"tcorrectorder"];
}

- (void)_resetOldSave {
    // rrebel = 0
    
    // old saves didn't have valid combinations
    [self _generateCombinations];
}

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    _accessLock = [NSRecursiveLock new];
    
    NSError* error = nil;
    NSData* defaultVarData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"GameVariables" ofType:@"plist"] options:0 error:&error];
    if (!defaultVarData) {
        [self release];
        @throw [NSException exceptionWithName:@"RXMissingDefaultEngineVariablesException"
                                       reason:@"Unable to find the default engine variables file."
                                     userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
    }
    
    NSString* error_str = nil;
    _variables = [[NSPropertyListSerialization propertyListFromData:defaultVarData
                                                   mutabilityOption:NSPropertyListMutableContainers
                                                             format:NULL
                                                   errorDescription:&error_str] retain];
    if (!_variables) {
        [self release];
        @throw [NSException exceptionWithName:@"RXInvalidDefaultEngineVariablesException"
                                       reason:@"Unable to load the default engine variables."
                                     userInfo:[NSDictionary dictionaryWithObject:error_str forKey:@"RXErrorString"]];
    }
    [error_str release];
    
    // generate random combinations for the game
    [self _generateCombinations];
    
    // set the inital card to the entry card of aspit
    RXSimpleCardDescriptor* scd = [[RXSimpleCardDescriptor alloc] initWithStackKey:@"aspit" ID:[[[g_world stackDescriptorForKey:@"aspit"] objectForKey:@"Entry"] unsignedShortValue]];
    [self setCurrentCard:scd];
    [scd release];
    
    // no URL for new game states
    _URL = nil;
    
    return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
    self = [super init];
    if (!self)
        return nil;
    
    _accessLock = [NSRecursiveLock new];

    if (![decoder containsValueForKey:@"VERSION"]) {
        [self release];
        return nil;
    }
    int32_t version = [decoder decodeInt32ForKey:@"VERSION"];
    
    switch (version) {
        case 4:
        case 3:
        case 2:
        case 1:
            if (![decoder containsValueForKey:@"returnCard"]) {
                [self release];
                @throw [NSException exceptionWithName:@"RXInvalidGameStateArchive"
                                               reason:@"Riven X does not understand the save file. It may be corrupted or may not be a Riven X save file at all."
                                             userInfo:nil];
            }
            _returnCard = [[decoder decodeObjectForKey:@"returnCard"] retain];
        
        case 0:
            if (![decoder containsValueForKey:@"currentCard"]) {
                [self release];
                @throw [NSException exceptionWithName:@"RXInvalidGameStateArchive"
                                               reason:@"Riven X does not understand the save file. It may be corrupted or may not be a Riven X save file at all."
                                             userInfo:nil];
            }
            _currentCard = [[decoder decodeObjectForKey:@"currentCard"] retain];

            if (![decoder containsValueForKey:@"variables"]) {
                [self release];
                @throw [NSException exceptionWithName:@"RXInvalidGameStateArchive"
                                               reason:@"Riven X does not understand the save file. It may be corrupted or may not be a Riven X save file at all."
                                             userInfo:nil];
            }
            _variables = [[decoder decodeObjectForKey:@"variables"] retain];
            
            break;
        
        default:
            @throw [NSException exceptionWithName:@"RXInvalidGameStateArchive"
                                           reason:@"Riven X does not understand the save file. It may be corrupted or may not be a Riven X save file at all."
                                         userInfo:nil];
    }
    
    // save versions below 3 need to be partially reset to have correct
    // inventory and combinations
    if (version < 3)
        [self _resetOldSave];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
    if (![encoder allowsKeyedCoding])
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"RXGameState only supports keyed archiving."
                                     userInfo:nil];
    
    [_accessLock lock];
    
    [encoder encodeInt32:RX_GAME_STATE_CURRENT_VERSION forKey:@"VERSION"];
    
    [encoder encodeObject:_currentCard forKey:@"currentCard"];
    [encoder encodeObject:_returnCard forKey:@"returnCard"];
    [encoder encodeObject:_variables forKey:@"variables"];
    
    [_accessLock unlock];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_variables release];
    [_currentCard release];
    [_returnCard release];
    [_URL release];
    [_accessLock release];
    
    [super dealloc];
}

- (void)dump {
    RXOLog(@"dumping\n%@", _variables);
}

- (NSURL*)URL {
    return _URL;
}

- (BOOL)writeToURL:(NSURL*)url error:(NSError**)error {
    // serialize ourselves as data
    NSData* gameStateData = [NSKeyedArchiver archivedDataWithRootObject:self];
    if (!gameStateData)
        ReturnValueWithError(NO,
                             RXErrorDomain,
                             0,
                             ([NSDictionary dictionaryWithObject:@"Riven X was unable to prepare the game to be saved." forKey:NSLocalizedDescriptionKey]),
                             error);
    
    // write the data
    BOOL success = [gameStateData writeToURL:url options:NSAtomicWrite error:error];
    
    // if we were successful, update our internal URL
    if (success && url != _URL) {
        [_URL release];
        _URL = [url retain];
    }
    
    return success;
}

- (uint16_t)unsignedShortForKey:(NSString*)key {
    key = [key lowercaseString];
    uint16_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n unsignedShortValue];
    else
        [self setUnsignedShort:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (int16_t)shortForKey:(NSString*)key {
    key = [key lowercaseString];
    int16_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n shortValue];
    else
        [self setShort:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (void)setUnsignedShort:(uint16_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %hu", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithUnsignedShort:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (void)setShort:(int16_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %hd", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithShort:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (uint32_t)unsigned32ForKey:(NSString*)key {
    key = [key lowercaseString];
    uint32_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n unsignedIntValue];
    else
        [self setUnsigned32:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (int32_t)signed32ForKey:(NSString*)key {
    key = [key lowercaseString];
    int32_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n intValue];
    else
        [self setSigned32:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (void)setUnsigned32:(uint32_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %u", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithUnsignedInt:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (void)setSigned32:(int32_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %d", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithInt:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (uint64_t)unsigned64ForKey:(NSString*)key {
    key = [key lowercaseString];
    uint64_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n unsignedLongLongValue];
    else
        [self setUnsigned64:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (int64_t)signed64ForKey:(NSString*)key {
    key = [key lowercaseString];
    int64_t v = 0;
    
    [_accessLock lock];
    NSNumber* n = [_variables objectForKey:key];
    if (n)
        v = [n longLongValue];
    else
        [self setSigned32:0 forKey:key];
    [_accessLock unlock];
    
    return v;
}

- (void)setUnsigned64:(uint64_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %llu", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithUnsignedLongLong:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (void)setSigned64:(int64_t)value forKey:(NSString*)key {
    key = [key lowercaseString];
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"setting variable %@ to %lld", key, value);
#endif
    [self willChangeValueForKey:key];
    [_accessLock lock];
    [_variables setObject:[NSNumber numberWithLongLong:value] forKey:key];
    [_accessLock unlock];
    [self didChangeValueForKey:key];
}

- (BOOL)isKeySet:(NSString*)key {
    key = [key lowercaseString];
    [_accessLock lock];
    BOOL b = ([_variables objectForKey:key]) ? YES : NO;
    [_accessLock unlock];
    return b;
}

- (RXSimpleCardDescriptor*)currentCard {
    [_accessLock lock];
    RXSimpleCardDescriptor* card = _currentCard;
    [_accessLock unlock];
    
    return card;
}

- (void)setCurrentCard:(RXSimpleCardDescriptor*)descriptor {
    [_accessLock lock];
    
    id old = _currentCard;
    _currentCard = [descriptor retain];
    [old release];
    
    [self setUnsignedShort:descriptor->cardID forKey:@"currentcardid"];
    [self setUnsignedShort:[[[g_world stackDescriptorForKey:descriptor->stackKey] objectForKey:@"ID"] unsignedShortValue] forKey:@"currentstackid"];
    
    [_accessLock unlock];
}

- (RXSimpleCardDescriptor*)returnCard {
    [_accessLock lock];
    RXSimpleCardDescriptor* card = _returnCard;
    [_accessLock unlock];
    
    return card;
}

- (void)setReturnCard:(RXSimpleCardDescriptor*)descriptor {
    [_accessLock lock];
    
    id old = _returnCard;
    _returnCard = [descriptor retain];
    [old release];
    
    if (descriptor) {
        [self setUnsignedShort:descriptor->cardID forKey:@"returncardid"];
        [self setUnsignedShort:[[[g_world stackDescriptorForKey:descriptor->stackKey] objectForKey:@"ID"] unsignedShortValue] forKey:@"returnstackid"];
    } else {
        [self setUnsignedShort:0 forKey:@"returncardid"];
        [self setUnsignedShort:0 forKey:@"returnstackid"];
    }
    
    [_accessLock unlock];
}

@end
