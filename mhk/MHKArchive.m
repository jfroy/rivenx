//
//  MHKArchive.m
//  MHKKit
//
//  Created by Jean-Francois Roy on 15/04/2005.
//  Copyright 2005-2010 MacStorm. All rights reserved.
//

#import <CoreServices/CoreServices.h>

#import <stdlib.h>
#import <limits.h>

#import "MHKArchive.h"

#import "MHKErrors.h"
#import "MHKFileHandle.h"


struct descriptor_binary_tree {
    uint16_t resource_id;
    NSMutableDictionary* descriptor;
};

static int __descriptor_binary_tree_compare(const void* v1, const void* v2) {
    struct descriptor_binary_tree* descriptor_1 = (struct descriptor_binary_tree*)v1;
    struct descriptor_binary_tree* descriptor_2 = (struct descriptor_binary_tree*)v2;
    
    if (descriptor_1->resource_id < descriptor_2->resource_id)
        return -1;
    if (descriptor_1->resource_id == descriptor_2->resource_id)
        return 0;
    return 1;
}

static int _MHK_file_table_entry_pointer_offset_compare(const void* v1, const void* v2) {
    MHK_file_table_entry** entry1 = (MHK_file_table_entry**)v1;
    MHK_file_table_entry** entry2 = (MHK_file_table_entry**)v2;
    
    if ((*entry1)->absolute_offset < (*entry2)->absolute_offset)
        return -1;
    if ((*entry1)->absolute_offset == (*entry2)->absolute_offset)
        return 0;
    return 1;
}

MHK_INLINE uint32_t compute_file_table_entry_length(MHK_file_table_entry* s) {
    uint32_t length = s->size_high;
    length = length << 16;
    length += s->size_low;
    return length;
}


@interface MHKFileHandle (Private)
- (id)_initWithArchive:(MHKArchive*)archive fork:(SInt16)fork descriptor:(NSDictionary*)desc;
@end


@implementation MHKArchive

+ (BOOL)accessInstanceVariablesDirectly {
    return NO;
}

- (id)autorelease {
    return [super autorelease];
}

- (void)compute_file_lengths {
    // if we've already been initialzed, return
    if (initialized)
        return;
    
    // we'll sort an array of file table entry pointers
    MHK_file_table_entry** file_table_entry_table = (MHK_file_table_entry**)calloc(file_table_count, sizeof(MHK_file_table_entry*));
    if (!file_table_entry_table)
        return;
    
    // load the pointers
    uint32_t file_table_index = 0;
    for (; file_table_index < file_table_count; file_table_index++)
        file_table_entry_table[file_table_index] = file_table + file_table_index;
    
    // we're going to sort with qsort since I have no idea about pre-sorting in existing MHK files, etc
    qsort(file_table_entry_table, file_table_count, sizeof(MHK_file_table_entry*), &_MHK_file_table_entry_pointer_offset_compare);
    
    // the pointers have been sorted in ascending order by file offset
    uint32_t file_length;
    uint32_t stored_file_length;
    
    for (file_table_index = 1; file_table_index < file_table_count; file_table_index++) {
        // compute the file length based on the space between the current file and the previous file
        file_length = file_table_entry_table[file_table_index]->absolute_offset - file_table_entry_table[file_table_index - 1]->absolute_offset;
        
        // get the metadata file length
        stored_file_length = compute_file_table_entry_length(file_table_entry_table[file_table_index - 1]);
        
        // if the length don't match, set it to the packed file length (e.g. as determined by the offsets)
        if (file_length != stored_file_length) {
#if defined(DEBUG) && DEBUG > 2
            fprintf(stderr, "file entry %03d -> packed file size: %u, stored file size: %u, delta: %d\n",
                    file_table_index - 1, file_length, stored_file_length, (int32_t)file_length - stored_file_length);
            
            NSEnumerator* types_enum = [file_descriptor_arrays keyEnumerator];
            NSString* type;
            while ((type = [types_enum nextObject])) {
                NSArray* type_descs = [file_descriptor_arrays objectForKey:type];
                
                NSEnumerator* files_enum = [type_descs objectEnumerator];
                NSDictionary* file_desc;
                while ((file_desc = [files_enum nextObject])) {
                    uint32_t file_index = [[file_desc objectForKey:@"Index"] unsignedIntValue] - 1;
                    if (file_index == file_table_index - 1)
                        fprintf(stderr, "    %s %d (%s)\n",
                                [type UTF8String], [[file_desc objectForKey:@"ID"] intValue],
                                [[file_desc objectForKey:@"Name"] UTF8String]);
                }
            }
#endif

            file_table_entry_table[file_table_index - 1]->size_high = (file_length & 0x00FF0000) >> 16;
            file_table_entry_table[file_table_index - 1]->size_low = file_length & 0x0000FFFF;
        }
    }
    
    // for the last entry, we compute the file length using the archive size
    file_length = archive_size - file_table_entry_table[file_table_count - 1]->absolute_offset;
    stored_file_length = compute_file_table_entry_length(file_table_entry_table[file_table_count - 1]);
    
    // if the length don't match, set it to the packed file length (e.g. as determined by the offsets)
    if (file_length != stored_file_length) {
#if defined(DEBUG) && DEBUG > 2
        fprintf(stderr, "file entry %03d -> packed file size: %u, stored file size: %u, delta: %d\n",
                file_table_count - 1, file_length, stored_file_length, (int32_t)file_length - stored_file_length);
        
        NSEnumerator* types_enum = [file_descriptor_arrays keyEnumerator];
        NSString* type;
        while ((type = [types_enum nextObject])) {
            NSArray* type_descs = [file_descriptor_arrays objectForKey:type];
            
            NSEnumerator* files_enum = [type_descs objectEnumerator];
            NSDictionary* file_desc;
            while ((file_desc = [files_enum nextObject])) {
                uint32_t file_index = [[file_desc objectForKey:@"Index"] unsignedIntValue] - 1;
                if (file_index == file_table_count - 1)
                    fprintf(stderr, "    %s %d (%s)\n",
                            [type UTF8String], [[file_desc objectForKey:@"ID"] intValue],
                            [[file_desc objectForKey:@"Name"] UTF8String]);
            }
        }
#endif

        file_table_entry_table[file_table_count - 1]->size_high = (file_length & 0x00FF0000) >> 16;
        file_table_entry_table[file_table_count - 1]->size_low = file_length & 0x0000FFFF;
    }
    
    // cleanup
    free(file_table_entry_table);
}

- (BOOL)load_mhk_type:(uint32_t)type_index {
    OSStatus err = noErr;
    
    // if we've already been initialzed, return
    if (initialized)
        return YES;
    
    // get the type table entry and swap it
    MHK_type_table_entry* type_table_entry = type_table + type_index;
    MHK_type_table_entry_fton(type_table_entry);
    
    // seek to the resource table
    err = FSSetForkPosition(forkRef, fsFromStart, resource_directory_absolute_offset + type_table_entry->rsrc_table_rsrc_dir_offset);
    if (err)
        return NO;
    
    // read the resource table header
    MHK_rsrc_table_header rsrc_table_header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_rsrc_table_header), &rsrc_table_header, NULL);
    if (err)
        return NO;
    MHK_rsrc_table_header_fton(&rsrc_table_header);
    
    // if there are no resources of this type, set an empty array of descriptors and exit
    if (rsrc_table_header.count == 0) {
        NSString* type_key = [[NSString alloc] initWithBytes:type_table_entry->name length:4 encoding:NSASCIIStringEncoding];
        NSArray* descriptors = [[NSArray alloc] init];
        [file_descriptor_arrays setObject:descriptors forKey:type_key];
        [file_descriptor_trees setObject:descriptors forKey:type_key];
        [file_descriptor_name_maps setObject:[NSDictionary dictionary] forKey:type_key];
        [descriptors release];
        [type_key release];
        return YES;
    }
    
    // allocate the resource table
    MHK_rsrc_table_entry* rsrc_table = (MHK_rsrc_table_entry*)calloc(rsrc_table_header.count, sizeof(MHK_rsrc_table_entry));
    if (!rsrc_table)
        return NO;
    
    // read the resource table
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_rsrc_table_entry) * rsrc_table_header.count, rsrc_table, NULL);
    if (err) {
        free(rsrc_table);
        return NO;
    }
    
    // seek to the name table
    err = FSSetForkPosition(forkRef, fsFromStart, resource_directory_absolute_offset + type_table_entry->name_table_rsrc_dir_offset);
    if (err) {
        free(rsrc_table);
        return NO;
    }
    
    // read the name table header
    MHK_name_table_header name_table_header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_name_table_header), &name_table_header, NULL);
    if (err) {
        free(rsrc_table);
        return NO;
    }
    MHK_name_table_header_fton(&name_table_header);
    
    // read the name table if there are any entries
    MHK_name_table_entry* name_table = NULL;
    if (name_table_header.count > 0 && name_list) {
        // allocate the name table
        name_table = (MHK_name_table_entry*)calloc(name_table_header.count, sizeof(MHK_name_table_entry));
        if (!name_table) {
            free(rsrc_table);
            return NO;
        }
        
        // read the name table
        err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_name_table_entry) * name_table_header.count, name_table, NULL);
        if (err) {
            free(name_table);
            free(rsrc_table);
            return NO;
        }
        
        // swap the name table entries
        uint16_t name_table_entry_index = 0;
        for (; name_table_entry_index < name_table_header.count; name_table_entry_index++)
            MHK_name_table_entry_fton(name_table + name_table_entry_index);
    }
    
    // we now have all the information we need to build the file descriptors
    id* file_descriptors = calloc(rsrc_table_header.count, sizeof(id));
    if (!file_descriptors) {
        free(name_table);
        free(rsrc_table);
        return NO;
    }
    
    // allocate the descriptor binary tree entries
    struct descriptor_binary_tree* descriptor_tree = calloc(rsrc_table_header.count, sizeof(struct descriptor_binary_tree));
    
    // allocate the name map right now since we'll build it as we go over the resources
    NSMutableDictionary* name_map = [[NSMutableDictionary alloc] init];
    
    // iterate over the resources
    uint16_t resource_index = 0;
    for (; resource_index < rsrc_table_header.count; resource_index++) {
        // get the resource table entry and swap it
        MHK_rsrc_table_entry* rsrc_entry = rsrc_table + resource_index;
        MHK_rsrc_table_entry_fton(rsrc_entry);
        
        // get the corresponding file table entry. WARNING: rsrc_entry->index IS 1 BASED
        MHK_file_table_entry* file_entry = file_table + rsrc_entry->index - 1;
        
        // attempt to find a resource name
        NSString* file_name = nil;
        if (name_table) {
            // attempt to do a quick "parallel array" lookup
            if (resource_index < name_table_header.count && name_table[resource_index].index == rsrc_entry->index) {
                // we found a matching name table entry
                char* c_name = name_list + name_table[resource_index].name_list_offset;
                file_name = [[NSString alloc] initWithBytes:c_name length:strlen(c_name) encoding:NSASCIIStringEncoding];
            } else {
                uint16_t name_index = 0;
                for (; name_index < name_table_header.count; name_index++) {
                    if (name_table[name_index].index == rsrc_entry->index) {
                        // we found a matching name table entry
                        char* c_name = name_list + name_table[name_index].name_list_offset;
                        file_name = [[NSString alloc] initWithBytes:c_name length:strlen(c_name) encoding:NSASCIIStringEncoding];
                        break;
                    }
                }
            }
        }
        
        // generate the file descriptor dictionary
        NSNumber* file_index_number = [[NSNumber alloc] initWithUnsignedShort:rsrc_entry->index];
        NSNumber* file_id_number = [[NSNumber alloc] initWithUnsignedShort:rsrc_entry->id];
        NSNumber* file_offset_number = [[NSNumber alloc] initWithUnsignedLong:file_entry->absolute_offset];
        
        NSMutableDictionary* file_descriptor = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
            file_index_number, @"Index",
            file_id_number, @"ID",
            file_offset_number, @"Offset",
            file_name, @"Name",
            nil];
        file_descriptors[resource_index] = file_descriptor;
        
        // release objects
        [file_index_number release];
        [file_id_number release];
        [file_offset_number release];
        [file_name release];
        
        // generate a descriptor binary tree entry
        descriptor_tree[resource_index].resource_id = rsrc_entry->id;
        descriptor_tree[resource_index].descriptor = file_descriptor;
        
        // if the resource has a name, map its name to its descriptor
        if (file_name)
            [name_map setObject:file_descriptor forKey:[file_name lowercaseString]];
    }
    
    // create the dictionary key for this resource type
    NSString* type_key = [[NSString alloc] initWithBytes:type_table_entry->name length:4 encoding:NSASCIIStringEncoding];
    
    // create an array from all the file descriptors and set it for the type
    NSArray* descriptors = [[NSArray alloc] initWithObjects:file_descriptors count:rsrc_table_header.count];
    [file_descriptor_arrays setObject:descriptors forKey:type_key];
    [descriptors release];
    
    // release every descriptor dictionary
    for (resource_index = 0; resource_index < rsrc_table_header.count; resource_index++)
        [file_descriptors[resource_index] release];
    
    // in order to be able to perform binary searching, we need to sort the descriptor tree entries
    // i'm guessing they will most likely already be sorted, so mergesort should be the fastest (and we've got plenty of ram now)
    mergesort(descriptor_tree, rsrc_table_header.count, sizeof(struct descriptor_binary_tree), &__descriptor_binary_tree_compare);
    
    // store the sorted array in a NSData, then associate to type with the trees dictionary
    NSMutableData* descriptor_tree_data = [[NSMutableData alloc] initWithBytesNoCopy:descriptor_tree
                                                                              length:rsrc_table_header.count * sizeof(struct descriptor_binary_tree)
                                                                        freeWhenDone:YES];
    [file_descriptor_trees setObject:descriptor_tree_data forKey:type_key];
    [descriptor_tree_data release];
    
    // associated the name map with the resource type key
    [file_descriptor_name_maps setObject:name_map forKey:type_key];
    [name_map release];
    
    // release the resource type dictionary key
    [type_key release];
    
    // free allocated memory
    if (file_descriptors)
        free(file_descriptors);
    if (name_table)
        free(name_table);
    if (rsrc_table)
        free(rsrc_table);
    
    return YES;
}

- (BOOL)load_mhk {
    OSStatus err = noErr;
    uint32_t table_iterator = 0;
    
    // if we've already been initialzed, return
    if (initialized)
        return YES;
    
#if defined(DEBUG) && DEBUG > 1
    fprintf(stderr, "loading %s\n", [[[self url] path] UTF8String]);
#endif
    
    // seek to start
    err = FSSetForkPosition(forkRef, fsFromStart, 0);
    if (err)
        return NO;
    
    // read the MHWK header
    MHK_chunk_header header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_chunk_header), &header, NULL);
    if (err)
        return NO;
    MHK_chunk_header_fton(&header);
    
    // check the header
    if (*(uint32_t *)header.signature != MHK_MHWK_signature_integer || header.content_length != archive_size - sizeof(MHK_chunk_header))
        return NO;
    
    // read the rsrc header
    MHK_RSRC_header rsrc_header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_RSRC_header), &rsrc_header, NULL);
    if (err)
        return NO;
    MHK_RSRC_header_fton(&rsrc_header);
    
    // check the rsrc header
    if (*(uint32_t *)rsrc_header.signature != MHK_RSRC_signature_integer || rsrc_header.total_archive_size != archive_size)
        return NO;
    
    // cache the information we'll really need
    resource_directory_absolute_offset = rsrc_header.rsrc_dir_absolute_offset;
    
    // seek to the type table, which is always at the beginning of the resource directory
    err = FSSetForkPosition(forkRef, fsFromStart, resource_directory_absolute_offset);
    if (err)
        return NO;
    
    // read the type table header
    MHK_type_table_header type_table_header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_type_table_header), &type_table_header, NULL);
    if (err)
        return NO;
    MHK_type_table_header_fton(&type_table_header);
    
    // allocate the type table
    type_table_count = type_table_header.count;
    type_table = (MHK_type_table_entry*)calloc(type_table_count, sizeof(MHK_type_table_entry));
    if (!type_table)
        return NO;
    
    // read the type table
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_type_table_entry) * type_table_count, type_table, NULL);
    if (err)
        return NO;
    
    // check if we have a resource name list
    if (type_table_header.rsrc_name_list_rsrc_dir_offset < rsrc_header.file_table_rsrc_dir_offset) {
        uint32_t name_list_length = rsrc_header.file_table_rsrc_dir_offset - type_table_header.rsrc_name_list_rsrc_dir_offset;
        
        name_list = (char*)malloc(name_list_length);
        if (!name_list)
            return NO;
        
        // seek to the resource name list
        err = FSSetForkPosition(forkRef, fsFromStart, resource_directory_absolute_offset + type_table_header.rsrc_name_list_rsrc_dir_offset);
        if (err)
            return NO;
        
        // read the resource name list
        err = FSReadFork(forkRef, fsAtMark, 0, name_list_length, name_list, NULL);
        if (err)
            return NO;
    } else
        name_list = NULL;
    
    // seek to the file table
    err = FSSetForkPosition(forkRef, fsFromStart, resource_directory_absolute_offset + rsrc_header.file_table_rsrc_dir_offset);
    if (err)
        return NO;
    
    // read the file table header
    MHK_file_table_header file_table_header;
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_file_table_header), &file_table_header, NULL);
    if (err)
        return NO;
    MHK_file_table_header_fton(&file_table_header);
    
    // consistency check
    if (rsrc_header.total_file_table_size != sizeof(MHK_file_table_header) + file_table_header.count * sizeof(MHK_file_table_entry))
        return NO;
    
    // allocate the file table
    file_table_count = file_table_header.count;
    file_table = (MHK_file_table_entry *)calloc(file_table_count, sizeof(MHK_file_table_entry));
    if (!file_table)
        return NO;
    
    // read the file table
    err = FSReadFork(forkRef, fsAtMark, 0, sizeof(MHK_file_table_entry) * file_table_count, file_table, NULL);
    if (err)
        return NO;
    
    // swap the file table entries
    for (table_iterator = 0; table_iterator < file_table_count; table_iterator++)
        MHK_file_table_entry_fton(file_table + table_iterator);
    
    // allocate descriptor arrays dictionary
    file_descriptor_arrays = [[NSMutableDictionary alloc] initWithCapacity:type_table_count];
    if (!file_descriptor_arrays)
        return NO;
    
    // allocate descriptor trees dictionary
    file_descriptor_trees = [[NSMutableDictionary alloc] initWithCapacity:type_table_count];
    if (!file_descriptor_trees)
        return NO;
    
    // allocate the descriptor name maps dictionary
    file_descriptor_name_maps = [[NSMutableDictionary alloc] initWithCapacity:type_table_count];
    if (!file_descriptor_name_maps)
        return NO;
    
    // process each type in the archive
    for (table_iterator = 0; table_iterator < type_table_count; table_iterator++) {
        if (![self load_mhk_type:table_iterator])
            return NO;
    }
    
    // compute the file lengths since MHK have bogus values
    [self compute_file_lengths];
    
    // we don't need the global tables anymore
    if (name_list)
        free(name_list);
    name_list = NULL;
    
    free (type_table);
    type_table = NULL;
    
    return YES;
}

#pragma mark -
#pragma mark Public methods

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initWithPath:(NSString*)path error:(NSError**)errorPtr {
    NSURL* url = [[NSURL alloc] initFileURLWithPath:path];
    id archive = [self initWithURL:url error:errorPtr];
    [url release];
    return archive;
}

- (id)initWithURL:(NSURL*)url error:(NSError**)errorPtr {
    self = [super init];
    if (!self)
        return nil;
    
    OSStatus err = noErr;
    
    // secure clean up
    file_descriptor_arrays = nil;
    file_descriptor_trees = nil;
    __open_files = 0;
    
    // when this is YES, the load methods will just exit
    initialized = NO;
    
    // cache the file url
    mhk_url = [url copy];
    
    // get the data fork name
    HFSUniStr255 dataForkName;
    err = FSGetDataForkName(&dataForkName);
    if (err)
        ReturnFromInitWithError(NSOSStatusErrorDomain, err, nil, errorPtr);
    
    // get an FSRef for the Mohak archive
    FSRef archiveRef;
    if (!CFURLGetFSRef((CFURLRef)mhk_url, &archiveRef))
        ReturnFromInitWithError(NSOSStatusErrorDomain, fnfErr, nil, errorPtr);
    
    // open the data fork in read-only mode
    forkRef = 0;
    err = FSOpenFork(&archiveRef, dataForkName.length, dataForkName.unicode, fsRdPerm, &forkRef);
    if (err)
        ReturnFromInitWithError(NSOSStatusErrorDomain, err, nil, errorPtr);
    
    // get the file size
    SInt64 fork_size = 0;
    err = FSGetForkSize(forkRef, &fork_size);
    if (err)
        ReturnFromInitWithError(NSOSStatusErrorDomain, err, nil, errorPtr);
    
    // we only support 32 bits for archive sizes
    if (fork_size > ULONG_MAX)
        ReturnFromInitWithError(MHKErrorDomain, errFileTooLarge, nil, errorPtr);
    archive_size = (uint32_t)fork_size;
    
    // process the archive
    if (![self load_mhk])
        ReturnFromInitWithError(MHKErrorDomain, errBadArchive, nil, errorPtr);
    
    // allocate the sound descriptor cache and its rw lock
    pthread_rwlock_init(&__cached_sound_descriptors_rwlock, NULL);
    __cached_sound_descriptors = [[NSMutableDictionary alloc] initWithCapacity:[[file_descriptor_arrays objectForKey:@"tWAV"] count]];
    
    // prepare the open files mutex
    pthread_mutex_init(&__open_files_mutex, NULL);
    
    initialized = YES;
    return self;
}

- (void)dealloc {
    // free memory resources
    [__cached_sound_descriptors release];
    pthread_rwlock_destroy(&__cached_sound_descriptors_rwlock);
    pthread_mutex_destroy(&__open_files_mutex);
    
    [file_descriptor_trees release];
    [file_descriptor_arrays release];
    [file_descriptor_name_maps release];
    
    if (file_table)
        free(file_table);
    if (name_list)
        free(name_list);
    if (type_table)
        free(type_table);
    
    [mhk_url release];
    
    // close the file
    if (forkRef)
        FSCloseFork(forkRef);
    
    [super dealloc];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %@", [super description], [mhk_url path]];
}

#pragma mark -

- (NSDictionary*)resourceDescriptorWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
    NSMutableData* binary_tree_data = [file_descriptor_trees objectForKey:type];
    if (!binary_tree_data)
        return nil;
    
    uint16_t n = (uint16_t)[[file_descriptor_arrays objectForKey:type] count];
    struct descriptor_binary_tree* binary_tree = [binary_tree_data mutableBytes];
    
    if (n == 0)
        return nil;
    
    uint16_t l = 0;
    uint16_t r = n - 1;
    
    // binary search for the requested ID
    while (l <= r) {
        uint16_t m = l + (r - l) / 2;
        if (resourceID == binary_tree[m].resource_id) {
            NSMutableDictionary* descriptor = binary_tree[m].descriptor;
            
            if (![descriptor objectForKey:@"Length"]) {
                MHK_file_table_entry* file_entry = file_table + [[descriptor objectForKey:@"Index"] unsignedIntValue] - 1;
                uint32_t file_size = compute_file_table_entry_length(file_entry);
                [descriptor setObject:[NSNumber numberWithUnsignedInt:file_size] forKey:@"Length"];
            }
            
            return [[descriptor copy] autorelease];
        } else if (resourceID < binary_tree[m].resource_id) {
            if (m == 0)
                return nil;
            else r = m - 1;
        } else
            l = m + 1;
    }
    
    return nil;
}

- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
    NSDictionary* descriptor = [self resourceDescriptorWithResourceType:type ID:resourceID];
    if (!descriptor)
        return nil;
    
    MHKFileHandle* fh = [[MHKFileHandle alloc] _initWithArchive:self fork:forkRef descriptor:descriptor];
    if (fh)
        [self performSelector:@selector(_fileDidAlloc)];
    return [fh autorelease];
}

- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
    NSDictionary *descriptor = [self resourceDescriptorWithResourceType:type ID:resourceID];
    if (!descriptor)
        return nil;
    
    MHKFileHandle* fh = [[MHKFileHandle alloc] _initWithArchive:self fork:forkRef descriptor:descriptor];
    if (fh)
        [self performSelector:@selector(_fileDidAlloc)];
    else
        return nil;
    
    void* buffer = malloc((size_t)[fh length]);
    if (!buffer) {
        [fh release];
        return nil;
    }
    
    if ([fh readDataToEndOfFileInBuffer:buffer error:NULL] == -1) {
        free(buffer);
        [fh release];
        return nil;
    }
    
    NSData* resourceData = [[NSData alloc] initWithBytesNoCopy:buffer length:[fh length] freeWhenDone:YES];
    
    [fh release];
    return [resourceData autorelease];
}

- (NSDictionary*)resourceDescriptorWithResourceType:(NSString*)type name:(NSString*)name {
    return [[file_descriptor_name_maps objectForKey:type] objectForKey:[name lowercaseString]];
}

- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type name:(NSString*)name {
    NSDictionary* descriptor = [self resourceDescriptorWithResourceType:type name:name];
    if (!descriptor)
        return nil;
    
    MHKFileHandle* fh = [[MHKFileHandle alloc] _initWithArchive:self fork:forkRef descriptor:descriptor];
    if (fh)
        [self performSelector:@selector(_fileDidAlloc)];
    return [fh autorelease];
}

- (NSData*)dataWithResourceType:(NSString*)type name:(NSString*)name {
    MHKFileHandle* fh = [self openResourceWithResourceType:type name:name];
    if (!fh)
        return nil;
    
    void* buffer = malloc((size_t)[fh length]);
    if (!buffer)
        return nil;
    
    if ([fh readDataToEndOfFileInBuffer:buffer error:NULL] == -1) {
        free(buffer);
        return nil;
    }
    
    return [[[NSData alloc] initWithBytesNoCopy:buffer length:[fh length] freeWhenDone:YES] autorelease];
}

- (void)_fileDidAlloc {
    pthread_mutex_lock(&__open_files_mutex);
    __open_files++;
    if (__open_files == 1)
        [self retain];
    pthread_mutex_unlock(&__open_files_mutex);
}

- (void)_fileDidDealloc {
    pthread_mutex_lock(&__open_files_mutex);
    __open_files--;
    if (__open_files == 0)
        [self autorelease];
    pthread_mutex_unlock(&__open_files_mutex);
}

#pragma mark -
#pragma mark KVC methods

- (NSURL*)url {
    return mhk_url;
}

- (NSArray*)resourceTypes {
    return [file_descriptor_arrays allKeys];
}

- (id)valueForUndefinedKey:(NSString*)key {
    return [file_descriptor_arrays objectForKey:key];
}

@end
