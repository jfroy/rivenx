/*
 *  GL_debug.c
 *  cidnectrl
 *
 *  Created by Jean-Francois Roy on 30/09/2007.
 *  Copyright 2007 Design III Equipe 1. All rights reserved.
 *
 */

#include <stdio.h>

#include "GL.h"
#include "GL_debug.h"

#include <OpenGL/CGLCurrent.h>
#include <OpenGL/CGLMacro.h>

#if defined(RIVENX)
#include "RXLogging.h"
#endif

#if defined(DEBUG_GL)

#if defined(__APPLE__)

void glReportErrorWithFileLineCGLMacro(CGLContextObj cgl_ctx, const char* file, const char* function, const int line)
{
  GLenum err = glGetError();
#if defined(RIVENX)
  if (GL_NO_ERROR != err) {
    RXCFLog(kRXLoggingGraphics, kRXLoggingLevelError, CFSTR("GL error in %s at %s:%d: %s (0x%x)\n"), function, file, line, gluErrorString(err),
            (unsigned int)err);
#else
  if (GL_NO_ERROR != err) {
    fprintf(stderr, "GL error in %s at %s:%d: %s (0x%x)\n", function, file, line, gluErrorString(err), (unsigned int)err);
#endif // RIVENX
    abort();
  }
}

#endif // __APPLE__

void glReportErrorWithFileLine(const char* file, const char* function, const int line)
{
#if defined(__APPLE__)
  CGL_MACRO_DECLARE_CONTEXT()
  glReportErrorWithFileLineCGLMacro(CGL_MACRO_CONTEXT, file, function, line);
#else
#error not implemented
#endif // __APPLE__
}

#endif // DEBUG_GL
