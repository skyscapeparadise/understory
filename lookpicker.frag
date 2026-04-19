#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float yaw;    // current look yaw in degrees
    float pitch;  // current look pitch in degrees
    float fovMM;  // focal length mm (full-frame equivalent)
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

    // Front-hemisphere sphere normal.
    // ndc.y > 0 = screen bottom = world down, so flip Y for world-up convention.
    float zSphere = sqrt(max(0.0, 1.0 - r2));
    vec3 sphereN  = normalize(vec3(ndc.x, -ndc.y, zSphere));

    // ── Sphere shading ─────────────────────────────────────────────────────
    vec3 lightDir = normalize(vec3(0.4, 0.7, 1.0));
    float diffuse  = max(0.0, dot(sphereN, lightDir));
    float spec     = pow(max(0.0, dot(reflect(-lightDir, sphereN), vec3(0.0, 0.0, 1.0))), 14.0);
    float light    = 0.10 + diffuse * 0.50 + spec * 0.18;
    vec4 color     = vec4(vec3(0.09, 0.11, 0.14) * light, 1.0);

    // ── 16:9 frame outline at (yaw, pitch) ────────────────────────────────
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

        float fw = 0.05; // outline half-width in frustum space
        bool inX   = fx > -(1.0 + fw) && fx < (1.0 + fw);
        bool inY   = fy > -(1.0 + fw) && fy < (1.0 + fw);
        bool edgeX = abs(abs(fx) - 1.0) < fw && inY;
        bool edgeY = abs(abs(fy) - 1.0) < fw && inX;

        if (edgeX || edgeY) {
            color = mix(color, vec4(1.0, 1.0, 1.0, 1.0), 0.88);
        }
    }

    // ── Direction marker ───────────────────────────────────────────────────
    // Sphere position of the look direction: (sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))
    float mx = sin(yawRad) * cos(pitchRad);
    float my = sin(pitchRad);          // world Y (positive = up)
    float mz = cos(yawRad) * cos(pitchRad);

    // "Beyond" = look direction is on or past the back hemisphere (z ≤ 0).
    bool beyond = mz <= 0.0;

    // Clamp the marker to the rim when the actual angle is beyond the hemisphere.
    float mr = sqrt(mx * mx + my * my);
    if (beyond && mr > 0.001) { mx /= mr; my /= mr; } // project to equator

    // Marker position in NDC: ndc.x = mx, ndc.y = -my (flip world-up to screen-up).
    vec2 markerNDC = vec2(mx, -my);
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
    fragColor = vec4(color.rgb, rimAlpha) * ubuf.qt_Opacity;
}
