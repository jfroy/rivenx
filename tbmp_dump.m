//
//  main.m
//  foo
//
//  Created by Jean-Francois Roy on 10/04/2005.
//  Copyright MacStorm 2005. All rights reserved.
//

#import <ApplicationServices/ApplicationServices.h>

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>

#import "mhk_dump_cmd.h"


static void texture_provider_data_release(void *info, const void *data, size_t size) {
    free((void *)data);
}

static void dump_bitmap(MHKArchive *archive, uint16_t tbmp_id) {
    NSError* error = nil;
    
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString *dump_folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Temporary/mhk_bitmap_dump"];
    [fm createDirectoryAtPath:dump_folder attributes:nil];
    
    dump_folder = [dump_folder stringByAppendingPathComponent:[[[archive url] path] lastPathComponent]];
    [fm createDirectoryAtPath:dump_folder attributes:nil];
    
    NSDictionary* resourceDescriptor = [archive resourceDescriptorWithResourceType:@"tBMP" ID:tbmp_id];
    NSDictionary* bmpDescriptor = [archive bitmapDescriptorWithID:tbmp_id error:&error];
    if (!bmpDescriptor || error) {
        NSLog(@"An error in the %@ domain with code %d (%@) has occured.", [error domain], [error code], UTCreateStringForOSType([error code]));
        return;
    }
    
    uint16_t width = [[bmpDescriptor valueForKey:@"Width"] unsignedShortValue];
    uint16_t height = [[bmpDescriptor valueForKey:@"Height"] unsignedShortValue];
    
    uint32_t texture_length = width * height * 4;
    void* texture_buffer = malloc(texture_length);
    [archive loadBitmapWithID:tbmp_id buffer:texture_buffer format:MHK_ARGB_UNSIGNED_BYTE_PACKED error:&error];
    if (error) {
        NSLog(@"An error in the %@ domain with code %d (%@) has occured.", [error domain], [error code], UTCreateStringForOSType([error code]));
        free(texture_buffer);
        return;
    }
    
    NSString* bmp_path_base = [dump_folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", tbmp_id]];
    NSString* bmp_name = [resourceDescriptor objectForKey:@"Name"];
    if (bmp_name)
        bmp_path_base = [bmp_path_base stringByAppendingFormat:@" - %@", bmp_name];
    
    bmp_path_base = [bmp_path_base stringByAppendingPathExtension:@"tiff"];
    NSURL* bmp_url = [NSURL fileURLWithPath:bmp_path_base];
    if (!bmp_url) {
        NSLog(@"The output URL failed to allocate!");
        free(texture_buffer);
        return;
    }
    
    CGImageDestinationRef imageDestRef = CGImageDestinationCreateWithURL((CFURLRef)bmp_url, kUTTypeTIFF, 1, NULL);
    if (!imageDestRef) {
        NSLog(@"Failed to create a CGImageDestinationRef from output URL!");
        free(texture_buffer);
        return;
    }
    
    CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(NULL, texture_buffer, texture_length, &texture_provider_data_release);
    CGColorSpaceRef genericRGBColorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    CGImageRef textureImageRef = CGImageCreate(width, height, 8, 32, width * 4, genericRGBColorSpaceRef, kCGImageAlphaFirst, dataProviderRef, NULL, 0, kCGRenderingIntentDefault);
    
    CFRelease(genericRGBColorSpaceRef);
    CFRelease(dataProviderRef);
    
    CGImageDestinationAddImage(imageDestRef, textureImageRef, NULL);
    CGImageDestinationFinalize(imageDestRef);
    
    CFRelease(imageDestRef);
    CFRelease(textureImageRef);
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    NSError* error = nil;
    
    MHKArchive* archive = [[MHKArchive alloc] initWithPath:[NSString stringWithUTF8String:argv[1]] error:&error];
    uint16_t tbmp_id = 539;
    
    dump_bitmap(archive, tbmp_id);
    
    [archive release];
    [p release];
    return 0;
}
