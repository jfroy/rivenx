uniform sampler2DRect source;
uniform sampler2DRect destination;

uniform float t;

void main()
{
	vec4 s = texture2DRect(source, gl_TexCoord[0].st);
	vec4 d = texture2DRect(destination, gl_TexCoord[0].st);
	gl_FragColor = mix(s, d, t);
}
