/*   Block.h Copyright (c) 1998-2006 Philippe Mougin.         */
/*   This software is open source. See the license.       */

#import "FSNSObject.h"

extern NSString *FS_Block_keyOfSetValueForKeyMessage(Block *block);

@class BlockInspector, MsgContext, BlockRep, SymbolTable, CompiledCodeNode, FSInterpreter, FSInterpreterResult;

@interface Block:NSObject <NSCopying , NSCoding>
{
  unsigned retainCount;    
  BlockRep *blockRep;
  BlockInspector *inspector;
}

+ allocWithZone:(NSZone *)zone;
+ blockWithSelector:(SEL)theSelector;
+ blockWithSource:(NSString *)source parentSymbolTable:(SymbolTable *)parentSymbolTable;  // May raise
+ blockWithSource:(NSString *)source parentSymbolTable:(SymbolTable *)parentSymbolTable onError:(Block *)errorBlock; // May raise
+ (void)initialize;

- (NSArray *)argumentsNames;
- (void) compilIfNeeded; // May raise
- (id) compilOnError:(Block *)errorBlock; // May raise
- copy;
- copyWithZone:(NSZone *)zone;
- (void)dealloc;
- (void)encodeWithCoder:(NSCoder *)aCoder;
- (FSInterpreterResult *)executeWithArguments:(NSArray *)arguments;
- (id) initWithBlockRep:(BlockRep *)theBlockRep;
- (id)initWithCoder:(NSCoder *)aDecoder;
- initWithCode:(CompiledCodeNode *)theCode symbolTable:(SymbolTable*)theSymbolTable signature:(struct BlockSignature)theSignature source:(NSString*)theSource isCompiled:(BOOL)is_comp isCompact:(BOOL)isCompactArg sel:(SEL)theSel selStr:(NSString*)theSelStr;
   // This method retains theCode, theSymbolTable and theSource. No copy.
- (BOOL) isCompact;  // May raise
- (MsgContext *)msgContext;
- (void) release;
- (id) retain;
- (unsigned int) retainCount;
- (SEL) selector;
- (NSString *) selectorStr;
- (void)setInterpreter:(FSInterpreter *)theInterpreter;
- (void)showError:(NSString*)errorMessage; 
- (void)showError:(NSString*)errorMessage start:(int)firstCharacterIndex end:(int)lastCharacterIndex;
- (SymbolTable *) symbolTable;
- (id) valueArgs:(id*)args count:(unsigned)count;

////////////////////////////// USER METHODS ////////////////////////

- (int)argumentCount;
- (Block*) clone;
- (id) guardedValue:(id)arg1;
- (unsigned) hash;
- (void) inspect;
- (BOOL) isEqual:anObject;
- (void) return;
- (void) return:(id)rv;
- (void)setValue:(Block *)operand;
- (id) value;
- (id) value:(id)arg1;
- (id) value:(id)arg1 value:(id)arg2;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7 value:(id)arg8;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7 value:(id)arg8 value:(id)arg9;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7 value:(id)arg8 value:(id)arg9 value:(id)arg10;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7 value:(id)arg8 value:(id)arg9 value:(id)arg10 value:(id)arg11;
- (id) value:(id)arg1 value:(id)arg2 value:(id)arg3 value:(id)arg4 value:(id)arg5 value:(id)arg6 value:(id)arg7 value:(id)arg8 value:(id)arg9 value:(id)arg10 value:(id)arg11 value:(id)arg12;
- (id) valueWithArguments:(NSArray *)operand;
- (void) whileFalse;
- (void) whileFalse:(Block*)iterationBlock;
- (void) whileTrue;
- (void) whileTrue:(Block*)iterationBlock;

@end
