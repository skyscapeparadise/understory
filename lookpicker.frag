#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float yaw;    // current look yaw in degrees
    float pitch;  // current look pitch in degrees
    float fovMM;  // focal length mm (full-frame equivalent)
    float back;   // 0 = front hemisphere, 1 = back hemisphere
} ubuf;

// No samplers — fully procedural.

const float PI = 3.14159265358979;

// Rotate around world Y axis (positive = rightward yaw).
vec3 rotYaw(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// Rotate around local X axis (positive = upward pitch).
vec3 rotPitch(vec3 v, float a) {
    float c = cos(a), s = sin(a);
    return vec3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
}

void main() {
    // NDC: (-1,-1) = top-left corner, (1,1) = bottom-right corner.
    vec2 ndc = qt_TexCoord0 * 2.0 - 1.0;
    float r2  = dot(ndc, ndc);
    float r   = sqrt(r2);

    // Discard pixels outside the circle.
    if (r > 1.02) { fragColor = vec4(0.0); return; }

    float zSphere = sqrt(max(0.0, 1.0 - r2));

    // Front/back hemisphere: flip z so the back view shows the opposite hemisphere.
    float zSign  = (ubuf.back > 0.5) ? -1.0 : 1.0;
    vec3 sphereN = normalize(vec3(ndc.x, -ndc.y, zSphere * zSign));

    // ── Concave white sphere — light as if viewing the interior ───────────
    // A dark centre → bright rim radial gradient is the primary visual cue
    // that the surface is concave.  A directional term adds subtle depth.
    vec3 lightDir = normalize(vec3(0.4, 0.7, 1.0));
    float diffuse = max(0.0, dot(-sphereN, lightDir));
    float light   = 0.35 + r2 * 0.55 + diffuse * 0.10;  // 0.35–1.00
    vec4 color    = vec4(vec3(light), 1.0);

    // ── 16:9 frame — transparent interior (negative space) ─────────────────
    float tanH = 18.0 / ubuf.fovMM;
    float tanV = tanH * (9.0 / 16.0);
    float yawRad   = ubuf.yaw   * PI / 180.0;
    float pitchRad = ubuf.pitch * PI / 180.0;

    // Rotate sphere point into the scene's local frame.
    vec3 local = rotYaw(rotPitch(sphereN, -pitchRad), -yawRad);

    if (local.z > 0.01) {
        // Frustum coordinates: ±1 at the frame edges.
        float fx =  local.x / (local.z * tanH);
        float fy = -local.y / (local.z * tanV); // flip Y: world-up → frame-top

        // Soft antialiasing at the frame boundary.
        float fw = 0.03;
        float insideX = smoothstep(-1.0 - fw, -1.0 + fw, fx) * (1.0 - smoothstep(1.0 - fw, 1.0 + fw, fx));
        float insideY = smoothstep(-1.0 - fw, -1.0 + fw, fy) * (1.0 - smoothstep(1.0 - fw, 1.0 + fw, fy));
        float cutout  = insideX * insideY;
        color.a *= (1.0 - cutout);
    }

    // ── Direction marker — white dot ───────────────────────────────────────
    // Use the same rotation convention as the frame projection so the marker
    // always sits at the frame centre: lookDir = rotPitch(rotYaw(+z, yaw), pitch).
    // Spherical-coordinate formulas diverge from this at back-hemisphere yaw values.
    vec3 lookDir = rotPitch(rotYaw(vec3(0.0, 0.0, 1.0), yawRad), pitchRad);

    // "Beyond" = look direction is on the wrong hemisphere for the current view.
    bool beyond = (ubuf.back > 0.5) ? lookDir.z >= 0.0 : lookDir.z <= 0.0;

    // Clamp marker to the rim when the angle is beyond the visible hemisphere.
    float mr = sqrt(lookDir.x * lookDir.x + lookDir.y * lookDir.y);
    if (beyond && mr > 0.001) { lookDir.x /= mr; lookDir.y /= mr; }

    // sphereN.y = -ndc.y in both modes, so markerNDC.y = -lookDir.y in both modes.
    vec2 markerNDC = vec2(lookDir.x, -lookDir.y);
    float dotDist  = length(ndc - markerNDC);
    float dotR     = 0.085;
    float strokeW  = 0.020;
    float aa       = 0.018;

    if (!beyond) {
        // Solid filled dot.
        float fill = 1.0 - smoothstep(dotR - aa, dotR + aa, dotDist);
        color = mix(color, vec4(1.0), fill);
    } else {
        // Hollow ring indicates the value is beyond the visible hemisphere.
        float outer = 1.0 - smoothstep(dotR - aa,          dotR + aa,          dotDist);
        float inner =       smoothstep(dotR - strokeW - aa, dotR - strokeW + aa, dotDist);
        float ring  = outer * inner;
        color = mix(color, vec4(1.0), ring);
    }

    // ── Rim antialiasing ────────────────────────────────────────────────────
    float rimAlpha = 1.0 - smoothstep(0.96, 1.02, r);
    fragColor = vec4(color.rgb, color.a * rimAlpha) * ubuf.qt_Opacity;
}
