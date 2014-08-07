// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#import "mhk/MHKArchive_Internal.h"

#import <string>
#import <vector>
#import <sys/stat.h>

#import "Base/RXBase.h"
#import "Base/RXErrorMacros.h"

#import "mhk/MHKErrors.h"
#import "mhk/MHKFileHandle_Internal.h"

static uint32_t GetLengthFromFileTableEntry(MHK_file_table_entry* s) {
  uint32_t length = s->size_high;
  length = length << 16;
  length += s->size_low;
  return length;
}

static const NSComparator ResourceIDComparator = ^NSComparisonResult(id lhs, id rhs) {
    MHKResourceDescriptor* lhs_rdesc = lhs;
    MHKResourceDescriptor* rhs_rdesc = rhs;
    if (lhs_rdesc.ID < rhs_rdesc.ID) {
      return NSOrderedAscending;
    } else if (lhs_rdesc.ID == rhs_rdesc.ID) {
      return NSOrderedSame;
    } else {
      return NSOrderedDescending;
    }
};

@implementation MHKResourceDescriptor {
 @package
  uint16_t _ID;
  uint32_t _index;
  NSString* _name;
  off_t _offset;
  off_t _length;
}

- (void)dealloc {
  [_name release];
  [super dealloc];
}

@end

@implementation MHKArchive {
  off_t _archiveSize;

  uint32_t _resourceDirectoryOffset;

  std::vector<MHK_type_table_entry> _typeTable;
  std::vector<MHK_file_table_entry> _fileTable;
  std::string _names;

  // resource descriptors
  NSMutableDictionary* _rdescArrays;
  NSMutableDictionary* _rdescNameMaps;
}

@dynamic resourceTypes;

- (id)init {
  [self doesNotRecognizeSelector:_cmd];
  return [self initWithURL:nil error:nullptr];
}

- (instancetype)initWithURL:(NSURL*)url error:(NSError**)outError {
  self = [super init];
  if (!self) {
    return nil;
  }

  if (!url) {
    [self release];
    return nil;
  }

  _url = [url copy];

  // open in read-only mode
  _fd = open([_url fileSystemRepresentation], O_RDONLY);
  if (_fd == -1) {
    SetErrorToPOSIXError(nil, outError);
    [self release];
    return nil;
  }

  // get the file size
  struct stat st;
  if (fstat(_fd, &st) == -1) {
    SetErrorToPOSIXError(nil, outError);
    [self release];
    return nil;
  }
  _archiveSize = st.st_size;

  // load resource descriptors
  if (![self _loadResourceDescriptors]) {
    [self release];
    ReturnValueWithError(nil, MHKErrorDomain, errBadArchive, nil, outError);
  }

  _sdescs = [[NSMutableDictionary alloc] initWithCapacity:[self resourceDescriptorsForType:@"tWAV"].count];

  return self;
}

- (instancetype)initWithPath:(NSString*)path error:(NSError**)outError {
  NSURL* url = [[NSURL alloc] initFileURLWithPath:path];
  MHKArchive* archive = [self initWithURL:url error:outError];
  [url release];
  return archive;
}

- (void)dealloc {
  if (_fd > 0) {
    close(_fd);
  }

  [_sdescs release];
  [_rdescArrays release];
  [_rdescNameMaps release];
  [_url release];

  [super dealloc];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ %@", [super description], [_url path]];
}

#pragma mark -

- (MHKResourceDescriptor*)resourceDescriptorWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
  NSArray* rdescs = _rdescArrays[type];
  if (!rdescs) {
    return nil;
  }

  MHKResourceDescriptor* search_rdesc = [MHKResourceDescriptor new];
  search_rdesc->_ID = resourceID;
  NSUInteger index = [rdescs indexOfObject:search_rdesc
                             inSortedRange:NSMakeRange(0, rdescs.count)
                                   options:NSBinarySearchingFirstEqual
                           usingComparator:ResourceIDComparator];
  [search_rdesc release];
  return (index == NSNotFound) ? nil : rdescs[index];
}

- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:type ID:resourceID];
  if (!rdesc) {
    return nil;
  }
  return [[[MHKFileHandle alloc] initWithArchive:self
                                          length:rdesc.length
                                   archiveOffset:rdesc.offset
                                        ioOffset:rdesc.offset] autorelease];
}

- (NSData*)dataWithResourceType:(NSString*)type ID:(uint16_t)resourceID {
  MHKFileHandle* fh = [self openResourceWithResourceType:type ID:resourceID];
  return [fh readDataToEndOfFile:nullptr];
}

- (MHKResourceDescriptor*)resourceDescriptorWithResourceType:(NSString*)type name:(NSString*)name {
  return ((NSDictionary*)_rdescNameMaps[type])[[name lowercaseString]];
}

- (MHKFileHandle*)openResourceWithResourceType:(NSString*)type name:(NSString*)name {
  MHKResourceDescriptor* rdesc = [self resourceDescriptorWithResourceType:type name:name];
  if (!rdesc) {
    return nil;
  }
  return [[[MHKFileHandle alloc] initWithArchive:self
                                          length:rdesc.length
                                   archiveOffset:rdesc.offset
                                        ioOffset:rdesc.offset] autorelease];
}

- (NSData*)dataWithResourceType:(NSString*)type name:(NSString*)name {
  MHKFileHandle* fh = [self openResourceWithResourceType:type name:name];
  return [fh readDataToEndOfFile:nullptr];
}

#pragma mark -

- (NSArray*)resourceTypes {
  return [_rdescArrays allKeys];
}

- (NSArray*)resourceDescriptorsForType:(NSString*)type {
  return _rdescArrays[type];
}

#pragma mark -

- (BOOL)_loadResourceDescriptors {
#if defined(DEBUG) && DEBUG > 1
  fprintf(stderr, "loading %s\n", [[[self url] path] UTF8String]);
#endif

  // seek to start
  lseek(_fd, 0, SEEK_SET);

  // read the MHWK header
  MHK_chunk_header header;
  if (read(_fd, &header, sizeof(MHK_chunk_header)) < (ssize_t)sizeof(MHK_chunk_header)) {
    return NO;
  }
  MHK_chunk_header_fton(&header);

  // check the header
  if (header.signature != MHK_MHWK_signature_integer ||
      header.content_length != _archiveSize - sizeof(MHK_chunk_header)) {
    return NO;
  }

  // read the rsrc header
  MHK_RSRC_header rsrc_header;
  if (read(_fd, &rsrc_header, sizeof(MHK_RSRC_header)) < (ssize_t)sizeof(MHK_RSRC_header)) {
    return NO;
  }
  MHK_RSRC_header_fton(&rsrc_header);

  // check the rsrc header
  if (rsrc_header.signature != MHK_RSRC_signature_integer || rsrc_header.total_archive_size != _archiveSize) {
    return NO;
  }

  // cache the information we'll really need
  _resourceDirectoryOffset = rsrc_header.rsrc_dir_absolute_offset;

  // seek to the type table, which is always at the beginning of the resource directory
  lseek(_fd, _resourceDirectoryOffset, SEEK_SET);

  // read the type table header
  MHK_type_table_header type_table_header;
  if (read(_fd, &type_table_header, sizeof(MHK_type_table_header)) < (ssize_t)sizeof(MHK_type_table_header)) {
    return NO;
  }
  MHK_type_table_header_fton(&type_table_header);

  // read the type table
  _typeTable.resize(type_table_header.count);
  ssize_t type_table_bytes = sizeof(MHK_type_table_entry) * type_table_header.count;
  if (read(_fd, &_typeTable.front(), type_table_bytes) < type_table_bytes) {
    return NO;
  }

  // load the resource name list if there is one
  if (type_table_header.rsrc_name_list_rsrc_dir_offset < rsrc_header.file_table_rsrc_dir_offset) {
    uint32_t name_list_length =
        rsrc_header.file_table_rsrc_dir_offset - type_table_header.rsrc_name_list_rsrc_dir_offset;
    _names.resize(name_list_length);

    // seek to the resource name list
    lseek(_fd, _resourceDirectoryOffset + type_table_header.rsrc_name_list_rsrc_dir_offset, SEEK_SET);

    // read the resource name list
    if (read(_fd, &_names.front(), name_list_length) < (ssize_t)name_list_length) {
      return NO;
    }
  }

  // seek to the file table
  lseek(_fd, _resourceDirectoryOffset + rsrc_header.file_table_rsrc_dir_offset, SEEK_SET);

  // read the file table header
  MHK_file_table_header file_table_header;
  if (read(_fd, &file_table_header, sizeof(MHK_file_table_header)) < (ssize_t)sizeof(MHK_file_table_header)) {
    return NO;
  }
  MHK_file_table_header_fton(&file_table_header);

  // consistency check
  if (rsrc_header.total_file_table_size !=
      sizeof(MHK_file_table_header) + file_table_header.count * sizeof(MHK_file_table_entry)) {
    return NO;
  }

  // read the file table
  _fileTable.resize(file_table_header.count);
  ssize_t file_table_bytes = sizeof(MHK_file_table_entry) * file_table_header.count;
  if (read(_fd, &_fileTable.front(), file_table_bytes) < file_table_bytes) {
    return NO;
  }

  // swap the file table entries
  for (auto& file_entry : _fileTable) {
    MHK_file_table_entry_fton(&file_entry);
  }

  // compute the file lengths since MHK have bogus values
  [self _computeFileLengths];

  // allocate descriptor containers
  _rdescArrays = [[NSMutableDictionary alloc] initWithCapacity:_typeTable.size()];
  release_assert(_rdescArrays);
  _rdescNameMaps = [[NSMutableDictionary alloc] initWithCapacity:_typeTable.size()];
  release_assert(_rdescNameMaps);

  // load earch resource type
  for (auto& type_entry : _typeTable) {
    @autoreleasepool {
      if (![self _loadResourceDescriptorsOfType:type_entry]) {
        return NO;
      }
    }
  }

  // don't need the type table anymore
  _typeTable.clear();

  return YES;
}

- (void)_computeFileLengths {
  // if there are no entries, return
  if (_fileTable.size() == 0) {
    return;
  }

  // sort an array of file table entry pointers by archive offset
  std::vector<MHK_file_table_entry*> file_entry_pointers(_fileTable.size());
  for (uint32_t file_table_index = 0; file_table_index < _fileTable.size(); ++file_table_index) {
    file_entry_pointers[file_table_index] = &_fileTable[file_table_index];
  }
  std::sort(
      std::begin(file_entry_pointers),
      std::end(file_entry_pointers),
      [](MHK_file_table_entry* lhs, MHK_file_table_entry* rhs) { return lhs->absolute_offset < rhs->absolute_offset; });

  // compute lengths assuming files are tightly packed in the archive
  auto update_length = [](MHK_file_table_entry& entry, off_t next_entry_offset) {
    off_t file_length = next_entry_offset - entry.absolute_offset;
    entry.size_high = (file_length & 0x00FF0000) >> 16;
    entry.size_low = file_length & 0xFFFF;
  };

  for (auto i = std::begin(file_entry_pointers), end = std::end(file_entry_pointers) - 1; i != end; ++i) {
    update_length(**i, (*(i + 1))->absolute_offset);
  }
  update_length(*file_entry_pointers.back(), _archiveSize);
}

- (BOOL)_loadResourceDescriptorsOfType:(MHK_type_table_entry&)type_entry {
  // swap the type entry
  MHK_type_table_entry_fton(&type_entry);

  // seek to the resource table
  lseek(_fd, _resourceDirectoryOffset + type_entry.rsrc_table_rsrc_dir_offset, SEEK_SET);

  // read the resource table header
  MHK_rsrc_table_header rsrc_table_header;
  if (read(_fd, &rsrc_table_header, sizeof(MHK_rsrc_table_header)) < (ssize_t)sizeof(MHK_rsrc_table_header)) {
    return NO;
  }
  MHK_rsrc_table_header_fton(&rsrc_table_header);

  // create the type key and the resource descriptor arrays
  NSString* type_key =
      [[[NSString alloc] initWithBytes:type_entry.name length:4 encoding:NSASCIIStringEncoding] autorelease];
  NSMutableArray* rdescs = [NSMutableArray arrayWithCapacity:rsrc_table_header.count];
  NSMutableDictionary* rdescNameMap = [NSMutableDictionary dictionaryWithCapacity:rsrc_table_header.count];
  _rdescArrays[type_key] = rdescs;
  _rdescNameMaps[type_key] = rdescNameMap;

  // if there are no resources of this type, we're done
  if (rsrc_table_header.count == 0) {
    return YES;
  }

  // read the resource table
  std::vector<MHK_rsrc_table_entry> rsrc_table(rsrc_table_header.count);
  ssize_t rsrc_table_bytes = sizeof(MHK_rsrc_table_entry) * rsrc_table_header.count;
  if (read(_fd, &rsrc_table.front(), rsrc_table_bytes) < rsrc_table_bytes) {
    return NO;
  }

  // seek to the name table
  lseek(_fd, _resourceDirectoryOffset + type_entry.name_table_rsrc_dir_offset, SEEK_SET);

  // read the name table header
  MHK_name_table_header name_table_header;
  if (read(_fd, &name_table_header, sizeof(MHK_name_table_header)) < (ssize_t)sizeof(MHK_name_table_header)) {
    return NO;
  }
  MHK_name_table_header_fton(&name_table_header);

  // read the name table if there are any entries
  std::vector<MHK_name_table_entry> name_table;
  if (name_table_header.count > 0 && _names.size() > 0) {
    // read the name table
    name_table.resize(name_table_header.count);
    ssize_t name_table_bytes = sizeof(MHK_name_table_entry) * name_table_header.count;
    if (read(_fd, &name_table.front(), name_table_bytes) < name_table_bytes) {
      return NO;
    }

    // swap the name table entries
    for (auto& name_entry : name_table) {
      MHK_name_table_entry_fton(&name_entry);
    }
  }

  // we now have all the information we need to build the resource descriptors

  for (uint16_t resource_index = 0; resource_index < rsrc_table_header.count; ++resource_index) {
    // get the resource table entry and swap it
    MHK_rsrc_table_entry* rsrc_entry = &rsrc_table[resource_index];
    MHK_rsrc_table_entry_fton(rsrc_entry);

    // get the corresponding file table entry
    // NOTE: rsrc_entry->index IS 1 BASED
    MHK_file_table_entry* file_entry = &_fileTable[rsrc_entry->index - 1];

    // attempt to find a resource name
    NSString* resource_name = nil;
    if (name_table.size() > 0) {
      // do a parallel array check first and fallback to a linear search if that fails
      uint16_t name_index;
      if (resource_index < name_table_header.count && name_table[resource_index].index == rsrc_entry->index) {
        name_index = resource_index;
      } else {
        for (name_index = 0; name_index < name_table_header.count; ++name_index) {
          if (name_table[name_index].index == rsrc_entry->index) {
            break;
          }
        }
      }

      // if we found a name, convert it to an NSString (referencing the C string data if possible to avoid a copy)
      if (name_index < name_table_header.count) {
        const char* resource_name_c = _names.data() + name_table[resource_index].name_list_offset;
        resource_name = [[NSString alloc] initWithBytesNoCopy:(void*)resource_name_c
                                                       length:strlen(resource_name_c)
                                                     encoding:NSASCIIStringEncoding
                                                 freeWhenDone:NO];
      }
    }

    // create the resource descriptor
    MHKResourceDescriptor* rdesc = [MHKResourceDescriptor new];
    rdesc->_ID = rsrc_entry->id;
    rdesc->_index = rsrc_entry->index;
    rdesc->_name = resource_name;
    rdesc->_offset = file_entry->absolute_offset;
    rdesc->_length = GetLengthFromFileTableEntry(file_entry);

    [rdescs addObject:rdesc];
    if (resource_name) {
      rdescNameMap[[resource_name lowercaseString]] = rdesc;
    }
    [rdesc release];
  }

  // sort the array of resource descriptors by ID to enable binary searching for by-ID lookups
  [rdescs sortUsingComparator:ResourceIDComparator];

  return YES;
}

@end
