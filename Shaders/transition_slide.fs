const vec2 cardSize = vec2(608.0, 392.0);

uniform sampler2DRect source;
uniform sampler2DRect destination;

uniform float t;

void main()
{
	vec4 s = texture2DRect(source, gl_TexCoord[0].st);
	vec4 d = texture2DRect(destination, gl_TexCoord[0].st);
	
	vec4 fragmentColor;
	if (gl_FragCoord.x < t * cardSize.x) fragmentColor = d;
	else fragmentColor = s;
	
	gl_FragColor = fragmentColor;
}
