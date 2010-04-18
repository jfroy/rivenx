#version 110

uniform sampler2DRect destination_card;
uniform vec4 modulate_color;

void main() {
	gl_FragColor = texture2DRect(destination_card, gl_TexCoord[0].st) * modulate_color;
}
