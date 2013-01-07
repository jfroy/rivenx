//
//  RXArchiveManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <Carbon/Carbon.h>

#import "Engine/RXArchiveManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"


@implementation RXArchiveManager

+ (RXArchiveManager*)sharedArchiveManager
{
    static dispatch_once_t once;
    static RXArchiveManager* shared = nil;
    dispatch_once(&once, ^(void)
    {
        shared = [RXArchiveManager new];
    });
    return shared;
}

+ (NSPredicate*)anyArchiveFilenamePredicate
{
    static dispatch_once_t once;
    static NSPredicate* predicate = nil;
    dispatch_once(&once, ^(void)
    {
        predicate = [[NSCompoundPredicate orPredicateWithSubpredicates:
                      [NSArray arrayWithObjects:
                       [self dataArchiveFilenamePredicate],
                       [self soundsArchiveFilenamePredicate],
                       [self extrasArchiveFilenamePredicate],
                       nil]]
                     retain];
    });
    return predicate;
}

+ (NSPredicate*)dataArchiveFilenamePredicate
{
    static dispatch_once_t once;
    static NSPredicate* predicate = nil;
    dispatch_once(&once, ^(void)
    {
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^[abgjoprt]_Data[0-9]?\\.MHK$"] retain];
    });
    return predicate;
}

+ (NSPredicate*)soundsArchiveFilenamePredicate
{
    static dispatch_once_t once;
    static NSPredicate* predicate = nil;
    dispatch_once(&once, ^(void)
    {
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^[abgjoprt]_Sounds[0-9]?\\.MHK$"] retain];
    });
    return predicate;
}

+ (NSPredicate*)extrasArchiveFilenamePredicate
{
    static dispatch_once_t once;
    static NSPredicate* predicate = nil;
    dispatch_once(&once, ^(void)
    {
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^Extras\\.MHK$"] retain];
    });
    return predicate;
}

- (id)init 
{
    self = [super init];
    if (!self)
        return nil;
    
    // cache the path to the Patches directory
    patches_directory = nil;
    
    return self;
}

- (void)dealloc 
{
    [patches_directory release];
    [extras_archive release];
    
    [super dealloc];
}

static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context)
{
    return [(NSString*)rhs compare:lhs options:(NSStringCompareOptions)(NSCaseInsensitiveSearch | NSNumericSearch)];
}

- (NSArray*)_archivesForExpression:(NSString*)regex error:(NSError**)error
{
    // create a predicate to match filenames against the provided regular expression, case insensitive
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSMutableArray* matching_paths = [NSMutableArray array];
    NSString* directory;
    NSArray* content;
    
    
    // first look in the world base
    directory = [[[RXWorld sharedWorld] worldBase] path];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content)
    {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // then look in a Data subdirectory of the world base
    directory = [[[[RXWorld sharedWorld] worldBase] path] stringByAppendingPathComponent:@"Data"];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content)
    {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // then look in the world cache base (e.g. where the installer will put the archives)
    directory = [[(RXWorld*)g_world worldCacheBase] path];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content)
    {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // then look inside Riven X
    directory = [[NSBundle mainBundle] resourcePath];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content)
    {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // load every archive found
    NSMutableArray* archives = [NSMutableArray array];
    NSEnumerator* enumerator = [matching_paths objectEnumerator];
    NSString* archive_path;
    while ((archive_path = [enumerator nextObject]))
    {
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
        if (!archive)
            return nil;
        
        [archives addObject:archive];
        [archive release];
    }
    
    // emit an error and return nil if no archives was found or loaded
    if ([archives count] == 0)
    {
        archives = nil;
        if (error)
            *error = [RXError errorWithDomain:RXErrorDomain code:kRXErrArchivesNotFound userInfo:nil];
    }
    
    return archives;
}

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error
{
    return [self _archivesForExpression:[NSString stringWithFormat:@"^%C_Data[0-9]?\\.MHK$", [stack_key characterAtIndex:0]] error:error];
}

- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error
{
    return [self _archivesForExpression:[NSString stringWithFormat:@"^%C_Sounds[0-9]?\\.MHK$", [stack_key characterAtIndex:0]] error:error];
}

- (MHKArchive*)extrasArchive:(NSError**)error
{
    if (!extras_archive)
    {
        NSArray* archives = [self _archivesForExpression:@"^Extras\\.MHK$" error:error];
        if ([archives count])
        {
            extras_archive = [[archives objectAtIndex:0] retain];
#if defined(DEBUG)
            RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"loaded Extras archive from %@", [[extras_archive url] path]);
#endif
        }
    }
    return [[extras_archive retain] autorelease];
}

@end
