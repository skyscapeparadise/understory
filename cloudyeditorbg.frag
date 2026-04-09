#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float scale;
    float driftSpeed;
    float intensity;
};

// 3D hash — maps a spatial+time coordinate to a pseudo-random value
float hash3(vec3 p) {
    p = fract(p * vec3(127.1, 311.7, 74.7));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y + p.z) * p.x);
}

// 3D smooth value noise — trilinear interpolation so noise evolves
// at each point rather than sliding as a rigid texture
float smoothNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i),                      hash3(i + vec3(1,0,0)), u.x),
            mix(hash3(i + vec3(0,1,0)),         hash3(i + vec3(1,1,0)), u.x), u.y),
        mix(mix(hash3(i + vec3(0,0,1)),         hash3(i + vec3(1,0,1)), u.x),
            mix(hash3(i + vec3(0,1,1)),         hash3(i + vec3(1,1,1)), u.x), u.y),
        u.z
    );
}

// Fractal brownian motion — 4 octaves
float fbm(vec3 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * smoothNoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}

void main() {
    // Time is the Z axis — noise morphs in place rather than translating
    vec3 uvt = vec3(qt_TexCoord0 * scale, time * driftSpeed);
    float noise = fbm(uvt);

    vec3 base = vec3(0.13, 0.13, 0.13);
    vec3 color = base + (noise - 0.5) * intensity;

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
