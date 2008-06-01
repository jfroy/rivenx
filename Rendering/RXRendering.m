//
//	RXRendering.m
//	rivenx
//
//	Created by Jean-Francois Roy on 11/12/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import "RXRendering.h"

const rx_size_t kRXCardViewportSize = {608, 392};
const float kRXCardViewportBorderRatios[2] = {0.5f, 0.75f};

const double kRXTransitionDuration = 0.3;

NSObject<RXWorldViewProtocol>* g_worldView = nil;
