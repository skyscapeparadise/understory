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

// Pseudo-random gradient direction at integer lattice point
vec3 gradDir(vec3 i) {
    vec3 p = fract(i * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p, p.zyx + 31.32);
    p = fract((p.xxy + p.yxx) * p.zyx);
    return normalize(p * 2.0 - 1.0);
}

// 3D gradient (Perlin-style) noise
// Gradient noise interpolates dot products of gradient vectors with offset
// vectors, producing directional flow rather than the spherical blobs of
// value noise — cross-sections through Z look like wisps, not pulsing blobs
float gradNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0); // quintic C2
    return mix(
        mix(mix(dot(gradDir(i),                f),
                dot(gradDir(i+vec3(1,0,0)),     f-vec3(1,0,0)), u.x),
            mix(dot(gradDir(i+vec3(0,1,0)),     f-vec3(0,1,0)),
                dot(gradDir(i+vec3(1,1,0)),     f-vec3(1,1,0)), u.x), u.y),
        mix(mix(dot(gradDir(i+vec3(0,0,1)),     f-vec3(0,0,1)),
                dot(gradDir(i+vec3(1,0,1)),     f-vec3(1,0,1)), u.x),
            mix(dot(gradDir(i+vec3(0,1,1)),     f-vec3(0,1,1)),
                dot(gradDir(i+vec3(1,1,1)),     f-vec3(1,1,1)), u.x), u.y),
        u.z
    );
}

// Ridge FBM — abs() per octave creates bright peaks with sharp dark rifts
// between them, the characteristic structure of turbulent clouds
float fbm(vec3 p, int octaves) {
    float v    = 0.0;
    float amp  = 0.5;
    float norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        float n = gradNoise(p);
        float ridge = 1.0 - abs(n) * 1.5; // 1.5 ≈ 1/max gradient magnitude
        v    += amp * ridge;
        norm += amp;
        p.xy *= 2.0;
        p.z  *= 1.4; // Z scales slower so octaves don't race through time cells
        amp  *= 0.5;
    }
    return v / norm;
}

void main() {
    // Correct for 16:9 aspect ratio
    vec2 uv = qt_TexCoord0 * vec2(16.0 / 9.0, 1.0) * scale;
    float t  = time * driftSpeed;
    vec3 uvt = vec3(uv, t);

    // Light domain warping — breaks residual grid structure without
    // over-distorting the cloud shapes
    vec3 warp = vec3(
        fbm(uvt + vec3(1.7, 9.2, 4.3), 2),
        fbm(uvt + vec3(8.3, 2.8, 1.5), 2),
        0.0
    );
    float noise = fbm(uvt + warp * 0.8, 4);

    vec3 base  = vec3(0.13, 0.13, 0.13);
    vec3 color = base + (noise - 0.5) * intensity;

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
