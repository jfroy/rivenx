/*
 *  GL.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 23/01/2010.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#if !defined(RX_GL_H)
#define RX_GL_H

#import <sys/cdefs.h>

__BEGIN_DECLS

#include <stdlib.h>

#if defined(WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include "glew.h"

#if defined(__APPLE__)
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#else
#include <GL/gl.h>
#include <GL/glu.h>
#endif

__END_DECLS

#endif // RX_GL_H
