#import "Base/RXBase.h"
#import <MHKKit/MHKKit.h>

#import <getopt.h>

#define BUFFER_OFFSET(buffer, bytes) (__typeof__(buffer))((uint8_t*)(buffer) + (bytes))
#define BUFFER_NOFFSET(buffer, bytes) (__typeof__(buffer))((uint8_t*)(buffer) - (bytes))

#pragma options align=packed
struct _vars_record {
    uint32_t u0;
    uint32_t u1;
    uint32_t value;
};
#pragma options align=reset

// courtesy RXStack
static NSArray* _loadNAMEResourceWithID(MHKArchive* archive, uint16_t resourceID) {
    NSData* nameData = [archive dataWithResourceType:@"NAME" ID:resourceID];
    if (!nameData) return nil;
    
    uint16_t recordCount = CFSwapInt16BigToHost(*(const uint16_t *)[nameData bytes]);
    NSMutableArray* recordArray = [[NSMutableArray alloc] initWithCapacity:recordCount];
    
    const uint16_t* offsetBase = (uint16_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t));
    const uint8_t* stringBase = (uint8_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t) + (sizeof(uint16_t) * 2 * recordCount));
    
    uint16_t currentRecordIndex = 0;
    for (; currentRecordIndex < recordCount; currentRecordIndex++) {
        uint16_t recordOffset = CFSwapInt16BigToHost(offsetBase[currentRecordIndex]);
        const unsigned char* entryBase = (const unsigned char *)stringBase + recordOffset;
        size_t recordLength = strlen((const char *)entryBase);
        
        // check for leading and closing 0xbd
        if (*entryBase == 0xbd) {
            entryBase++;
            recordLength--;
        }
        
        if (*(entryBase + recordLength - 1) == 0xbd) recordLength--;
        
        NSString* record = [[NSString alloc] initWithBytes:entryBase length:recordLength encoding:NSASCIIStringEncoding];
        [recordArray addObject:record];
        [record release];
    }
    
    return recordArray;
}

static const char* optString = "p";
static const struct option longOpts[] = {
    { "plist", no_argument, NULL, 'p' },
    { NULL, no_argument, NULL, 0 }
};

int main(int argc, char* argv[]) {
    NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
    
    BOOL plist_output = NO;
    
    int longIndex;
    int opt = getopt_long(argc, argv, optString, longOpts, &longIndex);
    while (opt != -1) {
        switch (opt) {
            case 'p':
                plist_output = YES;
                break;
        }
        
        opt = getopt_long(argc, argv, optString, longOpts, &longIndex);
    }
    
    if (optind == argc) {
        printf("usage: %s [save file 1] [save file 2, ...]\n", argv[0]);
        exit(1);
    }
    
    for (int savei = optind; savei < argc; savei++) {
        NSError* error = nil;
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:[NSString stringWithUTF8String:argv[savei]] error:&error];
        if (!archive) {
            fprintf(stderr, "failed to open archive (%s)\n", [[error description] UTF8String]);
            continue;
        }
        
        NSArray* names = _loadNAMEResourceWithID(archive, 1);
        NSData* varsData = [archive dataWithResourceType:@"VARS" ID:1];
        if (!varsData) {
            fprintf(stderr, "failed to load the VARS resource with ID 1 from the archive\n");
            continue;
        }
        
        NSMutableDictionary* plist = nil;
        if (plist_output)
            plist = [NSMutableDictionary dictionary];
        
        struct _vars_record* vars = (struct _vars_record*)[varsData bytes];
        uint32_t vars_count = [varsData length] / sizeof(struct _vars_record);
        uint32_t vars_index = 0;
        for (; vars_index < [names count]; vars_index++) {
    #if defined(__LITTLE_ENDIAN__)
            vars[vars_index].u0 = CFSwapInt32(vars[vars_index].u0);
            vars[vars_index].u1 = CFSwapInt32(vars[vars_index].u1);
            vars[vars_index].value = CFSwapInt32(vars[vars_index].value);
    #endif
            if (!plist_output)
                printf("%s: u0=%u, u1=%u, value=%u\n", [[names objectAtIndex:vars_index] UTF8String], vars[vars_index].u0, vars[vars_index].u1, vars[vars_index].value);
            else
                [plist setObject:[NSNumber numberWithUnsignedLong:vars[vars_index].value] forKey:[names objectAtIndex:vars_index]];
        }
        
        for (; vars_index < vars_count; vars_index++) {
    #if defined(__LITTLE_ENDIAN__)
            vars[vars_index].u0 = CFSwapInt32(vars[vars_index].u0);
            vars[vars_index].u1 = CFSwapInt32(vars[vars_index].u1);
            vars[vars_index].value = CFSwapInt32(vars[vars_index].value);
    #endif
            if (!plist_output)
                printf("%u: u0=%u, u1=%u, value=%u\n", vars_index, vars[vars_index].u0, vars[vars_index].u1, vars[vars_index].value);
            else 
                [plist setObject:[NSNumber numberWithUnsignedLong:vars[vars_index].value] forKey:[NSString stringWithFormat:@"%u", vars_index]];
        }
        
        if (plist)
            [plist writeToFile:[[[[archive url] path] stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"] atomically:NO];
    }
    
    [p release];
    return 0;
}
