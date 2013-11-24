//
//  NSString+RXStringAdditions.h
//
//  Copyright 2012 MacStorm. All rights reserved.
//

#import <Foundation/NSString.h>

@interface NSString (RXNSStringAdditions)

//! Calls NSString -compare:options: with NSNumericSearch.
- (NSComparisonResult)rx_numericCompare:(id)rhs;

//! Returns a copy of the receiver with all whitespace and newline characters removed.
- (NSString*)rx_removeWhiteSpaceCharacters;

//! Scans a build string to extract the build prefix and number. For example, given 9F100, the prefix will be 9F and the number 100.
- (BOOL)rx_scanBuildPrefix:(NSString**)prefix number:(NSInteger*)number;

//! Compares the receiver with \a version and returns true if the receiver is older than \a version.
- (BOOL)rx_versionIsOlderThan:(NSString*)version;

/*! Returns a copy of the receiver with \a components appended to the string using \a separator as the separator string. If \a unique is true,
        components are tested for equality and duplicates are removed. */
- (NSString*)rx_appendComponents:(NSArray*)components usingSeparator:(NSString*)separator unique:(BOOL)unique;

/*! Returns a copy of the receiver with the components in \a componentString appended to the string using \a separator as the separator string.
        If \a unique is true, components are tested for equality and duplicates are removed. */
- (NSString*)rx_appendComponentsString:(NSString*)componentsString usingSeparator:(NSString*)separator unique:(BOOL)unique;

@end
