/*   System.h Copyright (c) 1998-2006 Philippe Mougin.  */
/*   This software is open source. See the license.  */  

#import "FSNSObject.h"

@class Block;
@class Executor;

@interface System:NSObject <NSCopying>
// Note : Support for NSCoding is only here for backward compatibility with old archives.
// It is deprecated. 
{
  Executor *executor; 
  // A System object point to an Executor instance. Why not an FSInterpreter
  // instance instead? Because it would create a retain cycle that would 
  // prevent the whole object graph (FSInterpreter, Executor, SymbolTable etc.)
  // to be dealoced. But pointing to the Executor also creates a cycle! 
  // However, the dealloc method of FSInterpreter do what is necessary to break 
  // this cycle. 
  // Could the problem be resolved by System not retaining the FSInterpreter?
  // No, because a System object can be referenced "externaly" by other objects.
  // Hence its lifecycle is not always determined by  the lifecycle of the 
  // FSInterpreter instance.
}

+ system:(id)theSys;

- copy;
- copyWithZone:(NSZone *)zone;
- (void)dealloc;
- init:(id)theSys;

///////////////////////////////////// USER METHODS ////////////////////////

- (void)attach:(id)objectContext;
- (void)beep;
- blockFromString:(NSString *)source;
- blockFromString:(NSString *)source onError:(Block *)errorBlock;
- (void)browse;
- (void)browse:(id)anObject;
- (System *)clone;
- (void)enableJava;
- (NSString *)fullUserName;
- (NSString *)homeDirectory;
- (NSString *)homeDirectoryForUser:(NSString *)userName;
- (id)ktest;
- (Array *)identifiers;
- (void)installFlightTutorial;
- (id)load;
- (id)load:(NSString *)fileName;
- (void)loadSpace;
- (void)loadSpace:(NSString *)fileName;
- (void)log:(id)object;
- (void)saveSpace;
- (void)saveSpace:(NSString *)fileName;
- (void)setValue:(System *)operand ;
- (NSString *)userName;

@end
