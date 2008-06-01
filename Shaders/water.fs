#version 110

uniform sampler2DRect card_texture;
uniform sampler2DRect water_displacement_map;
uniform sampler2DRect previous_frame;

void main()
{
	vec4 displacement_sample = texture2DRect(water_displacement_map, gl_TexCoord[0].st);
	vec4 previous_sample = texture2DRect(previous_frame, gl_TexCoord[0].st);
	
	vec2 st_disturb = (255.0 * displacement_sample.st) - vec2(127.0, 127.0);
	vec2 st = gl_TexCoord[0].st + st_disturb;
	vec4 disturbed_sample = texture2DRect(card_texture, st);
	
	gl_FragColor = mix(previous_sample, disturbed_sample, displacement_sample.a);
}
