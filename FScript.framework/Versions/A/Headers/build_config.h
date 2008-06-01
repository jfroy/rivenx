/*   build_config.h Copyright (c) 1999 Philippe Mougin.    */
/*   This software is open source. See the license.    */  

/* Some parameters in order to control the build process of the F-Script framework itself */

//#define BUILD_FOR_GNUSTEP

#ifdef BUILD_FOR_GNUSTEP
//------------------------- GNUSTEP --------------------------

// Do we use the AppKit? 
//#define BUILD_WITH_APPKIT 

// Do we use the JavaVM framework ?
//#define BUILD_WITH_JAVAVMFRAMEWORK


// In order to force the interpreter to always use NSInvocation when sending
// a F-Script message to an object.
#define MESSAGING_USES_NSINVOCATION

#else
//--------------------------- APPLE --------------------------

#define BUILD_WITH_APPKIT
#define BUILD_WITH_JAVAVMFRAMEWORK
//#define MESSAGING_USES_NSINVOCATION

#endif
  
