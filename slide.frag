#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;
    int   direction;
} ubuf;

// Qt Quick assigns sampler bindings in ascending alphabetical order of property name.
// "sourceIn" < "sourceOut", so sourceIn = binding 1, sourceOut = binding 2.
layout(binding = 1) uniform sampler2D sourceIn;
layout(binding = 2) uniform sampler2D sourceOut;

void main() {
    vec2 uv = qt_TexCoord0;
    float p = ubuf.progress;

    // direction 0=right: old slides right, new enters from left
    // direction 1=left:  old slides left,  new enters from right
    // direction 2=down:  old slides down,  new enters from top
    // direction 3=up:    old slides up,    new enters from bottom
    //
    // At progress p, the dividing line is at coordinate p along the sweep axis.
    // Old scene occupies [p, 1], new scene occupies [0, p].
    // step(p, coord) → 1 when coord >= p (old region), 0 when coord < p (new region).

    vec4 cOut, cIn;
    float inOld;

    if (ubuf.direction == 0) {
        cOut  = texture(sourceOut, vec2(uv.x - p,       uv.y));
        cIn   = texture(sourceIn,  vec2(uv.x - p + 1.0, uv.y));
        inOld = step(p, uv.x);
    } else if (ubuf.direction == 1) {
        cOut  = texture(sourceOut, vec2(uv.x + p,       uv.y));
        cIn   = texture(sourceIn,  vec2(uv.x + p - 1.0, uv.y));
        inOld = step(uv.x, 1.0 - p);
    } else if (ubuf.direction == 2) {
        cOut  = texture(sourceOut, vec2(uv.x, uv.y - p));
        cIn   = texture(sourceIn,  vec2(uv.x, uv.y - p + 1.0));
        inOld = step(p, uv.y);
    } else {
        cOut  = texture(sourceOut, vec2(uv.x, uv.y + p));
        cIn   = texture(sourceIn,  vec2(uv.x, uv.y + p - 1.0));
        inOld = step(uv.y, 1.0 - p);
    }

    // mix(cIn, cOut, inOld): shows cOut where inOld=1 (old region), cIn where inOld=0 (new region)
    fragColor = mix(cIn, cOut, inOld) * ubuf.qt_Opacity;
}
