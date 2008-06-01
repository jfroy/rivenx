varying vec2 fragment_position;

void main()
{
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_TexCoord[1] = gl_MultiTexCoord1;
    
    fragment_position = gl_Vertex.xy;
    gl_Position = ftransform();
}
