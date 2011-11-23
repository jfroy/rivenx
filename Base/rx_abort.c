//
//  rx_abort.c
//  rivenx
//

#import "Base/RXBase.h"

#import <stdio.h>
#import <sys/syslog.h>


__attribute__((__used__))
static char* __crashreporter_info__ = 0;

void rx_abort(const char* format, ...)
{
	va_list args;
	va_start(args, format);
	
	char* str = NULL;
	vasprintf(&str, format, args);
	
	va_end(args);
	
	if (__crashreporter_info__)
	{
		size_t concat_size = strlen(__crashreporter_info__) + strlen(str) + 2;
		char* concat_string = malloc(concat_size);
		strlcpy(concat_string, __crashreporter_info__, concat_size);
		strlcat(concat_string, "\n", concat_size);
		strlcat(concat_string, str, concat_size);
		free(str);
		__crashreporter_info__ = str;
	}
	else
		__crashreporter_info__ = str;
	
	syslog(LOG_ERR, "aborting: %s\n", str);
	
	abort();
	// never reached
}
