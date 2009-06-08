//
//  NSFontAdditions.m
//  rivenx
//
//  Created by Jean-Francois Roy on 05/09/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import <ApplicationServices/ApplicationServices.h>
#import "NSFontAdditions.h"


@implementation NSFont (NSFontAdditions)

+ (NSFont *)fontWithURL:(NSURL *)fontURL name:(NSString *)fontName size:(float)fontSize {
    if (!fontURL) [NSException raise:NSInvalidArgumentException format:@"nil font URL"];
    
    // URL to FSRef
    FSRef fontRef;
    if (!CFURLGetFSRef((CFURLRef)fontURL, &fontRef)) return nil;
    
    // FSRef to FSSpec
    FSSpec fontSpec;
    OSStatus err = FSGetCatalogInfo(&fontRef, kFSCatInfoNone, NULL, NULL, &fontSpec, NULL);
    if (err) return nil;
    
    // activate font using ATS
    ATSFontContainerRef fontContainer;
    err = ATSFontActivateFromFileSpecification(&fontSpec, kATSFontContextLocal, kATSFontFormatUnspecified, NULL, kATSOptionFlagsDefault, &fontContainer);
    if (err) return nil;
    
    // how many fonts were contained in that file?
    ItemCount fontCount;
    err = ATSFontFindFromContainer(fontContainer, kATSOptionFlagsDefault, 0, NULL, &fontCount);
    if (err) return nil;
    
    // allocate font array and retrive the font refs
    ATSFontRef* fontRefs = (ATSFontRef *)malloc(fontCount * sizeof(ATSFontRef));
    err = ATSFontFindFromContainer(fontContainer, kATSOptionFlagsDefault, fontCount, fontRefs, &fontCount);
    if (err) {
        free(fontRefs);
        return nil;
    }
    
    // if we were asked for a specific font name, iterate to find it
    NSFont* theFont = nil;
    if (fontName) {
        ItemCount currentFontIndex;
        for (currentFontIndex = 0; currentFontIndex < fontCount; currentFontIndex++) {
            CFStringRef postscriptName;
            ATSFontGetPostScriptName(fontRefs[currentFontIndex], kATSOptionFlagsDefault, &postscriptName);
            if ([fontName isEqual:(NSString *)postscriptName]) theFont = [NSFont fontWithName:fontName size:fontSize];
        }
    } else {
        // just return the first font
        CFStringRef postscriptName;
        ATSFontGetPostScriptName(fontRefs[0], kATSOptionFlagsDefault, &postscriptName);
        theFont = [NSFont fontWithName:(NSString*)postscriptName size:fontSize];
    }
    
    free(fontRefs);
    return theFont;
}

@end
