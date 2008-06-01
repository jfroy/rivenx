/*
 *	GL.h
 *	cidnectrl
 *
 *	Created by Jean-Francois Roy on 30/09/2007.
 *	Copyright 2007 Design III Equipe 1. All rights reserved.
 *
 */

#if !defined(GL_H_INCLUDED)
#define GL_H_INCLUDED

#import <sys/cdefs.h>

__BEGIN_DECLS

#include <stdlib.h>

#if defined(WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include "GLee.h"

#if defined(__APPLE__)
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#else
#include <GL/gl.h>
#include <GL/glu.h>
#endif

#if defined(__cplusplus)
}
#endif

#endif // GL_H_INCLUDED
