/*
 
 File: ImagePreviewCell.m
 
 Abstract: Provides a cell implementation that draws an image, title, 
 sub-title, and has a custom trackable button that highlights
 when the mouse moves over it.
 
 Version: 1.0
 
 Disclaimer: IMPORTANT:	 This Apple software is supplied to you by Apple
 Computer, Inc. ("Apple") in consideration of your agreement to the
 following terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of these
 terms.	 If you do not agree with these terms, please do not use,
 install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software. 
 Neither the name, trademarks, service marks or logos of Apple Computer,
 Inc. may be used to endorse or promote products derived from the Apple
 Software without specific prior written permission from Apple.	 Except
 as expressly stated in this notice, no other rights or licenses, express
 or implied, are granted by Apple herein, including but not limited to
 any patent rights that may be infringed by your derivative works or by
 other works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright ¬© 2006 Apple Computer, Inc., All Rights Reserved
 
 */ 

#import "ImagePreviewCell.h"

@implementation ImagePreviewCell

- (id)init {
	self = [super init];
	if (self != nil) {
		[self setLineBreakMode:NSLineBreakByTruncatingTail];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	self = [super initWithCoder:aDecoder];
	return self;
}

// NSTableView likes to copy a cell before tracking -- therefore we need to properly implement copyWithZone.
- (id)copyWithZone:(NSZone *)zone {
	ImagePreviewCell* result = [super copyWithZone:zone];
	if (result != nil) {
		// We must clear out the image beforehand; otherwise, it would contain the previous image (which wouldn't be retained), 
		// and doing the setImage: would be a nop since it is the same image. This would eventually lead to a crash after you click on the cell 
		// in a tableview, since it copies the cell at that time, and later releases it.
		result->_image = nil;
		result->_subTitle = nil;
		[result setImage:[self image]];
		[result setSubTitle:[self subTitle]];
	}
	return result;
}

- (void)dealloc {
	[_image release];
	[_subTitle release];
	[super dealloc];
}

- (NSImage *)image {
	return _image;
}

- (void)setImage:(NSImage *)image {
	if (image != _image) {
		[_image release];
		_image = [image retain];
	}
}

- (NSString *)subTitle {
	return _subTitle;
}

- (void)setSubTitle:(NSString *)subTitle {
	if ((_subTitle == nil) || ![_subTitle isEqualToString:subTitle]) {
		[_subTitle release];
		_subTitle = [subTitle retain];
	}
}

- (NSAttributedString *)attributedStringValue {
	NSAttributedString* result = [super attributedStringValue];
	if ([self isHighlighted]) {
		NSMutableAttributedString* mutableResult = [result mutableCopy];
		
		NSFont* boldFont = [[NSFontManager sharedFontManager] fontWithFamily:@"Lucida Grande" traits:0 weight:9 size:13.];
		NSColor* whiteColor = [NSColor whiteColor];
		
		NSShadow* shadow = [[[NSShadow allocWithZone:nil] init] autorelease];
		[shadow setShadowOffset:NSMakeSize(0.0, -1.0)];
		[shadow setShadowBlurRadius:0.1];
		[shadow setShadowColor:[[NSColor shadowColor] colorWithAlphaComponent:0.2]];
		
		[mutableResult beginEditing];
		{
			[mutableResult addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(0, [result length])];
			[mutableResult addAttribute:NSForegroundColorAttributeName value:whiteColor range:NSMakeRange(0, [result length])];
			[mutableResult addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, [result length])];
		}
		[mutableResult endEditing];
		
		return [mutableResult autorelease];
	} else {
		NSMutableAttributedString* mutableResult = [result mutableCopy];
		
		NSFont* boldFont = [[NSFontManager sharedFontManager] fontWithFamily:@"Lucida Grande" traits:0 weight:5 size:13.];
		[mutableResult beginEditing];
		{
			[mutableResult addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(0, [result length])];
		}
		[mutableResult endEditing];
		
		return [mutableResult autorelease];
	}
	
	return result;
}

- (NSAttributedString *)attributedSubTitle {
	NSAttributedString* result = nil;
	if (_subTitle) {
		NSDictionary* attrs = nil;
		if ([self isHighlighted]) {
			NSShadow* shadow = [[[NSShadow allocWithZone:nil] init] autorelease];
			[shadow setShadowOffset:NSMakeSize(0.0, -1.0)];
			[shadow setShadowBlurRadius:0.1];
			[shadow setShadowColor:[[NSColor shadowColor] colorWithAlphaComponent:0.2]];
			
			attrs = [NSDictionary dictionaryWithObjectsAndKeys:
				[[NSFontManager sharedFontManager] fontWithFamily:@"Lucida Grande" traits:0 weight:9 size:11.], NSFontAttributeName,
				[NSColor whiteColor], NSForegroundColorAttributeName,
				shadow, NSShadowAttributeName,
				nil];
		} else {
			attrs = [NSDictionary dictionaryWithObjectsAndKeys:
				[[NSFontManager sharedFontManager] fontWithFamily:@"Lucida Grande" traits:0 weight:5 size:11.], NSFontAttributeName,
				[NSColor grayColor], NSForegroundColorAttributeName,
				nil];
		}
		
		result = [[NSAttributedString alloc] initWithString:_subTitle attributes:attrs];
	}
	
	return [result autorelease];
}

#define PADDING_BEFORE_IMAGE 5.0
#define PADDING_BETWEEN_TITLE_AND_IMAGE 8.0
#define VERTICAL_PADDING_FOR_IMAGE 4.0

- (NSRect)rectForSubTitleBasedOnTitleRect:(NSRect)titleRect inBounds:(NSRect)bounds {
	NSAttributedString* subTitle = [self attributedSubTitle];
	if (subTitle != nil) {
		titleRect.origin.y += titleRect.size.height;
		titleRect.size.width = [subTitle size].width;
		// Make sure it doesn't go past the bounds
		CGFloat amountPast = NSMaxX(titleRect) - NSMaxX(bounds);
		if (amountPast > 0) {
			titleRect.size.width -= amountPast;
		}
		return titleRect;
	} else {
		return NSZeroRect;
	}
}

- (NSRect)subTitleRectForBounds:(NSRect)bounds {
	NSRect titleRect = [self titleRectForBounds:bounds];
	return [self rectForSubTitleBasedOnTitleRect:titleRect inBounds:bounds];
}
	
- (NSRect)imageRectForBounds:(NSRect)bounds {
	NSRect result = bounds;
	result.origin.y += VERTICAL_PADDING_FOR_IMAGE;
	result.origin.x += PADDING_BEFORE_IMAGE;
	if (_image != nil) { 
		// Take the actual image and center it in the result
		result.size = [_image size];
		CGFloat widthCenter = [_image size].width - NSWidth(result);
		if (widthCenter > 0) {
			result.origin.x += round(widthCenter / 2.0);
		}
		CGFloat heightCenter = [_image size].height - NSHeight(result);
		if (heightCenter > 0) {
			result.origin.y += round(heightCenter / 2.0);
		}
	} else {
		result.size.width = result.size.height = 0.0;
	}		 
	return result;
}

- (NSRect)titleRectForBounds:(NSRect)bounds {
	NSAttributedString* title = [self attributedStringValue];
	NSAttributedString* subTitle = [self attributedSubTitle];
	NSRect result = bounds;
	
	// The x origin is easy
	result.origin.x += PADDING_BEFORE_IMAGE + [_image size].width + PADDING_BETWEEN_TITLE_AND_IMAGE;
	
	// The y origin should be inline with the image
	//result.origin.y += VERTICAL_PADDING_FOR_IMAGE;
	result.origin.y += ([_image size].height / 2.0) - (([title size].height / 2.0) + ([subTitle size].height / 2.0));
	
	// Set the width and the height based on the texts real size. Notice the nil check! Otherwise, the resulting NSSize could be undefined if we messaged a nil object.
	if (title != nil) {
		result.size = [title size];
	} else {
		result.size = NSZeroSize;		 
	}
	// Now, we have to constrain us to the bounds. The max x we can go to has to be the same as the bounds.
	CGFloat maxX = NSMaxX(bounds);
	CGFloat maxWidth = maxX - NSMinX(result);
	if (maxWidth < 0) maxWidth = 0;
	// Constrain us to these bounds
	result.size.width = MIN(NSWidth(result), maxWidth);
	return result;
}

- (NSSize)cellSizeForBounds:(NSRect)bounds {
	NSSize result;
	// Figure out the natural cell size and confine it to the bounds given
	NSRect titleRect = [self titleRectForBounds:bounds];
	result.width = PADDING_BEFORE_IMAGE + [_image size].width + PADDING_BETWEEN_TITLE_AND_IMAGE + titleRect.size.width;
	result.height = VERTICAL_PADDING_FOR_IMAGE + [_image size].height + VERTICAL_PADDING_FOR_IMAGE;
	// Constrain it to the bounds passed in
	result.width = MIN(result.width, NSWidth(bounds));
	result.height = MIN(result.height, NSHeight(bounds));
	return result;	  
}

- (void)drawInteriorWithFrame:(NSRect)bounds inView:(NSView *)controlView {
	// This code is similar to what is in DateCell.m
	BOOL isKeyAndHighlighted = NO;
	NSWindow* window = [controlView window];
	if ([self isHighlighted] && [window isKeyWindow]) {
		if ([window firstResponder] == controlView) {
			// If our control is the firstResponder, we need to use highlighted text
			isKeyAndHighlighted = YES;			  
		} else if (([(NSControl *)controlView currentEditor] != nil) && ([window firstResponder] == [(NSControl *)controlView currentEditor])) {
			// In addition, if we have an editor, and the firstResponder is that editor, we want to display highlighted text. 
			// Forgetting to do this will cause your text to turn black when editing a different column on that row.
			isKeyAndHighlighted = YES;			  
		}
	}	 
	
	// We have to set the needsHighlightedText flag ourselves because we aren't calling super to do the drawing. 
	// This will properly give us the white highlighted text when using [self attributedStringValue].
	_cFlags.needsHighlightedText = isKeyAndHighlighted;
	
	NSRect imageRect = [self imageRectForBounds:bounds];
	if (_image != nil) {
		[_image setFlipped:[controlView isFlipped]];
		[_image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	} else {
		NSBezierPath* path = [NSBezierPath bezierPathWithRect:imageRect];
		CGFloat pattern[2] = { 4.0, 2.0 };
		[path setLineDash:pattern count:2 phase:1.0];
		[path setLineWidth:0];
		[[NSColor grayColor] set];
		[path stroke];
	}
	
	NSRect titleRect = [self titleRectForBounds:bounds];
	NSAttributedString* title = [self attributedStringValue];
	if ([title length] > 0) {
		[title drawInRect:titleRect];
	}
	
	NSAttributedString* attributedSubTitle = [self attributedSubTitle];
	if ([attributedSubTitle length] > 0) {
		NSRect attributedSubTitleRect = [self rectForSubTitleBasedOnTitleRect:titleRect inBounds:bounds];
		[attributedSubTitle drawInRect:attributedSubTitleRect];
	}	   
}

@end
