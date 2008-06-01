#version 110

uniform sampler2DRect destination_card;

void main()
{
	gl_FragColor = texture2DRect(destination_card, gl_TexCoord[0].st);
}
