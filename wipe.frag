#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;
    float feather;
    int   direction;
} ubuf;

// Qt Quick assigns sampler bindings in ascending alphabetical order of property name.
// "sourceIn" < "sourceOut", so sourceIn = binding 1, sourceOut = binding 2.
layout(binding = 1) uniform sampler2D sourceIn;
layout(binding = 2) uniform sampler2D sourceOut;

void main() {
    vec2 uv = qt_TexCoord0;

    // edge: position along the sweep axis (0=leading edge, 1=trailing edge).
    // direction 0=right: sweep left→right, new scene enters from left.
    // direction 1=left:  sweep right→left, new scene enters from right.
    // direction 2=down:  sweep top→bottom, new scene enters from top.
    // direction 3=up:    sweep bottom→top, new scene enters from bottom.
    float edge;
    if      (ubuf.direction == 0) edge = uv.x;
    else if (ubuf.direction == 1) edge = 1.0 - uv.x;
    else if (ubuf.direction == 2) edge = uv.y;
    else                          edge = 1.0 - uv.y;

    // smoothstep feathers the boundary.  hw prevents division-by-zero at feather=0.
    float hw    = max(ubuf.feather * 0.5, 0.001);
    float blend = smoothstep(ubuf.progress - hw, ubuf.progress + hw, edge);

    // blend=0 → sourceIn (incoming/new scene), blend=1 → sourceOut (outgoing/old scene)
    vec4 cIn  = texture(sourceIn,  uv);
    vec4 cOut = texture(sourceOut, uv);
    fragColor = mix(cIn, cOut, blend) * ubuf.qt_Opacity;
}
