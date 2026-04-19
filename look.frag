#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float progress;    // 0→1 raw animation progress
    float yaw;         // total look yaw in degrees  (positive = right)
    float pitch;       // total look pitch in degrees (positive = up)
    float fovMM;       // focal length mm full-frame equivalent, e.g. 24.0
    float overshoot;   // back-ease-out s parameter: 0=none, 1.70158=standard
    float shutter;     // fraction of animation spanned per frame: 0=sharp, 0.10=cinematic
} ubuf;

// Qt Quick assigns sampler bindings in ascending alphabetical order of property name.
// "sourceIn" < "sourceOut", so sourceIn = binding 1, sourceOut = binding 2.
layout(binding = 1) uniform sampler2D sourceIn;   // incoming new scene
layout(binding = 2) uniform sampler2D sourceOut;  // outgoing old scene

const float PI           = 3.14159265358979;
const int   BLUR_SAMPLES = 24;

// Back-ease-out: f(0)=0, f(1)=1, overshoots past 1.0 around t∈[0.5,0.9].
// s controls overshoot amount (1.70158 = standard CSS back-ease-out).
float backEaseOut(float t, float s) {
    float t1 = t - 1.0;
    return 1.0 + (s + 1.0) * t1 * t1 * t1 + s * t1 * t1;
}

// Rotate around world Y axis: positive angle = rightward yaw.
vec3 rotYaw(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// Rotate around local X axis: positive angle = upward pitch.
vec3 rotPitch(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
}

// Sample a flat scene centered at (sYaw, sPitch) from a world ray.
// UVs are clamped to [0,1] so off-screen directions smear the nearest edge pixel —
// this is what creates the parallel smear lines visible between the two scenes.
vec4 sampleScene(vec3 worldRay, float sYaw, float sPitch,
                 float tanH, float tanV, sampler2D tex) {
    vec3 local = rotYaw(rotPitch(worldRay, -sPitch), -sYaw);
    // Clamp z away from zero; negative z (scene behind camera) also smears edge.
    float z = max(local.z, 0.001);
    float ux =  (local.x / (z * tanH)) * 0.5 + 0.5;
    float uy = -(local.y / (z * tanV)) * 0.5 + 0.5; // flip Y: world-up → screen-top
    vec2 uv = vec2(ux, uy);
    if (ux < 0.0 || ux > 1.0 || uy < 0.0 || uy > 1.0) {
        // Find nearest boundary point along the ray from scene center (0.5, 0.5).
        // This gives a diagonal seam at corners instead of collapsing to a single pixel.
        vec2 dir = uv - vec2(0.5);
        float t = 1.0;
        if (abs(dir.x) > 0.0001) t = min(t, 0.5 / abs(dir.x));
        if (abs(dir.y) > 0.0001) t = min(t, 0.5 / abs(dir.y));
        uv = clamp(vec2(0.5) + dir * t, 0.0, 1.0);
    }
    return texture(tex, uv);
}

void main() {
    vec2 ndc = qt_TexCoord0 * 2.0 - 1.0;

    // FOV from focal length (full-frame 36 × 24 mm sensor).
    float tanH = 18.0 / ubuf.fovMM;
    float tanV = tanH * (9.0 / 16.0); // 16:9 aspect

    float sceneYawRad   = ubuf.yaw   * PI / 180.0;
    float scenePitchRad = ubuf.pitch * PI / 180.0;

    // World direction of scene B's center (scene A is always at (0,0,1)).
    vec3 sceneBDir = rotPitch(rotYaw(vec3(0.0, 0.0, 1.0), sceneYawRad), scenePitchRad);

    // Camera-local ray from NDC.
    // ndc.y negated: screen-down → world-down, so world +Y is "up".
    vec3 camRay = normalize(vec3(ndc.x * tanH, -ndc.y * tanV, 1.0));

    // ── Temporal motion blur ────────────────────────────────────────────────
    // Simulates a camera shutter open for a window of time around the current
    // frame.  Each sample represents a distinct instant along the rotation arc,
    // with its own eased camera position and independent scene selection.
    // This accumulates light exactly as a physical shutter does — no crossfade,
    // no filter kernel, just geometry at different moments in time.
    //
    float SHUTTER = ubuf.shutter;

    vec4 colorAcc = vec4(0.0);

    for (int i = 0; i < BLUR_SAMPLES; i++) {
        // Distribute samples evenly across [progress - SHUTTER/2, progress + SHUTTER/2],
        // clamped so we never evaluate outside the [0, 1] animation range.
        float offset        = (float(i) / float(BLUR_SAMPLES - 1) - 0.5) * SHUTTER;
        float sampleProgress = clamp(ubuf.progress + offset, 0.0, 1.0);

        // Apply the easing to this sample's progress so blur follows the actual
        // motion path — faster in the middle, slower at the start and end.
        float sampleEased = backEaseOut(sampleProgress, ubuf.overshoot);

        float sYaw   = sceneYawRad   * sampleEased;
        float sPitch = scenePitchRad * sampleEased;

        // Camera forward and world ray for this temporal sample.
        vec3 camFwd  = rotPitch(rotYaw(vec3(0.0, 0.0, 1.0), sYaw), sPitch);
        vec3 worldRay = rotPitch(rotYaw(camRay, sYaw), sPitch);

        // Show whichever scene the camera faces at this instant.
        // Samples near the start favour scene A; samples near the end favour scene B.
        // At the transition midpoint both scenes contribute, which produces the
        // characteristic optical smear of a real whip-pan.
        float dotA = dot(camFwd, vec3(0.0, 0.0, 1.0));
        float dotB = dot(camFwd, sceneBDir);

        if (dotA >= dotB) {
            colorAcc += sampleScene(worldRay, 0.0, 0.0, tanH, tanV, sourceOut);
        } else {
            colorAcc += sampleScene(worldRay, sceneYawRad, scenePitchRad, tanH, tanV, sourceIn);
        }
    }

    fragColor = (colorAcc / float(BLUR_SAMPLES)) * ubuf.qt_Opacity;
}
