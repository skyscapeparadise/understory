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

// Peak barrel-distortion coefficient at transition midpoint. Gives the sensation
// of being inside a curved sphere. Zero at both endpoints — seamless cut points.
const float SPHERE_BARREL = 0.065;

// Back-ease-out: f(0)=0, f(1)=1, overshoots past 1.0 around t∈[0.5,0.9].
float backEaseOut(float t, float s) {
    float t1 = t - 1.0;
    return 1.0 + (s + 1.0) * t1 * t1 * t1 + s * t1 * t1;
}

vec3 rotYaw(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

vec3 rotPitch(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
}

// Clamp out-of-bounds UV to nearest scene boundary point along the ray from center.
vec2 clampToEdge(vec2 uv) {
    vec2 dir = uv - vec2(0.5);
    float t = 1.0;
    if (abs(dir.x) > 0.0001) t = min(t, 0.5 / abs(dir.x));
    if (abs(dir.y) > 0.0001) t = min(t, 0.5 / abs(dir.y));
    return clamp(vec2(0.5) + dir * t, 0.0, 1.0);
}

// Project a world ray onto a scene at (sYaw, sPitch) using perspective projection —
// the same "Project from View" mapping Blender uses. Returns the UV and sets
// inFrustum true only when the ray lands inside the scene's [0,1]×[0,1] rectangle.
vec2 projectScene(vec3 worldRay, float sYaw, float sPitch,
                  float tanH, float tanV, out bool inFrustum) {
    vec3 local = rotYaw(rotPitch(worldRay, -sPitch), -sYaw);
    float z    = max(local.z, 0.001);
    float ux   =  (local.x / (z * tanH)) * 0.5 + 0.5;
    float uy   = -(local.y / (z * tanV)) * 0.5 + 0.5;
    inFrustum  = local.z > 0.0 && ux >= 0.0 && ux <= 1.0 && uy >= 0.0 && uy <= 1.0;
    return vec2(ux, uy);
}

void main() {
    vec2 ndc = qt_TexCoord0 * 2.0 - 1.0;

    float tanH = 18.0 / ubuf.fovMM;
    float tanV = tanH * (9.0 / 16.0);

    float sceneYawRad   = ubuf.yaw   * PI / 180.0;
    float scenePitchRad = ubuf.pitch * PI / 180.0;

    // Fixed world direction of scene B's center (scene A is always at (0,0,1)).
    vec3 sceneBDir = rotPitch(rotYaw(vec3(0.0, 0.0, 1.0), sceneYawRad), scenePitchRad);

    // Screen-space wipe axis: points in the direction of the look (yaw → +x, pitch → -y
    // since world +Y maps to screen top which is ndc.y < 0). The wipe edge sweeps in
    // the opposite direction, so the new scene reveals from the side you're looking toward.
    vec2 lookDir = vec2(sceneYawRad, -scenePitchRad);
    vec2 wipeDir = length(lookDir) > 0.001 ? normalize(lookDir) : vec2(1.0, 0.0);

    // ── Temporal motion blur ────────────────────────────────────────────────
    // Each sample is a distinct camera orientation along the rotation arc.
    // Both scenes are projected onto the sphere at all times; which one a pixel
    // shows depends on where its world ray lands, not on a global scene switch.
    // This produces a natural per-pixel wipe with motion-blur smear, matching
    // how the transition looks from inside the sphere in the Blender mockup.
    //
    vec4 colorAcc = vec4(0.0);

    for (int i = 0; i < BLUR_SAMPLES; i++) {
        float offset        = (float(i) / float(BLUR_SAMPLES - 1) - 0.5) * ubuf.shutter;
        float sampleProgress = clamp(ubuf.progress + offset, 0.0, 1.0);
        float sampleEased   = backEaseOut(sampleProgress, ubuf.overshoot);

        float sYaw   = sceneYawRad   * sampleEased;
        float sPitch = scenePitchRad * sampleEased;

        // Barrel-distort the viewport ray: 0 at endpoints, peaks mid-transition.
        float k            = SPHERE_BARREL * sin(sampleProgress * PI);
        vec2  distortedNDC = ndc * (1.0 + k * dot(ndc, ndc));
        vec3  camRay       = normalize(vec3(distortedNDC.x * tanH, -distortedNDC.y * tanV, 1.0));

        // Rotate the viewport ray to world space for this camera orientation.
        vec3 worldRay = rotPitch(rotYaw(camRay, sYaw), sPitch);

        // Project the world ray onto both scene patches simultaneously.
        // inA / inB are true only when the ray falls inside that scene's frustum.
        bool inA, inB;
        vec2 uvA = projectScene(worldRay, 0.0,         0.0,          tanH, tanV, inA);
        vec2 uvB = projectScene(worldRay, sceneYawRad, scenePitchRad, tanH, tanV, inB);

        // Sample each scene — real texture inside its frustum, edge smear outside.
        vec4 colA = texture(sourceOut, inA ? uvA : clampToEdge(uvA));
        vec4 colB = texture(sourceIn,  inB ? uvB : clampToEdge(uvB));

        // Directional feathered wipe: the edge sweeps opposite to the look direction,
        // positioned by the camera's angular progress between the two scenes so it
        // always hits the midpoint at the rotational centre regardless of easing.
        vec3  camFwd   = rotPitch(rotYaw(vec3(0.0, 0.0, 1.0), sYaw), sPitch);
        float t        = clamp(0.5 + 0.5 * (dot(camFwd, sceneBDir) - dot(camFwd, vec3(0.0, 0.0, 1.0))), 0.0, 1.0);
        float pixelPos = dot(ndc, wipeDir);
        float threshold = mix(1.5, -1.5, t);
        float wipe     = smoothstep(threshold - 0.3, threshold + 0.3, pixelPos);
        colorAcc += mix(colA, colB, wipe);
    }

    fragColor = (colorAcc / float(BLUR_SAMPLES)) * ubuf.qt_Opacity;
}
