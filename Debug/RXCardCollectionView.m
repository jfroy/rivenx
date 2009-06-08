//
//  RXCardCollectionView.m
//  rivenx
//
//  Created by Jean-Francois Roy on 22/01/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <QTKit/QTKit.h>

#import "RXCardCollectionView.h"

#import "Rendering/Graphics/RXMovieProxy.h"
#import "Rendering/Graphics/RXPicture.h"


@implementation RXCardCollectionView

- (NSCollectionViewItem*)newItemForRepresentedObject:(id)object {
    NSView* view = nil;
    if ([object isMemberOfClass:[RXMovie class]] || [object isMemberOfClass:[RXMovieProxy class]]) {
        view = [[QTMovieView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [(QTMovieView*)view setPreservesAspectRatio:YES];
        [(QTMovieView*)view setMovie:[(RXMovie*)object movie]];
    } else if ([object isMemberOfClass:[RXPicture class]]) {
        view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [(NSImageView*)view setImage:[NSApp applicationIconImage]];
        [(NSImageView*)view setImageScaling:NSScaleProportionally];
    }
    
    NSCollectionViewItem* item = [NSCollectionViewItem new];
    [item setRepresentedObject:object];
    [item setView:view];
    [view release];
    return item;
}

@end
