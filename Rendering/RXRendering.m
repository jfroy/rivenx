//
//  RXRendering.m
//  rivenx
//
//  Created by Jean-Francois Roy on 11/12/2005.
//  Copyright 2005 MacStorm. All rights reserved.
//

#import "Rendering/RXRendering.h"


const rx_size_t kRXRendererViewportSize = {640, 480};

const rx_size_t kRXCardViewportSize = {608, 392};
const rx_point_t kRXCardViewportOriginOffset = {16, 66};

const double kRXTransitionDuration = 0.4;

const float kRXSoundGainDivisor = 256.0f;

NSView<RXWorldViewProtocol>* g_worldView = nil;
