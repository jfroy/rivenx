#version 110

attribute vec4 position;
attribute vec4 tex_coord0;

void main() {
	gl_TexCoord[0] = tex_coord0;
	gl_Position = gl_ModelViewProjectionMatrix * position;
}
