// RX_DIRECTION
// 0: left
// 1: right
// 2: top
// 3: bottom

#if !defined(RX_DIRECTION)
#define RX_DIRECTION -1
#error RX_DIRECTION must be defined.
#elif RX_DIRECTION < 0 || RX_DIRECTION > 3
#error RX_DIRECTION must be between 0 and 3
#endif

uniform vec2 cardSize;

uniform float margin;

uniform sampler2DRect source;
uniform sampler2DRect destination;

uniform float t;

vec2 getSourceSampleCoords() {
	return gl_TexCoord[0].st;
}

vec2 getDestinationSampleCoords() {
#if RX_DIRECTION == 0
	return vec2(gl_TexCoord[0].s - ((1.0 - t) * cardSize.x), gl_TexCoord[0].t);
#elif RX_DIRECTION == 1
	return vec2(gl_TexCoord[0].s + ((1.0 - t) * cardSize.x), gl_TexCoord[0].t);
#elif RX_DIRECTION == 2
	return vec2(gl_TexCoord[0].s, gl_TexCoord[0].t + ((1.0 - t) * cardSize.y));
#elif RX_DIRECTION == 3
	return vec2(gl_TexCoord[0].s, gl_TexCoord[0].t - ((1.0 - t) * cardSize.y));
#endif
}

void main() {
	vec2 sourceSampleCoords = getSourceSampleCoords();
	vec2 destinationSampleCoords = getDestinationSampleCoords();
	
	vec4 fragmentColor;
#if RX_DIRECTION == 0
	if (gl_FragCoord.x - margin >= (1.0 - t) * cardSize.x)
		fragmentColor = texture2DRect(destination, destinationSampleCoords);
#elif RX_DIRECTION == 1
	if (gl_FragCoord.x - margin < t * cardSize.x)
		fragmentColor = texture2DRect(destination, destinationSampleCoords);
#elif RX_DIRECTION == 2
	if (gl_FragCoord.y - margin < t * cardSize.y)
		fragmentColor = texture2DRect(destination, destinationSampleCoords);
#elif RX_DIRECTION == 3
	if (gl_FragCoord.y - margin >= (1.0 - t) * cardSize.y)
		fragmentColor = texture2DRect(destination, destinationSampleCoords);
#endif
	else fragmentColor = texture2DRect(source, sourceSampleCoords);
	
	gl_FragColor = fragmentColor;
}
