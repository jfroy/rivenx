#version 110

uniform sampler2DRect texture_units[4];
uniform vec4 texture_blend_weights;

void main() {
/*
	vec4 samples[4];
	samples[0] = texture2DRect(texture_units[0], gl_TexCoord[0].st);
	samples[1] = texture2DRect(texture_units[1], gl_TexCoord[0].st);
	samples[2] = texture2DRect(texture_units[2], gl_TexCoord[0].st);
	samples[3] = texture2DRect(texture_units[3], gl_TexCoord[0].st);
	gl_FragColor = samples[0] * texture_blend_weights.x 
		+ samples[1] * texture_blend_weights.y 
		+ samples[2] * texture_blend_weights.z  
		+ samples[3] * texture_blend_weights.w;
*/
	vec4 color = texture2DRect(texture_units[0], gl_TexCoord[0].st);
	gl_FragColor = color * texture_blend_weights.x;
}
