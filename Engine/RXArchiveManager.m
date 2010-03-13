//
//  RXArchiveManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Carbon/Carbon.h>

#import "Engine/RXArchiveManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"
#import "Utilities/GTMObjectSingleton.h"


@implementation RXArchiveManager

GTMOBJECT_SINGLETON_BOILERPLATE(RXArchiveManager, sharedArchiveManager)

+ (NSPredicate*)anyArchiveFilenamePredicate {
    static NSPredicate* predicate = nil;
    if (!predicate)
        predicate = [[NSCompoundPredicate orPredicateWithSubpredicates:
                      [NSArray arrayWithObjects:
                       [self dataArchiveFilenamePredicate],
                       [self soundsArchiveFilenamePredicate],
                       [self extrasArchiveFilenamePredicate],
                       nil]]
                     retain];
    return predicate;
}

+ (NSPredicate*)dataArchiveFilenamePredicate {
    static NSPredicate* predicate = nil;
    if (!predicate)
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^[abgjoprt]_Data[0-9]?\\.MHK$"] retain];
    return predicate;
}

+ (NSPredicate*)soundsArchiveFilenamePredicate {
    static NSPredicate* predicate = nil;
    if (!predicate)
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^[abgjoprt]_Sounds[0-9]?\\.MHK$"] retain];
    return predicate;
}

+ (NSPredicate*)extrasArchiveFilenamePredicate {
    static NSPredicate* predicate = nil;
    if (!predicate)
        predicate = [[NSPredicate predicateWithFormat:@"SELF matches[c] %@", @"^Extras\\.MHK$"] retain];
    return predicate;
}

- (id)init  {
    self = [super init];
    if (!self)
        return nil;
    
    // find the Editions directory
    NSString* editions_directory = [[NSBundle mainBundle] pathForResource:@"Editions" ofType:nil];
    if (!editions_directory)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Riven X could not find the Editions bundle resource directory."
                                     userInfo:nil];
    
    // cache the path to the Patches directory
    patches_directory = [[editions_directory stringByAppendingPathComponent:@"Patches"] retain];
    
    // get the location of the local data store
    local_data_store = [[[[[RXWorld sharedWorld] worldBase] path] stringByAppendingPathComponent:@"Data"] retain];
    
#if defined(DEBUG)
    if (!BZFSDirectoryExists(local_data_store)) {
        [local_data_store release];
        local_data_store = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Data"] retain];
    }
#endif
    
    // check if the local data store exists (it is not required)
    if (!BZFSDirectoryExists(local_data_store)) {
        [local_data_store release];
        local_data_store = nil;
#if defined(DEBUG)
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"no local data store could be found");
#endif
    }
    
//    BOOL option_pressed = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
//    if (default_edition && !option_pressed)
//        [self performSelectorOnMainThread:@selector(_makeEditionChoiceMemoryCurrent) withObject:nil waitUntilDone:NO];
//    else {
//        // show the edition manager
////        [self showEditionManagerWindow];
//    }
    
    return self;
}

- (void)dealloc {    
    [local_data_store release];
    [patches_directory release];
    [extras_archive release];
    
    [super dealloc];
}

static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
    return [(NSString*)lhs compare:rhs options:NSCaseInsensitiveSearch | NSNumericSearch];
}

- (NSArray*)_archivesForExpression:(NSString*)regex error:(NSError**)error {
    // create a predicate to match filenames against the provided regular expression, case insensitive
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSMutableArray* matching_paths = [NSMutableArray array];
    NSString* directory;
    NSArray* content;
    
    // first look in the local data store
    if (local_data_store) {
        directory = local_data_store;
        content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
        if (content) {
            NSEnumerator* enumerator = [content objectEnumerator];
            NSString* filename;
            while ((filename = [enumerator nextObject]))
                [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
        }
    }
    
    // then look in the world shared base (e.g. /Users/Shared/Riven X, where the installer will put the archives)
    directory = [[(RXWorld*)g_world worldSharedBase] path];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content) {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // then look inside Riven X
    directory = [[NSBundle mainBundle] resourcePath];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content) {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // load every archive found
    NSMutableArray* archives = [NSMutableArray array];
    NSEnumerator* enumerator = [matching_paths objectEnumerator];
    NSString* archive_path;
    while ((archive_path = [enumerator nextObject])) {
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
        if (!archive)
            return nil;
        
        [archives addObject:archive];
        [archive release];
    }
    
    // emit an error and return nil if no archives was found or loaded
    if ([archives count] == 0) {
        archives = nil;
        if (error)
            *error = [NSError errorWithDomain:RXErrorDomain code:kRXErrArchivesNotFound userInfo:nil];
    }
    
    return archives;
}

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
    return [self _archivesForExpression:[NSString stringWithFormat:@"^%C_Data[0-9]?\\.MHK$", [stack_key characterAtIndex:0]] error:error];
}

- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
    return [self _archivesForExpression:[NSString stringWithFormat:@"^%C_Sounds[0-9]?\\.MHK$", [stack_key characterAtIndex:0]] error:error];
}

- (MHKArchive*)extrasArchive:(NSError**)error {
    if (!extras_archive) {
        NSArray* archives = [self _archivesForExpression:@"^Extras\\.MHK$" error:error];
        if ([archives count]) {
            extras_archive = [[archives objectAtIndex:0] retain];
#if defined(DEBUG)
            RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"loaded Extras archive from %@", [[extras_archive url] path]);
#endif
        }
    }
    return [[extras_archive retain] autorelease];
}

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
//    NSString* edition_patches_directory = [_patches_directory stringByAppendingPathComponent:[current_edition valueForKey:@"key"]];
//    NSDictionary* patch_archives = [current_edition valueForKey:@"patchArchives"];
//    
//    // if the edition has no patch archives, return an empty array
//    if (!patch_archives)
//        return [NSArray array];
//    
//    // get the patch archives for the requested stack; if there are none, return an empty array
//    NSDictionary* stack_patch_archives = [patch_archives objectForKey:stack_key];
//    if (!stack_patch_archives)
//        return [NSArray array];
//    
//    // get the data patch archives; if there are none, return an empty array
//    NSArray* data_patch_archives = [stack_patch_archives objectForKey:@"Data Archives"];
//    if (!data_patch_archives)
//        return [NSArray array];
//    
//    // load the data archives
//    NSMutableArray* data_archives = [NSMutableArray array];
//    
//    NSEnumerator* archive_enumerator = [data_patch_archives objectEnumerator];
//    NSString* archive_name;
//    while ((archive_name = [archive_enumerator nextObject])) {
//        NSString* archive_path = BZFSSearchDirectoryForItem(edition_patches_directory, archive_name, YES, error);
//        if (!BZFSFileExists(archive_path))
//            continue;
//        
//        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
//        if (!archive)
//            return nil;
//        
//        [data_archives addObject:archive];
//        [archive release];
//    }
//    
//    return data_archives;
    // FIXME: need to re-implement this w/o editions
    return [NSArray array];
}

@end
