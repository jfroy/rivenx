//
//	RXExceptions.m
//	rivenx
//
//	Created by Jean-Francois RoyJean-Francois Roy on 7/27/07.
//	Copyright 2007 Apple, Inc. All rights reserved.
//

#import "RXErrors.h"

NSString* const RXErrorDomain = @"RXErrorDomain";

NSException* RXArchiveManagerArchiveNotFoundExceptionWithArchiveName(NSString* name) {
	return [NSException exceptionWithName:@"RXArchiveManagerArchiveNotFoundException" reason:[NSString stringWithFormat:@"RXArchiveManager could not find \"%@\".", name] userInfo:nil];
}
