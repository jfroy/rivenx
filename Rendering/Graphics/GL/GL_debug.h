/*
 *  GL_debug.h
 *  cidnectrl
 *
 *  Created by Jean-Francois Roy on 30/09/2007.
 *  Copyright 2007 Design III Equipe 1. All rights reserved.
 *
 */

#if !defined(GL_DEBUG_H_INCLUDED)
#define GL_DEBUG_H_INCLUDED

#include <sys/cdefs.h>

__BEGIN_DECLS

#if defined(DEBUG_GL)

extern void glReportErrorWithFileLine(const char* file, const char* function, const int line);

#if defined(__APPLE__)
#include <OpenGL/CGLTypes.h>

extern void glReportErrorWithFileLineCGLMacro(CGLContextObj cgl_ctx, const char* file, const char* function, const int line);

#if defined(_CGLMACRO_H)
#define glReportError() glReportErrorWithFileLineCGLMacro(cgl_ctx, __FILE__, __PRETTY_FUNCTION__, __LINE__)
#else
#define glReportError() glReportErrorWithFileLine(__FILE__, __PRETTY_FUNCTION__, __LINE__)
#endif // _CGLMACRO_H

#else

#define glReportError() glReportErrorWithFileLine(__FILE__, __PRETTY_FUNCTION__, __LINE__)

#endif // __APPLE__

#else
#define glReportError()
#endif // DEBUG_GL

__END_DECLS

#endif // GL_DEBUG_H_INCLUDED
