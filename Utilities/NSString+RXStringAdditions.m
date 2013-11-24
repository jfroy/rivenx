//
//  NSString+RXStringAdditions.m
//
//  Copyright 2012 MacStorm. All rights reserved.
//

#import "NSString+RXStringAdditions.h"

#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSScanner.h>

@implementation NSString (RXNSStringAdditions)

- (NSComparisonResult)rx_numericCompare:(id)rhs { return [self compare:rhs options:NSNumericSearch]; }

- (NSString*)rx_removeWhiteSpaceCharacters
{
  NSCharacterSet* characters = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  NSMutableString* result = [self mutableCopy];

  NSRange range = [result rangeOfCharacterFromSet:characters];
  while (range.location != NSNotFound) {
    [result deleteCharactersInRange:range];
    range = [result rangeOfCharacterFromSet:characters];
  }

  return [result autorelease];
}

- (BOOL)rx_scanBuildPrefix:(NSString**)prefix number:(NSInteger*)number
{
  // extract the build number prefix
  NSScanner* scanner = [NSScanner scannerWithString:self];
  if ([scanner scanInteger:NULL] == NO)
    return NO;

  if ([scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ"] intoString:NULL] == NO)
    return NO;

  if (prefix)
    *prefix = [self substringToIndex:[scanner scanLocation]];

  if ([scanner scanInteger:number] == NO)
    return NO;

  return YES;
}

- (BOOL)rx_versionIsOlderThan:(NSString*)version { return [self compare:version options:NSNumericSearch] == NSOrderedAscending; }

- (NSString*)rx_appendComponents:(NSArray*)components usingSeparator:(NSString*)separator unique:(BOOL)unique
{
  NSArray* base_components = nil;
  if ([self length] > 0u)
    base_components = [self componentsSeparatedByString:separator];

  NSArray* merged_components;
  if (unique) {
    NSMutableSet* components_set = [NSMutableSet new];
    NSMutableArray* mutable_components = [NSMutableArray new];
    NSArray* arrays[2] = {base_components, components};

    for (size_t i = 0; i < ARRAY_LENGTH(arrays); ++i) {
      NSArray* array = arrays[i];
      if (array == nil)
        continue;

      for (NSString* component in array) {
        if ([components_set containsObject:component] == NO) {
          [mutable_components addObject:component];
          [components_set addObject:component];
        }
      }
    }

    [components_set release];
    merged_components = [mutable_components autorelease];
  } else {
    if ([base_components count] > 0u)
      merged_components = [base_components arrayByAddingObjectsFromArray:components];
    else
      merged_components = components;
  }

  return [merged_components componentsJoinedByString:separator];
}

- (NSString*)rx_appendComponentsString:(NSString*)componentsString usingSeparator:(NSString*)separator unique:(BOOL)unique
{
  if ([componentsString length] == 0u)
    return self;
  else
    return [self rx_appendComponents:[componentsString componentsSeparatedByString:separator] usingSeparator:separator unique:unique];
}

@end
