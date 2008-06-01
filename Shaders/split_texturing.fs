const vec4 red = vec4(1.0, 0.0, 0.0, 1.0);

uniform sampler2DRect top_texture;
uniform sampler2DRect bottom_texture;
uniform vec2 texture_size;

uniform vec3 origin;
uniform vec3 dimension;

uniform float split_factor;

void main() {
    float split_position = floor(split_factor * texture_size.y);
    
    float t1 = gl_TexCoord[0].t + split_position;
    vec4 color1 = texture2DRect(top_texture, vec2(gl_TexCoord[0].s, t1));
    
    float t2 = gl_TexCoord[1].t + split_position - texture_size.y;
    vec4 color2 = texture2DRect(bottom_texture, vec2(gl_TexCoord[1].s, t2));
    
    float overlap_factor = t1 - texture_size.y;
    if (overlap_factor > 0.0) {
        if (overlap_factor < 1.0) {
            //gl_FragColor = red;
            gl_FragColor = (color1 * 0.5) + (color2 * 0.5);
        } else {
            gl_FragColor = color2;
        }
    } else {
        gl_FragColor = color1;
    }
}
