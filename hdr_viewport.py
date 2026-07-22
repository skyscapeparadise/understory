"""
hdr_viewport.py -- native HDR video pipeline bridge for understory's live
preview viewport (Phase 4 complete; Phase 5 Stage A: linear-light offscreen
compositing, laying the groundwork for native images/text).

Replaces understory's Qt Quick viewport with a real native SDL_GPU pipeline,
gated entirely behind the opt-in `appSettings.nativeRenderMode` setting
("off"/"sdr"/"hdr", restart required -- read once at startup). "hdr" targets
an HDR10_ST2084 swapchain (MSL shader doing HLG decode + PQ re-encode);
"sdr" (Phase 8) targets a standard swapchain with no HDR-display requirement
at all, using the same pipeline and an srgb_oetf() final encode instead.
With the mode "off", on unsupported hardware, or if any of the native
dependencies aren't importable, this module does nothing at all and the
existing Qt pipeline is untouched.

Architecture (validated across prototypes/hdr_phase0-3 before this file was
written -- see prototypes/ and the project_hdr_pipeline memory doc):
  - Qt Quick's own window has no HDR display path, so the native content
    can't be fed in as a texture -- it needs its own physical native surface
    on screen. That surface is a plain SDL-owned NSWindow, glued to the real
    Qt window as a Cocoa child window (`addChildWindow:ordered:`), and
    repositioned every tick to match `contentScaler`'s live on-screen rect.
  - Geometry sync rides on Qt's own position/size-changed signals (a native
    resize/move drag runs through a tight Cocoa tracking loop that a plain
    timer doesn't fire during), with an NSTimer driving the actual
    render/present tick.
  - `NSWindowWillCloseNotification` (not QML's `onClosing`) is the reliable
    signal that the app is closing -- proven necessary even though the real
    app already quits fine unassisted (`quitOnLastWindowClosed`), since the
    attached child window can reintroduce the same "app.exec() never
    returns" flakiness the standalone prototypes hit.
  - Borderless NSWindows still get Cocoa's default drop shadow -- disabled
    via `setHasShadow_(False)` right after creation, otherwise a thin grey
    line is visible around the video's edges.

Qualification (`SceneContent.nativeEligible`/`nativeVideoPath`, computed once
per `loadScene()`) is polled from `viewport.activeNativeEligible` /
`activeNativeVideoPath` every render tick -- a single fullscreen video and
nothing else on the active scene layer, not a self-crossfade loop. Anything
else (multiple elements, non-fullscreen video, no video at all) falls back
to the existing Qt pipeline with a hard cut, no native compositing.

Stage 3 adds real audio/video sync: `SceneContent.nativeVideoPlayer` (the
qualifying video's actual `MediaPlayer`, resolved via
`videosRepeater.itemAt(0)` one event-loop tick after `loadScene()` since the
Repeater's delegate isn't guaranteed to exist yet at the exact point
`nativeEligible` is computed) is polled every render tick as
`viewport.activeNativeVideoPlayer`. `_VideoSource`'s decode thread no longer
paces itself against wall-clock `frame.time` -- it decodes unthrottled into a
small bounded ring buffer (blocking once full, which naturally throttles
decode to roughly match real consumption -- no manual sleep needed), and the
render tick selects the newest buffered frame with `pts <= position`. A
sharp backward jump in `position` (MediaPlayer looping back to ~0) is
detected and clears the buffer outright, so stale end-of-previous-cycle
frames don't permanently wedge the decode thread waiting for buffer room
that would otherwise never free up.

Stage 4 adds native transition compositing for wipe/slide/look -- the
`.frag` shaders understory already uses, ported to MSL (see
prototypes/hdr_phase2_embed_transitions_test.py, the validated reference).
Every render tick polls `viewport.wiping`/`sliding`/`looking`/`dissolving`
(entirely driven by the *existing* QML `NumberAnimation`s and
`startPendingTransition()`/`performSwap()` -- no changes to
`InteractivityEngine.js` or the trigger chain). The native/Qt compositing
decision is latched once, the instant a transition flag first flips true,
and held for that transition's whole duration -- there's no way to hand off
between Qt `ShaderEffectSource` compositing and native GPU-texture
compositing mid-blend. It goes native only if the transition type has an
MSL port (`dissolve` never got one) AND both the outgoing and incoming
scene qualify (`viewport.activeNativeEligible`/`stagingNativeEligible`);
otherwise it's `"qt_fallback"` -- native stays hidden for the transition's
duration and Qt composites the whole thing on its own, same as it already
does today (our opaque overlay was simply covering Qt's own
`VideoOutput`/`ShaderEffectSource` compositing this whole time in the
steady-state case, so hiding mid-transition doesn't disturb it). During a
real native transition, both sides get their own `_VideoSource` and their
own `MediaPlayer` position poll (`stagingNativeVideoPlayer` mirrors
`activeNativeVideoPlayer`); at the end, the incoming source is promoted to
the new steady-state `self._source` rather than released and reopened,
since it's already loaded and playing in sync.

Phase 5 begins here: extending native rendering to images and text
alongside video (never shaders -- a separate, much larger initiative; see
the project_hdr_pipeline memory doc). The hard problem is compositing
ordinary SDR content (images, rasterized text) correctly alongside real HDR
video -- naively blending an SDR texture's white the same as HDR video's
white either washes out the SDR content or flattens the video. Stage A
(this state) replaces the steady-state single-video render with a
two-pass linear-light architecture, video-only, with no qualification or
visible behavior change -- a pure regression check before Stage B adds
images: every element (video now, images/text later) is drawn as a quad
(`QUAD_VERTEX_SHADER_MSL`, a per-draw NDC rect uniform, replacing the old
fixed fullscreen-triangle assumption) into an offscreen `R16G16B16A16_FLOAT`
buffer in linear display-nits, with standard non-premultiplied alpha-over
blending enabled (correct in linear light; blending PQ-encoded values
directly would be photometrically wrong, since PQ is a non-linear
perceptual curve). A final fullscreen pass then PQ-encodes the composited
buffer once for the real swapchain. Validated first as a standalone
prototype (`prototypes/hdr_phase5_mixed_compositing_test.py`) with real HDR
video plus a real photo plus a synthetic alpha-transparent text PNG,
confirming correct per-element rect placement, no fringing at alpha edges,
and that an SDR reference-white of 203 nits (ITU-R BT.2408's recommended
nominal peak for SDR-in-HDR compositing) looks right next to the graded
video -- before any of this touched the real app.
"""

import collections
import concurrent.futures
import ctypes
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time
import traceback
from dataclasses import dataclass, field

from PySide6.QtCore import QObject, Signal, Slot

try:
    import av
    import objc
    import sdl3
    from AppKit import NSWindowWillCloseNotification
    from av.codec.hwaccel import HWAccel
    from Foundation import NSNotificationCenter, NSRunLoop, NSRunLoopCommonModes, NSTimer
    from PySide6.QtCore import QPointF, QRectF, Qt
    from PySide6.QtGui import QImage, QPainter
    from PySide6.QtQuick import QQuickItem
    from PySide6.QtSvg import QSvgRenderer
    from Quartz import CATransaction

    _HDR_DEPS_AVAILABLE = True
except Exception:
    _HDR_DEPS_AVAILABLE = False

BT709_TRC = 1
TRANSFER_PQ = 16
TRANSFER_HLG = 18

_HLG_A = 0.17883277
_HLG_B = 1.0 - 4.0 * _HLG_A
_HLG_C = 0.5 - _HLG_A * math.log(4.0 * _HLG_A)

_PQ_M1 = 2610.0 / 16384.0
_PQ_M2 = 2523.0 / 4096.0 * 128.0
_PQ_C1 = 3424.0 / 4096.0
_PQ_C2 = 2413.0 / 4096.0 * 32.0
_PQ_C3 = 2392.0 / 4096.0 * 32.0

# Calibrated by direct comparison against QuickTime playback (see
# project_hdr_pipeline memory doc, finding 7) -- shared across steady-state
# and all three transition shaders so grading doesn't shift between them.
_PEAK_NITS = 600.0
_EXPOSURE = 0.9
_CONTRAST = 1.1
_GAMMA = 1.2 + 0.42 * math.log10(max(_PEAK_NITS, 1.0) / 1000.0)

# SDR reference white for images/rasterized text composited alongside HDR
# video, independent of _PEAK_NITS -- ITU-R BT.2408's recommended nominal
# peak for SDR-in-HDR compositing. Confirmed against the graded HDR test
# video in prototypes/hdr_phase5_mixed_compositing_test.py (Stage 0);
# user confirmed the default looked right with no adjustment needed.
_SDR_REF_NITS = 203.0

# Scene-card thumbnail capture: matches understoryui.qml's
# captureAndSaveThumbnail()'s own grabToImage(Qt.size(540, 300)) target size,
# so the two paths (Qt's grabToImage vs. this native readback) produce
# identically-sized files regardless of which one a given tick uses.
_THUMB_W = 540
_THUMB_H = 300

# Phase 10: how long a _VideoSource stays cached after it's no longer
# referenced by anything on screen, before actually being torn down and
# released -- see _reconcile_video_sources. Revisiting a scene within this
# window (a very common navigation pattern -- bouncing between two scenes,
# browsing a small set) reuses the still-decoding source instead of paying
# a fresh av.open()+decode-thread-startup cost and the brief black flash
# that comes with it (a freshly-created source has no real frames yet).
# Cheap to keep around: _VideoSource's decode thread blocks once its ring
# buffer fills (see _buffer_put), so an idle cached-but-unused source isn't
# burning CPU, just holding a little memory and a blocked thread.
_VIDEO_SOURCE_GRACE_SECONDS = 30.0

# Phase 8 Stage 2: HLG's own graceful-SDR-fallback behavior -- re-running
# the SAME hlg_inverse_oetf/hlg_ootf decode chain used for genuine HDR
# output, but re-targeted at an SDR-appropriate peak instead of
# _PEAK_NITS=600. Reuses _SDR_REF_NITS as the starting peak-nits hypothesis
# so HLG-graded video's peak brightness lands consistent with every other
# SDR-referred element (images/chrome/cursor/plain-SDR-video) sharing the
# same frame, mirroring why _PEAK_NITS=600 was originally chosen relative
# to pq_oetf's absolute scale. EXPOSURE=1.0/CONTRAST=1.0 -- fully neutral,
# i.e. no manual fudge factor at all -- is the FINAL confirmed value,
# reached only after an important correction: initial calibration against
# prototypes/hdrtest.mov alone (an unusually dark, moody test clip) landed
# on EXPOSURE=4.0, which looked right for that one file but badly blew out
# real, normally-exposed HLG footage (iPhone-shot daylight clips) -- a flat
# exposure multiplier tuned against one atypical clip's grade doesn't
# generalize, and correctness for typical real-world content matters more
# than exactly matching one stylized test file. Confirmed by the user
# against both hdrtest.mov (t=6s/t=30s) and real iPhone HLG footage
# (files/pathway/IMG_0893.MOV) at EXPOSURE=1.0.
#
# GAMMA is deliberately NOT the raw BT.2100 system-gamma formula evaluated
# at this low a peak -- that formula (1.2 + 0.42*log10(peak/1000)) drops
# below 1.0 once peak is much under ~700 nits (confirmed: 0.909 at 203),
# and hlg_ootf's gain term (peak_nits * pow(scene_luma, gamma-1.0)) uses
# gamma-1.0 as a power exponent on scene luma -- a NEGATIVE exponent
# there is an inverse power that blows up near black instead of gracefully
# darkening, not just "extrapolated below its intended range" but actively
# broken math (confirmed empirically: rendered solid black). The formula's
# example anchors are all >=1000 nits; it was never meant to be evaluated
# this low. Using a flat 1.2 (BT.2100's own commonly-cited reference-gamma
# constant, keeping gamma-1.0 safely positive) instead.
_SDR_HLG_PEAK_NITS = _SDR_REF_NITS
_SDR_HLG_GAMMA = 1.2
_SDR_HLG_EXPOSURE = 1.0
_SDR_HLG_CONTRAST = 1.0

VERTEX_SHADER_MSL = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vs_main(uint vertex_id [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 uvs[3]       = { float2(0.0, 1.0),   float2(2.0, 1.0),  float2(0.0, -1.0) };
    VertexOut out;
    out.position = float4(positions[vertex_id], 0.0, 1.0);
    out.uv = uvs[vertex_id];
    return out;
}
"""

# Shared HLG/PQ/YCbCr decode helpers for the two-source transition shaders
# below (out=outgoing/current scene, in=incoming/new scene), matching
# wipe.frag/slide.frag/look.frag's sourceOut/sourceIn naming.
COMMON_MSL = f"""
#include <metal_stdlib>
using namespace metal;

struct VertexOut {{
    float4 position [[position]];
    float2 uv;
}};

constant float HLG_A = {_HLG_A};
constant float HLG_B = {_HLG_B};
constant float HLG_C = {_HLG_C};

constant float PQ_M1 = {_PQ_M1};
constant float PQ_M2 = {_PQ_M2};
constant float PQ_C1 = {_PQ_C1};
constant float PQ_C2 = {_PQ_C2};
constant float PQ_C3 = {_PQ_C3};

float3 hlg_inverse_oetf(float3 e_prime) {{
    e_prime = clamp(e_prime, 0.0, 1.0);
    float3 lo = (e_prime * e_prime) / 3.0;
    float3 hi = (exp((e_prime - HLG_C) / HLG_A) + HLG_B) / 12.0;
    return select(hi, lo, e_prime <= 0.5);
}}

float3 hlg_ootf(float3 scene_linear, float peak_nits, float gamma) {{
    float ys = max(0.2627 * scene_linear.r + 0.6780 * scene_linear.g + 0.0593 * scene_linear.b, 0.0);
    float gain = (ys > 0.0) ? peak_nits * pow(ys, gamma - 1.0) : 0.0;
    return scene_linear * gain;
}}

float3 apply_trim(float3 nits, float peak_nits, float exposure, float contrast) {{
    nits *= exposure;
    if (contrast == 1.0) {{
        return nits;
    }}
    float3 normalized = max(nits, 0.0) / peak_nits;
    float3 shaped = pow(normalized, float3(contrast));
    return shaped * peak_nits;
}}

float3 srgb_eotf(float3 c) {{
    float3 lo = c / 12.92;
    float3 hi = pow((c + 0.055) / 1.055, float3(2.4));
    return select(hi, lo, c <= 0.04045);
}}

// Phase 8: linear -> gamma encode, the missing inverse of srgb_eotf()
// above -- used only by SDR_FINAL_FRAGMENT_MSL's final encode step for
// native SDR mode (mirrors pq_oetf()'s role for HDR mode). Standard IEC
// 61966-2-1, verified byte-exact against known inputs in
// prototypes/hdr_phase8_stage0_sdr_swapchain_test.py before being added
// here.
float3 srgb_oetf(float3 c) {{
    c = clamp(c, 0.0, 1.0);
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return select(hi, lo, c <= 0.0031308);
}}

// Phase 8: BT.2020 -> BT.709 linear-light primaries conversion (D65, no
// chromatic adaptation needed -- both use the same white point). Needed
// only in native SDR mode: the SDR swapchain composition assumes BT.709/
// sRGB primaries, but HLG/PQ video is decoded via the BT.2020 YCbCr matrix
// (ycbcr_to_rgb_bt2020 below) and stays in BT.2020 primaries all the way
// through hlg_ootf's output -- displaying those numbers directly as BT.709
// without this conversion under-saturates real footage (BT.2020's wider
// primaries collapse toward BT.709's narrower triangle) -- this was the
// real cause of a "washed out, missing saturation" report on real iPhone
// HLG footage (initially misdiagnosed as an exposure/contrast tuning
// issue), confirmed both via a numpy round-trip on a real captured linear
// buffer showing mean per-pixel channel spread (a saturation proxy)
// increasing after this exact matrix was applied, and by the user's own
// visual comparison after the fix landed. In native HDR mode this is
// skipped entirely -- the HDR10
// swapchain natively accepts Rec.2020 output, so the OS/display handles
// gamut mapping and no in-shader conversion is needed (see COMMON_MSL's
// ycbcr_to_rgb_bt2020 doc comment history for the HDR-mode reasoning).
float3 bt2020_to_bt709(float3 c) {{
    float3x3 m = float3x3(
        float3( 1.6605, -0.1246, -0.0182),
        float3(-0.5876,  1.1329, -0.1006),
        float3(-0.0728, -0.0083,  1.1187)
    );
    return max(m * c, 0.0);
}}

float3 pq_oetf(float3 nits) {{
    float3 yp = clamp(nits, 0.0, 10000.0) / 10000.0;
    float3 yp_m1 = pow(yp, PQ_M1);
    float3 num = PQ_C1 + PQ_C2 * yp_m1;
    float3 den = 1.0 + PQ_C3 * yp_m1;
    return pow(num / den, PQ_M2);
}}

float3 ycbcr_to_rgb_bt2020(float y, float cb, float cr) {{
    float yy = (y - 64.0 / 1023.0) * (1023.0 / 876.0);
    float pb = (cb - 512.0 / 1023.0) * (1023.0 / 896.0);
    float pr = (cr - 512.0 / 1023.0) * (1023.0 / 896.0);
    float r = yy + 1.4746 * pr;
    float g = yy - 0.16455 * pb - 0.57135 * pr;
    float b = yy + 1.8814 * pb;
    return float3(r, g, b);
}}

// Phase 7 Part 1: BT.709 sibling of the BT.2020 matrix above, for plain SDR
// video (8-bit yuv420p sources normalize to the same [0,1] fractional legal
// range regardless of bit depth, since everything is uploaded as R16_UNORM/
// R16G16_UNORM -- the 64/1023 etc. constants represent a fraction of full
// range, not an absolute 10-bit value, so they're correct here unchanged).
float3 ycbcr_to_rgb_bt709(float y, float cb, float cr) {{
    float yy = (y - 64.0 / 1023.0) * (1023.0 / 876.0);
    float pb = (cb - 512.0 / 1023.0) * (1023.0 / 896.0);
    float pr = (cr - 512.0 / 1023.0) * (1023.0 / 896.0);
    float r = yy + 1.5748 * pr;
    float g = yy - 0.1873 * pb - 0.4681 * pr;
    float b = yy + 1.8556 * pb;
    return float3(r, g, b);
}}

// Sample + full HLG decode for one scene at a given UV -> display-linear
// nits (no trim, no PQ encode yet -- those happen once after blending).
// Out-of-[0,1] UVs clamp to edge (matches the samplers' CLAMP_TO_EDGE mode).
float3 sample_scene_nits(texture2d<float> yTex, texture2d<float> uvTex,
                          sampler ySmp, sampler uvSmp, float2 uv,
                          float peak_nits, float gamma) {{
    float y = yTex.sample(ySmp, uv).r;
    float2 cbcr = uvTex.sample(uvSmp, uv).rg;
    float3 signal = clamp(ycbcr_to_rgb_bt2020(y, cbcr.x, cbcr.y), 0.0, 1.0);
    return hlg_ootf(hlg_inverse_oetf(signal), peak_nits, gamma);
}}
"""

# --- Phase 5 steady-state pipeline: composite into a linear-light offscreen
# buffer, then PQ-encode once at the end (see prototypes/
# hdr_phase5_mixed_compositing_test.py, the validated reference) ---

# Unit-quad vertex shader: 6 vertices (2 triangles) from vertex_id, no vertex
# buffer -- parameterized by a per-draw vertex-uniform NDC rect, replacing
# the old single-element fullscreen-triangle assumption. Video is still the
# only element in Stage A, but always drawn through this general mechanism
# now rather than a fullscreen-only shader.
QUAD_VERTEX_SHADER_MSL = (
    COMMON_MSL
    + """
struct RectUniform {
    float4 rect; // x0, y0 (top), x1, y1 (bottom) in NDC
};

vertex VertexOut vs_main(uint vertex_id [[vertex_id]], constant RectUniform &u [[buffer(0)]]) {
    float2 positions[6] = {
        float2(u.rect.x, u.rect.y), float2(u.rect.z, u.rect.y), float2(u.rect.x, u.rect.w),
        float2(u.rect.x, u.rect.w), float2(u.rect.z, u.rect.y), float2(u.rect.z, u.rect.w)
    };
    float2 uvs[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };
    VertexOut out;
    out.position = float4(positions[vertex_id], 0.0, 1.0);
    out.uv = uvs[vertex_id];
    return out;
}
"""
)

# Video quad -> linear nits, alpha=1. Same math as the old steady-state
# passthrough shader, minus the final pq_oetf -- that now happens once, in
# the final pass, after all elements are composited.
VIDEO_LINEAR_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float peak_nits;
    float gamma;
    float exposure;
    float contrast;
    float gamut_convert;
    float opacity;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                                 texture2d<float> yTex [[texture(0)]],
                                 texture2d<float> uvTex [[texture(1)]],
                                 sampler ySmp [[sampler(0)]],
                                 sampler uvSmp [[sampler(1)]],
                                 constant Uniforms &u [[buffer(0)]]) {
    float3 nits = sample_scene_nits(yTex, uvTex, ySmp, uvSmp, in.uv, u.peak_nits, u.gamma);
    nits = apply_trim(nits, u.peak_nits, u.exposure, u.contrast);
    if (u.gamut_convert > 0.5) {
        nits = bt2020_to_bt709(nits);
    }
    return float4(nits, u.opacity);
}
"""
)

# Final pass: sample the composited linear buffer, PQ-encode once for the
# real swapchain. The only shader that ever touches the swapchain directly
# in the steady-state path (uses the existing fullscreen-triangle vertex
# shader below, VERTEX_SHADER_MSL/vs_main -- also shared with the wipe/
# slide/look transition pipelines, which are untouched by this refactor).
FINAL_FRAGMENT_MSL = (
    COMMON_MSL
    + """
fragment float4 fs_main(VertexOut in [[stage_in]],
                          texture2d<float> tex [[texture(0)]],
                          sampler smp [[sampler(0)]]) {
    float3 nits = tex.sample(smp, in.uv).rgb;
    float3 pq = pq_oetf(nits);
    return float4(pq, 1.0);
}
"""
)

# Phase 8: SDR sibling of FINAL_FRAGMENT_MSL above -- same shared linear-nits
# buffer, but normalizes by sdr_ref_nits (the same 203-nit reference white
# every SDR-referred element -- images/SDR video/chrome/cursor -- is already
# written into the buffer scaled to, see SDR_FRAGMENT_MSL/SDRUniforms below)
# and srgb_oetf()-encodes instead of PQ-encoding. Mathematically exact
# inverse of that existing write path, so no changes are needed anywhere
# else in the compositing pipeline for SDR-referred content to display
# correctly through this pass. Reuses SDRUniforms (single sdr_ref_nits
# float) rather than a new ctypes struct -- identical shape.
SDR_FINAL_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct SDRFinalUniforms {
    float sdr_ref_nits;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                          texture2d<float> tex [[texture(0)]],
                          sampler smp [[sampler(0)]],
                          constant SDRFinalUniforms &u [[buffer(0)]]) {
    float3 nits = tex.sample(smp, in.uv).rgb;
    float3 normalized = clamp(nits / u.sdr_ref_nits, 0.0, 1.0);
    float3 srgb = srgb_oetf(normalized);
    return float4(srgb, 1.0);
}
"""
)

# SDR quad (image, and later rasterized text) -> linear nits scaled to its
# own reference white, independent of the video's peak_nits -- the core fix
# validated in prototypes/hdr_phase5_mixed_compositing_test.py (Stage 0).
SDR_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct SDRUniforms {
    float sdr_ref_nits;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> tex [[texture(0)]],
                         sampler smp [[sampler(0)]],
                         constant SDRUniforms &u [[buffer(0)]]) {
    float4 c = tex.sample(smp, in.uv);
    float3 lin = srgb_eotf(c.rgb) * u.sdr_ref_nits;
    return float4(lin, c.a);
}
"""
)

# Phase 7 Part 4: solid-color quad for native editor-canvas chrome (selection
# border edges, resize-handle dots) -- shares QUAD_VERTEX_SHADER_MSL's rect-
# from-uniform geometry, no texture/sampler at all. Scaled to SDR reference
# white exactly like SDR_FRAGMENT_MSL, not literal 1.0 -- a plain white
# border/handle would otherwise PQ-encode to a barely-visible value next to
# real HDR content, the same class of bug already found and fixed for user
# shaders in Part 2 (see _ShaderSource's docstring).
CHROME_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct ChromeUniforms {
    float4 color;
    float sdr_ref_nits;
    float shape; // 0 = filled rect (default), 1 = filled circle inscribed in the quad
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         constant ChromeUniforms &u [[buffer(0)]]) {
    float alpha = u.color.a;
    if (u.shape > 0.5) {
        float dist = distance(in.uv, float2(0.5, 0.5));
        if (dist > 0.5) alpha = 0.0;
    }
    float3 lin = srgb_eotf(u.color.rgb) * u.sdr_ref_nits;
    return float4(lin, alpha);
}
"""
)

# Phase 7 Part 1: SDR video quad -> linear nits, via BT.709 matrix + sRGB
# EOTF + SDR reference white, sibling of VIDEO_LINEAR_FRAGMENT_MSL (HDR/HLG)
# and SDR_FRAGMENT_MSL (SDR image). No HLG functions, no apply_trim -- SDR
# video shares the exact same "scale to sdr_ref_nits" model already used for
# SDR images, just starting from Y/UV planes instead of an RGBA texture.
SDR_VIDEO_LINEAR_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct SDRVideoUniforms {
    float sdr_ref_nits;
    float opacity;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> yTex [[texture(0)]],
                         texture2d<float> uvTex [[texture(1)]],
                         sampler ySmp [[sampler(0)]],
                         sampler uvSmp [[sampler(1)]],
                         constant SDRVideoUniforms &u [[buffer(0)]]) {
    float y = yTex.sample(ySmp, in.uv).r;
    float2 cbcr = uvTex.sample(uvSmp, in.uv).rg;
    float3 signal = clamp(ycbcr_to_rgb_bt709(y, cbcr.x, cbcr.y), 0.0, 1.0);
    float3 lin = srgb_eotf(signal) * u.sdr_ref_nits;
    return float4(lin, u.opacity);
}
"""
)

# --- Phase 6 Part 2: two-input linear variants of wipe/slide/look ---
#
# The original single-video wipe/slide/look shaders (which sampled two
# *video* sources directly via YCbCr planes, full HLG decode + trim inline,
# because a native transition only ever blended exactly two fullscreen
# videos) were removed in Phase 11 -- dead code since this per-element-pass
# rewrite superseded them in Phase 6, confirmed via grep that their
# pipelines were built at attach and released at teardown but never bound
# or drawn anywhere. Now that nativeTransitionEligible
# matches steady-state nativeEligible (any mix of <=1 video plus images/
# text per side), each side of a transition is first composited through the
# existing steady-state per-element pass into its own offscreen linear-nits
# buffer (_out_linear_buffer/_in_linear_buffer, see _render_transition),
# exactly like the single steady-state _linear_buffer already is. These
# shaders then blend those two pre-composited buffers directly and PQ-
# encode once -- no YCbCr/HLG decode (the buffers are already display-linear
# nits) and, critically, no apply_trim (trim is already baked into each
# buffer by VIDEO_LINEAR_FRAGMENT_MSL/SDR_FRAGMENT_MSL during that per-
# element pass; re-applying it here would double-apply exposure/contrast).
# This also means each side becomes pixel-identical to its own steady-state
# frame at progress 0/1, tightening the transition-boundary handoff versus
# the old blend-after-trim math.

# Phase 7 Part 3: dissolve was never ported to MSL in Phase 4-6 (pure Qt
# opacity-crossfade, no shader involved at all on the Qt side) -- always
# qt_fallback until now. It's structurally the simplest of the four
# transition types: no directional/spatial math, just a linear opacity mix
# between the two pre-composited buffers, driven by dissolveOpacity (0..1,
# animated by the existing Qt NumberAnimation the same as before -- only the
# *rendering* moves to native, the trigger/animation-driving chain in
# understoryui.qml is untouched). Porting this closes the last standing
# qt_fallback gap for two native-eligible sides -- see the module docstring
# history / project memory for why "no fallback possible" needed this too.
LINEAR_DISSOLVE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float3 colOut = outTex.sample(outSmp, in.uv).rgb;
    float3 colIn = inTex.sample(inSmp, in.uv).rgb;
    float3 nits = mix(colOut, colIn, u.progress);
    float3 pq = pq_oetf(nits);
    return float4(pq, 1.0);
}
"""
)

# Phase 9: SDR sibling of LINEAR_DISSOLVE_FRAGMENT_MSL above. Both inputs
# are already-composited linear-nits buffers produced by
# _composite_elements_pass (already mode-correct and gamut-fixed there, see
# Phase 8 Stage 2.5) -- so unlike the legacy single-video shaders below,
# there's no HLG/gamut logic to re-derive here, only the final encode line
# changes (pq_oetf -> srgb_oetf(clamp(nits/sdr_ref_nits, 0, 1))) plus one
# new sdr_ref_nits uniform field. Verified byte-exact in
# prototypes/hdr_phase9_stage0_sdr_dissolve_test.py before being added here.
SDR_LINEAR_DISSOLVE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float sdr_ref_nits;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float3 colOut = outTex.sample(outSmp, in.uv).rgb;
    float3 colIn = inTex.sample(inSmp, in.uv).rgb;
    float3 nits = mix(colOut, colIn, u.progress);
    float3 normalized = clamp(nits / u.sdr_ref_nits, 0.0, 1.0);
    float3 srgb = srgb_oetf(normalized);
    return float4(srgb, 1.0);
}
"""
)

LINEAR_WIPE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float feather;
    float direction;  // 0=right 1=left 2=down 3=up
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    int dir = int(u.direction);

    float edge;
    if (dir == 0) edge = uv.x;
    else if (dir == 1) edge = 1.0 - uv.x;
    else if (dir == 2) edge = uv.y;
    else edge = 1.0 - uv.y;

    float hw = max(u.feather * 0.5, 0.001);
    float blend = smoothstep(u.progress - hw, u.progress + hw, edge);

    float3 colIn = inTex.sample(inSmp, uv).rgb;
    float3 colOut = outTex.sample(outSmp, uv).rgb;
    float3 nits = mix(colIn, colOut, blend);
    float3 pq = pq_oetf(nits);
    return float4(pq, 1.0);
}
"""
)

# Phase 9: SDR sibling of LINEAR_WIPE_FRAGMENT_MSL above -- same pattern as
# SDR_LINEAR_DISSOLVE_FRAGMENT_MSL (both inputs already gamut-correct linear
# nits, only the final encode line + one new uniform field change).
SDR_LINEAR_WIPE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float feather;
    float direction;  // 0=right 1=left 2=down 3=up
    float sdr_ref_nits;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    int dir = int(u.direction);

    float edge;
    if (dir == 0) edge = uv.x;
    else if (dir == 1) edge = 1.0 - uv.x;
    else if (dir == 2) edge = uv.y;
    else edge = 1.0 - uv.y;

    float hw = max(u.feather * 0.5, 0.001);
    float blend = smoothstep(u.progress - hw, u.progress + hw, edge);

    float3 colIn = inTex.sample(inSmp, uv).rgb;
    float3 colOut = outTex.sample(outSmp, uv).rgb;
    float3 nits = mix(colIn, colOut, blend);
    float3 normalized = clamp(nits / u.sdr_ref_nits, 0.0, 1.0);
    float3 srgb = srgb_oetf(normalized);
    return float4(srgb, 1.0);
}
"""
)

LINEAR_SLIDE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float direction;  // 0=right 1=left 2=down 3=up
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float p = u.progress;
    int dir = int(u.direction);

    float2 outUV, inUV;
    float inOld;

    if (dir == 0) {
        outUV = float2(uv.x - p, uv.y);
        inUV  = float2(uv.x - p + 1.0, uv.y);
        inOld = step(p, uv.x);
    } else if (dir == 1) {
        outUV = float2(uv.x + p, uv.y);
        inUV  = float2(uv.x + p - 1.0, uv.y);
        inOld = step(uv.x, 1.0 - p);
    } else if (dir == 2) {
        outUV = float2(uv.x, uv.y - p);
        inUV  = float2(uv.x, uv.y - p + 1.0);
        inOld = step(p, uv.y);
    } else {
        outUV = float2(uv.x, uv.y + p);
        inUV  = float2(uv.x, uv.y + p - 1.0);
        inOld = step(uv.y, 1.0 - p);
    }

    float3 colOut = outTex.sample(outSmp, outUV).rgb;
    float3 colIn = inTex.sample(inSmp, inUV).rgb;
    float3 nits = mix(colIn, colOut, inOld);
    float3 pq = pq_oetf(nits);
    return float4(pq, 1.0);
}
"""
)

# Phase 9: SDR sibling of LINEAR_SLIDE_FRAGMENT_MSL above, same pattern.
SDR_LINEAR_SLIDE_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float direction;  // 0=right 1=left 2=down 3=up
    float sdr_ref_nits;
};

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float p = u.progress;
    int dir = int(u.direction);

    float2 outUV, inUV;
    float inOld;

    if (dir == 0) {
        outUV = float2(uv.x - p, uv.y);
        inUV  = float2(uv.x - p + 1.0, uv.y);
        inOld = step(p, uv.x);
    } else if (dir == 1) {
        outUV = float2(uv.x + p, uv.y);
        inUV  = float2(uv.x + p - 1.0, uv.y);
        inOld = step(uv.x, 1.0 - p);
    } else if (dir == 2) {
        outUV = float2(uv.x, uv.y - p);
        inUV  = float2(uv.x, uv.y - p + 1.0);
        inOld = step(p, uv.y);
    } else {
        outUV = float2(uv.x, uv.y + p);
        inUV  = float2(uv.x, uv.y + p - 1.0);
        inOld = step(uv.y, 1.0 - p);
    }

    float3 colOut = outTex.sample(outSmp, outUV).rgb;
    float3 colIn = inTex.sample(inSmp, inUV).rgb;
    float3 nits = mix(colIn, colOut, inOld);
    float3 normalized = clamp(nits / u.sdr_ref_nits, 0.0, 1.0);
    float3 srgb = srgb_oetf(normalized);
    return float4(srgb, 1.0);
}
"""
)

LINEAR_LOOK_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float yaw;
    float pitch;
    float fovMM;
    float overshoot;
    float shutter;
    float num_samples;
    float scene_yaw_rad;
    float scene_pitch_rad;
    float wipeDir_x, wipeDir_y;
    float sample_yaw[24];
    float sample_pitch[24];
    float sample_threshold[24];
};

float3 rot_yaw(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

float3 rot_pitch(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
}

float2 clamp_to_edge(float2 uv) {
    float2 dir = uv - float2(0.5);
    float t = 1.0;
    if (abs(dir.x) > 0.0001) t = min(t, 0.5 / abs(dir.x));
    if (abs(dir.y) > 0.0001) t = min(t, 0.5 / abs(dir.y));
    return clamp(float2(0.5) + dir * t, 0.0, 1.0);
}

float2 project_scene(float3 worldRay, float sYaw, float sPitch,
                      float tanH, float tanV, thread bool &inFrustum) {
    float3 local = rot_yaw(rot_pitch(worldRay, -sPitch), -sYaw);
    float z = max(local.z, 0.001);
    float ux = (local.x / (z * tanH)) * 0.5 + 0.5;
    float uy = -(local.y / (z * tanV)) * 0.5 + 0.5;
    inFrustum = local.z > 0.0 && ux >= 0.0 && ux <= 1.0 && uy >= 0.0 && uy <= 1.0;
    return float2(ux, uy);
}

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 ndc = in.uv * 2.0 - 1.0;

    float tanH = 18.0 / u.fovMM;
    float tanV = tanH * (9.0 / 16.0);

    float2 wipeDir = float2(u.wipeDir_x, u.wipeDir_y);
    float3 camRay = normalize(float3(ndc.x * tanH, -ndc.y * tanV, 1.0));

    float3 colorAcc = float3(0.0);
    int n = int(u.num_samples);

    for (int i = 0; i < n; i++) {
        float sYaw = u.sample_yaw[i];
        float sPitch = u.sample_pitch[i];
        float threshold = u.sample_threshold[i];

        float3 worldRay = rot_pitch(rot_yaw(camRay, sYaw), sPitch);

        bool inA = false, inB = false;
        float2 uvA = project_scene(worldRay, 0.0, 0.0, tanH, tanV, inA);
        float2 uvB = project_scene(worldRay, u.scene_yaw_rad, u.scene_pitch_rad, tanH, tanV, inB);

        float3 colA = outTex.sample(outSmp, inA ? uvA : clamp_to_edge(uvA)).rgb;
        float3 colB = inTex.sample(inSmp, inB ? uvB : clamp_to_edge(uvB)).rgb;

        float pixelPos = dot(ndc, wipeDir);
        float wipe = smoothstep(threshold - 0.3, threshold + 0.3, pixelPos);
        colorAcc += mix(colA, colB, wipe);
    }

    float3 nits = colorAcc / float(n);
    float3 pq = pq_oetf(nits);
    return float4(pq, 1.0);
}
"""
)

# Phase 9: SDR sibling of LINEAR_LOOK_FRAGMENT_MSL above, same pattern as
# the other three linear shaders -- full body duplicated (MSL shader
# strings don't share scope for their local helper functions across
# separately-compiled sources, unlike COMMON_MSL's shared preamble), only
# the final encode line + one new uniform field (appended after the fixed-
# size sample arrays, matching LinearLookUniforms's ctypes field order)
# actually change.
SDR_LINEAR_LOOK_FRAGMENT_MSL = (
    COMMON_MSL
    + """
struct Uniforms {
    float progress;
    float yaw;
    float pitch;
    float fovMM;
    float overshoot;
    float shutter;
    float num_samples;
    float scene_yaw_rad;
    float scene_pitch_rad;
    float wipeDir_x, wipeDir_y;
    float sample_yaw[24];
    float sample_pitch[24];
    float sample_threshold[24];
    float sdr_ref_nits;
};

float3 rot_yaw(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

float3 rot_pitch(float3 v, float a) {
    float c = cos(a), s = sin(a);
    return float3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
}

float2 clamp_to_edge(float2 uv) {
    float2 dir = uv - float2(0.5);
    float t = 1.0;
    if (abs(dir.x) > 0.0001) t = min(t, 0.5 / abs(dir.x));
    if (abs(dir.y) > 0.0001) t = min(t, 0.5 / abs(dir.y));
    return clamp(float2(0.5) + dir * t, 0.0, 1.0);
}

float2 project_scene(float3 worldRay, float sYaw, float sPitch,
                      float tanH, float tanV, thread bool &inFrustum) {
    float3 local = rot_yaw(rot_pitch(worldRay, -sPitch), -sYaw);
    float z = max(local.z, 0.001);
    float ux = (local.x / (z * tanH)) * 0.5 + 0.5;
    float uy = -(local.y / (z * tanV)) * 0.5 + 0.5;
    inFrustum = local.z > 0.0 && ux >= 0.0 && ux <= 1.0 && uy >= 0.0 && uy <= 1.0;
    return float2(ux, uy);
}

fragment float4 fs_main(VertexOut in [[stage_in]],
                         texture2d<float> outTex [[texture(0)]],
                         texture2d<float> inTex [[texture(1)]],
                         sampler outSmp [[sampler(0)]],
                         sampler inSmp [[sampler(1)]],
                         constant Uniforms &u [[buffer(0)]]) {
    float2 ndc = in.uv * 2.0 - 1.0;

    float tanH = 18.0 / u.fovMM;
    float tanV = tanH * (9.0 / 16.0);

    float2 wipeDir = float2(u.wipeDir_x, u.wipeDir_y);
    float3 camRay = normalize(float3(ndc.x * tanH, -ndc.y * tanV, 1.0));

    float3 colorAcc = float3(0.0);
    int n = int(u.num_samples);

    for (int i = 0; i < n; i++) {
        float sYaw = u.sample_yaw[i];
        float sPitch = u.sample_pitch[i];
        float threshold = u.sample_threshold[i];

        float3 worldRay = rot_pitch(rot_yaw(camRay, sYaw), sPitch);

        bool inA = false, inB = false;
        float2 uvA = project_scene(worldRay, 0.0, 0.0, tanH, tanV, inA);
        float2 uvB = project_scene(worldRay, u.scene_yaw_rad, u.scene_pitch_rad, tanH, tanV, inB);

        float3 colA = outTex.sample(outSmp, inA ? uvA : clamp_to_edge(uvA)).rgb;
        float3 colB = inTex.sample(inSmp, inB ? uvB : clamp_to_edge(uvB)).rgb;

        float pixelPos = dot(ndc, wipeDir);
        float wipe = smoothstep(threshold - 0.3, threshold + 0.3, pixelPos);
        colorAcc += mix(colA, colB, wipe);
    }

    float3 nits = colorAcc / float(n);
    float3 normalized = clamp(nits / u.sdr_ref_nits, 0.0, 1.0);
    float3 srgb = srgb_oetf(normalized);
    return float4(srgb, 1.0);
}
"""
)

# Phase 6 Part 2: uniforms for the two-input linear blend shaders above --
# peak_nits/gamma/exposure/contrast drop out entirely (trim is already baked
# into each pre-composited buffer, see LINEAR_WIPE_FRAGMENT_MSL's docstring).
class LinearDissolveUniforms(ctypes.Structure):
    _fields_ = [("progress", ctypes.c_float)]


class SdrLinearDissolveUniforms(ctypes.Structure):
    _fields_ = [("progress", ctypes.c_float), ("sdr_ref_nits", ctypes.c_float)]


class LinearWipeUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("feather", ctypes.c_float),
        ("direction", ctypes.c_float),
    ]


class SdrLinearWipeUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("feather", ctypes.c_float),
        ("direction", ctypes.c_float),
        ("sdr_ref_nits", ctypes.c_float),
    ]


class LinearSlideUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("direction", ctypes.c_float),
    ]


class SdrLinearSlideUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("direction", ctypes.c_float),
        ("sdr_ref_nits", ctypes.c_float),
    ]


class LinearLookUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("yaw", ctypes.c_float),
        ("pitch", ctypes.c_float),
        ("fovMM", ctypes.c_float),
        ("overshoot", ctypes.c_float),
        ("shutter", ctypes.c_float),
        ("num_samples", ctypes.c_float),
        ("scene_yaw_rad", ctypes.c_float),
        ("scene_pitch_rad", ctypes.c_float),
        ("wipeDir_x", ctypes.c_float),
        ("wipeDir_y", ctypes.c_float),
        ("sample_yaw", ctypes.c_float * 24),
        ("sample_pitch", ctypes.c_float * 24),
        ("sample_threshold", ctypes.c_float * 24),
    ]


class SdrLinearLookUniforms(ctypes.Structure):
    _fields_ = [
        ("progress", ctypes.c_float),
        ("yaw", ctypes.c_float),
        ("pitch", ctypes.c_float),
        ("fovMM", ctypes.c_float),
        ("overshoot", ctypes.c_float),
        ("shutter", ctypes.c_float),
        ("num_samples", ctypes.c_float),
        ("scene_yaw_rad", ctypes.c_float),
        ("scene_pitch_rad", ctypes.c_float),
        ("wipeDir_x", ctypes.c_float),
        ("wipeDir_y", ctypes.c_float),
        ("sample_yaw", ctypes.c_float * 24),
        ("sample_pitch", ctypes.c_float * 24),
        ("sample_threshold", ctypes.c_float * 24),
        ("sdr_ref_nits", ctypes.c_float),
    ]


_BLUR_SAMPLES = 24


def _back_ease_out(t, s):
    t1 = t - 1.0
    return 1.0 + (s + 1.0) * t1**3 + s * t1**2


def _rot_yaw_py(v, a):
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    return (c * x + s * z, y, -s * x + c * z)


def _rot_pitch_py(v, a):
    c, s = math.cos(a), math.sin(a)
    x, y, z = v
    return (x, c * y + s * z, -s * y + c * z)


def _dot3(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _compute_look_sample_uniforms(progress, yaw_deg, pitch_deg, overshoot, shutter, transitioning):
    """CPU-side precompute for look.frag's per-sample math -- see
    hdr_gpu_look_transition_test.py for why this is hoisted off the GPU."""
    scene_yaw_rad = math.radians(yaw_deg)
    scene_pitch_rad = math.radians(pitch_deg)
    scene_b_dir = _rot_pitch_py(_rot_yaw_py((0.0, 0.0, 1.0), scene_yaw_rad), scene_pitch_rad)

    look_dir = (scene_yaw_rad, -scene_pitch_rad)
    look_len = math.hypot(*look_dir)
    wipe_dir = (look_dir[0] / look_len, look_dir[1] / look_len) if look_len > 0.001 else (1.0, 0.0)

    num_samples = _BLUR_SAMPLES if transitioning else 1
    sample_yaw = [0.0] * _BLUR_SAMPLES
    sample_pitch = [0.0] * _BLUR_SAMPLES
    sample_threshold = [0.0] * _BLUR_SAMPLES
    for i in range(num_samples):
        offset = (i / (num_samples - 1) - 0.5) * shutter if num_samples > 1 else 0.0
        sample_progress = max(0.0, min(1.0, progress + offset))
        sample_eased = _back_ease_out(sample_progress, overshoot)

        s_yaw = scene_yaw_rad * sample_eased
        s_pitch = scene_pitch_rad * sample_eased
        sample_yaw[i] = s_yaw
        sample_pitch[i] = s_pitch

        cam_fwd = _rot_pitch_py(_rot_yaw_py((0.0, 0.0, 1.0), s_yaw), s_pitch)
        t = max(0.0, min(1.0, 0.5 + 0.5 * (_dot3(cam_fwd, scene_b_dir) - _dot3(cam_fwd, (0.0, 0.0, 1.0)))))
        sample_threshold[i] = 1.5 - 3.0 * t

    return num_samples, scene_yaw_rad, scene_pitch_rad, wipe_dir, sample_yaw, sample_pitch, sample_threshold


def _sdl_check(ok, what):
    if not ok:
        raise RuntimeError(f"{what} failed: {sdl3.SDL_GetError().decode()}")


def _plane_bytes(plane):
    return (ctypes.c_ubyte * plane.buffer_size).from_address(plane.buffer_ptr)


# Phase 7 Part 2: native user shaders are authored as raw .frag/.vert GLSL
# (no .qsb -- see the module-level docstring history / project memory for
# why: Qt Shader Tools' licensing terms and the ergonomics of requiring
# users to externally run `qsb` themselves were both poor fits). Compiled
# via `glslc` (part of `shaderc`, Apache-2.0, `brew install shaderc`) to
# SPIR-V, then `spirv-cross` (Khronos, Apache-2.0, `brew install spirv-cross`)
# to MSL source text -- which loads through the exact same _create_shader()
# every hand-ported built-in shader in this file already uses. Validated
# standalone first in prototypes/hdr_phase7_shader_toolchain_test.py
# (confirmed bit-exact pixel output through a sampler2D + uniform buffer
# round trip) before being wired in here.
#
# SDL_ShaderCross (PySDL3 declares bindings for it) was tried first but its
# compiled library isn't bundled with PySDL3 and upstream has no prebuilt
# release -- spirv-cross is simpler and needs no new API surface beyond
# what this file already has.
def _glsl_to_spirv(source_path, stage_name, spv_path):
    """.frag/.vert GLSL source file -> SPIR-V bytecode file, via glslc.
    `stage_name` is "vert" or "frag"."""
    result = subprocess.run(
        ["glslc", f"-fshader-stage={stage_name}", source_path, "-o", spv_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"glslc failed to compile {source_path!r}:\n{result.stderr}")


def _spirv_to_msl(spv_path, stage_name, renamed_entry):
    """SPIR-V bytecode file -> MSL source text, via spirv-cross. Renames the
    GLSL entry point (always "main") to match _create_shader()'s hardcoded
    vs_main/fs_main convention (see its docstring -- every independently-
    compiled MSL string in this file reuses these names with zero
    collision, since each is its own Metal library)."""
    result = subprocess.run(
        ["spirv-cross", spv_path, "--msl", "--rename-entry-point", "main", renamed_entry, stage_name],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"spirv-cross failed to transpile {spv_path!r}:\n{result.stderr}")
    return result.stdout


def _spirv_reflect(spv_path):
    """SPIR-V bytecode file -> parsed reflection dict (uniform block members,
    sampler2D bindings), via spirv-cross --reflect. This is the native
    pipeline's replacement for `qsb -d` (see ShaderInspector in
    understory.py for the Qt/.qsb-side equivalent, used when native
    rendering is off)."""
    result = subprocess.run(
        ["spirv-cross", spv_path, "--reflect"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"spirv-cross --reflect failed for {spv_path!r}:\n{result.stderr}")
    return json.loads(result.stdout)


def _strip_file_scheme(path):
    """Element/cursor paths are commonly stored as file:// URLs (matching
    how video/image/cursorPath values already are, via FileDialog.
    selectedFile.toString()) -- PyAV's `file:` protocol handler accepts
    these directly, but external CLI tools (glslc, spirv-cross) and Qt's
    QSvgRenderer/QFile do not, so strip the scheme here rather than relying
    on every caller to have already done it."""
    if path.startswith("file://"):
        return path[len("file://"):]
    return path


def compile_and_reflect_glsl(source_path, stage_name, renamed_entry):
    """Compiles a .frag/.vert file to both MSL source text and its
    reflection dict in one glslc + spirv-cross round trip. Public (no
    leading underscore) since understory.py's ShaderInspector reuses this
    for reflection-only introspection in the property panel."""
    source_path = _strip_file_scheme(source_path)
    with tempfile.TemporaryDirectory() as tmpdir:
        spv_path = os.path.join(tmpdir, "shader.spv")
        _glsl_to_spirv(source_path, stage_name, spv_path)
        msl = _spirv_to_msl(spv_path, stage_name, renamed_entry)
        reflection = _spirv_reflect(spv_path)
        return msl, reflection


# Default vertex shader for a shader element that supplies only a .frag (no
# custom .vert) -- the common case, mirroring Qt ShaderEffect's own implicit
# default vertex shader. Deliberately compiled through the *same* GLSL ->
# SPIR-V -> MSL toolchain as any user .vert, rather than reusing the existing
# hand-written QUAD_VERTEX_SHADER_MSL directly: spirv-cross and hand-written
# MSL number vertex-output/fragment-input attribute locations differently,
# and mixing a hand-written-MSL vertex stage with a spirv-cross-compiled
# fragment stage risks a silent attribute-location mismatch. Compiling both
# stages through the identical pipeline guarantees consistent numbering.
# Same fullscreen-quad-from-RectUniform geometry as QUAD_VERTEX_SHADER_MSL.
DEFAULT_SHADER_VERT_GLSL = """#version 450

layout(location = 0) out vec2 v_uv;

layout(binding = 0) uniform RectUniform {
    vec4 rect; // x0, y0 (top), x1, y1 (bottom) in NDC
} u;

void main() {
    vec2 positions[6] = vec2[](
        vec2(u.rect.x, u.rect.y), vec2(u.rect.z, u.rect.y), vec2(u.rect.x, u.rect.w),
        vec2(u.rect.x, u.rect.w), vec2(u.rect.z, u.rect.y), vec2(u.rect.z, u.rect.w)
    );
    vec2 uvs[6] = vec2[](
        vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0),
        vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0)
    );
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    v_uv = uvs[gl_VertexIndex];
}
"""


def _create_shader(device, source, stage, num_samplers=0, num_uniform_buffers=0):
    code = source.encode("utf-8")
    code_buf = ctypes.create_string_buffer(code, len(code))
    info = sdl3.SDL_GPUShaderCreateInfo()
    info.code_size = len(code)
    info.code = ctypes.cast(code_buf, ctypes.POINTER(ctypes.c_ubyte))
    info.entrypoint = b"vs_main" if stage == sdl3.SDL_GPU_SHADERSTAGE_VERTEX else b"fs_main"
    info.format = sdl3.SDL_GPU_SHADERFORMAT_MSL
    info.stage = stage
    info.num_samplers = num_samplers
    info.num_storage_textures = 0
    info.num_storage_buffers = 0
    info.num_uniform_buffers = num_uniform_buffers
    info.props = 0
    shader = sdl3.SDL_CreateGPUShader(device, ctypes.byref(info))
    if not shader:
        raise RuntimeError(f"SDL_CreateGPUShader failed: {sdl3.SDL_GetError().decode()}")
    return shader, code_buf


def _create_pipeline(device, vertex_shader, fragment_shader, target_format, blend=False):
    color_target_desc = sdl3.SDL_GPUColorTargetDescription()
    color_target_desc.format = target_format
    if blend:
        # Standard non-premultiplied alpha-over, applied in LINEAR light --
        # correct for compositing SDR content over HDR video (blending in
        # PQ-encoded space would be photometrically wrong, since PQ is a
        # non-linear perceptual curve). Harmless no-op for opaque draws
        # (alpha=1 -> dst factor 0 -> plain overwrite).
        bs = color_target_desc.blend_state
        bs.enable_blend = True
        bs.src_color_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_SRC_ALPHA
        bs.dst_color_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        bs.color_blend_op = sdl3.SDL_GPU_BLENDOP_ADD
        bs.src_alpha_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_ONE
        bs.dst_alpha_blendfactor = sdl3.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
        bs.alpha_blend_op = sdl3.SDL_GPU_BLENDOP_ADD

    pipeline_info = sdl3.SDL_GPUGraphicsPipelineCreateInfo()
    pipeline_info.vertex_shader = vertex_shader
    pipeline_info.fragment_shader = fragment_shader
    pipeline_info.primitive_type = sdl3.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST
    pipeline_info.target_info.color_target_descriptions = ctypes.pointer(color_target_desc)
    pipeline_info.target_info.num_color_targets = 1
    pipeline_info.rasterizer_state.fill_mode = sdl3.SDL_GPU_FILLMODE_FILL
    pipeline_info.rasterizer_state.cull_mode = sdl3.SDL_GPU_CULLMODE_NONE
    pipeline_info.multisample_state.sample_count = sdl3.SDL_GPU_SAMPLECOUNT_1

    pipeline = sdl3.SDL_CreateGPUGraphicsPipeline(device, ctypes.byref(pipeline_info))
    if not pipeline:
        raise RuntimeError(f"SDL_CreateGPUGraphicsPipeline failed: {sdl3.SDL_GetError().decode()}")
    return pipeline


def _make_texture(device, fmt, w, h, usage):
    info = sdl3.SDL_GPUTextureCreateInfo()
    info.type = sdl3.SDL_GPU_TEXTURETYPE_2D
    info.format = fmt
    info.usage = usage
    info.width = w
    info.height = h
    info.layer_count_or_depth = 1
    info.num_levels = 1
    info.sample_count = sdl3.SDL_GPU_SAMPLECOUNT_1
    tex = sdl3.SDL_CreateGPUTexture(device, ctypes.byref(info))
    if not tex:
        raise RuntimeError(f"SDL_CreateGPUTexture failed: {sdl3.SDL_GetError().decode()}")
    return tex


class VideoLinearUniforms(ctypes.Structure):
    _fields_ = [
        ("peak_nits", ctypes.c_float),
        ("gamma", ctypes.c_float),
        ("exposure", ctypes.c_float),
        ("contrast", ctypes.c_float),
        ("gamut_convert", ctypes.c_float),
        # Phase 10 Stage 2: always 1.0 for a normal single draw -- only the
        # crossfade secondary ("B") draw ever passes something else, see
        # _composite_elements_pass's video branch.
        ("opacity", ctypes.c_float),
    ]


class RectUniform(ctypes.Structure):
    _fields_ = [("rect", ctypes.c_float * 4)]


class SDRUniforms(ctypes.Structure):
    _fields_ = [("sdr_ref_nits", ctypes.c_float)]


class SDRVideoUniforms(ctypes.Structure):
    """Phase 10 Stage 2: was reusing SDRUniforms above (coincidentally the
    same 1-field shape) -- needs its own dedicated ctypes class now that it
    has a second field, matching its already-dedicated MSL struct name."""

    _fields_ = [("sdr_ref_nits", ctypes.c_float), ("opacity", ctypes.c_float)]


class ChromeUniforms(ctypes.Structure):
    _fields_ = [("color", ctypes.c_float * 4), ("sdr_ref_nits", ctypes.c_float), ("shape", ctypes.c_float)]


class _AsyncSourceLoader:
    """Runs each scene source's slow, GPU-free setup work (file I/O,
    container probing, image decode, shader subprocess compile) on a shared
    background thread pool, off the render thread -- the render tick only
    ever does the fast GPU-resource creation with the finished result, so a
    slow-to-open file never stalls playback of everything else already on
    screen (the bug this replaces: _reconcile_video_sources used to call
    av.open() straight from the render tick, and while that blocked, every
    other already-playing video's decode ring buffer would starve since
    nothing was pulling frames for it that whole time).

    Deliberately dependency-free beyond stdlib threading -- no SDL, no Qt --
    since this is meant to carry over unchanged into the future Qt-less
    runtime; only the reconcile methods that call it are Qt/SDL-facing.

    One instance is shared across video/image/shader sources, keyed by
    caller-chosen tuples (e.g. ("video", path)) so all three can queue work
    on the same pool without colliding."""

    def __init__(self, max_workers=4):
        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
        self._pending = {}  # key -> Future

    def request(self, key, fn, *args):
        """No-op if `key` is already queued or in flight -- callers are
        expected to call this every tick for everything in their `wanted`
        set, same shape as the existing reconcile methods' "skip if already
        in the cache dict" check."""
        if key not in self._pending:
            self._pending[key] = self._executor.submit(fn, *args)

    def poll_ready(self, kind):
        """Yields (key, result, exc) once for each finished job whose key
        starts with `kind`, then forgets it -- exactly one of result/exc is
        not None. Never blocks: jobs still running are simply skipped this
        tick. Filtered by `kind` (not just "all finished jobs") because
        multiple independent reconcile methods share one loader instance --
        without this, whichever one happened to poll first would pop and
        discard results meant for another (e.g. _reconcile_video_sources
        silently eating a crossfade secondary's finished load before
        _reconcile_crossfade_sources ever saw it)."""
        for key in [k for k, fut in self._pending.items() if k[0] == kind and fut.done()]:
            future = self._pending.pop(key)
            exc = future.exception()
            yield key, (None if exc else future.result()), exc

    def cancel(self, key):
        """For a source that fell out of the caller's `wanted` set before
        its load finished -- cancels it if it hasn't started yet; if it's
        already running, this just stops it from being polled again (the
        thread finishes on its own, its result quietly discarded)."""
        future = self._pending.pop(key, None)
        if future is not None:
            future.cancel()

    def pending_keys(self):
        return list(self._pending.keys())

    def is_pending(self, key):
        return key in self._pending

    def shutdown(self):
        for future in self._pending.values():
            future.cancel()
        self._pending = {}
        self._executor.shutdown(wait=False, cancel_futures=True)


@dataclass
class _VideoSourcePrepared:
    """Result of _VideoSource.prepare() -- everything about opening and
    probing a video file that involves no SDL/GPU calls, done off the render
    thread. Handed to _VideoSource.__init__, which does only the fast part
    (GPU texture/buffer creation) with it."""

    path: str
    container: object
    hw_decode: bool
    transfer: object
    primaries: object
    is_hdr: bool
    width: int
    height: int


class _VideoSource:
    """Threaded/hardware-decoded HDR video source. Decodes unthrottled into
    a small bounded ring buffer; frame selection is driven by the caller
    handing in the real MediaPlayer position each tick (see try_upload_latest)
    rather than any wall-clock pacing of our own. Upload is non-blocking so a
    slow/late frame never stalls the Qt main thread this render tick runs on."""

    @staticmethod
    def prepare(path):
        """Opens and probes the file -- av.open() plus the hwaccel fallback
        it can trigger, both genuine (sometimes slow) file I/O -- with no
        SDL/GPU calls at all, so this is safe to run on a background thread
        via _AsyncSourceLoader rather than blocking the render tick (the bug
        this replaces: this used to run inline in _reconcile_video_sources,
        and while it blocked, every other already-playing video's decode
        ring buffer would starve since nothing was pulling frames for it).
        Returns a _VideoSourcePrepared for __init__ to finish on the render
        thread."""
        try:
            container = av.open(path, hwaccel=HWAccel("videotoolbox"))
            hw_decode = True
        except Exception:
            container = av.open(path)
            hw_decode = False
        print(f"[hdr_viewport] video decode: {os.path.basename(path)} hw_decode={hw_decode}")
        stream = container.streams.video[0]
        cc = stream.codec_context
        transfer = cc.color_trc or BT709_TRC
        primaries = cc.color_primaries
        # Phase 7 Part 1: this classification was previously computed and
        # discarded (self.transfer was assigned but never branched on) --
        # every source went through the same BT.2020/HLG math in
        # sample_scene_nits() regardless of its real colorimetry, silently
        # mangling plain SDR video whenever hdrPreviewEnabled was on. Real
        # story assets confirm the expected split: SDR clips are 8-bit
        # yuv420p/bt709, HDR clips are 10-bit yuv420p10le/bt2020/arib-std-b67
        # (HLG). PQ is included for completeness even though no test asset
        # uses it yet.
        is_hdr = transfer in (TRANSFER_HLG, TRANSFER_PQ)
        return _VideoSourcePrepared(
            path=path, container=container, hw_decode=hw_decode, transfer=transfer,
            primaries=primaries, is_hdr=is_hdr, width=cc.width, height=cc.height,
        )

    def __init__(self, device, prepared):
        self.device = device
        self.path = prepared.path
        self.container = prepared.container
        self.hw_decode = prepared.hw_decode
        self.transfer = prepared.transfer
        self.primaries = prepared.primaries
        self.is_hdr = prepared.is_hdr

        width, height = prepared.width, prepared.height
        self.width, self.height = width, height
        self.uv_width, self.uv_height = width // 2, height // 2

        self.y_texture = self._make_plane_texture(sdl3.SDL_GPU_TEXTUREFORMAT_R16_UNORM, width, height)
        self.uv_texture = self._make_plane_texture(
            sdl3.SDL_GPU_TEXTUREFORMAT_R16G16_UNORM, self.uv_width, self.uv_height
        )

        self.y_size = width * height * 2
        self.uv_size = self.uv_width * self.uv_height * 4
        transfer_info = sdl3.SDL_GPUTransferBufferCreateInfo()
        transfer_info.usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD
        transfer_info.size = self.y_size + self.uv_size
        self.transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(device, ctypes.byref(transfer_info))
        if not self.transfer_buffer:
            raise RuntimeError(f"SDL_CreateGPUTransferBuffer failed: {sdl3.SDL_GetError().decode()}")

        # GPU texture memory isn't zero-initialized by drivers (Metal
        # doesn't guarantee it) -- without this, a freshly created source
        # shows a flash of whatever garbage bytes happened to be in that
        # memory (seen as e.g. a solid cyan rectangle) until the decode
        # thread's first real frame lands, which is most noticeable right at
        # a transition's start (the incoming source is brand new).
        #
        # Phase 10: an all-zero UV plane does NOT decode to true black,
        # despite this comment's own prior claim -- confirmed both by hand
        # and empirically (the actual bug the user saw): Y=0 is correctly
        # "black luma" in limited-range terms, but Cb=Cr=0 is nowhere near
        # neutral chroma (which sits at ycbcr_to_rgb_bt2020's own centering
        # constant, 512/1023, not 0) -- it decodes to a strongly negative-
        # red/negative-blue signal that clamps to a saturated GREEN
        # (confirmed: clamp(ycbcr_to_rgb_bt2020(0,0,0), 0, 1) == (0, 0.347,
        # 0)), not black. Root cause of a real, previously-unnoticed green
        # flash at every transition boundary that creates a fresh source
        # (dissolve/wipe/slide/look/cut alike -- any of them can hit this,
        # not just "cut" as originally suspected). Fixed by uploading
        # neutral chroma (512/1023, ~32800 as a 16-bit UNORM value) instead
        # of zero for Cb/Cr -- verified this combination genuinely clamps
        # to (0,0,0) before shipping.
        zero_y = bytes(self.y_size)
        neutral_chroma_word = round((512 / 1023) * 65535).to_bytes(2, "little")
        neutral_uv = (neutral_chroma_word * 2) * (self.uv_size // 4)
        init_cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(device)
        init_copy_pass = sdl3.SDL_BeginGPUCopyPass(init_cmdbuf)
        self._upload_bytes(init_copy_pass, zero_y, neutral_uv)
        sdl3.SDL_EndGPUCopyPass(init_copy_pass)
        sdl3.SDL_SubmitGPUCommandBuffer(init_cmdbuf)

        # Bounded ring buffer of (pts_seconds, y_bytes, uv_bytes), a handful of
        # frames deep. The decode thread blocks in _buffer_put() once full --
        # backpressure that naturally keeps decode paced to roughly
        # MediaPlayer.position's actual consumption rate, no manual sleep/
        # wall-clock pacing needed (that's the Stage 1/2 approach this
        # replaces; position is now the sole clock of record).
        self._buffer = collections.deque()
        self._buffer_maxlen = 8
        self._buffer_lock = threading.Lock()
        self._buffer_not_full = threading.Condition(self._buffer_lock)
        self._stop = threading.Event()
        # Diagnostic-only throttles (see _decode_loop/_advance_to) -- last
        # time each warning fired, so a sustained problem logs once a
        # second instead of once a frame/tick.
        self._last_decode_lag_log = 0.0
        self._last_starve_log = 0.0
        # True once try_upload_latest has uploaded a genuine decoded frame
        # (not just this __init__'s own neutral-chroma placeholder above) --
        # queried via HDRVideoBridge.is_native_video_ready(), which
        # SceneContent.qml's video readiness gate polls in place of Qt's own
        # decoded-frame count when native rendering is what's actually going
        # to paint this path (see that method's docstring for why: the two
        # decoders are otherwise unrelated, and Qt's own frame count says
        # nothing about whether native has anything to show yet).
        #
        # Deliberately set from the decode thread the moment a frame is
        # buffered (_buffer_put below), NOT from try_upload_latest actually
        # uploading one -- try_upload_latest is only ever called for a
        # staging/pre-warming path once a transition has already started
        # (see _render_unsafe vs _render_transition's differing
        # video_players arguments), which is *after* whatever readiness gate
        # this flag feeds is supposed to have already passed. Gating
        # readiness on upload created a real deadlock: a jump could never
        # start because it was waiting on an upload that only happens once
        # the jump has already started. Decode-thread readiness has no such
        # cycle -- it only depends on _reconcile_video_sources having
        # constructed the source, which already happens for staging paths
        # every ordinary tick.
        self.has_decoded_frame = False
        self._thread = threading.Thread(target=self._decode_loop, daemon=True)
        self._thread.start()

    def _buffer_put(self, item):
        with self._buffer_not_full:
            while len(self._buffer) >= self._buffer_maxlen and not self._stop.is_set():
                self._buffer_not_full.wait(timeout=0.5)
            if self._stop.is_set():
                return
            self._buffer.append(item)
        self.has_decoded_frame = True

    def _make_plane_texture(self, fmt, w, h):
        info = sdl3.SDL_GPUTextureCreateInfo()
        info.type = sdl3.SDL_GPU_TEXTURETYPE_2D
        info.format = fmt
        info.usage = sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER
        info.width = w
        info.height = h
        info.layer_count_or_depth = 1
        info.num_levels = 1
        info.sample_count = sdl3.SDL_GPU_SAMPLECOUNT_1
        tex = sdl3.SDL_CreateGPUTexture(self.device, ctypes.byref(info))
        if not tex:
            raise RuntimeError(f"SDL_CreateGPUTexture failed: {sdl3.SDL_GetError().decode()}")
        return tex

    def _decoded_frames(self):
        while True:
            got_any = False
            for frame in self.container.decode(video=0):
                got_any = True
                yield frame
            if not got_any:
                return
            self.container.seek(0)

    def _decode_loop(self):
        last_pts = None
        for frame in self._decoded_frames():
            if self._stop.is_set():
                return
            t0 = time.monotonic()
            rf = frame.reformat(width=self.width, height=self.height, format="p016le")
            y_bytes = bytes(_plane_bytes(rf.planes[0]))
            uv_bytes = bytes(_plane_bytes(rf.planes[1]))
            decode_elapsed = time.monotonic() - t0

            # Diagnostic only: a loop wrap makes frame.time jump back to ~0,
            # which would otherwise read as a hugely negative interval here --
            # skip the check on that tick rather than flag a false lag.
            if last_pts is not None and frame.time > last_pts:
                frame_interval = frame.time - last_pts
                if decode_elapsed > frame_interval:
                    now = time.monotonic()
                    if now - self._last_decode_lag_log > 1.0:
                        print(
                            f"[hdr_viewport] video decode falling behind realtime: "
                            f"{os.path.basename(self.path)} decode={decode_elapsed * 1000:.1f}ms "
                            f"> frame_interval={frame_interval * 1000:.1f}ms (hw_decode={self.hw_decode})"
                        )
                        self._last_decode_lag_log = now
            last_pts = frame.time

            self._buffer_put((frame.time, y_bytes, uv_bytes))

    def _advance_to(self, position_seconds):
        """Selects the newest buffered frame with pts <= position_seconds,
        discarding older ones. Returns None if nothing qualifies yet (decode
        is behind, or briefly ahead right at a loop wrap) -- caller should
        just keep showing the current texture in that case.

        Handles MediaPlayer looping back to ~0: if position drops sharply
        versus the oldest buffered pts, that's a wrap, not jitter -- the
        buffer is fully cleared so the decode thread's _buffer_put() unblocks
        and can fill in fresh low-pts frames matching the new cycle, rather
        than being permanently wedged holding stale end-of-previous-cycle
        frames that will never again satisfy pts <= position this cycle."""
        with self._buffer_not_full:
            if self._buffer and position_seconds < self._buffer[0][0] - 0.5:
                self._buffer.clear()
                self._buffer_not_full.notify_all()
                return None
            selected = None
            while self._buffer and self._buffer[0][0] <= position_seconds:
                selected = self._buffer.popleft()
                self._buffer_not_full.notify_all()
            if selected is None and not self._buffer:
                # Diagnostic only: buffer is genuinely empty (decode can't
                # keep pace), not just momentarily ahead of position -- this
                # is the "frozen frame" symptom, logged here at its source.
                now = time.monotonic()
                if now - self._last_starve_log > 1.0:
                    print(
                        f"[hdr_viewport] video buffer starved (frame frozen): "
                        f"{os.path.basename(self.path)} position={position_seconds:.2f}s "
                        f"(hw_decode={self.hw_decode})"
                    )
                    self._last_starve_log = now
            return selected

    def _upload_bytes(self, copy_pass, y_bytes, uv_bytes):
        ptr = sdl3.SDL_MapGPUTransferBuffer(self.device, self.transfer_buffer, True)
        ctypes.memmove(ptr, y_bytes, len(y_bytes))
        ctypes.memmove(ptr + self.y_size, uv_bytes, len(uv_bytes))
        sdl3.SDL_UnmapGPUTransferBuffer(self.device, self.transfer_buffer)

        for offset, tex, w, h in (
            (0, self.y_texture, self.width, self.height),
            (self.y_size, self.uv_texture, self.uv_width, self.uv_height),
        ):
            src = sdl3.SDL_GPUTextureTransferInfo()
            src.transfer_buffer = self.transfer_buffer
            src.offset = offset
            src.pixels_per_row = w
            src.rows_per_layer = h
            dst = sdl3.SDL_GPUTextureRegion()
            dst.texture = tex
            dst.mip_level = 0
            dst.layer = 0
            dst.x = dst.y = dst.z = 0
            dst.w = w
            dst.h = h
            dst.d = 1
            sdl3.SDL_UploadToGPUTexture(copy_pass, ctypes.byref(src), ctypes.byref(dst), True)

    def try_upload_latest(self, copy_pass, position_seconds):
        selected = self._advance_to(position_seconds)
        if selected is None:
            return False
        _pts, y_bytes, uv_bytes = selected
        self._upload_bytes(copy_pass, y_bytes, uv_bytes)
        return True

    def release(self):
        self._stop.set()
        with self._buffer_not_full:
            self._buffer_not_full.notify_all()
        # Deliberately not joined: the decode thread never touches SDL_GPU
        # resources (it only ever writes decoded bytes into the Python-level
        # _buffer deque; the actual texture upload happens exclusively on
        # the render thread via try_upload_latest), so it's safe to release
        # these immediately rather than block. release() runs on the same
        # thread as the NSTimer render callback (called from
        # _reconcile_video_sources during a scene jump) -- a synchronous
        # join here could stall the
        # whole UI for up to its timeout if the decode thread's current
        # blocking call (e.g. an I/O hiccup) takes a moment to notice
        # _stop, a real and avoidable source of jank on rapid scene jumps.
        # The still-running daemon thread will notice _stop and exit on its
        # own; its PyAV container is left for garbage collection rather
        # than closed here, since closing it from this thread while the
        # decode thread might still be mid-decode would be a new race.
        sdl3.SDL_ReleaseGPUTexture(self.device, self.y_texture)
        sdl3.SDL_ReleaseGPUTexture(self.device, self.uv_texture)
        sdl3.SDL_ReleaseGPUTransferBuffer(self.device, self.transfer_buffer)


class _PlaceholderVideoSource:
    """Stand-in occupying a video path's slot in self._video_sources for the
    real (sometimes multi-tick -- av.open() is genuine file I/O) window
    between the path becoming wanted and _VideoSource.prepare() finishing on
    the background loader. Without this, _composite_elements_pass finds
    nothing for the element and skips drawing it entirely -- which reads as
    a black flash (the render pass's own clear color) on every scene jump,
    a visible regression from when _VideoSource construction (including its
    own neutral-chroma placeholder upload, see that class's __init__
    comment) ran synchronously and so already existed by the first tick.

    Fixed tiny (2x2) size: the video pipeline always draws a source as a
    textured quad stretched to the element's rect via RectUniform, so the
    texture's real pixel dimensions never matter -- this looks pixel-for-
    pixel identical to a correctly-sized _VideoSource showing the same
    neutral fill before its own first decoded frame lands."""

    is_hdr = False

    def __init__(self, device):
        self.device = device
        w = h = 2
        self.y_texture = _make_texture(device, sdl3.SDL_GPU_TEXTUREFORMAT_R16_UNORM, w, h, sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER)
        self.uv_texture = _make_texture(
            device, sdl3.SDL_GPU_TEXTUREFORMAT_R16G16_UNORM, w, h, sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER
        )
        y_size, uv_size = w * h * 2, w * h * 4
        transfer_info = sdl3.SDL_GPUTransferBufferCreateInfo()
        transfer_info.usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD
        transfer_info.size = y_size + uv_size
        transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(device, ctypes.byref(transfer_info))
        if not transfer_buffer:
            raise RuntimeError(f"SDL_CreateGPUTransferBuffer failed: {sdl3.SDL_GetError().decode()}")

        # Same neutral-chroma reasoning as _VideoSource's own initial upload:
        # an all-zero UV plane does not decode to black, it clamps to a
        # saturated green (see that class's __init__ comment for the full
        # story).
        zero_y = bytes(y_size)
        neutral_chroma_word = round((512 / 1023) * 65535).to_bytes(2, "little")
        neutral_uv = (neutral_chroma_word * 2) * (w * h)
        ptr = sdl3.SDL_MapGPUTransferBuffer(device, transfer_buffer, True)
        ctypes.memmove(ptr, zero_y, y_size)
        ctypes.memmove(ptr + y_size, neutral_uv, uv_size)
        sdl3.SDL_UnmapGPUTransferBuffer(device, transfer_buffer)

        cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(device)
        copy_pass = sdl3.SDL_BeginGPUCopyPass(cmdbuf)
        for offset, tex in ((0, self.y_texture), (y_size, self.uv_texture)):
            src = sdl3.SDL_GPUTextureTransferInfo()
            src.transfer_buffer = transfer_buffer
            src.offset = offset
            src.pixels_per_row = w
            src.rows_per_layer = h
            dst = sdl3.SDL_GPUTextureRegion()
            dst.texture = tex
            dst.mip_level = 0
            dst.layer = 0
            dst.x = dst.y = dst.z = 0
            dst.w = w
            dst.h = h
            dst.d = 1
            sdl3.SDL_UploadToGPUTexture(copy_pass, ctypes.byref(src), ctypes.byref(dst), True)
        sdl3.SDL_EndGPUCopyPass(copy_pass)
        sdl3.SDL_SubmitGPUCommandBuffer(cmdbuf)
        sdl3.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer)

    def try_upload_latest(self, copy_pass, position_seconds):
        return False

    def release(self):
        sdl3.SDL_ReleaseGPUTexture(self.device, self.y_texture)
        sdl3.SDL_ReleaseGPUTexture(self.device, self.uv_texture)


_SVG_RASTER_SIZE = 1024


def _rasterize_svg(path):
    """Phase 7 Part 5: tool-cursor icons (and any user-chosen custom cursor
    SVG) are rasterized entirely in Python via QSvgRenderer -- already
    available in this same PySide6 process, confirmed via a standalone
    go/no-go prototype (prototypes/hdr_phase7_part5_stage0_svg_rasterize_test.py)
    before this was wired in for real. Rasterizes at a fixed base resolution
    regardless of final on-screen size (matching how the texture is decoded
    once and cached by path, independent of the current zoom/story
    resolution -- the same principle _ImageSource already follows for real
    images), aspect-correct and centered like Qt's own Image.PreserveAspectFit
    (the fillMode the real Qt-side cursor Image already uses)."""
    renderer = QSvgRenderer(path)
    if not renderer.isValid():
        raise RuntimeError(f"QSvgRenderer failed to load {path!r}")
    size = _SVG_RASTER_SIZE
    image = QImage(size, size, QImage.Format.Format_RGBA8888)
    image.fill(Qt.GlobalColor.transparent)
    view_box = renderer.viewBoxF()
    if view_box.width() <= 0 or view_box.height() <= 0:
        raise RuntimeError(f"{path!r} has no usable viewBox: {view_box}")
    scale = min(size / view_box.width(), size / view_box.height())
    draw_w = view_box.width() * scale
    draw_h = view_box.height() * scale
    target_rect = QRectF((size - draw_w) / 2.0, (size - draw_h) / 2.0, draw_w, draw_h)
    painter = QPainter(image)
    renderer.render(painter, target_rect)
    painter.end()
    return image, size, size


class _ImageSource:
    """One-shot decode of a plain SDR image (PNG/JPG, including alpha, or an
    SVG tool-cursor icon) to an RGBA8 texture -- no threading, no ring
    buffer, since these are static (decoded once and cached by (path, rev)
    -- see HDRVideoBridge._reconcile_image_sources). Raster images decoded
    via PyAV, already a confirmed dependency; validated directly in
    prototypes/hdr_phase5_mixed_compositing_test.py against a real JPG.
    SVGs decoded via QSvgRenderer -- see _rasterize_svg()."""

    def __init__(self, device, path):
        self.device = device
        path = _strip_file_scheme(path)

        if path.lower().endswith(".svg"):
            image, self.width, self.height = _rasterize_svg(path)
            raw = bytes(image.constBits())
            row_bytes = self.width * 4
            bytes_per_line = image.bytesPerLine()
            if bytes_per_line == row_bytes:
                data = raw
            else:
                data = b"".join(raw[r * bytes_per_line : r * bytes_per_line + row_bytes] for r in range(self.height))
        else:
            container = av.open(path)
            frame = next(container.decode(video=0))
            rgba = frame.reformat(format="rgba")
            self.width, self.height = rgba.width, rgba.height
            plane = rgba.planes[0]
            container.close()
            # plane.line_size (bytes per row, as decoded) can be larger than
            # width*4 due to row-alignment padding -- this only happened to be
            # equal for the one JPG this was originally validated against.
            # Uploading the raw padded buffer while telling SDL_GPU the
            # destination-width-based stride reads every row after the first
            # starting a few bytes off from where it actually began, an offset
            # that compounds every row -- exactly the diagonal-shear/skew
            # artifact seen on a real rasterized text PNG (whose width, unlike a
            # video frame's, has no reason to land on a convenient alignment
            # boundary). Tried telling SDL_GPU the real stride via
            # pixels_per_row instead of stripping -- confirmed via a direct
            # GPU-roundtrip test that this alone did *not* fix it (the upload
            # still sheared), so rather than chase SDL_GPU's exact multi-row
            # transfer semantics further, just strip the padding in Python
            # first so the buffer handed to SDL is always genuinely
            # tightly-packed, matching what it already assumes.
            raw = bytes(_plane_bytes(plane))
            row_bytes = self.width * 4
            if plane.line_size == row_bytes:
                data = raw
            else:
                data = b"".join(raw[r * plane.line_size : r * plane.line_size + row_bytes] for r in range(self.height))

        self.texture = _make_texture(
            device, sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, self.width, self.height, sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER
        )
        transfer_info = sdl3.SDL_GPUTransferBufferCreateInfo()
        transfer_info.usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD
        transfer_info.size = len(data)
        transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(device, ctypes.byref(transfer_info))
        if not transfer_buffer:
            raise RuntimeError(f"SDL_CreateGPUTransferBuffer failed: {sdl3.SDL_GetError().decode()}")

        ptr = sdl3.SDL_MapGPUTransferBuffer(device, transfer_buffer, True)
        ctypes.memmove(ptr, data, len(data))
        sdl3.SDL_UnmapGPUTransferBuffer(device, transfer_buffer)

        cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(device)
        copy_pass = sdl3.SDL_BeginGPUCopyPass(cmdbuf)
        src = sdl3.SDL_GPUTextureTransferInfo()
        src.transfer_buffer = transfer_buffer
        src.offset = 0
        src.pixels_per_row = self.width
        src.rows_per_layer = self.height
        dst = sdl3.SDL_GPUTextureRegion()
        dst.texture = self.texture
        dst.mip_level = 0
        dst.layer = 0
        dst.x = dst.y = dst.z = 0
        dst.w = self.width
        dst.h = self.height
        dst.d = 1
        sdl3.SDL_UploadToGPUTexture(copy_pass, ctypes.byref(src), ctypes.byref(dst), True)
        sdl3.SDL_EndGPUCopyPass(copy_pass)
        sdl3.SDL_SubmitGPUCommandBuffer(cmdbuf)
        sdl3.SDL_ReleaseGPUTransferBuffer(device, transfer_buffer)

    def release(self):
        sdl3.SDL_ReleaseGPUTexture(self.device, self.texture)


class _ShaderSource:
    """Phase 7 Part 2: a compiled native shader element -- a fragment shader
    (the user's .frag) plus either the user's own .vert or the shared
    DEFAULT_SHADER_VERT_GLSL, each compiled fresh through
    compile_and_reflect_glsl() and built into its own pipeline (unlike the
    fixed built-in pipelines, every user shader is genuinely different MSL).

    Sampler2D uniforms are always standalone file paths (confirmed: no
    sourcesJson/uniformsJson mechanism anywhere lets a shader reference
    another canvas element's already-decoded texture) -- resolved via
    _ImageSource, which decodes just the first frame for a video file.
    Animated/looping video-as-shader-texture is an explicit, known scope
    reduction for this first pass, not yet built; static images are the
    common case and fully supported.

    uniformsJson's non-sampler entries (float/int/vec2/vec3/vec4) are packed
    into a raw uniform buffer matching spirv-cross's reflected member
    offsets -- see pack_uniform_buffer()."""

    def __init__(self, device, frag_path, vert_path):
        self.device = device
        self.frag_path = frag_path
        self.vert_path = vert_path
        self.vertex_shader = None
        self.vertex_code = None
        self.fragment_shader = None
        self.fragment_code = None
        self.pipeline = None
        self._sampler_sources = {}   # uniform name -> _ImageSource
        self._sampler_order = []     # uniform names, ordered by reflected binding
        self._uniform_members = []   # [{name, type, offset}] from reflection
        self._uniform_block_size = 0
        # The user's own shader renders into this small R8G8B8A8_UNORM
        # texture -- an "SDR-space image" the shader produces fresh every
        # tick -- rather than writing straight into the shared linear-nits
        # buffer. Without this, a shader's raw fragColor (e.g. 1.0 for
        # white) would be composited as literal *nits* with no reference-
        # white scaling at all: 1 nit PQ-encodes to a code value of ~0.15,
        # nearly black next to a 600-nit HDR video or 203-nit SDR image --
        # confirmed empirically (a real user shader looked "solid black
        # with a thin bright sliver" until this fix). Routing through this
        # intermediate texture lets the *existing*, already-correct SDR
        # image path (srgb_eotf() * _SDR_REF_NITS, same as _ImageSource)
        # handle the nits scaling, so a shader author's colors read the
        # same as they would have in Qt's own SDR ShaderEffect rendering,
        # with zero extra requirements on their GLSL.
        self.output_texture = None
        self.output_w = 0
        self.output_h = 0
        # A uniform named "time" is auto-driven from a live wall-clock (never
        # read from uniformsJson) -- mirrors the old Qt ShaderEffect system's
        # own special-casing of a "time" property (an infinite NumberAnimation
        # in understoryui.qml's buildShaderQml), so a shader written to expect
        # a free-running clock behaves the same way under either pipeline.
        # Not reset on scene revisit -- an ever-increasing clock is what the
        # Qt convention already provides too (its NumberAnimation never resets
        # either), so looping is left entirely up to the shader's own math
        # (fract()/sin()/cos()), not something this harness manages.
        self._start_time = time.monotonic()

        with tempfile.TemporaryDirectory() as tmpdir:
            actual_vert_path = vert_path
            if not actual_vert_path:
                actual_vert_path = os.path.join(tmpdir, "default.vert")
                with open(actual_vert_path, "w") as f:
                    f.write(DEFAULT_SHADER_VERT_GLSL)
            vert_msl, _vert_reflection = compile_and_reflect_glsl(actual_vert_path, "vert", "vs_main")
            frag_msl, frag_reflection = compile_and_reflect_glsl(frag_path, "frag", "fs_main")

        textures = sorted(frag_reflection.get("textures", []), key=lambda t: t["binding"])
        self._sampler_order = [t["name"] for t in textures]

        ubos = frag_reflection.get("ubos", [])
        if ubos:
            ubo = ubos[0]
            self._uniform_block_size = ubo["block_size"]
            self._uniform_members = frag_reflection["types"][ubo["type"]]["members"]

        self.vertex_shader, self.vertex_code = _create_shader(
            device, vert_msl, sdl3.SDL_GPU_SHADERSTAGE_VERTEX, num_uniform_buffers=1
        )
        self.fragment_shader, self.fragment_code = _create_shader(
            device, frag_msl, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT,
            num_samplers=len(self._sampler_order),
            num_uniform_buffers=1 if ubos else 0,
        )
        # Targets R8G8B8A8_UNORM (SDR-image-like), not the shared linear-nits
        # buffer -- see output_texture's docstring above.
        self.pipeline = _create_pipeline(
            device, self.vertex_shader, self.fragment_shader, sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, blend=True
        )

    def ensure_output_texture(self, w, h):
        """(Re)allocates output_texture if the element's on-screen pixel
        size differs from what it's currently sized for."""
        w, h = max(1, int(round(w))), max(1, int(round(h)))
        if (w, h) == (self.output_w, self.output_h) and self.output_texture is not None:
            return
        if self.output_texture is not None:
            sdl3.SDL_ReleaseGPUTexture(self.device, self.output_texture)
        self.output_w, self.output_h = w, h
        self.output_texture = _make_texture(
            self.device, sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, w, h,
            sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        )

    def render_to_output(self, cmdbuf, sampler, uniforms_list):
        """Runs the user's own shader in its own render pass, filling the
        whole of output_texture (a fullscreen quad from its own point of
        view -- this texture IS this shader's entire canvas). Must complete
        before the main per-element compositing pass opens, since SDL_GPU
        (like Vulkan/Metal) doesn't allow nested/interleaved render passes.
        No-ops (leaves stale content) if any sampler failed to open --
        caller is responsible for deciding whether to still composite it."""
        textures = self.sampler_textures()
        if any(t is None for t in textures):
            return
        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = self.output_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_CLEAR
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        target.clear_color = sdl3.SDL_FColor(0.0, 0.0, 0.0, 0.0)
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)
        rect_u = RectUniform((ctypes.c_float * 4)(-1.0, 1.0, 1.0, -1.0))
        sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
        uniform_bytes = self.pack_uniform_buffer(uniforms_list)
        if uniform_bytes is not None:
            ub = ctypes.create_string_buffer(uniform_bytes, len(uniform_bytes))
            sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ub, len(uniform_bytes))
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline)
        if textures:
            bindings = (sdl3.SDL_GPUTextureSamplerBinding * len(textures))(*[
                sdl3.SDL_GPUTextureSamplerBinding(texture=t.texture, sampler=sampler) for t in textures
            ])
            sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, bindings, len(textures))
        sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
        sdl3.SDL_EndGPURenderPass(render_pass)

    def sync_samplers(self, uniforms_list):
        """Ensures an _ImageSource exists for each sampler2D uniform's
        current file-path value, releasing/reopening when the path changes.
        Call once per tick this shader is drawn (cheap no-op if unchanged,
        matching _reconcile_image_sources' pattern)."""
        by_name = {u.get("name"): u for u in uniforms_list if isinstance(u, dict)}
        for name in self._sampler_order:
            u = by_name.get(name)
            path = str(u.get("value") or "") if u else ""
            existing = self._sampler_sources.get(name)
            if existing is not None and existing.path == path:
                continue
            if existing is not None:
                existing.release()
                del self._sampler_sources[name]
            if not path:
                continue
            try:
                source = _ImageSource(self.device, path)
                source.path = path
                self._sampler_sources[name] = source
            except Exception as exc:
                print(f"[hdr_viewport] failed to open shader sampler texture {path!r} for uniform {name!r}: {exc}")

    def pack_uniform_buffer(self, uniforms_list):
        """Packs uniformsJson's non-sampler {name,type,value} entries into a
        raw byte buffer matching the reflected uniform block layout, or None
        if this shader declares no uniform block at all."""
        if self._uniform_block_size == 0:
            return None
        buf = bytearray(self._uniform_block_size)
        by_name = {u.get("name"): u for u in uniforms_list if isinstance(u, dict)}
        for member in self._uniform_members:
            name = member.get("name")
            offset = member["offset"]
            t = member.get("type")
            if name == "time" and t == "float":
                struct.pack_into("<f", buf, offset, time.monotonic() - self._start_time)
                continue
            u = by_name.get(name)
            if u is None:
                continue
            value = u.get("value")
            try:
                if t == "float":
                    struct.pack_into("<f", buf, offset, float(value))
                elif t == "int":
                    struct.pack_into("<i", buf, offset, int(value))
                elif t == "vec2":
                    struct.pack_into("<2f", buf, offset, *[float(v) for v in value])
                elif t == "vec3":
                    struct.pack_into("<3f", buf, offset, *[float(v) for v in value])
                elif t == "vec4":
                    struct.pack_into("<4f", buf, offset, *[float(v) for v in value])
            except (TypeError, ValueError, struct.error):
                continue
        return bytes(buf)

    def sampler_textures(self):
        """Ordered list of _ImageSource (or None) matching self._sampler_order's
        binding order -- a None entry means that sampler's source failed to
        open; the caller should skip drawing this shader entirely rather
        than bind a hole."""
        return [self._sampler_sources.get(name) for name in self._sampler_order]

    def release(self):
        for source in self._sampler_sources.values():
            source.release()
        self._sampler_sources = {}
        if self.output_texture is not None:
            sdl3.SDL_ReleaseGPUTexture(self.device, self.output_texture)
            self.output_texture = None
        if self.pipeline is not None:
            sdl3.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline)
        if self.vertex_shader is not None:
            sdl3.SDL_ReleaseGPUShader(self.device, self.vertex_shader)
        if self.fragment_shader is not None:
            sdl3.SDL_ReleaseGPUShader(self.device, self.fragment_shader)


def _qjsvalue_to_list(value):
    """QQuickItem.property() on a QML `var`/`list<var>` holding a JS array
    (e.g. nativeVideoPlayers' [{path, player}, ...]) returns a raw QJSValue,
    not an already-converted Python list -- unlike plain bool/str/number
    properties, which PySide6 does convert automatically. .toVariant()
    is the real conversion step (QJSValue -> QVariantList -> Python list of
    dicts, with each QObject value inside preserved as a live PyObject
    wrapper via QVariant's native QObject* support)."""
    if value is None:
        return []
    variant = value.toVariant() if hasattr(value, "toVariant") else value
    return list(variant) if variant else []


@dataclass(frozen=True)
class QmlSnapshot:
    """One atomic, self-consistent read of every piece of "structural" QML
    state the render loop needs, taken once per Qt sync (see
    HDRVideoBridge._sync_snapshot, connected to QQuickWindow.beforeSynchronizing).

    Phase 4/5's render loop polled `.property()` directly on an independent
    NSTimer tick, entirely unsynchronized with Qt's own property-update
    cycle. QML compound changes -- e.g. performSwap() flipping
    foregroundLayer + currentSceneId + clearing staging all in one
    synchronous JS block -- could be observed mid-update by a poll landing
    at the wrong run-loop instant, producing a torn read (new elements list
    paired with a stale video path, or vice versa). beforeSynchronizing
    fires with the GUI thread quiescent and the frame's bindings already
    settled, so a snapshot built there is always one fully-applied
    generation, never a mix of two. The render tick reads self._snapshot
    once per tick instead of calling .property() itself for anything held
    here -- eliminating that whole class of bug by construction, at the
    cost of the snapshot occasionally lagging Qt's true state by up to one
    frame (never torn, just briefly the previous consistent generation).

    Deliberately excluded: MediaPlayer.position. Qt Quick stops emitting
    beforeSynchronizing/frameSwapped when its own scene is idle (measured
    ~2 Hz on a static scene vs. ~60 Hz while something is animating), so a
    snapshot-sourced position would judder/stall video during any steady
    playback period where the rest of the UI isn't independently
    animating. Position stays a direct, live `.property("position")` read
    on the player object *references* captured here, every NSTimer tick,
    regardless of how stale the rest of the snapshot is.
    """

    preview_active: bool = False
    transition_flag: str | None = None
    dissolve_opacity: float = 0.0
    wipe_progress: float = 0.0
    wipe_feather: float = 0.0
    wipe_direction: int = 0
    slide_progress: float = 0.0
    slide_direction: int = 0
    look_progress: float = 0.0
    look_yaw: float = 0.0
    look_pitch: float = 0.0
    look_fov_mm: float = 24.0
    look_overshoot: float = 1.0
    look_shutter: float = 0.0
    active_native_eligible: bool = False
    staging_native_eligible: bool = False
    active_native_transition_eligible: bool = False
    staging_native_transition_eligible: bool = False
    active_native_elements_json: str = "[]"
    staging_native_elements_json: str = "[]"
    # Phase 7 Part 4: [{x1,y1,x2,y2}] for the single selected element's
    # border+handles, or "[]" -- see SceneContent.qml's _buildNativeChrome().
    active_native_chrome_json: str = "[]"
    # Phase 7 Part 4: viewport-level chrome (creation rubber-bands, box-
    # select marquee, multi-select groupBBox) -- see understoryui.qml's
    # viewport.nativeChromeExtraJson.
    native_chrome_extra_json: str = "[]"
    # Phase 10 Stage 1: one {"path": str, "player": QObject} dict per
    # native-eligible video element, replacing the old singular
    # active_native_video_path/active_native_video_player pair (and its
    # staging-side twin) now that any number of videos can be native at
    # once -- see SceneContent.qml's nativeVideoPlayers.
    active_native_video_players: list = field(default_factory=list)
    staging_native_video_players: list = field(default_factory=list)
    # Story resolution -- read from the same snapshot rather than a direct
    # self._viewport poll inside _ensure_linear_buffer(), so that function
    # (part of the render core) takes its input as plain data too.
    content_width: int = 1920
    content_height: int = 1080
    # Phase 7 Part 4: true whenever the scene editor screen itself is showing
    # (covers both plain editing and previewing) -- see _should_be_visible.
    scene_editor_visible: bool = False
    # Mirrors viewportBlackOverlay.opacity (understoryui.qml) -- the black
    # fade Qt already plays on scene-editor enter/exit. Qt's own overlay
    # Rectangle sits above `viewport` in its scene graph, but the native
    # render surface sits above the whole Qt window at the OS compositor
    # level, so it never sees that overlay -- see _composite_fade_pass.
    fade_black_opacity: float = 0.0
    # Mirrors viewport.navPickerOpen -- true while the nav-jump/
    # interactivity-target scene picker (navigationViewportOverlay, a Qt
    # Rectangle inside `viewport`) is open. See _should_be_visible: the
    # native window hides while this is true so that Qt overlay (and clicks
    # into it, already passed through regardless) actually becomes visible.
    nav_picker_open: bool = False


class HDRVideoBridge(QObject):
    """Owns the native SDL/Cocoa side of the native preview pipeline. Does
    nothing (leaves `active` False) unless nativeRenderMode is "sdr" or
    "hdr", the platform/dependencies check out, and -- for "hdr" mode only
    -- an HDR10 swapchain is actually supported ("sdr" mode has no such
    requirement)."""

    # Emitted once a capture_thumbnail() request's PNG is actually on disk
    # (path, success) -- fired from a background thread (see
    # _poll_thumbnail_fence), so QML's connected handler runs via Qt's
    # automatic queued cross-thread connection, on the main thread, once its
    # event loop gets to it.
    thumbnailCaptured = Signal(str, bool)

    def __init__(self, window, parent=None):
        super().__init__(parent)
        self.active = False
        # Phase 8: "sdr" or "hdr" once attached, matching appSettings.
        # nativeRenderMode -- set at the top of _attach(), read by
        # _composite_elements_pass's HLG-graded-video branch.
        self._mode = None
        self._window = window
        self._device = None
        self._sdl_window = None
        self._timer = None
        self._snapshot = QmlSnapshot()
        # Phase 10 Stage 1: one _VideoSource per video path currently
        # referenced by any element list this tick (steady-state, or the
        # active+staging union during a transition) -- replaces the old
        # single self._source/_current_path slot (and the separate
        # _transition_out_source/_transition_in_source pair) now that any
        # number of videos can be native at once. Reconciled the same way
        # _image_sources already is, see _reconcile_video_sources. A
        # crossfading video's secondary ("B") decode instance is cached
        # here too, under a synthetic f"{path}#B" key -- same file, a
        # second fully independent decode at a different playback
        # position, not a different asset.
        self._video_sources = {}
        # Shared background loader for slow, GPU-free source setup work
        # (currently just _VideoSource.prepare(); image/shader reconciliation
        # are meant to move onto this same instance later) -- see
        # _AsyncSourceLoader's docstring for why this exists.
        self._async_loader = _AsyncSourceLoader()
        # Phase 10: dict[path -> monotonic timestamp last referenced],
        # driving the grace period above -- only touched for plain-path
        # keys (crossfade "#B" secondary sources are always released
        # immediately, no grace period, see _reconcile_crossfade_sources).
        self._video_source_last_used = {}
        # Phase 10 Stage 2: dict[path -> {"opacity": float, "needed": bool,
        # "player_b": QObject}], rebuilt fresh every steady-state render
        # tick from Qt's own already-computed crossfade state (see
        # _poll_crossfade_state) -- native never re-derives preroll/fade
        # timing itself, just mirrors whatever Qt's state machine (which
        # keeps running regardless of native mode, since it also drives
        # audio) has already decided.
        self._crossfade_state = {}
        self._sampler = None
        self._vertex_shader = None
        self._vs_code = None
        self._last_rect = None

        # Phase 5: linear-light offscreen compositing. Stage A added video;
        # Stage B adds images (rendered via the SDR pipeline, cached by
        # (path, rev) in _image_sources so static content isn't re-decoded
        # every tick).
        self._linear_format = None
        self._linear_buffer = None
        self._linear_w = None
        self._linear_h = None
        self._quad_vertex_shader = None
        self._quad_vs_code = None
        self._video_linear_fs = None
        self._video_linear_fs_code = None
        self._video_linear_pipeline = None
        # Phase 7 Part 1: SDR video sibling of the HDR video pipeline above.
        self._sdr_video_fs = None
        self._sdr_video_fs_code = None
        self._sdr_video_pipeline = None
        self._sdr_fs = None
        self._sdr_fs_code = None
        self._sdr_pipeline = None
        self._chrome_fs = None
        self._chrome_fs_code = None
        self._chrome_pipeline = None
        self._final_fs = None
        self._final_fs_code = None
        self._final_pipeline = None
        # Scene-card thumbnail capture (see capture_thumbnail): always the
        # SDR encode shader/pipeline/texture regardless of self._mode, so a
        # thumbnail is always SDR even while live-previewing in HDR mode --
        # built once in _attach(), independent of self._final_fs/_pipeline
        # above (which follow the live mode).
        self._thumb_fs = None
        self._thumb_fs_code = None
        self._thumb_pipeline = None
        self._thumb_texture = None
        self._thumb_transfer_buffer = None
        # Set by capture_thumbnail(), cleared by _poll_thumbnail_fence() once
        # the GPU work it submitted is actually done -- see both.
        self._thumb_pending_fence = None
        self._thumb_pending_path = None
        self._image_sources = {}
        # Phase 7 Part 2: compiled native shader elements, keyed by
        # (fragPath, vertPath) -- reconciled the same way _image_sources is.
        self._shader_sources = {}
        self._last_elements_json = None
        # Phase 7 Part 5: the tool-cursor icon. Only ever one active per
        # tick (unlike _image_sources' multi-entry reconciliation, which is
        # keyed off the element list and only re-runs when that list
        # changes) -- a single slot swapped whenever the incoming path
        # differs, released when no cursor item is present this tick.
        self._cursor_icon_source = None
        self._cursor_icon_path = None

        # Transition-compositing state (Stage 4). `_active_flag` mirrors the
        # raw QML transition flag (None/"dissolve"/"wipe"/"slide"/"look") so
        # a direct type-to-type change (one transition's onStopped firing and
        # the next starting within the same synchronous QML tick, e.g. a
        # queued jump) is still detected -- comparing against the committed
        # `_active_transition` alone would miss it whenever the outgoing one
        # had fallen back to "qt_fallback" (a value _current_transition_flag()
        # never returns, so it would never compare equal and would instead
        # re-run begin/end every tick). `_active_transition` is the committed
        # rendering mode: None (steady state), "wipe"/"slide"/"look" (native
        # compositing live), or "qt_fallback" (a transition is running but Qt
        # is doing the compositing -- dissolve was never ported, or one side
        # of the jump doesn't qualify -- so we just stay hidden for its
        # duration).
        self._active_flag = None
        self._active_transition = None

        # Phase 6 Part 2: mixed-scene native transitions. Each side of a
        # transition is first composited through the same per-element pass
        # steady-state rendering uses, into its own linear-nits buffer, then
        # blended by the two-input shaders below -- see _render_transition.
        # Allocated lazily (_ensure_transition_buffers) on first native
        # transition rather than unconditionally, since they're otherwise
        # idle memory during steady-state playback.
        self._out_linear_buffer = None
        self._in_linear_buffer = None
        self._linear_dissolve_pipeline = None
        self._linear_wipe_pipeline = None
        self._linear_slide_pipeline = None
        self._linear_look_pipeline = None
        self._linear_dissolve_fs = None
        self._linear_wipe_fs = None
        self._linear_slide_fs = None
        self._linear_look_fs = None
        self._linear_dissolve_fs_code = None
        self._linear_wipe_fs_code = None
        self._linear_slide_fs_code = None
        self._linear_look_fs_code = None

        if not _HDR_DEPS_AVAILABLE or sys.platform != "darwin":
            return

        self._content_scaler = window.findChild(QQuickItem, "contentScaler")
        self._viewport = window.findChild(QObject, "viewport")
        self._app_settings = window.findChild(QObject, "appSettings")
        if self._content_scaler is None or self._viewport is None or self._app_settings is None:
            print(
                f"[hdr_viewport] required QML objects not found (contentScaler={self._content_scaler}, "
                f"viewport={self._viewport}, appSettings={self._app_settings}) -- using Qt pipeline"
            )
            return
        mode = str(self._app_settings.property("nativeRenderMode") or "off")
        if mode not in ("sdr", "hdr"):
            return

        try:
            self._attach(mode)
        except Exception as exc:
            print(f"[hdr_viewport] failed to attach native pipeline, falling back to Qt: {exc}")
            self._teardown_partial()
            return

        self.active = True
        print(f"[hdr_viewport] native pipeline attached (mode={mode}) (Phase 8: native SDR mode)")

    def _attach(self, mode):
        self._mode = mode
        qt_nsview = objc.objc_object(c_void_p=int(self._window.winId()))
        qt_nswindow = qt_nsview.window()

        _sdl_check(sdl3.SDL_Init(sdl3.SDL_INIT_VIDEO), "SDL_Init")
        sdl_window = sdl3.SDL_CreateWindow(b"understory native HDR overlay", 100, 100, sdl3.SDL_WINDOW_BORDERLESS)
        if not sdl_window:
            raise RuntimeError(f"SDL_CreateWindow failed: {sdl3.SDL_GetError().decode()}")
        self._sdl_window = sdl_window
        sdl_props = sdl3.SDL_GetWindowProperties(sdl_window)
        sdl_nswindow_ptr = sdl3.SDL_GetPointerProperty(sdl_props, sdl3.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, None)
        self._sdl_nswindow = objc.objc_object(c_void_p=sdl_nswindow_ptr)

        device = sdl3.SDL_CreateGPUDevice(sdl3.SDL_GPU_SHADERFORMAT_MSL, True, None)
        if not device:
            raise RuntimeError(f"SDL_CreateGPUDevice failed: {sdl3.SDL_GetError().decode()}")
        self._device = device
        _sdl_check(sdl3.SDL_ClaimWindowForGPUDevice(device, sdl_window), "SDL_ClaimWindowForGPUDevice")

        # Checked before attaching as a child window / registering the close
        # observer below -- on an unsupported display we bail out here and
        # _teardown_partial() destroys the (not-yet-attached) SDL window,
        # with nothing else left dangling for the fallback-to-Qt path.
        # Phase 8: this capability check only applies to "hdr" mode --
        # SDL_GPU_SWAPCHAINCOMPOSITION_SDR (mode == "sdr") needs no query at
        # all, it's the universal baseline every display supports (confirmed
        # via prototypes/hdr_phase8_stage0_sdr_swapchain_test.py). This is
        # the actual fix for "no HDR10 display -> no native pipeline at
        # all" -- users without an HDR display can now pick sdr mode instead.
        if mode == "hdr":
            supports_hdr10 = sdl3.SDL_WindowSupportsGPUSwapchainComposition(
                device, sdl_window, sdl3.SDL_GPU_SWAPCHAINCOMPOSITION_HDR10_ST2084
            )
            if not supports_hdr10:
                print("[hdr_viewport] display doesn't support HDR10_ST2084 -- falling back to Qt pipeline")
                raise RuntimeError("HDR10_ST2084 swapchain not supported on this display")

        # Cocoa gives every NSWindow a default drop shadow, including
        # borderless ones -- without disabling it, a thin grey line/glow is
        # visible around the video's edges against the black Qt background.
        self._sdl_nswindow.setHasShadow_(False)
        qt_nswindow.addChildWindow_ordered_(self._sdl_nswindow, 1)  # NSWindowAbove

        # Phase 7 Part 4: the plain editor canvas now goes native too, not
        # just preview -- and unlike preview, editing needs real mouse
        # interaction (select/drag/resize) to keep working. Rather than
        # reimplementing hit-testing/drag math natively, Qt's own chrome
        # (selection border/handles/rubber-bands) stays fully live but
        # invisible (opacity 0, not visible: false -- see SceneContent.qml's
        # qtPresentationSuspended usage) underneath this opaque window, and
        # ignoresMouseEvents passes every click straight through to it.
        # Verified empirically (prototypes/hdr_phase7_part4_stage0_ignores_mouse_test.py)
        # that this reaches the specific parent window in the same Cocoa
        # child-window group, not whatever's behind that in full desktop
        # z-order, and doesn't affect the parent's own window-level drag/resize.
        self._sdl_nswindow.setIgnoresMouseEvents_(True)

        def on_qt_window_will_close(notification):
            from PySide6.QtGui import QGuiApplication

            app = QGuiApplication.instance()
            if app is not None:
                app.quit()

        NSNotificationCenter.defaultCenter().addObserverForName_object_queue_usingBlock_(
            NSWindowWillCloseNotification, qt_nswindow, None, on_qt_window_will_close
        )

        composition = (
            sdl3.SDL_GPU_SWAPCHAINCOMPOSITION_HDR10_ST2084
            if mode == "hdr"
            else sdl3.SDL_GPU_SWAPCHAINCOMPOSITION_SDR
        )
        _sdl_check(
            sdl3.SDL_SetGPUSwapchainParameters(device, sdl_window, composition, sdl3.SDL_GPU_PRESENTMODE_VSYNC),
            "SDL_SetGPUSwapchainParameters",
        )
        # Queried rather than hardcoded (previously always
        # R10G10B10A2_UNORM) -- the real format is a function of the active
        # composition mode; SDR composition returns a standard 8-bit format
        # (confirmed B8G8R8A8_UNORM via prototypes/hdr_phase8_stage0_sdr_
        # swapchain_test.py), HDR10 returns the 10-bit format the old
        # hardcoded value assumed. Must be queried after
        # SDL_SetGPUSwapchainParameters, not before.
        swapchain_format = sdl3.SDL_GetGPUSwapchainTextureFormat(device, sdl_window)
        if swapchain_format == sdl3.SDL_GPU_TEXTUREFORMAT_INVALID:
            raise RuntimeError("SDL_GetGPUSwapchainTextureFormat returned INVALID")

        self._vertex_shader, self._vs_code = _create_shader(device, VERTEX_SHADER_MSL, sdl3.SDL_GPU_SHADERSTAGE_VERTEX)

        # Steady-state pipeline (Phase 5 Stage A): composite into a linear-
        # light offscreen buffer via a per-element quad, then PQ-encode once
        # in a final fullscreen pass. Video is still the only element this
        # stage, but always drawn through the general per-element mechanism
        # now (see prototypes/hdr_phase5_mixed_compositing_test.py, the
        # validated reference) so images/text can be added in Stage B/C
        # without another rendering-model change.
        self._linear_format = sdl3.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT
        self._quad_vertex_shader, self._quad_vs_code = _create_shader(
            device, QUAD_VERTEX_SHADER_MSL, sdl3.SDL_GPU_SHADERSTAGE_VERTEX, num_uniform_buffers=1
        )
        self._video_linear_fs, self._video_linear_fs_code = _create_shader(
            device, VIDEO_LINEAR_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
        )
        # Phase 7 Part 1: SDR video sibling -- same 2-sampler/1-uniform-buffer
        # shape as the HDR video shader above, picked per-source in
        # _composite_elements_pass based on _VideoSource.is_hdr.
        self._sdr_video_fs, self._sdr_video_fs_code = _create_shader(
            device, SDR_VIDEO_LINEAR_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
        )
        # Stage B: SDR quad pipeline for images (and, later, rasterized text).
        self._sdr_fs, self._sdr_fs_code = _create_shader(
            device, SDR_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=1, num_uniform_buffers=1
        )
        # Phase 7 Part 4: solid-color chrome quad (selection border edges +
        # handle dots) -- no texture/sampler at all, just a uniform color.
        self._chrome_fs, self._chrome_fs_code = _create_shader(
            device, CHROME_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=0, num_uniform_buffers=1
        )
        # Phase 8: which final-encode shader gets built depends on mode --
        # kept under the same self._final_fs/_final_pipeline attribute
        # names either way (rather than two parallel sets of attributes) so
        # the single steady-state render call site and teardown's release
        # loop need zero mode-aware changes.
        if mode == "sdr":
            self._final_fs, self._final_fs_code = _create_shader(
                device, SDR_FINAL_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=1, num_uniform_buffers=1
            )
        else:
            self._final_fs, self._final_fs_code = _create_shader(
                device, FINAL_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=1, num_uniform_buffers=0
            )
        self._video_linear_pipeline = _create_pipeline(
            device, self._quad_vertex_shader, self._video_linear_fs, self._linear_format, blend=True
        )
        self._sdr_video_pipeline = _create_pipeline(
            device, self._quad_vertex_shader, self._sdr_video_fs, self._linear_format, blend=True
        )
        self._sdr_pipeline = _create_pipeline(
            device, self._quad_vertex_shader, self._sdr_fs, self._linear_format, blend=True
        )
        self._chrome_pipeline = _create_pipeline(
            device, self._quad_vertex_shader, self._chrome_fs, self._linear_format, blend=True
        )
        self._final_pipeline = _create_pipeline(device, self._vertex_shader, self._final_fs, swapchain_format)

        # Scene-card thumbnails must always render as SDR, even in "hdr" live
        # mode -- built unconditionally here (not branched on `mode` like
        # self._final_fs/_pipeline above), targeting a small fixed-size,
        # fixed-format (R8G8B8A8_UNORM) offscreen texture rather than
        # `swapchain_format`, which in "hdr" mode is a 10-bit PQ format
        # unsuitable for a plain PNG. See capture_thumbnail().
        self._thumb_fs, self._thumb_fs_code = _create_shader(
            device, SDR_FINAL_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=1, num_uniform_buffers=1
        )
        thumb_format = sdl3.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
        self._thumb_pipeline = _create_pipeline(device, self._vertex_shader, self._thumb_fs, thumb_format)
        self._thumb_texture = _make_texture(
            device, thumb_format, _THUMB_W, _THUMB_H, sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET
        )
        transfer_info = sdl3.SDL_GPUTransferBufferCreateInfo()
        transfer_info.usage = sdl3.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD
        transfer_info.size = _THUMB_W * _THUMB_H * 4
        self._thumb_transfer_buffer = sdl3.SDL_CreateGPUTransferBuffer(device, ctypes.byref(transfer_info))
        if not self._thumb_transfer_buffer:
            raise RuntimeError(f"SDL_CreateGPUTransferBuffer failed: {sdl3.SDL_GetError().decode()}")

        # Placeholder allocation only -- at this point (right after
        # engine.load(), before any story is open) contentWidth/contentHeight
        # are still mainWindow's declared defaults (1920x1080), not
        # necessarily the real story's resolution. _ensure_linear_buffer(),
        # called every render tick, reallocates once the real size is known
        # (and again on any later resolution change) -- skipping that check
        # caused a real bug: a story authored at a resolution other than
        # 1920x1080 rendered zoomed/cropped, since element rects (in real
        # story-space units) were being converted to NDC against this stale
        # placeholder size instead of the actual one.
        self._linear_w = int(self._viewport.property("contentWidth") or 1920)
        self._linear_h = int(self._viewport.property("contentHeight") or 1080)
        self._linear_buffer = _make_texture(
            device, self._linear_format, self._linear_w, self._linear_h,
            sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        )

        # Phase 6 Part 2: two-input linear blend pipelines -- same shared
        # fullscreen-triangle vertex shader as steady-state's own quad pass,
        # but only 2 samplers each (pre-composited linear buffers, not YUV
        # planes -- the original 4-sampler single-video wipe/slide/look
        # pipelines this superseded were removed in Phase 11, see the
        # comment above LINEAR_WIPE_FRAGMENT_MSL's definition).
        # Phase 7 Part 3 adds dissolve alongside these (see
        # LINEAR_DISSOLVE_FRAGMENT_MSL's docstring).
        #
        # Phase 9: dissolve's shader source is mode-branched, same pattern
        # as the final pass (self._final_fs) -- kept under the same
        # self._linear_dissolve_fs/_pipeline attribute names either way, so
        # _render_transition's dissolve branch doesn't need to know which
        # mode built them, only whether to push the extra sdr_ref_nits
        # uniform field.
        if mode == "sdr":
            self._linear_dissolve_fs, self._linear_dissolve_fs_code = _create_shader(
                device, SDR_LINEAR_DISSOLVE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
        else:
            self._linear_dissolve_fs, self._linear_dissolve_fs_code = _create_shader(
                device, LINEAR_DISSOLVE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
        if mode == "sdr":
            self._linear_wipe_fs, self._linear_wipe_fs_code = _create_shader(
                device, SDR_LINEAR_WIPE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
            self._linear_slide_fs, self._linear_slide_fs_code = _create_shader(
                device, SDR_LINEAR_SLIDE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
            self._linear_look_fs, self._linear_look_fs_code = _create_shader(
                device, SDR_LINEAR_LOOK_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
        else:
            self._linear_wipe_fs, self._linear_wipe_fs_code = _create_shader(
                device, LINEAR_WIPE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
            self._linear_slide_fs, self._linear_slide_fs_code = _create_shader(
                device, LINEAR_SLIDE_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
            self._linear_look_fs, self._linear_look_fs_code = _create_shader(
                device, LINEAR_LOOK_FRAGMENT_MSL, sdl3.SDL_GPU_SHADERSTAGE_FRAGMENT, num_samplers=2, num_uniform_buffers=1
            )
        self._linear_dissolve_pipeline = _create_pipeline(device, self._vertex_shader, self._linear_dissolve_fs, swapchain_format)
        self._linear_wipe_pipeline = _create_pipeline(device, self._vertex_shader, self._linear_wipe_fs, swapchain_format)
        self._linear_slide_pipeline = _create_pipeline(device, self._vertex_shader, self._linear_slide_fs, swapchain_format)
        self._linear_look_pipeline = _create_pipeline(device, self._vertex_shader, self._linear_look_fs, swapchain_format)

        sampler_info = sdl3.SDL_GPUSamplerCreateInfo()
        sampler_info.min_filter = sdl3.SDL_GPU_FILTER_LINEAR
        sampler_info.mag_filter = sdl3.SDL_GPU_FILTER_LINEAR
        sampler_info.mipmap_mode = sdl3.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST
        sampler_info.address_mode_u = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
        sampler_info.address_mode_v = sdl3.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
        self._sampler = sdl3.SDL_CreateGPUSampler(device, ctypes.byref(sampler_info))
        if not self._sampler:
            raise RuntimeError(f"SDL_CreateGPUSampler failed: {sdl3.SDL_GetError().decode()}")

        for signal in (
            self._content_scaler.xChanged,
            self._content_scaler.yChanged,
            self._content_scaler.widthChanged,
            self._content_scaler.heightChanged,
            # Phase 7 Part 4: _sync_geometry tracks `viewport` itself (not
            # contentScaler) while plain editing -- also react to its
            # geometry changing (e.g. entering/exiting preview flips which
            # item is tracked and changes viewport's own scale/position).
            self._viewport.xChanged,
            self._viewport.yChanged,
            self._viewport.widthChanged,
            self._viewport.heightChanged,
            self._window.xChanged,
            self._window.yChanged,
            self._window.widthChanged,
            self._window.heightChanged,
            self._window.visibilityChanged,
        ):
            signal.connect(self._sync_geometry)

        # Rebuild the structural-state snapshot every time Qt itself
        # finishes updating and is about to sync the scene graph -- this is
        # the one moment a compound QML change (e.g. performSwap()) is
        # guaranteed fully applied, never partway through. Build one now so
        # self._snapshot isn't still the QmlSnapshot() default on the very
        # first NSTimer tick, before Qt has had a reason to sync yet.
        self._window.beforeSynchronizing.connect(self._sync_snapshot)
        self._sync_snapshot()

        self._timer = NSTimer.timerWithTimeInterval_repeats_block_(1.0 / 60.0, True, lambda t: self._render())
        NSRunLoop.currentRunLoop().addTimer_forMode_(self._timer, NSRunLoopCommonModes)

    def _sync_snapshot(self):
        """Connected to QQuickWindow.beforeSynchronizing. Keep this handler
        to plain QObject.property() reads and dataclass construction only --
        no Cocoa/SDL calls -- so it stays safe even if a future Qt render-
        loop configuration moves signal emission off the main thread.
        Publishing via a single attribute assignment is what makes this
        lock-free: a reader either gets the old snapshot object or the new
        one, never a partially-built one."""
        v = self._viewport
        self._snapshot = QmlSnapshot(
            preview_active=bool(self._window.property("previewActive")),
            transition_flag=(
                "dissolve" if bool(v.property("dissolving")) else
                "wipe" if bool(v.property("wiping")) else
                "slide" if bool(v.property("sliding")) else
                "look" if bool(v.property("looking")) else
                None
            ),
            dissolve_opacity=float(v.property("dissolveOpacity") or 0.0),
            wipe_progress=float(v.property("wipeProgress") or 0.0),
            wipe_feather=float(v.property("wipeFeather") or 0.0),
            wipe_direction=int(v.property("wipeDirection") or 0),
            slide_progress=float(v.property("slideProgress") or 0.0),
            slide_direction=int(v.property("slideDirection") or 0),
            look_progress=float(v.property("lookProgress") or 0.0),
            look_yaw=float(v.property("lookYaw") or 0.0),
            look_pitch=float(v.property("lookPitch") or 0.0),
            look_fov_mm=float(v.property("lookFovMM") or 24.0),
            look_overshoot=float(v.property("lookOvershoot") or 1.0),
            look_shutter=float(v.property("lookShutter") or 0.0),
            active_native_eligible=bool(v.property("activeNativeEligible")),
            staging_native_eligible=bool(v.property("stagingNativeEligible")),
            active_native_transition_eligible=bool(v.property("activeNativeTransitionEligible")),
            staging_native_transition_eligible=bool(v.property("stagingNativeTransitionEligible")),
            active_native_elements_json=str(v.property("activeNativeElementsJson") or "[]"),
            staging_native_elements_json=str(v.property("stagingNativeElementsJson") or "[]"),
            active_native_chrome_json=str(v.property("activeNativeChromeJson") or "[]"),
            native_chrome_extra_json=str(v.property("nativeChromeExtraJson") or "[]"),
            active_native_video_players=_qjsvalue_to_list(v.property("activeNativeVideoPlayers")),
            staging_native_video_players=_qjsvalue_to_list(v.property("stagingNativeVideoPlayers")),
            content_width=int(v.property("contentWidth") or 1920),
            content_height=int(v.property("contentHeight") or 1080),
            scene_editor_visible=bool(v.property("sceneEditorVisible")),
            fade_black_opacity=float(v.property("viewportBlackOverlayOpacity") or 0.0),
            nav_picker_open=bool(v.property("navPickerOpen")),
        )

    def _sync_geometry(self):
        # Phase 7 Part 4: in preview, contentScaler already spans the real
        # story's rendered rect at native resolution (letterboxed as
        # needed) -- unchanged from Phase 4. While plain editing, chrome
        # (rubber-bands/marquee/groupBBox, all children of `viewport`
        # itself, not contentScaler) can extend beyond contentScaler's
        # letterboxed bounds into the surrounding editor canvas, so the
        # native window needs to cover the full `viewport` rect (960x540,
        # unscaled while not previewing) instead, or that chrome would clip
        # at contentScaler's edge with nothing to draw onto.
        preview_active = bool(self._window.property("previewActive"))
        item = self._content_scaler if preview_active else self._viewport
        top_left = item.mapToScene(QPointF(0, 0))
        bottom_right = item.mapToScene(QPointF(item.width(), item.height()))
        w = bottom_right.x() - top_left.x()
        h = bottom_right.y() - top_left.y()

        win_pos = self._window.position()
        screen = self._window.screen()
        if screen is None or w <= 0 or h <= 0:
            return
        screen_height = screen.geometry().height()

        global_x = win_pos.x() + top_left.x()
        global_y_topdown = win_pos.y() + top_left.y()
        cocoa_y = screen_height - (global_y_topdown + h)
        rect = (global_x, cocoa_y, w, h)
        if rect != self._last_rect:
            self._last_rect = rect
            CATransaction.begin()
            CATransaction.setDisableActions_(True)
            self._sdl_nswindow.setFrame_display_(((rect[0], rect[1]), (rect[2], rect[3])), True)
            CATransaction.commit()

    def _should_be_visible(self, snap):
        # Phase 7 Part 3: once Qt's own on-screen presentation is suspended
        # (qtPresentationSuspended, see SceneContent.qml/understoryui.qml),
        # the native overlay must stay up covering the whole canvas
        # regardless of this scene's native eligibility or transition type.
        # Previously this hid whenever the scene/transition wasn't native-
        # eligible, letting Qt's own (still-running) rendering show through
        # underneath as a fallback -- that fallback path is exactly what's
        # now gone, so hiding here would show nothing at all rather than a
        # graceful fallback. A non-eligible scene (e.g. a legacy .qsb
        # shader) or a qt_fallback-tagged transition instead renders
        # black/empty through the normal steady-state path below -- this
        # is the literal "no fallback possible" behavior.
        #
        # Phase 7 Part 4: qtPresentationSuspended is now just "native
        # rendering is active" (true from app startup, not scoped to
        # preview), since the plain editor canvas is also fully native now,
        # not just preview/simulate mode. That means "native mode is on" is
        # no longer the right condition here -- it's true even on the
        # splash/story-hub screens, where this bridge has nothing to draw
        # and covering them with an opaque window would just show a black
        # rectangle over otherwise-normal Qt UI. scene_editor_visible (true
        # for both plain editing and previewing, false everywhere else) is
        # the correct, broader replacement for preview_active here.
        #
        # Phase 9: confirmed by the user this must stay as-is -- briefly
        # tried scoping to active_native_eligible too (to reveal a genuine
        # Qt fallback for non-eligible scenes), reverted alongside
        # qtPresentationSuspended's matching revert in SceneContent.qml.
        # The native pipeline must put zero Qt rendering in the viewport
        # once active; a non-eligible scene showing black is the correct,
        # deliberate contract, not a bug.
        #
        # nav_picker_open is a different axis, not a content-eligibility
        # fallback: navigationViewportOverlay (the nav-jump/interactivity-
        # target scene picker) is a full-screen modal Qt Rectangle living
        # inside `viewport` itself, not a SceneContent element -- it was
        # always meant to render via Qt, on top of whatever's beneath it.
        # Clicks into it already reach Qt's own MouseAreas regardless (the
        # native window ignores mouse events unconditionally), so hiding
        # here only fixes visibility, matching how scene_editor_visible
        # itself already suspends native output for a full-screen Qt state.
        return snap.scene_editor_visible and not snap.nav_picker_open

    def _reconcile_video_sources(self, elements):
        """Adds/keeps a _VideoSource per distinct video path referenced by
        a "video" element this tick, releasing any no longer referenced --
        mirrors _reconcile_image_sources exactly, except keyed by path
        alone (not (path, rev): a video's identity is its file, there's no
        rev-bump-on-edit concept the way rasterized text/replaced images
        have). One shared cache serves both steady-state rendering (called
        with just the active scene's elements) and transitions (called with
        the active+staging union, so the incoming side's video is already
        decoding/caching by the time the transition actually starts
        compositing it -- the same "pre-load the incoming source" effect
        the old single-slot design got from a dedicated _open_source() call,
        now just a natural consequence of one shared reconciled cache.

        Only ever touches plain-path keys -- Phase 10 Stage 2's crossfade
        secondary sources live in this same dict under a synthetic
        f"{path}#B" key, reconciled separately by
        _reconcile_crossfade_sources() (never referenced by `elements`
        itself, so this function's own cleanup pass must skip them or it
        would release a just-created secondary source the very next tick).

        Phase 10: a path no longer referenced isn't released immediately --
        it stays cached (still decoding, ready to go) for
        _VIDEO_SOURCE_GRACE_SECONDS after it was last wanted, so quickly
        revisiting a scene doesn't pay a fresh decode + black-flash cost.
        Only actually torn down once the grace period elapses with the
        path still unwanted -- at which point any load still in flight for
        it is cancelled too.

        A newly-wanted path gets a _PlaceholderVideoSource in its slot the
        same tick its real load is requested, immediately swapped for the
        real _VideoSource once that finishes -- without this, a path with
        no entry yet is simply skipped by _composite_elements_pass, which
        reads as a black flash on every scene jump for however long
        av.open() takes (now genuinely off the render thread, so no longer
        bounded to "however fast this tick's Python code runs").

        Requesting new loads only needs to happen when `elements` itself
        changes, so the caller gates this whole method behind an
        elements-JSON-changed cache (see _render_unsafe). Swapping *finished*
        loads into self._video_sources does not belong behind that same
        gate -- a background thread completing is a wall-clock event
        completely unrelated to whether the JSON changed, and gating it the
        same way caused a real, hard-to-see bug: a load could sit finished
        for many seconds (sometimes 10-25+) with nothing ever collecting it,
        until some *unrelated* scene change elsewhere happened to touch
        nativeElementsJson and incidentally trigger a poll. This mirrors
        _reconcile_crossfade_sources' own "polled every tick, unlike the
        video/image/shader reconciliation above" comment -- same principle,
        just missed here originally since the async loader didn't exist yet
        when that comment was written. See _poll_video_loads, called
        unconditionally every tick regardless of this method."""
        now = time.monotonic()
        wanted = {e["path"] for e in elements if e.get("type") == "video" and e.get("path")}
        self._video_wanted = wanted
        for path in wanted:
            self._video_source_last_used[path] = now
        for path in list(self._video_sources.keys()):
            if path.endswith("#B") or path in wanted:
                continue
            last_used = self._video_source_last_used.get(path, 0.0)
            if now - last_used >= _VIDEO_SOURCE_GRACE_SECONDS:
                self._video_sources.pop(path).release()
                self._video_source_last_used.pop(path, None)
                self._async_loader.cancel(("video", path))
        for path in wanted:
            existing = self._video_sources.get(path)
            if existing is not None and not isinstance(existing, _PlaceholderVideoSource):
                continue
            if self._async_loader.is_pending(("video", path)):
                continue
            if existing is None:
                self._video_sources[path] = _PlaceholderVideoSource(self._device)
            self._async_loader.request(("video", path), _VideoSource.prepare, path)

    def _poll_video_loads(self):
        """Swaps any finished async video loads into self._video_sources --
        called every render tick, unconditionally (see _reconcile_video_
        sources' docstring for why this can't be gated behind the same
        elements-JSON-changed cache its own request-submission half uses)."""
        wanted = getattr(self, "_video_wanted", set())
        for key, result, exc in self._async_loader.poll_ready("video"):
            _kind, path = key
            existing = self._video_sources.get(path)
            is_placeholder = isinstance(existing, _PlaceholderVideoSource)
            if exc is not None:
                print(f"[hdr_viewport] failed to open video {path!r}, skipping this element: {exc}")
                if is_placeholder:
                    self._video_sources.pop(path).release()
                continue
            if path not in wanted or (existing is not None and not is_placeholder):
                # Fell out of `wanted` while this load was in flight, or a
                # real source already exists for this path somehow -- the
                # opened container is unused either way, close it rather
                # than leaking the file handle/decoder.
                result.container.close()
                continue
            if is_placeholder:
                existing.release()
            self._video_sources[path] = _VideoSource(self._device, result)

    def _upload_video_positions(self, copy_pass, video_players):
        """Feeds each live video's current MediaPlayer.position into its
        matching _VideoSource, given the {"path", "player"} list the
        QmlSnapshot carries (active_native_video_players, optionally
        concatenated with staging_native_video_players during a
        transition). Position is deliberately still a live poll each tick
        (see QmlSnapshot's docstring) -- only the player *references* come
        from the snapshot."""
        for entry in video_players:
            path = entry.get("path") if isinstance(entry, dict) else None
            player = entry.get("player") if isinstance(entry, dict) else None
            if not path or player is None:
                continue
            source = self._video_sources.get(path)
            if source is None:
                continue
            try:
                position_seconds = player.property("position") / 1000.0
            except RuntimeError:
                # Scene closed between this snapshot being captured and this
                # tick running -- the QML MediaPlayer behind this stale
                # reference is already gone. Skip just this entry rather than
                # letting it blow up the whole render tick (see
                # _poll_crossfade_state's identical guard just below).
                continue
            source.try_upload_latest(copy_pass, position_seconds)

    def _poll_crossfade_state(self, video_players):
        """Phase 10 Stage 2: rebuilds self._crossfade_state fresh every
        steady-state tick by polling each video delegate's own live QML
        properties -- vidCfActive/vidCfPrerolling (SceneContent.qml's
        already-running preroll/fade state machine, which keeps going
        regardless of native mode since it also drives audio) and
        secondaryOpacity (vidOutputB's own live-animated opacity, the exact
        blend amount Qt itself is currently showing). Native never
        re-derives crossfade timing itself, only mirrors what Qt already
        decided -- cannot drift out of sync with it this way. Steady-state
        only (transitions never call this): crossfade already hard-resets
        to a clean single-video state the instant a transition begins (see
        SceneContent.qml's on_InTransitionWatcherChanged)."""
        state = {}
        for entry in video_players:
            path = entry.get("path") if isinstance(entry, dict) else None
            item = entry.get("item") if isinstance(entry, dict) else None
            if not path or item is None:
                continue
            try:
                active = bool(item.property("vidCfActive"))
                prerolling = bool(item.property("vidCfPrerolling"))
                opacity = float(item.property("secondaryOpacity") or 0.0)
                player_b = item.property("playerB")
            except RuntimeError:
                # Scene closed between this snapshot being captured and this
                # tick running -- the QML delegate item behind this stale
                # reference is already gone. Skip just this entry rather than
                # letting it blow up the whole render tick and blank the
                # entire native overlay (the previous behavior, via
                # _render's catch-all).
                continue
            if not (active or prerolling or opacity > 0.0):
                continue
            state[path] = {"opacity": opacity, "player_b": player_b}
        return state

    def _reconcile_crossfade_sources(self, crossfade_state):
        """Adds/keeps a secondary _VideoSource (keyed f"{path}#B") for each
        path currently crossfading, releasing any no longer needed --
        matches _reconcile_video_sources' shape but driven by
        self._crossfade_state instead of the elements list, and created/
        destroyed on demand rather than for a video's whole lifetime
        (mirrors Qt's own vidPlayerB, which only ever plays during preroll/
        fade, not continuously)."""
        wanted = {f"{path}#B" for path in crossfade_state}
        for key in list(self._video_sources.keys()):
            if key.endswith("#B") and key not in wanted:
                self._video_sources.pop(key).release()
        for loader_key in [k for k in self._async_loader.pending_keys() if k[0] == "video_b" and k[1] not in wanted]:
            self._async_loader.cancel(loader_key)
        for path in crossfade_state:
            key = f"{path}#B"
            if key in self._video_sources:
                continue
            self._async_loader.request(("video_b", key), _VideoSource.prepare, path)
        for loader_key, result, exc in self._async_loader.poll_ready("video_b"):
            _kind, key = loader_key
            if exc is not None:
                print(f"[hdr_viewport] failed to open crossfade secondary {key[:-2]!r}, skipping: {exc}")
                continue
            if key not in wanted or key in self._video_sources:
                result.container.close()
                continue
            self._video_sources[key] = _VideoSource(self._device, result)

    def _upload_crossfade_positions(self, copy_pass, crossfade_state):
        """Sibling of _upload_video_positions for crossfade secondary
        sources -- same live-poll-position pattern, off each entry's own
        player_b reference."""
        for path, info in crossfade_state.items():
            player_b = info.get("player_b")
            source = self._video_sources.get(f"{path}#B")
            if player_b is None or source is None:
                continue
            position_seconds = player_b.property("position") / 1000.0
            source.try_upload_latest(copy_pass, position_seconds)

    def _ensure_linear_buffer(self, snap):
        """Reallocates the offscreen linear buffer if the story's real
        resolution differs from what it was last sized for -- checked every
        render tick since contentWidth/contentHeight aren't known for real
        until a story is actually opened (well after _attach()'s initial
        placeholder allocation), and could change later via a resolution
        migration. Element rects are in real story-space units, so this
        must be correct before _story_rect_to_ndc() is used for anything.
        Takes `snap` (plain data) rather than polling self._viewport itself --
        part of Phase 6 Part 3's seam for eventual Qt-free reuse."""
        story_w, story_h = snap.content_width, snap.content_height
        if (story_w, story_h) == (self._linear_w, self._linear_h):
            return
        sdl3.SDL_ReleaseGPUTexture(self._device, self._linear_buffer)
        self._linear_w, self._linear_h = story_w, story_h
        self._linear_buffer = _make_texture(
            self._device, self._linear_format, story_w, story_h,
            sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        )
        # A resolution change invalidates the transition buffers too, if
        # they've been allocated -- _ensure_transition_buffers() re-checks
        # size the same way every time _begin_transition() runs.
        if self._out_linear_buffer is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._out_linear_buffer)
            self._out_linear_buffer = None
        if self._in_linear_buffer is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._in_linear_buffer)
            self._in_linear_buffer = None

    def _ensure_transition_buffers(self):
        """Lazily (re)allocates _out_linear_buffer/_in_linear_buffer sized
        to match _linear_w/_linear_h -- called from _begin_transition() so
        steady-state playback never pays for these while idle."""
        if self._out_linear_buffer is None:
            self._out_linear_buffer = _make_texture(
                self._device, self._linear_format, self._linear_w, self._linear_h,
                sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            )
        if self._in_linear_buffer is None:
            self._in_linear_buffer = _make_texture(
                self._device, self._linear_format, self._linear_w, self._linear_h,
                sdl3.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl3.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            )

    def _story_rect_to_ndc(self, x1, y1, x2, y2):
        """story-space (top-left origin, y-down) -> NDC (y-up) rect, matching
        prototypes/hdr_phase5_mixed_compositing_test.py's validated math."""
        ndc_x0 = (x1 / self._linear_w) * 2.0 - 1.0
        ndc_x1 = (x2 / self._linear_w) * 2.0 - 1.0
        ndc_y0 = 1.0 - (y1 / self._linear_h) * 2.0  # top edge -> larger NDC y
        ndc_y1 = 1.0 - (y2 / self._linear_h) * 2.0  # bottom edge -> smaller NDC y
        return (ndc_x0, ndc_y0, ndc_x1, ndc_y1)

    def _parse_elements(self, elements_json):
        try:
            elements = json.loads(elements_json)
        except Exception as exc:
            print(f"[hdr_viewport] failed to parse nativeElementsJson, showing nothing this tick: {exc}")
            return []
        return elements if isinstance(elements, list) else []

    def _parse_chrome(self, chrome_json):
        try:
            chrome = json.loads(chrome_json)
        except Exception as exc:
            print(f"[hdr_viewport] failed to parse nativeChromeJson, showing no chrome this tick: {exc}")
            return []
        return chrome if isinstance(chrome, list) else []

    def _reconcile_image_sources(self, elements):
        """Adds/keeps an _ImageSource per (path, rev) referenced by an
        "image" or "text" element this tick, releasing any no longer
        referenced -- static content is decoded once and cached, not
        re-decoded per tick. Rasterized text (Stage C) is indistinguishable
        from a real image once Qt has written it to a PNG -- same decode,
        same SDR shader, just a different upstream source for the file."""
        wanted = {
            (e["path"], e.get("rev", 0)) for e in elements if e.get("type") in ("image", "text") and e.get("path")
        }
        for key in list(self._image_sources.keys()):
            if key not in wanted:
                self._image_sources.pop(key).release()
        for path, rev in wanted:
            key = (path, rev)
            if key in self._image_sources:
                continue
            try:
                self._image_sources[key] = _ImageSource(self._device, path)
            except Exception as exc:
                print(f"[hdr_viewport] failed to open image/text texture {path!r}, skipping this element: {exc}")

    def _reconcile_shader_sources(self, elements):
        """Adds/keeps a compiled _ShaderSource per (fragPath, vertPath)
        referenced by a "shader" element this tick, releasing any no
        longer referenced -- compilation (a handful of glslc/spirv-cross
        subprocess calls) only happens once per unique path pair, not
        every tick, mirroring _reconcile_image_sources."""
        wanted = {
            (e["fragPath"], e.get("vertPath") or "")
            for e in elements if e.get("type") == "shader" and e.get("fragPath")
        }
        for key in list(self._shader_sources.keys()):
            if key not in wanted:
                self._shader_sources.pop(key).release()
        for frag_path, vert_path in wanted:
            key = (frag_path, vert_path)
            if key in self._shader_sources:
                continue
            try:
                self._shader_sources[key] = _ShaderSource(self._device, frag_path, vert_path)
            except Exception as exc:
                print(f"[hdr_viewport] failed to compile shader {frag_path!r}, skipping this element: {exc}")

    def _begin_transition(self, flag, snap):
        can_native = (
            flag in ("dissolve", "wipe", "slide", "look")
            # Phase 9: the mode gate that used to force qt_fallback in sdr
            # mode is gone -- the four "linear" transition shaders
            # (_render_transition's actual code path; the legacy single-
            # video wipe/slide/look shaders built alongside them are dead
            # code, unused by either mode since Phase 6 Part 2's move to
            # two-buffer compositing) now have SDR-encode siblings, mode-
            # branched into the same pipeline attribute names at attach
            # time exactly like the steady-state final pass already was.
            and snap.active_native_transition_eligible
            and snap.staging_native_transition_eligible
        )
        if not can_native:
            self._active_transition = "qt_fallback"
            return

        self._ensure_transition_buffers()
        active_elements = self._parse_elements(snap.active_native_elements_json)
        staging_elements = self._parse_elements(snap.staging_native_elements_json)
        # Phase 10 Stage 1: reconciling video sources against the
        # active+staging union is what pre-loads the incoming side's
        # video(s) -- the outgoing side's are already cached from ordinary
        # steady-state rendering (a no-op re-add here), any new video(s) on
        # the staging side get created fresh, same "pre-load the incoming
        # source" effect the old single-slot design needed a dedicated
        # _open_source() call for.
        self._reconcile_video_sources(active_elements + staging_elements)
        self._poll_video_loads()
        self._reconcile_image_sources(active_elements + staging_elements)
        self._reconcile_shader_sources(active_elements + staging_elements)
        # Phase 10 Stage 2: crossfade never composites during a transition
        # (Qt already hard-resets it the instant one begins, see
        # SceneContent.qml's on_InTransitionWatcherChanged) -- release any
        # secondary sources now rather than leaving them decoding unused
        # for the transition's whole duration. _render_transition never
        # repopulates this, so it stays empty until steady-state resumes.
        self._crossfade_state = {}
        self._reconcile_crossfade_sources(self._crossfade_state)
        self._active_transition = flag

    def _end_transition(self, snap):
        # Phase 10 Stage 1: no source promotion needed anymore -- the next
        # steady-state tick's own _reconcile_video_sources(elements) call,
        # given the now-active (former staging) scene's elements, keeps
        # whatever's still referenced and releases whatever isn't (the old
        # outgoing side's video, if the new active scene doesn't also
        # reference it) -- exactly the same reconciliation that already
        # runs every ordinary tick, no transition-specific cleanup required.
        self._active_transition = None

    def _render(self):
        """Thin wrapper: an unhandled exception anywhere in a render tick
        must never be allowed to propagate up through the NSTimer callback
        and abort mid-tick, since that can leave the SDL child window frozen
        at whatever size/position it last successfully set -- e.g. mid-
        transition, when it legitimately covers the whole contentScaler
        area. A window stuck in that state visually blocks mouse clicks to
        the real Qt window underneath it, including its close button --
        which looks exactly like "closing the window doesn't quit the app"
        even though the actual quit mechanism (NSWindowWillCloseNotification)
        is untouched and fine. Fall back to hidden + reset transition state
        on any failure instead."""
        try:
            self._poll_thumbnail_fence()
            self._render_unsafe(self._snapshot)
        except Exception as exc:
            print(f"[hdr_viewport] render tick failed, hiding native overlay: {exc}")
            print(traceback.format_exc())
            try:
                self._last_rect = (0, 0, 0, 0)
                self._sdl_nswindow.setFrame_display_(((0, 0), (0, 0)), True)
            except Exception:
                pass
            self._active_flag = None
            self._active_transition = None
            # Phase 10 Stage 1: no separate transition source slots to release
            # anymore -- self._video_sources is a single reconciled cache, and
            # the next successful tick's own reconciliation naturally releases
            # anything no longer referenced by whatever's active then.

    def _composite_elements_pass(self, cmdbuf, elements, target_texture):
        """Composites `elements` (z-sorted) into `target_texture`, an
        R16G16B16A16_FLOAT linear-nits offscreen buffer, back-to-front with
        alpha-over blending -- the one per-element pass shared by steady-
        state rendering (target=self._linear_buffer) and each side of a
        mixed-scene native transition (target=_out_linear_buffer/
        _in_linear_buffer -- see _render_transition). Phase 10 Stage 1: each
        "video" element looks up its own source from self._video_sources by
        path (reconciled by the caller before this runs), instead of being
        handed a single shared source -- any number of video elements can
        now render correctly in one pass, each with its own decode."""
        # Pre-pass: run every shader element's own arbitrary GLSL into its
        # own small output_texture *before* the shared render_pass below
        # opens -- SDL_GPU (like Vulkan/Metal) doesn't allow a nested/
        # interleaved render pass inside an already-open one, so this must
        # fully complete first. The main loop below then treats "shader"
        # exactly like "image", sampling output_texture through the same
        # SDR nits-scaling pipeline.
        for elem in elements:
            if elem.get("type") != "shader":
                continue
            shader_source = self._shader_sources.get((elem.get("fragPath"), elem.get("vertPath") or ""))
            if shader_source is None:
                continue
            try:
                w_px = float(elem["x2"]) - float(elem["x1"])
                h_px = float(elem["y2"]) - float(elem["y1"])
            except (KeyError, TypeError, ValueError):
                continue
            shader_source.ensure_output_texture(w_px, h_px)
            shader_source.render_to_output(cmdbuf, self._sampler, elem.get("uniforms") or [])

        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = target_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_CLEAR
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        target.clear_color = sdl3.SDL_FColor(0.0, 0.0, 0.0, 1.0)
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)

        for elem in elements:
            etype = elem.get("type")
            try:
                rect_ndc = self._story_rect_to_ndc(
                    float(elem["x1"]), float(elem["y1"]), float(elem["x2"]), float(elem["y2"])
                )
            except (KeyError, TypeError, ValueError):
                continue
            rect_u = RectUniform((ctypes.c_float * 4)(*rect_ndc))

            if etype == "video":
                video_source = self._video_sources.get(elem.get("path"))
                if video_source is None:
                    continue
                sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
                # Phase 7 Part 1: branch per-source on its real colorimetry
                # rather than always running the HDR/HLG math -- previously
                # every video (including plain SDR) went through
                # _video_linear_pipeline unconditionally, silently mangling
                # SDR content whenever hdrPreviewEnabled was on.
                if video_source.is_hdr:
                    # Phase 8 Stage 2: HLG's graceful-SDR-fallback behavior
                    # is the same decode chain (VIDEO_LINEAR_FRAGMENT_MSL
                    # never PQ-encodes itself, just writes absolute nits --
                    # see its own comment), just re-targeted at an SDR-
                    # appropriate peak instead of _PEAK_NITS=600 -- same
                    # shader, same pipeline, only the uniform values differ.
                    if self._mode == "sdr":
                        video_uniforms = VideoLinearUniforms(
                            peak_nits=_SDR_HLG_PEAK_NITS,
                            gamma=_SDR_HLG_GAMMA,
                            exposure=_SDR_HLG_EXPOSURE,
                            contrast=_SDR_HLG_CONTRAST,
                            gamut_convert=1.0,
                            opacity=1.0,
                        )
                    else:
                        video_uniforms = VideoLinearUniforms(
                            peak_nits=_PEAK_NITS,
                            gamma=_GAMMA,
                            exposure=_EXPOSURE,
                            contrast=_CONTRAST,
                            gamut_convert=0.0,
                            opacity=1.0,
                        )
                    sdl3.SDL_PushGPUFragmentUniformData(
                        cmdbuf, 0, ctypes.byref(video_uniforms), ctypes.sizeof(video_uniforms)
                    )
                    sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._video_linear_pipeline)
                else:
                    sdr_video_uniforms = SDRVideoUniforms(sdr_ref_nits=_SDR_REF_NITS, opacity=1.0)
                    sdl3.SDL_PushGPUFragmentUniformData(
                        cmdbuf, 0, ctypes.byref(sdr_video_uniforms), ctypes.sizeof(sdr_video_uniforms)
                    )
                    sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._sdr_video_pipeline)
                video_bindings = (sdl3.SDL_GPUTextureSamplerBinding * 2)(
                    sdl3.SDL_GPUTextureSamplerBinding(texture=video_source.y_texture, sampler=self._sampler),
                    sdl3.SDL_GPUTextureSamplerBinding(texture=video_source.uv_texture, sampler=self._sampler),
                )
                sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, video_bindings, 2)
                sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

                # Phase 10 Stage 2: crossfade ping-pong's secondary ("B")
                # draw, on top of the primary just drawn above, blended at
                # Qt's own live-animated opacity -- same rect, same pipeline
                # selection logic, just a second source and a non-1.0
                # opacity uniform. The existing blend-enabled pipelines do
                # the alpha-over compositing automatically.
                cf = self._crossfade_state.get(elem.get("path"))
                cf_source = self._video_sources.get(f"{elem.get('path')}#B") if cf else None
                if cf is not None and cf_source is not None:
                    sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
                    if cf_source.is_hdr:
                        if self._mode == "sdr":
                            cf_uniforms = VideoLinearUniforms(
                                peak_nits=_SDR_HLG_PEAK_NITS,
                                gamma=_SDR_HLG_GAMMA,
                                exposure=_SDR_HLG_EXPOSURE,
                                contrast=_SDR_HLG_CONTRAST,
                                gamut_convert=1.0,
                                opacity=cf["opacity"],
                            )
                        else:
                            cf_uniforms = VideoLinearUniforms(
                                peak_nits=_PEAK_NITS,
                                gamma=_GAMMA,
                                exposure=_EXPOSURE,
                                contrast=_CONTRAST,
                                gamut_convert=0.0,
                                opacity=cf["opacity"],
                            )
                        sdl3.SDL_PushGPUFragmentUniformData(
                            cmdbuf, 0, ctypes.byref(cf_uniforms), ctypes.sizeof(cf_uniforms)
                        )
                        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._video_linear_pipeline)
                    else:
                        cf_uniforms = SDRVideoUniforms(sdr_ref_nits=_SDR_REF_NITS, opacity=cf["opacity"])
                        sdl3.SDL_PushGPUFragmentUniformData(
                            cmdbuf, 0, ctypes.byref(cf_uniforms), ctypes.sizeof(cf_uniforms)
                        )
                        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._sdr_video_pipeline)
                    cf_bindings = (sdl3.SDL_GPUTextureSamplerBinding * 2)(
                        sdl3.SDL_GPUTextureSamplerBinding(texture=cf_source.y_texture, sampler=self._sampler),
                        sdl3.SDL_GPUTextureSamplerBinding(texture=cf_source.uv_texture, sampler=self._sampler),
                    )
                    sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, cf_bindings, 2)
                    sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
            elif etype in ("image", "text"):
                source = self._image_sources.get((elem.get("path"), elem.get("rev", 0)))
                if source is None:
                    continue
                sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
                sdr_uniforms = SDRUniforms(sdr_ref_nits=_SDR_REF_NITS)
                sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(sdr_uniforms), ctypes.sizeof(sdr_uniforms))
                sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._sdr_pipeline)
                sdr_binding = (sdl3.SDL_GPUTextureSamplerBinding * 1)(
                    sdl3.SDL_GPUTextureSamplerBinding(texture=source.texture, sampler=self._sampler)
                )
                sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, sdr_binding, 1)
                sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
            elif etype == "shader":
                # Phase 7 Part 2: the user's own shader already rendered into
                # its output_texture during the pre-pass above -- from here
                # on it's composited exactly like an image, through the same
                # SDR nits-scaling pipeline (srgb_eotf() * _SDR_REF_NITS),
                # which is what actually fixes the raw-nits problem: this
                # shader's colors get the same reference-white treatment
                # every other SDR element already gets.
                shader_source = self._shader_sources.get((elem.get("fragPath"), elem.get("vertPath") or ""))
                if shader_source is None or shader_source.output_texture is None:
                    continue
                sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
                sdr_uniforms = SDRUniforms(sdr_ref_nits=_SDR_REF_NITS)
                sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(sdr_uniforms), ctypes.sizeof(sdr_uniforms))
                sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._sdr_pipeline)
                sdr_binding = (sdl3.SDL_GPUTextureSamplerBinding * 1)(
                    sdl3.SDL_GPUTextureSamplerBinding(texture=shader_source.output_texture, sampler=self._sampler)
                )
                sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, sdr_binding, 1)
                sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

        sdl3.SDL_EndGPURenderPass(render_pass)

    def _composite_chrome_pass(self, cmdbuf, chrome_items, target_texture):
        """Draws selection chrome on top of whatever _composite_elements_pass
        already wrote into target_texture this tick -- solid-color quads via
        _chrome_pipeline, no texture/sampler, scaled to SDR reference white
        like every other SDR-referred element (see CHROME_FRAGMENT_MSL's
        docstring). Mirrors Qt's own paint order (content first, chrome drawn
        on top via higher z) by using LOADOP_LOAD, not CLEAR -- this pass
        must run after _composite_elements_pass, never before or standalone.
        Only ever called in the steady-state path, never during a transition
        (chrome is a plain-editing concern; there's no "selected element"
        during a scene-to-scene transition).

        `chrome_items` is the merged active_native_chrome_json (single
        selected element, no "kind" -- white border+handles) and
        native_chrome_extra_json (viewport-level: "rubberband" is a white
        border only, matching Qt's own in-progress creation/box-select boxes
        which never show resize handles; "group" is the multi-select
        groupBBox, white border+handles like a normal element; "delete" is
        the destroy-tool's live hover target, a red border+interior fill
        both ramping with "progress" [0..1], no handles; "relayerHover" is
        the relayer-tool's live hover target, a plain white thicker border,
        no fill, no handles; "areaOutline" (Phase 11) is one entry per area
        element, the always-on hotspot boundary shown while editing --
        explicit "borderColor" [r,g,b] and "fillAlpha" fields instead of a
        fixed color/ramp, since it's white when selected and grey
        otherwise, no handles)."""
        if not chrome_items:
            return
        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = target_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_LOAD
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._chrome_pipeline)

        def make_uniforms(rgba, shape=0.0):
            return ChromeUniforms(color=(ctypes.c_float * 4)(*rgba), sdr_ref_nits=_SDR_REF_NITS, shape=shape)

        white_uniforms = make_uniforms((1.0, 1.0, 1.0, 1.0))
        # Handle dots are circles, matching every real SceneContent.qml
        # resize-handle Rectangle's own radius: 4/editorScaleFactor (exactly
        # half its 8/editorScaleFactor width, i.e. a full circle) -- native
        # was drawing plain squares here until this was pointed out.
        white_circle_uniforms = make_uniforms((1.0, 1.0, 1.0, 1.0), shape=1.0)

        def draw_quad(x1, y1, x2, y2, uniforms=white_uniforms):
            rect_ndc = self._story_rect_to_ndc(x1, y1, x2, y2)
            rect_u = RectUniform((ctypes.c_float * 4)(*rect_ndc))
            sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
            sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(uniforms), ctypes.sizeof(uniforms))
            sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

        # Two passes, not one: every item's border+fill draws first, then
        # every item's handle dots draw last, all in one final sub-pass.
        # Needed because "kind" entries aren't independent self-contained
        # layers -- an area's continuous border specifically comes from a
        # *separate*, later-in-the-list "areaOutline" item than the one
        # supplying its handle dots (its own selection-chrome item, drawn
        # earlier, with noBorder set -- see below). Interleaving border-
        # then-handles per item (the original single-pass approach) meant
        # that later item's border painted right over the earlier item's
        # already-drawn dots at every corner they shared -- exactly the
        # "handles render behind the border" bug the user caught. Handles
        # can never be a per-item afterthought here; they must be the very
        # last thing drawn across the whole pass.
        pending_handles = []  # [(x1,y1,x2,y2,handle_size), ...]

        for item in chrome_items:
            try:
                x1, y1, x2, y2 = float(item["x1"]), float(item["y1"]), float(item["x2"]), float(item["y2"])
                border_width = float(item.get("borderWidth", 2.0))
            except (KeyError, TypeError, ValueError):
                continue
            kind = item.get("kind")

            # Border color/alpha: "delete" ramps red with progress, matching
            # Qt's own Qt.rgba(1,0,0, 0.4 + deleteProgress*0.6) exactly;
            # "areaOutline" carries its own explicit borderColor/fillAlpha
            # (white when selected, grey otherwise -- computed QML-side
            # since selection/hover state lives there); everything else
            # (including "relayerHover") is plain white.
            fill_uniforms = None
            if kind == "delete":
                try:
                    progress = float(item.get("progress", 0.0))
                except (TypeError, ValueError):
                    progress = 0.0
                border_uniforms = make_uniforms((1.0, 0.0, 0.0, 0.4 + progress * 0.6))
                fill_uniforms = make_uniforms((1.0, 0.0, 0.0, progress * 0.6))
            elif kind == "areaOutline":
                try:
                    r, g, b = (float(c) for c in item.get("borderColor", (1.0, 1.0, 1.0)))
                    fill_alpha = float(item.get("fillAlpha", 0.0))
                except (TypeError, ValueError):
                    r, g, b, fill_alpha = 1.0, 1.0, 1.0, 0.0
                border_uniforms = make_uniforms((r, g, b, 1.0))
                if fill_alpha > 0.0:
                    fill_uniforms = make_uniforms((1.0, 1.0, 1.0, fill_alpha))
            else:
                border_uniforms = white_uniforms

            # Border: 4 edge quads (top/bottom/left/right), not a single
            # stroked rect -- CHROME_FRAGMENT_MSL only draws filled quads.
            # Phase 11: "noBorder" (area's own selection chrome only) skips
            # this -- an area's continuous border line comes entirely from
            # the separate "areaOutline" push at its own 28px-inset rect,
            # not from this raw-rect selection-chrome item; only its handle
            # dots (below) belong at the raw rect, matching the real
            # SceneContent.qml corner/edge handle Items' own positions.
            if not item.get("noBorder"):
                draw_quad(x1, y1, x2, y1 + border_width, uniforms=border_uniforms)
                draw_quad(x1, y2 - border_width, x2, y2, uniforms=border_uniforms)
                draw_quad(x1, y1, x1 + border_width, y2, uniforms=border_uniforms)
                draw_quad(x2 - border_width, y1, x2, y2, uniforms=border_uniforms)

            if fill_uniforms is not None:
                draw_quad(x1 + border_width, y1 + border_width, x2 - border_width, y2 - border_width, uniforms=fill_uniforms)

            if kind in ("rubberband", "delete", "relayerHover", "areaOutline"):
                continue  # these never show resize handles

            try:
                handle_size = float(item.get("handleSize", 8.0))
            except (TypeError, ValueError):
                continue
            pending_handles.append((x1, y1, x2, y2, handle_size, border_width))

        # 8 handle dots per pending item: 4 corners + 4 edge midpoints,
        # centered exactly like each delegate's own handle Items in
        # SceneContent.qml -- drawn last, on top of every border/fill above
        # (including any later-in-the-list item's, like an area's
        # "areaOutline" border relative to its own earlier handle-dot item).
        #
        # Each dot is centered on the border's own visual stroke, not on the
        # raw x1/y1/x2/y2 corner the border quads are anchored to -- a
        # border quad is drawn *inward* from that raw coordinate by
        # border_width (see draw_quad calls above), so its centerline sits
        # border_width/2 further in. Centering a dot at the raw corner
        # instead put it visibly outside the border's own middle -- caught
        # live by the user ("control points are not centered over the
        # border lines, they are 1 or 2px outwards"). ix1/iy1/ix2/iy2 below
        # are the border-centerline equivalents of x1/y1/x2/y2; mid_x/mid_y
        # need no adjustment, already centered between two such edges.
        for x1, y1, x2, y2, handle_size, border_width in pending_handles:
            mid_x, mid_y = (x1 + x2) / 2.0, (y1 + y2) / 2.0
            half_border = border_width / 2.0
            ix1, iy1, ix2, iy2 = x1 + half_border, y1 + half_border, x2 - half_border, y2 - half_border
            half = handle_size / 2.0
            for cx, cy in (
                (ix1, iy1), (mid_x, iy1), (ix2, iy1),
                (ix1, mid_y), (ix2, mid_y),
                (ix1, iy2), (mid_x, iy2), (ix2, iy2),
            ):
                draw_quad(cx - half, cy - half, cx + half, cy + half, uniforms=white_circle_uniforms)

        sdl3.SDL_EndGPURenderPass(render_pass)

    def _composite_cursor_pass(self, cmdbuf, cursor_item, target_texture):
        """Draws the tool-cursor icon on top of everything else this tick
        (matching normal cursor-on-top-of-all-UI convention), right after
        _composite_chrome_pass. This is a textured-quad draw (an SVG icon,
        rasterized to a texture via _ImageSource -- see _rasterize_svg), not
        a solid-fill chrome draw, so it can't go through _chrome_pipeline
        (no sampler support at all) -- structurally a one-item copy of
        _composite_elements_pass's own "image"/"text" branch, reusing the
        same _sdr_pipeline/_sampler/SDRUniforms. `cursor_item` is a single
        {path,x,y,size} dict or None -- there's only ever one active cursor
        icon per tick, so no multi-entry reconciliation is needed the way
        _reconcile_image_sources does for real scene elements."""
        if cursor_item is None:
            if self._cursor_icon_source is not None:
                self._cursor_icon_source.release()
                self._cursor_icon_source = None
                self._cursor_icon_path = None
            return

        path = cursor_item.get("path")
        if not path:
            return
        if path != self._cursor_icon_path:
            if self._cursor_icon_source is not None:
                self._cursor_icon_source.release()
                self._cursor_icon_source = None
            try:
                self._cursor_icon_source = _ImageSource(self._device, path)
                self._cursor_icon_path = path
            except Exception as exc:
                print(f"[hdr_viewport] failed to load cursor icon {path!r}, skipping this tick: {exc}")
                self._cursor_icon_path = None
                return
        if self._cursor_icon_source is None:
            return

        try:
            x, y, size = float(cursor_item["x"]), float(cursor_item["y"]), float(cursor_item["size"])
        except (KeyError, TypeError, ValueError):
            return

        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = target_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_LOAD
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)
        rect_ndc = self._story_rect_to_ndc(x, y, x + size, y + size)
        rect_u = RectUniform((ctypes.c_float * 4)(*rect_ndc))
        sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
        sdr_uniforms = SDRUniforms(sdr_ref_nits=_SDR_REF_NITS)
        sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(sdr_uniforms), ctypes.sizeof(sdr_uniforms))
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._sdr_pipeline)
        sdr_binding = (sdl3.SDL_GPUTextureSamplerBinding * 1)(
            sdl3.SDL_GPUTextureSamplerBinding(texture=self._cursor_icon_source.texture, sampler=self._sampler)
        )
        sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, sdr_binding, 1)
        sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
        sdl3.SDL_EndGPURenderPass(render_pass)

    def _composite_fade_pass(self, cmdbuf, opacity, target_texture):
        """Draws a full-story-rect black quad on top of everything else this
        tick, mirroring understoryui.qml's viewportBlackOverlay (the fade Qt
        plays on scene-editor enter/exit) -- see QmlSnapshot.fade_black_opacity.
        Reuses _chrome_pipeline/ChromeUniforms exactly as-is: pure black rgb
        PQ/SDR-encodes to 0 regardless of sdr_ref_nits, so only alpha matters
        here, and the pipeline's existing SRC_ALPHA blending is already what
        a fade needs."""
        if opacity <= 0.0:
            return
        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = target_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_LOAD
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._chrome_pipeline)
        rect_ndc = self._story_rect_to_ndc(0, 0, self._linear_w, self._linear_h)
        rect_u = RectUniform((ctypes.c_float * 4)(*rect_ndc))
        sdl3.SDL_PushGPUVertexUniformData(cmdbuf, 0, ctypes.byref(rect_u), ctypes.sizeof(rect_u))
        uniforms = ChromeUniforms(color=(ctypes.c_float * 4)(0.0, 0.0, 0.0, opacity), sdr_ref_nits=_SDR_REF_NITS, shape=0.0)
        sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(uniforms), ctypes.sizeof(uniforms))
        sdl3.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0)
        sdl3.SDL_EndGPURenderPass(render_pass)

    @Slot(str, result=bool)
    def is_native_video_ready(self, path):
        """Called from SceneContent.qml's video readiness gate in place of
        counting Qt's own decoded frames, whenever native rendering is what
        will actually paint this path. Qt's MediaPlayer/VideoOutput keep
        decoding even while native is active (it's still needed live for
        _upload_video_positions' audio/position clock -- see that method,
        and the runtime-roadmap note that this Qt dependency itself is a
        future removal target, not a permanent fixture) but its frame count
        says nothing about whether this file's *separate* PyAV/SDL decode
        (self._video_sources, populated by _reconcile_video_sources via
        _AsyncSourceLoader) has produced anything yet. Without this, the
        scene-jump gate could fire the instant Qt's own decoder got 2
        frames while the native side was still showing its placeholder --
        a black flash on jump/transition despite the gate supposedly having
        waited for the destination to be ready. Checks has_decoded_frame
        (set by the decode thread the moment it buffers a frame), not
        whether a frame has been uploaded to the GPU yet -- upload only
        happens once a path is in try_upload_latest's video_players list,
        which for a staging/pre-warming path is only true after a
        transition has already started (see _VideoSource.has_decoded_frame's
        own comment for the deadlock that gating on upload caused)."""
        source = self._video_sources.get(path)
        return isinstance(source, _VideoSource) and source.has_decoded_frame

    @Slot(str)
    def capture_thumbnail(self, path):
        """Called directly from QML (understoryui.qml's
        captureAndSaveThumbnail) whenever the native pipeline is active and
        Qt's own grabToImage() would just capture black -- every
        SceneContent.qml element delegate sits at opacity 0 while
        qtPresentationSuspended (see viewport.activeContent), since the
        native pipeline is the one actually drawing pixels, not Qt. Always
        encodes through self._thumb_pipeline (the SDR final-encode shader,
        built once in _attach() regardless of live mode -- see there)
        rather than whatever self._mode currently is, so a thumbnail saved
        while live-previewing in HDR mode still looks right in the (SDR)
        story-hub/scene-menu cards.

        Fire-and-forget: only *submits* the GPU work here and returns
        immediately -- the original version instead blocked the Qt main
        thread on SDL_WaitForGPUFences (routinely several ms, sometimes
        much more if the GPU queue was already busy) plus a synchronous
        PNG encode+disk write, which froze the entire app (including the
        "close scene" window animation) for that whole span. The fence is
        now polled non-blockingly from the existing per-tick _render() (see
        _poll_thumbnail_fence) instead of waited on here, and the actual PNG
        encode/write -- pure CPU+IO work once the pixels are read back, no
        GPU/SDL calls left -- happens on a background thread. Completion is
        reported via thumbnailCaptured(path, success), not a return value."""
        if self._device is None or self._linear_buffer is None or not self._linear_w or not self._linear_h:
            self.thumbnailCaptured.emit(path, False)
            return
        if self._thumb_pending_fence is not None:
            # Only ever one capture in flight in practice (captureAndSave
            # Thumbnail() is called once, right before the scene editor
            # closes) -- guard anyway rather than leaking the stale fence.
            sdl3.SDL_ReleaseGPUFence(self._device, self._thumb_pending_fence)
            self._thumb_pending_fence = None

        # Re-run just the elements pass (no chrome/cursor/fade overlay) fresh
        # into self._linear_buffer -- mirrors Qt's own thumbnail source
        # (thumbnailCaptureSurface's ShaderEffectSource, sourced from
        # viewport.activeContent alone, no editor chrome). Safe to do off-
        # tick: the next regular render tick clears and recomposites this
        # same buffer from scratch anyway (see _render_unsafe's Pass 1), so
        # scribbling over it here has no lasting effect on the live frame.
        elements = self._parse_elements(self._snapshot.active_native_elements_json)
        cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(self._device)
        self._composite_elements_pass(cmdbuf, elements, self._linear_buffer)

        target = sdl3.SDL_GPUColorTargetInfo()
        target.texture = self._thumb_texture
        target.load_op = sdl3.SDL_GPU_LOADOP_DONT_CARE
        target.store_op = sdl3.SDL_GPU_STOREOP_STORE
        render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(target), 1, None)
        sdl3.SDL_BindGPUGraphicsPipeline(render_pass, self._thumb_pipeline)
        binding = (sdl3.SDL_GPUTextureSamplerBinding * 1)(
            sdl3.SDL_GPUTextureSamplerBinding(texture=self._linear_buffer, sampler=self._sampler)
        )
        sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, binding, 1)
        uniforms = SDRUniforms(sdr_ref_nits=_SDR_REF_NITS)
        sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(uniforms), ctypes.sizeof(uniforms))
        sdl3.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
        sdl3.SDL_EndGPURenderPass(render_pass)

        copy_pass = sdl3.SDL_BeginGPUCopyPass(cmdbuf)
        region = sdl3.SDL_GPUTextureRegion()
        region.texture = self._thumb_texture
        region.w = _THUMB_W
        region.h = _THUMB_H
        region.d = 1
        transfer_info = sdl3.SDL_GPUTextureTransferInfo()
        transfer_info.transfer_buffer = self._thumb_transfer_buffer
        transfer_info.pixels_per_row = _THUMB_W
        transfer_info.rows_per_layer = _THUMB_H
        sdl3.SDL_DownloadFromGPUTexture(copy_pass, ctypes.byref(region), ctypes.byref(transfer_info))
        sdl3.SDL_EndGPUCopyPass(copy_pass)

        fence = sdl3.SDL_SubmitGPUCommandBufferAndAcquireFence(cmdbuf)
        if not fence:
            self.thumbnailCaptured.emit(path, False)
            return
        self._thumb_pending_fence = fence
        self._thumb_pending_path = path

    def _poll_thumbnail_fence(self):
        """Called every render tick from _render() (regardless of
        _should_be_visible -- a capture_thumbnail() request lands right as
        the scene editor is closing, so the native window may already be
        hidden by the time its fence signals). Non-blocking: SDL_QueryGPUFence
        just checks whether the GPU work capture_thumbnail() submitted has
        completed yet, unlike SDL_WaitForGPUFences which would stall this
        (main) thread until it does."""
        if self._thumb_pending_fence is None:
            return
        if not sdl3.SDL_QueryGPUFence(self._device, self._thumb_pending_fence):
            return
        sdl3.SDL_ReleaseGPUFence(self._device, self._thumb_pending_fence)
        self._thumb_pending_fence = None
        path = self._thumb_pending_path
        self._thumb_pending_path = None

        ptr = sdl3.SDL_MapGPUTransferBuffer(self._device, self._thumb_transfer_buffer, False)
        if not ptr:
            self.thumbnailCaptured.emit(path, False)
            return
        try:
            pixels = ctypes.string_at(ptr, _THUMB_W * _THUMB_H * 4)
        finally:
            sdl3.SDL_UnmapGPUTransferBuffer(self._device, self._thumb_transfer_buffer)

        # Everything left is plain CPU/IO work on a copy of the pixels
        # already in hand -- no GPU or SDL calls, so unlike the rest of this
        # class's methods (all main-thread-only), this is safe to run on a
        # background thread, keeping a slow PNG encode or disk write off the
        # render tick and off whatever QML flow is waiting on this signal.
        def encode_and_save():
            image = QImage(pixels, _THUMB_W, _THUMB_H, _THUMB_W * 4, QImage.Format_RGBA8888)
            ok = bool(image.save(path))
            self.thumbnailCaptured.emit(path, ok)

        threading.Thread(target=encode_and_save, daemon=True).start()

    def _render_unsafe(self, snap):
        # `snap` is the most recent beforeSynchronizing-built snapshot,
        # passed in explicitly by _render() rather than read from
        # self._snapshot internally -- every structural decision below
        # reads from this single generation, never re-polling QML directly,
        # so a scene jump or transition boundary can't be observed torn
        # across two different generations mid-tick. Taking it as a
        # parameter (Phase 6 Part 3) also means this function's only input
        # is plain data plus GPU/source state -- no direct self._viewport
        # reference -- which is the seam a future Qt-free runtime would need
        # to reuse this same rendering core with its own snapshot producer.
        flag = snap.transition_flag
        if flag != self._active_flag:
            if self._active_flag is not None:
                self._end_transition(snap)
            if flag is not None:
                self._begin_transition(flag, snap)
            self._active_flag = flag

        if not self._should_be_visible(snap):
            if self._last_rect != (0, 0, 0, 0):
                self._last_rect = (0, 0, 0, 0)
                self._sdl_nswindow.setFrame_display_(((0, 0), (0, 0)), True)
            return

        if self._active_transition in ("dissolve", "wipe", "slide", "look"):
            self._render_transition(self._active_transition, snap)
            return

        self._ensure_linear_buffer(snap)

        elements = self._parse_elements(snap.active_native_elements_json)
        # Phase 12: reconcile (not composite -- see the composite call
        # below, which still only ever draws `elements`) against staging's
        # elements too, not just active's. Qt already pre-warms its own
        # MediaPlayer for the scene's first jump target ~300ms after
        # arrival (understoryui.qml's preWarmTimer/preWarmNextScene,
        # stagingContent.loadScene()) -- but the native pipeline was never
        # told about that pre-warmed staging content until a real
        # transition's _begin_transition actually started, so a fresh
        # _VideoSource for the destination video only ever began decoding
        # at the moment of the jump, not before, and its ring buffer had no
        # real frames ready yet -- a black-frame flash on every jump except
        # to a scene already warm from a *previous* recent visit (Phase
        # 10's grace-period cache only helps that second case). Piggy-
        # backing on Qt's existing pre-warm here gives the destination
        # source's decode thread the same head start Qt's own MediaPlayer
        # already gets, for free -- explicitly deferred at the end of
        # Phase 10 as "lower-certainty payoff, unclear whether the app's
        # architecture offers meaningful lead time at all"; it does.
        staging_elements = self._parse_elements(snap.staging_native_elements_json)
        elements_key = (snap.active_native_elements_json, snap.staging_native_elements_json)
        if elements_key != self._last_elements_json:
            self._reconcile_video_sources(elements + staging_elements)
            self._reconcile_image_sources(elements + staging_elements)
            self._reconcile_shader_sources(elements + staging_elements)
            self._last_elements_json = elements_key
        # Unconditional, unlike the block above -- a background video load
        # finishing is a wall-clock event independent of whether
        # nativeElementsJson changed this tick. Gating this the same way the
        # request-submission half above legitimately can be was a real bug:
        # a finished load could sit uncollected for many seconds until some
        # unrelated scene change elsewhere happened to touch the JSON and
        # incidentally trigger a poll. See _poll_video_loads' own docstring.
        self._poll_video_loads()
        # Phase 7 Part 3: previously hid the native window here for an
        # empty element list (e.g. a legacy .qsb-shader-only scene, not yet
        # native-eligible), letting Qt's own rendering show through as a
        # fallback. Qt's on-screen presentation is now suspended whenever
        # this pipeline is active (see _should_be_visible), so falling
        # through to render a plain black frame is what "no fallback
        # possible" actually requires -- _composite_elements_pass already
        # handles an empty list correctly (clears to black, draws nothing).

        # Phase 10 Stage 2: polled and reconciled every tick, unlike the
        # video/image/shader reconciliation above -- crossfade opacity
        # animates continuously (not just when the element list itself
        # changes), so this can't be gated behind the elements_json guard.
        self._crossfade_state = self._poll_crossfade_state(snap.active_native_video_players)
        self._reconcile_crossfade_sources(self._crossfade_state)

        self._sync_geometry()
        sdl3.SDL_PumpEvents()

        cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(self._device)
        copy_pass = sdl3.SDL_BeginGPUCopyPass(cmdbuf)
        # None right after a scene switch until the deferred
        # _bindNativeVideoPlayers() QML call resolves -- repeat the last
        # frame (or show nothing yet) rather than guessing a position.
        self._upload_video_positions(copy_pass, snap.active_native_video_players)
        self._upload_crossfade_positions(copy_pass, self._crossfade_state)
        sdl3.SDL_EndGPUCopyPass(copy_pass)

        # --- Pass 1: composite every element into the linear-light buffer,
        # back-to-front in the z-order nativeElementsJson already sorted ---
        self._composite_elements_pass(cmdbuf, elements, self._linear_buffer)

        # --- Pass 1b: selection chrome, drawn on top ---
        all_chrome_items = self._parse_chrome(snap.active_native_chrome_json) + self._parse_chrome(
            snap.native_chrome_extra_json
        )
        # "cursor" is a textured-icon draw, not a solid-color chrome shape --
        # pulled out here and handled by its own pass (below), never passed
        # to _composite_chrome_pass itself.
        cursor_item = next((i for i in all_chrome_items if i.get("kind") == "cursor"), None)
        chrome_items = [i for i in all_chrome_items if i.get("kind") != "cursor"]
        self._composite_chrome_pass(cmdbuf, chrome_items, self._linear_buffer)

        # --- Pass 1c: tool-cursor icon, drawn on top of everything else ---
        self._composite_cursor_pass(cmdbuf, cursor_item, self._linear_buffer)

        # --- Pass 1d: scene-editor enter/exit black fade, on top of all of the above ---
        self._composite_fade_pass(cmdbuf, snap.fade_black_opacity, self._linear_buffer)

        # --- Pass 2: PQ-encode the composited buffer to the real swapchain ---
        swapchain_texture = ctypes.POINTER(sdl3.SDL_GPUTexture)()
        sw_w, sw_h = ctypes.c_uint(0), ctypes.c_uint(0)
        got = sdl3.SDL_WaitAndAcquireGPUSwapchainTexture(
            cmdbuf, self._sdl_window, ctypes.byref(swapchain_texture), ctypes.byref(sw_w), ctypes.byref(sw_h)
        )
        if got and swapchain_texture:
            swap_target = sdl3.SDL_GPUColorTargetInfo()
            swap_target.texture = swapchain_texture
            swap_target.load_op = sdl3.SDL_GPU_LOADOP_CLEAR
            swap_target.store_op = sdl3.SDL_GPU_STOREOP_STORE
            swap_target.clear_color = sdl3.SDL_FColor(0.0, 0.0, 0.0, 1.0)
            final_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(swap_target), 1, None)
            sdl3.SDL_BindGPUGraphicsPipeline(final_pass, self._final_pipeline)
            final_binding = (sdl3.SDL_GPUTextureSamplerBinding * 1)(
                sdl3.SDL_GPUTextureSamplerBinding(texture=self._linear_buffer, sampler=self._sampler)
            )
            sdl3.SDL_BindGPUFragmentSamplers(final_pass, 0, final_binding, 1)
            if self._mode == "sdr":
                sdr_final_uniforms = SDRUniforms(sdr_ref_nits=_SDR_REF_NITS)
                sdl3.SDL_PushGPUFragmentUniformData(
                    cmdbuf, 0, ctypes.byref(sdr_final_uniforms), ctypes.sizeof(sdr_final_uniforms)
                )
            sdl3.SDL_DrawGPUPrimitives(final_pass, 3, 1, 0, 0)
            sdl3.SDL_EndGPURenderPass(final_pass)

        sdl3.SDL_SubmitGPUCommandBuffer(cmdbuf)

    def _render_transition(self, flag, snap):
        """Phase 6 Part 2: each side is first composited through the same
        per-element pass steady-state rendering uses (_composite_elements_pass)
        into its own linear-nits buffer (_out_linear_buffer/_in_linear_buffer),
        then the two-input LINEAR_*_FRAGMENT_MSL shaders blend those two
        buffers directly and PQ-encode once -- no per-source YUV/HLG decode
        here (already done compositing into each buffer) and no apply_trim
        (already baked into each buffer, see LINEAR_WIPE_FRAGMENT_MSL's
        module-level comment)."""
        self._sync_geometry()
        sdl3.SDL_PumpEvents()

        # Re-parsed fresh every tick (cheap) rather than cached at
        # _begin_transition time, so a text rasterization or conditional-
        # source swap that completes mid-transition is picked up the same
        # way steady-state rendering already handles it.
        active_elements = self._parse_elements(snap.active_native_elements_json)
        staging_elements = self._parse_elements(snap.staging_native_elements_json)
        self._reconcile_video_sources(active_elements + staging_elements)
        self._poll_video_loads()
        self._reconcile_image_sources(active_elements + staging_elements)
        self._reconcile_shader_sources(active_elements + staging_elements)

        cmdbuf = sdl3.SDL_AcquireGPUCommandBuffer(self._device)
        copy_pass = sdl3.SDL_BeginGPUCopyPass(cmdbuf)
        # Positions stay a live poll each tick (see QmlSnapshot's docstring)
        # off the player references the snapshot carries for both sides.
        self._upload_video_positions(copy_pass, snap.active_native_video_players + snap.staging_native_video_players)
        sdl3.SDL_EndGPUCopyPass(copy_pass)

        # --- Pass 1/2: composite each side into its own linear buffer ---
        self._composite_elements_pass(cmdbuf, active_elements, self._out_linear_buffer)
        self._composite_elements_pass(cmdbuf, staging_elements, self._in_linear_buffer)

        # --- Pass 3: blend the two linear buffers directly to the swapchain ---
        swapchain_texture = ctypes.POINTER(sdl3.SDL_GPUTexture)()
        sw_w, sw_h = ctypes.c_uint(0), ctypes.c_uint(0)
        got = sdl3.SDL_WaitAndAcquireGPUSwapchainTexture(
            cmdbuf, self._sdl_window, ctypes.byref(swapchain_texture), ctypes.byref(sw_w), ctypes.byref(sw_h)
        )
        if got and swapchain_texture:
            color_target = sdl3.SDL_GPUColorTargetInfo()
            color_target.texture = swapchain_texture
            color_target.load_op = sdl3.SDL_GPU_LOADOP_CLEAR
            color_target.store_op = sdl3.SDL_GPU_STOREOP_STORE
            color_target.clear_color = sdl3.SDL_FColor(0.0, 0.0, 0.0, 1.0)

            if flag == "dissolve":
                if self._mode == "sdr":
                    uniforms = SdrLinearDissolveUniforms(progress=snap.dissolve_opacity, sdr_ref_nits=_SDR_REF_NITS)
                else:
                    uniforms = LinearDissolveUniforms(progress=snap.dissolve_opacity)
                pipeline = self._linear_dissolve_pipeline
            elif flag == "wipe":
                if self._mode == "sdr":
                    uniforms = SdrLinearWipeUniforms(
                        progress=snap.wipe_progress,
                        feather=snap.wipe_feather,
                        direction=snap.wipe_direction,
                        sdr_ref_nits=_SDR_REF_NITS,
                    )
                else:
                    uniforms = LinearWipeUniforms(
                        progress=snap.wipe_progress,
                        feather=snap.wipe_feather,
                        direction=snap.wipe_direction,
                    )
                pipeline = self._linear_wipe_pipeline
            elif flag == "slide":
                if self._mode == "sdr":
                    uniforms = SdrLinearSlideUniforms(
                        progress=snap.slide_progress,
                        direction=snap.slide_direction,
                        sdr_ref_nits=_SDR_REF_NITS,
                    )
                else:
                    uniforms = LinearSlideUniforms(
                        progress=snap.slide_progress,
                        direction=snap.slide_direction,
                    )
                pipeline = self._linear_slide_pipeline
            else:
                progress = snap.look_progress
                yaw = snap.look_yaw
                pitch = snap.look_pitch
                overshoot = snap.look_overshoot
                shutter = snap.look_shutter
                # progress is 0 at the very start/end (matches production's
                # instantaneous 0->1 animation, never a sustained hold at
                # those values) -- treat 0<progress<1 as "actively
                # transitioning" for the shutter/blur sample count, per the
                # look.frag port's finding (memory doc finding 12).
                transitioning = 0.0 < progress < 1.0
                (num_samples, scene_yaw_rad, scene_pitch_rad, wipe_dir,
                 sample_yaw, sample_pitch, sample_threshold) = _compute_look_sample_uniforms(
                    progress, yaw, pitch, overshoot, shutter if transitioning else 0.0, transitioning
                )
                look_kwargs = dict(
                    progress=progress,
                    yaw=yaw,
                    pitch=pitch,
                    fovMM=snap.look_fov_mm,
                    overshoot=overshoot,
                    shutter=shutter if transitioning else 0.0,
                    num_samples=float(num_samples),
                    scene_yaw_rad=scene_yaw_rad,
                    scene_pitch_rad=scene_pitch_rad,
                    wipeDir_x=wipe_dir[0],
                    wipeDir_y=wipe_dir[1],
                    sample_yaw=(ctypes.c_float * _BLUR_SAMPLES)(*sample_yaw),
                    sample_pitch=(ctypes.c_float * _BLUR_SAMPLES)(*sample_pitch),
                    sample_threshold=(ctypes.c_float * _BLUR_SAMPLES)(*sample_threshold),
                )
                if self._mode == "sdr":
                    uniforms = SdrLinearLookUniforms(sdr_ref_nits=_SDR_REF_NITS, **look_kwargs)
                else:
                    uniforms = LinearLookUniforms(**look_kwargs)
                pipeline = self._linear_look_pipeline

            sdl3.SDL_PushGPUFragmentUniformData(cmdbuf, 0, ctypes.byref(uniforms), ctypes.sizeof(uniforms))

            render_pass = sdl3.SDL_BeginGPURenderPass(cmdbuf, ctypes.byref(color_target), 1, None)
            sdl3.SDL_BindGPUGraphicsPipeline(render_pass, pipeline)
            bindings = (sdl3.SDL_GPUTextureSamplerBinding * 2)(
                sdl3.SDL_GPUTextureSamplerBinding(texture=self._out_linear_buffer, sampler=self._sampler),
                sdl3.SDL_GPUTextureSamplerBinding(texture=self._in_linear_buffer, sampler=self._sampler),
            )
            sdl3.SDL_BindGPUFragmentSamplers(render_pass, 0, bindings, 2)
            sdl3.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
            sdl3.SDL_EndGPURenderPass(render_pass)

        sdl3.SDL_SubmitGPUCommandBuffer(cmdbuf)

    def _teardown_partial(self):
        """Best-effort cleanup if _attach() raised partway through."""
        if self._timer is not None:
            self._timer.invalidate()
            self._timer = None
        self._async_loader.shutdown()
        for source in self._video_sources.values():
            source.release()
        self._video_sources = {}
        self._video_source_last_used = {}
        for source in self._image_sources.values():
            source.release()
        self._image_sources = {}
        for source in self._shader_sources.values():
            source.release()
        self._shader_sources = {}
        if self._cursor_icon_source is not None:
            self._cursor_icon_source.release()
            self._cursor_icon_source = None
            self._cursor_icon_path = None
        self._last_elements_json = None
        if self._sampler is not None:
            sdl3.SDL_ReleaseGPUSampler(self._device, self._sampler)
        if self._thumb_pending_fence is not None:
            sdl3.SDL_ReleaseGPUFence(self._device, self._thumb_pending_fence)
            self._thumb_pending_fence = None
        if self._thumb_transfer_buffer is not None:
            sdl3.SDL_ReleaseGPUTransferBuffer(self._device, self._thumb_transfer_buffer)
            self._thumb_transfer_buffer = None
        if self._thumb_texture is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._thumb_texture)
            self._thumb_texture = None
        if self._linear_buffer is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._linear_buffer)
            self._linear_buffer = None
        if self._out_linear_buffer is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._out_linear_buffer)
            self._out_linear_buffer = None
        if self._in_linear_buffer is not None:
            sdl3.SDL_ReleaseGPUTexture(self._device, self._in_linear_buffer)
            self._in_linear_buffer = None
        for pipeline in (
            self._video_linear_pipeline,
            self._sdr_video_pipeline,
            self._sdr_pipeline,
            self._chrome_pipeline,
            self._final_pipeline,
            self._thumb_pipeline,
            self._linear_dissolve_pipeline,
            self._linear_wipe_pipeline,
            self._linear_slide_pipeline,
            self._linear_look_pipeline,
        ):
            if pipeline is not None:
                sdl3.SDL_ReleaseGPUGraphicsPipeline(self._device, pipeline)
        for shader in (
            self._vertex_shader,
            self._quad_vertex_shader,
            self._video_linear_fs,
            self._sdr_video_fs,
            self._sdr_fs,
            self._chrome_fs,
            self._final_fs,
            self._thumb_fs,
            self._linear_dissolve_fs,
            self._linear_wipe_fs,
            self._linear_slide_fs,
            self._linear_look_fs,
        ):
            if shader is not None:
                sdl3.SDL_ReleaseGPUShader(self._device, shader)
        if self._sdl_window is not None and self._device is not None:
            sdl3.SDL_ReleaseWindowFromGPUDevice(self._device, self._sdl_window)
        if self._device is not None:
            sdl3.SDL_DestroyGPUDevice(self._device)
            self._device = None
        if self._sdl_window is not None:
            sdl3.SDL_DestroyWindow(self._sdl_window)
            self._sdl_window = None

    def cleanup(self):
        if not self.active:
            return
        self._teardown_partial()
        sdl3.SDL_Quit()
        self.active = False
