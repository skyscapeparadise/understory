import QtQuick
import QtMultimedia
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import QtQuick.Dialogs
import Qt.labs.platform as Platform
import "InteractivityEngine.js" as IE

// SceneContent — one instance per scene layer (dual-buffer architecture).
// The viewport instantiates two of these (sceneLayerA, sceneLayerB) and
// ping-pongs between them for seamless transitions. The "foreground" layer
// is interactive and visible; the "staging" layer loads silently in the
// background and signals readyForDisplay when all media is buffered.
//
// For shader transitions (dissolve, wipe, look) the viewport wraps each
// layer in a ShaderEffectSource, feeding both as textures into a
// transition ShaderEffect — neither layer needs to know about this.
Item {
    id: sceneContent

    // ── External references ─────────────────────────────────────────────────
    // Pass the viewport and buttonGrid items so delegates can bind to their
    // properties without needing them to be in scope via id lookup.
    property var viewportRef:    null
    property var buttonGridRef:  null
    property var variablesModel: null
    property var nodeWorkspaceRef: null

    // Scale factor from story-resolution coordinates to the 960×540 editor
    // viewport.  In the editor this equals mainWindow.editorScale (e.g. 0.5 for
    // 1920×1080 stories); in preview/simulate it is still the editor value, but
    // handles are only shown in the editor so preview behaviour is unchanged.
    // All hardcoded handle pixel sizes are divided by this factor so they appear
    // as a fixed visual size (e.g. 28 editor-pixels) regardless of story resolution.
    property real editorScaleFactor: viewportRef ? viewportRef.editorScale : 1.0

    // ── Layer mode ──────────────────────────────────────────────────────────
    // false = staging: all mouse events suppressed, tool overlays hidden.
    property bool isInteractive: true
    // Set to true when the viewport is in fullscreen preview.  Disables
    // per-delegate layers so VideoOutput and Image render directly into the
    // contentScaler FBO instead of through intermediate sub-FBOs that Qt
    // sizes based on the screen-projected area (not story resolution).
    property bool previewActive: false
    property bool globalMuted: false

    // Phase 7 Part 3: raw hdrPreviewEnabled setting, threaded in from
    // appSettings (see qtPresentationSuspended below for the actual gate).
    property bool hdrPreviewEnabled: false

    // True whenever the native SDL3 pipeline is the sole renderer for the
    // viewport right now. Phase 7 Part 3 scoped this to preview/simulate
    // mode only (hdrPreviewEnabled && previewActive), since the plain
    // editor canvas had real interactive chrome (selection/resize handles
    // etc.) drawn by Qt on top of content, and the native overlay was a
    // fully opaque top-most window with no awareness of that chrome.
    // Part 4 solves that (see hdr_viewport.py's _attach(), the
    // ignoresMouseEvents wiring): chrome stays fully live but invisible
    // (opacity 0, not visible: false, so hit-testing/drag/cursor-shape
    // changes keep working) underneath the opaque native window, which is
    // click-through. That means the plain editor canvas is native too now,
    // not just preview -- so this simplifies to hdrPreviewEnabled alone.
    //
    // Gates Qt's own on-screen visual presentation (VideoOutput/Image/
    // interactive-TextEdit painting) so its real content never becomes
    // visible as a "fallback" underneath the native overlay, without
    // touching MediaPlayer decode/position/audio (those must keep running
    // regardless -- native syncs to their position and Qt's own
    // QAudioSink mixer is still the only real audio path) or the offscreen
    // text-capture Text twin (native "text" is literally a grab of that
    // item, so its own rendering must continue). Named/scoped as a single,
    // explicit switch on purpose -- this is a concrete seam toward an
    // eventual Qt-free .canopy runtime: every place that reads this
    // property today is a place where "ask Qt to present something" would
    // instead need to become "ask a non-Qt backend," so keeping the check
    // itself narrow and centrally-named (rather than scattered ad hoc
    // hdrPreviewEnabled checks) is what makes that future swap tractable.
    readonly property bool qtPresentationSuspended: hdrPreviewEnabled

    // ── Load readiness ──────────────────────────────────────────────────────
    property int pendingLoads: 0
    signal readyForDisplay()

    // Called by image onStatusChanged and video onMediaStatusChanged.
    function imageLoadComplete() {
        if (pendingLoads > 0) {
            pendingLoads--
            if (pendingLoads === 0) readyForDisplay()
        }
    }

    // ── Per-layer stack state ───────────────────────────────────────────────
    property int nextStackOrder: 0

    // ── Models (public aliases so viewport/sidebar can reference them) ──────
    ListModel { id: areasModelInst }
    readonly property alias areasModel: areasModelInst

    ListModel { id: textBoxesModelInst }
    readonly property alias textBoxesModel: textBoxesModelInst

    ListModel { id: imagesModelInst }
    readonly property alias imagesModel: imagesModelInst

    ListModel { id: videosModelInst }
    readonly property alias videosModel: videosModelInst

    ListModel { id: shadersModelInst }
    readonly property alias shadersModel: shadersModelInst

    // audioTracksModelInst rows: manually-added mixer tracks (via the "+" button or a
    // file dropped straight onto the mixer) that aren't tied to any other on-canvas
    // element. Behave like ambient background audio for the scene: loop continuously
    // unless assigned to a sync group, in which case the sync group's start timecode
    // and end behavior (loop/freeze/hide) drive playback instead.
    ListModel { id: audioTracksModelInst }
    readonly property alias audioTracksModel: audioTracksModelInst

    // ── Timeline state (bound by viewport from NodeWorkspace) ───────────────
    property real chapterPlayheadTime: 0
    property int  activeChapterId: -1

    // elementType/elementIdx identify which on-canvas element is firing — the
    // "sound" command needs these to build a stable key for its mixer track's
    // live level meter (cue sounds play through a rotating one-shot pool, so
    // there's no fixed player to attach a meter to otherwise).
    function _ieContext(elementType, elementIdx) {
        return {
            viewport:            viewportRef,
            variablesModel:      variablesModel,
            chapterPlayheadTime: sceneContent.chapterPlayheadTime,
            activeChapterId:     sceneContent.activeChapterId,
            elementType:         elementType,
            elementIdx:          elementIdx
        }
    }

    // ── Scene management ────────────────────────────────────────────────────

    function collectJumpTargets() {
        var seen = {}
        var result = []
        var models = [areasModelInst, textBoxesModelInst, imagesModelInst, videosModelInst, shadersModelInst]
        for (var m = 0; m < models.length; m++) {
            var mdl = models[m]
            for (var i = 0; i < mdl.count; i++) {
                var el = mdl.get(i)
                if (!el.interactivityJson) continue
                var items = parseInteractivityJson(el.interactivityJson)
                for (var j = 0; j < items.length; j++) {
                    var it = items[j]
                    if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0
                            && !seen[it.itemTargetSceneId]) {
                        seen[it.itemTargetSceneId] = true
                        result.push(it.itemTargetSceneId)
                    }
                }
            }
        }
        return result
    }

    function clear() {
        areasModelInst.clear()
        textBoxesModelInst.clear()
        imagesModelInst.clear()
        videosModelInst.clear()
        shadersModelInst.clear()
        audioTracksModelInst.clear()
        nextStackOrder = 0
        if (viewportRef) viewportRef.clearSelection()
    }

    // Load pre-parsed element array into this layer.
    // Counts images + videos first so pendingLoads is set before any
    // append() call (cached images fire onStatusChanged synchronously).
    function loadScene(elements) {
        clear()
        var imgCount = 0
        var vidCount = 0
        for (var i = 0; i < elements.length; i++) {
            if (elements[i].type === "image") imgCount++
            else if (elements[i].type === "video") vidCount++
        }
        pendingLoads = imgCount + vidCount
        if (pendingLoads === 0) Qt.callLater(function() { readyForDisplay() })

        for (var i = 0; i < elements.length; i++) {
            var el = elements[i]
            var z = el.z_order !== undefined ? el.z_order : nextStackOrder
            if (el.type === "area") {
                areasModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            } else if (el.type === "text") {
                textBoxesModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    family:    el.family    || "Mona Sans",
                    tbWeight:  el.tbWeight  !== undefined ? el.tbWeight : Font.Normal,
                    size:      el.size      || 16,
                    italic:    el.italic    || false,
                    underline: el.underline || false,
                    textColor: el.textColor || "#FFFFFF",
                    content:   el.content   || "",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false,
                    nativeTexturePath: "",
                    nativeTextureRev: 0
                })
            } else if (el.type === "image") {
                imagesModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    filePath: el.filePath || "",
                    // baseFilePath is the authored/persisted source -- only a user
                    // edit (file picker, drag-drop, clearSources) ever changes it.
                    // filePath is the live/rendered value that the how-condition
                    // system (evaluateAllSourcesForContent etc.) is free to
                    // overwrite every scene load without corrupting what gets
                    // saved back to the database (see collectElements() below).
                    baseFilePath: el.filePath || "",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    sourcesJson: el.sourcesJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            } else if (el.type === "video") {
                videosModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    filePath: el.filePath || "",
                    baseFilePath: el.filePath || "",  // see image case above
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    sourcesJson: el.sourcesJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false,
                    vidLoop: el.vidLoop !== undefined ? el.vidLoop : true,
                    vidCrossfade: el.vidCrossfade || false,
                    vidCrossfadePct: el.vidCrossfadePct !== undefined ? el.vidCrossfadePct : 5,
                    mixerTrackName: el.mixerTrackName || "",
                    mixerVolume: el.mixerVolume !== undefined ? el.mixerVolume : 1.0,
                    mixerPan: el.mixerPan !== undefined ? el.mixerPan : 0.0,
                    syncGroupId: el.syncGroupId !== undefined ? el.syncGroupId : -1,
                    inTransition: false
                })
            } else if (el.type === "shader") {
                shadersModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    fragPath:     el.fragPath     || "",
                    vertPath:     el.vertPath     || "",
                    baseFragPath: el.fragPath     || "",  // see image case above
                    baseVertPath: el.vertPath     || "",
                    uniformsJson: el.uniformsJson || "[]",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    sourcesJson: el.sourcesJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            } else if (el.type === "audioTrack") {
                audioTracksModelInst.append({
                    filePath: el.filePath || "",
                    mixerTrackName: el.mixerTrackName || "",
                    mixerVolume: el.mixerVolume !== undefined ? el.mixerVolume : 1.0,
                    mixerPan: el.mixerPan !== undefined ? el.mixerPan : 0.0,
                    syncGroupId: el.syncGroupId !== undefined ? el.syncGroupId : -1
                })
            }
            if (z >= nextStackOrder) nextStackOrder = z + 1
        }
        nativeEligible = _computeNativeEligible()
        nativeTransitionEligible = _computeNativeTransitionEligible()
        // nativeEligible no longer implies exactly one video (Phase 5 allows
        // image/text-only scenes) -- guard the count before indexing.
        nativeVideoPath = (nativeEligible && videosModelInst.count === 1) ? videosModelInst.get(0).filePath : ""
        nativeVideoPlayer = null
        // videosRepeater's delegate (vidDelegate) may not exist yet at this exact
        // point in some model-update orderings -- Qt.callLater defers this one
        // event-loop tick, by which point Repeater delegate creation is done.
        if (nativeEligible && videosModelInst.count === 1) Qt.callLater(_bindNativeVideoPlayer)
        _buildNativeElements()
        _buildNativeChrome()
    }

    // Re-resolves nativeVideoPlayer from the live Repeater state. Safe to call
    // redundantly (e.g. if a second loadScene() fires before this one's
    // callLater runs) since it always reads current state, not a snapshot.
    function _bindNativeVideoPlayer() {
        if (!nativeEligible) return
        var item = videosRepeater.itemAt(0)
        nativeVideoPlayer = item ? item.player : null
    }

    // ── Native HDR preview pipeline (Phase 4/5) ─────────────────────────────
    // Two distinct eligibility rules. Steady-state (nativeEligible) is
    // relaxed as of Phase 5: 0 or 1 video (image/text-only scenes now
    // qualify) plus any number of images/text, nothing else on canvas
    // besides areas (which render nothing). A video, if present, still must
    // be fullscreen and non-crossfade -- the renderer no longer strictly
    // needs that, but relaxing it further is separate future work, not this
    // phase's risk to take on. Transition eligibility (nativeTransitionEligible)
    // preserves Phase 4's original strict rule verbatim (exactly one
    // fullscreen video, nothing else at all) since native wipe/slide/look
    // compositing only ever learned to blend two video sources -- a
    // transition into/out of anything else falls back to Qt for that
    // transition's duration (see hdr_viewport.py's qt_fallback path).
    // Both recomputed once per loadScene() call, not live bindings -- editing
    // only happens outside preview mode, and re-evaluating on every model
    // mutation during editing would be wasted work.
    property bool nativeEligible: false
    property bool nativeTransitionEligible: false
    property string nativeVideoPath: ""
    // The real MediaPlayer driving the qualifying video, so the native
    // pipeline can sync its own frame selection to MediaPlayer.position
    // instead of reimplementing audio-independent playback pacing.
    property var nativeVideoPlayer: null
    // z-sorted [{type,x1,y1,x2,y2,z,path,rev}, ...] snapshot for the native
    // pipeline to render -- see _buildNativeElements().
    property string nativeElementsJson: "[]"

    // Phase 7 Part 2: a shader element only disqualifies the scene if it's
    // still a legacy .qsb shader (Qt-only, per the explicit compatibility
    // model -- old .qsb stories are viewed with hdrPreviewEnabled off). A
    // .frag/.vert shader (the new native format) no longer disqualifies.
    function _shaderIsLegacyQsb(s) {
        var p = (s.fragPath || "").toLowerCase()
        return p.length > 0 && p.endsWith(".qsb")
    }

    function _computeNativeEligible() {
        for (var i = 0; i < shadersModelInst.count; i++) {
            if (_shaderIsLegacyQsb(shadersModelInst.get(i))) return false
        }
        if (videosModelInst.count > 1) return false
        // Phase 7 Part 4: previously also required the sole video to span
        // the full canvas -- a Phase 5-era scoping decision, not a real
        // renderer requirement (video composites through the exact same
        // per-element rect mechanism as image/text/shader, see
        // _composite_elements_pass). That restriction became a real problem
        // once the editor canvas went native too: resizing the video away
        // from full-canvas mid-drag would disqualify the whole scene,
        // blanking it -- previously unreachable since native rendering never
        // ran during plain editing before this phase. Dropped entirely; a
        // video can now be any rect.
        if (videosModelInst.count === 1) {
            var v = videosModelInst.get(0)
            if (v.vidCrossfade) return false
        }
        var renderable = videosModelInst.count + imagesModelInst.count + textBoxesModelInst.count + shadersModelInst.count
        return renderable > 0
    }

    // Phase 6 Part 2: identical to _computeNativeEligible() -- now that
    // native transitions composite each side through the same per-element
    // linear-buffer pass steady-state rendering already uses (see
    // hdr_viewport.py's _render_transition), a transition no longer needs
    // to be stricter than steady-state eligibility. Kept as a separate
    // function/property (rather than aliasing nativeEligible directly) so
    // the two concepts stay independently named at the QML/Python boundary,
    // even though their rules now match.
    function _computeNativeTransitionEligible() {
        return _computeNativeEligible()
    }

    // Builds the z-sorted element snapshot the native pipeline polls. Called
    // from loadScene() and whenever a resolved path changes outside a full
    // reload (image sourcesJson swaps -- see the image delegate).
    function _buildNativeElements() {
        if (!nativeEligible) { nativeElementsJson = "[]"; return }
        var elems = []
        var i, m
        for (i = 0; i < videosModelInst.count; i++) {
            m = videosModelInst.get(i)
            elems.push({ type: "video", x1: m.x1, y1: m.y1, x2: m.x2, y2: m.y2, z: m.stackOrder, path: m.filePath, rev: 0 })
        }
        for (i = 0; i < imagesModelInst.count; i++) {
            m = imagesModelInst.get(i)
            elems.push({ type: "image", x1: m.x1, y1: m.y1, x2: m.x2, y2: m.y2, z: m.stackOrder, path: m.filePath, rev: 0 })
        }
        // Matches tbDelegate._tbPad / tbCaptureText's own inset in the video/image
        // Repeater above -- the rasterized PNG's content only covers the inset
        // interior (matching where Qt's real tbTextEdit actually sits, not the
        // full model box), so its on-screen position must be inset the same way.
        var tbPad = 6 / editorScaleFactor
        for (i = 0; i < textBoxesModelInst.count; i++) {
            m = textBoxesModelInst.get(i)
            if (!m.nativeTexturePath) continue  // not rasterized yet -- skip until it is
            elems.push({
                type: "text", z: m.stackOrder, path: m.nativeTexturePath, rev: m.nativeTextureRev,
                x1: m.x1 + tbPad, y1: m.y1 + tbPad, x2: m.x2 - tbPad, y2: m.y2 - tbPad
            })
        }
        // Phase 7 Part 2: only .frag/.vert shaders ever reach here --
        // _computeNativeEligible() already disqualified the whole scene if
        // any shader is still a legacy .qsb path.
        for (i = 0; i < shadersModelInst.count; i++) {
            m = shadersModelInst.get(i)
            var uniforms = []
            try { uniforms = JSON.parse(m.uniformsJson || "[]") } catch (e) { uniforms = [] }
            elems.push({
                type: "shader", x1: m.x1, y1: m.y1, x2: m.x2, y2: m.y2, z: m.stackOrder,
                fragPath: m.fragPath, vertPath: m.vertPath, uniforms: uniforms
            })
        }
        elems.sort(function(a, b) { return a.z - b.z })
        nativeElementsJson = JSON.stringify(elems)
    }

    // Coalesces rebuild requests fired synchronously in a loop (e.g. a "how
    // condition" sourcesJson evaluation swapping several image rows' paths
    // one after another, each one triggering the image delegate's
    // onTrackedFilePathChanged) into a single _buildNativeElements() call.
    // Qt.callLater still runs before Qt's next scene-graph sync, so the
    // native pipeline's beforeSynchronizing-driven snapshot never observes a
    // stale intermediate JSON -- this only removes N-1 redundant rebuilds
    // per swap pass, it isn't load-bearing for correctness on its own.
    property bool _nativeElementsRebuildScheduled: false
    function _scheduleNativeElementsRebuild() {
        if (sceneContent._nativeElementsRebuildScheduled) return
        sceneContent._nativeElementsRebuildScheduled = true
        Qt.callLater(function() {
            sceneContent._nativeElementsRebuildScheduled = false
            // Phase 7 Part 4: re-derive eligibility too, not just the element
            // list -- previously only loadScene() ever recomputed this, which
            // was fine when native rendering only ran during preview (nothing
            // could resize mid-preview). Now the editor canvas is native too,
            // so a live drag can break a geometry-dependent rule (e.g. the
            // sole video no longer spanning the full canvas) that was only
            // true at load time. Without this, nativeElementsJson would keep
            // compositing the video at its new, smaller rect while the rest
            // of the canvas -- no longer covered by anything -- rendered
            // black, since there's no Qt fallback left to show through.
            // Recomputing here instead correctly disqualifies the whole
            // scene the instant the invariant breaks, same "no fallback
            // possible" contract already accepted for legacy .qsb scenes.
            sceneContent.nativeEligible = sceneContent._computeNativeEligible()
            sceneContent.nativeTransitionEligible = sceneContent._computeNativeTransitionEligible()
            sceneContent._buildNativeElements()
        })
    }

    // Phase 7 Part 4: [{x1,y1,x2,y2}] for the single selected element (border
    // + 8 handles), or "[]" when nothing/more-than-one is selected, the
    // active tool isn't "select", or the element is locked -- matching the
    // exact same conditions each delegate's own handle Items already gate on
    // (isActive && selectionCount===1 && !model.locked). Native draws this
    // instead of Qt once qtPresentationSuspended (see the opacity gates added
    // to each border/handle above). Deliberately only the selected element's
    // chrome -- an unselected area's always-on boundary outline doesn't get a
    // native equivalent yet (see the border opacity-gate comment).
    property string nativeChromeJson: "[]"

    function _buildNativeChrome() {
        var m = null
        if (viewportRef && buttonGridRef && buttonGridRef.selectedTool === "select" && viewportRef.selectionCount === 1) {
            if (viewportRef.selectedAreas.length === 1) m = areasModelInst.get(viewportRef.selectedAreas[0])
            else if (viewportRef.selectedTbs.length === 1) m = textBoxesModelInst.get(viewportRef.selectedTbs[0])
            else if (viewportRef.selectedImages.length === 1) m = imagesModelInst.get(viewportRef.selectedImages[0])
            else if (viewportRef.selectedVideos.length === 1) m = videosModelInst.get(viewportRef.selectedVideos[0])
            else if (viewportRef.selectedShaders.length === 1) m = shadersModelInst.get(viewportRef.selectedShaders[0])
        }
        if (!m || m.locked) {
            nativeChromeJson = "[]"
            return
        }
        // handleSize/borderWidth are story-space values already divided by
        // editorScaleFactor, exactly like every handle/border Item's own
        // geometry above -- this is what makes them render as a fixed
        // on-screen size regardless of the story's resolution or the
        // editor's current zoom. Sending them pre-computed means the Python
        // side never needs to know about editorScaleFactor at all.
        nativeChromeJson = JSON.stringify([{
            x1: m.x1, y1: m.y1, x2: m.x2, y2: m.y2,
            handleSize: 8 / editorScaleFactor,
            borderWidth: 2 / editorScaleFactor
        }])
    }

    property bool _nativeChromeRebuildScheduled: false
    function _scheduleNativeChromeRebuild() {
        if (sceneContent._nativeChromeRebuildScheduled) return
        sceneContent._nativeChromeRebuildScheduled = true
        Qt.callLater(function() {
            sceneContent._nativeChromeRebuildScheduled = false
            sceneContent._buildNativeChrome()
        })
    }

    // Selection changes (selectArea/selectImage/.../clearSelection, all on
    // viewportRef) always bump selectionRevision, and tool switches change
    // which chrome (if any) should show -- both need a rebuild independent
    // of any one delegate's own model-role changes below.
    Connections {
        target: viewportRef
        enabled: viewportRef !== null
        function onSelectionRevisionChanged() { sceneContent._scheduleNativeChromeRebuild() }
    }
    Connections {
        target: buttonGridRef
        enabled: buttonGridRef !== null
        function onSelectedToolChanged() { sceneContent._scheduleNativeChromeRebuild() }
    }

    // Serialize this layer's scene to a JSON string for DB persistence.
    // Note: caller is responsible for flushing selectSettings.saveCurrentInteractivity()
    // before calling this if the select tool is active.
    function collectElements() {
        var elements = []
        var i, m
        for (i = 0; i < areasModelInst.count; i++) {
            m = areasModelInst.get(i)
            elements.push({ type: "area",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                name: m.name || "", z_order: m.stackOrder,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < textBoxesModelInst.count; i++) {
            m = textBoxesModelInst.get(i)
            elements.push({ type: "text",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                z_order: m.stackOrder, name: m.name || "",
                family: m.family, tbWeight: m.tbWeight, size: m.size,
                italic: m.italic, underline: m.underline,
                textColor: m.textColor, content: m.content,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < imagesModelInst.count; i++) {
            m = imagesModelInst.get(i)
            elements.push({ type: "image",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                // Persist baseFilePath (the authored source), not filePath (the
                // how-condition system's live/resolved value) -- see loadScene().
                name: m.name || "", z_order: m.stackOrder, filePath: m.baseFilePath,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                sourcesJson: m.sourcesJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < videosModelInst.count; i++) {
            m = videosModelInst.get(i)
            elements.push({ type: "video",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                // See the image case above -- persist baseFilePath, not filePath.
                name: m.name || "", z_order: m.stackOrder, filePath: m.baseFilePath,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                sourcesJson: m.sourcesJson || "[]",
                template: m.template || "none",
                locked: m.locked || false,
                vidLoop: m.vidLoop !== undefined ? m.vidLoop : true,
                vidCrossfade: m.vidCrossfade || false,
                vidCrossfadePct: m.vidCrossfadePct !== undefined ? m.vidCrossfadePct : 5,
                mixerTrackName: m.mixerTrackName || "",
                mixerVolume: m.mixerVolume !== undefined ? m.mixerVolume : 1.0,
                mixerPan: m.mixerPan !== undefined ? m.mixerPan : 0.0,
                syncGroupId: m.syncGroupId !== undefined ? m.syncGroupId : -1 })
        }
        for (i = 0; i < shadersModelInst.count; i++) {
            m = shadersModelInst.get(i)
            elements.push({ type: "shader",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                name: m.name || "", z_order: m.stackOrder,
                // Persist baseFragPath/baseVertPath (authored), not fragPath/
                // vertPath (the how-condition system's live/resolved value).
                fragPath: m.baseFragPath, vertPath: m.baseVertPath,
                uniformsJson: m.uniformsJson,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                sourcesJson: m.sourcesJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < audioTracksModelInst.count; i++) {
            m = audioTracksModelInst.get(i)
            elements.push({ type: "audioTrack",
                filePath: m.filePath || "",
                mixerTrackName: m.mixerTrackName || "",
                mixerVolume: m.mixerVolume !== undefined ? m.mixerVolume : 1.0,
                mixerPan: m.mixerPan !== undefined ? m.mixerPan : 0.0,
                syncGroupId: m.syncGroupId !== undefined ? m.syncGroupId : -1 })
        }
        return JSON.stringify(elements)
    }

    function serializeInteractivityModel(mdl) {
        var items = []
        for (var i = 0; i < mdl.count; i++) {
            var e = mdl.get(i)
            items.push({
                itemTrigger: e.itemTrigger, itemAction: e.itemAction,
                itemCommand: e.itemCommand, itemTransition: e.itemTransition,
                itemTransitionSpeed: e.itemTransitionSpeed,
                itemSoundSpeed: e.itemSoundSpeed, itemSoundSpeedLinked: e.itemSoundSpeedLinked,
                itemWipeFeather: e.itemWipeFeather, itemWipeDirection: e.itemWipeDirection,
                itemPushDirection: e.itemPushDirection,
                itemLookYaw: e.itemLookYaw, itemLookPitch: e.itemLookPitch,
                itemLookFovMM: e.itemLookFovMM, itemLookOvershoot: e.itemLookOvershoot, itemLookShutter: e.itemLookShutter,
                itemTargetSceneId: e.itemTargetSceneId, itemTargetSceneName: e.itemTargetSceneName,
                itemConditionVar: e.itemConditionVar, itemConditionOp: e.itemConditionOp,
                itemConditionVal: e.itemConditionVal, itemSoundPath: e.itemSoundPath,
                itemSoundVolume: e.itemSoundVolume, itemSoundPan: e.itemSoundPan,
                itemSoundTrackName: e.itemSoundTrackName, itemSoundSyncGroupId: e.itemSoundSyncGroupId,
                itemVideoPath: e.itemVideoPath, itemVideoTarget: e.itemVideoTarget,
                itemUpdateVar: e.itemUpdateVar, itemUpdateOp: e.itemUpdateOp, itemUpdateVal: e.itemUpdateVal,
                itemWhereNetworkId: e.itemWhereNetworkId, itemWhereCharName: e.itemWhereCharName,
                itemWhereOp: e.itemWhereOp, itemWhereNodeName: e.itemWhereNodeName,
                itemWhenChapterId: e.itemWhenChapterId, itemWhenOp: e.itemWhenOp,
                itemWhenSeconds: e.itemWhenSeconds, itemWhenFormat: e.itemWhenFormat, itemWhenTC: e.itemWhenTC
            })
        }
        return JSON.stringify(items)
    }

    function loadInteractivityModel(mdl, json) {
        mdl.clear()
        var items = []
        try { items = JSON.parse(json || "[]") } catch(e) {}
        for (var i = 0; i < items.length; i++) {
            var e = items[i]
            mdl.append({
                itemTrigger:         e.itemTrigger         || "click",
                itemAction:          e.itemAction          || "cue",
                itemCommand:         e.itemCommand         || "jump",
                itemTransition:      e.itemTransition      || "cut",
                itemTransitionSpeed: e.itemTransitionSpeed !== undefined ? e.itemTransitionSpeed : 1.0,
                itemSoundSpeed:      e.itemSoundSpeed       !== undefined ? e.itemSoundSpeed       : 1.0,
                itemSoundSpeedLinked: e.itemSoundSpeedLinked !== undefined ? e.itemSoundSpeedLinked : true,
                itemWipeFeather:     e.itemWipeFeather     !== undefined ? e.itemWipeFeather     : 0.0,
                itemWipeDirection:   e.itemWipeDirection   || "right",
                itemPushDirection:   e.itemPushDirection   || "right",
                itemLookYaw:         e.itemLookYaw         !== undefined ? e.itemLookYaw         : 90.0,
                itemLookPitch:       e.itemLookPitch       !== undefined ? e.itemLookPitch       : 0.0,
                itemLookFovMM:       e.itemLookFovMM       !== undefined ? e.itemLookFovMM       : 24.0,
                itemLookOvershoot:   e.itemLookOvershoot   !== undefined ? e.itemLookOvershoot   : 1.0,
                itemLookShutter:     e.itemLookShutter     !== undefined ? e.itemLookShutter     : 0.10,
                itemTargetSceneId:   e.itemTargetSceneId   !== undefined ? e.itemTargetSceneId : -1,
                itemTargetSceneName: e.itemTargetSceneName || "",
                itemConditionVar:    e.itemConditionVar    || "",
                itemConditionOp:     e.itemConditionOp     || "is",
                itemConditionVal:    e.itemConditionVal    || "",
                itemSoundPath:       e.itemSoundPath       || "",
                itemSoundVolume:     e.itemSoundVolume     !== undefined ? e.itemSoundVolume : 1.0,
                itemSoundPan:        e.itemSoundPan        !== undefined ? e.itemSoundPan    : 0.0,
                itemSoundTrackName:  e.itemSoundTrackName  || "",
                itemSoundSyncGroupId: e.itemSoundSyncGroupId !== undefined ? e.itemSoundSyncGroupId : -1,
                itemVideoPath:       e.itemVideoPath       || "",
                itemVideoTarget:     e.itemVideoTarget     || "fill",
                itemUpdateVar:       e.itemUpdateVar       || "",
                itemUpdateOp:        e.itemUpdateOp        || "=",
                itemUpdateVal:       e.itemUpdateVal       || "",
                itemWhereNetworkId:  e.itemWhereNetworkId  !== undefined ? e.itemWhereNetworkId : -1,
                itemWhereCharName:   e.itemWhereCharName   || "",
                itemWhereOp:         e.itemWhereOp         || "is at",
                itemWhereNodeName:   e.itemWhereNodeName   || "",
                itemWhenChapterId:   e.itemWhenChapterId   !== undefined ? e.itemWhenChapterId : -1,
                itemWhenOp:          e.itemWhenOp          || "=",
                itemWhenSeconds:     e.itemWhenSeconds      !== undefined ? e.itemWhenSeconds  : 0.0,
                itemWhenFormat:      e.itemWhenFormat       || "",
                itemWhenTC:          e.itemWhenTC           || ""
            })
        }
    }

    function parseInteractivityJson(json) {
        try { return JSON.parse(json || "[]") } catch(e) { return [] }
    }

    // Scans every on-canvas element's interactivity list for "sound" cue commands
    // and returns a flat descriptor array for the audio mixer. Not live-reactive —
    // callers re-fetch this (e.g. when the mixer tab opens or the scene changes).
    function collectSoundCommandSources() {
        var result = []
        var groups = [
            { model: areasModelInst,      elementType: "area" },
            { model: textBoxesModelInst,  elementType: "text" },
            { model: imagesModelInst,     elementType: "image" },
            { model: videosModelInst,     elementType: "video" },
            { model: shadersModelInst,    elementType: "shader" }
        ]
        for (var g = 0; g < groups.length; g++) {
            var mdl = groups[g].model
            for (var i = 0; i < mdl.count; i++) {
                var el = mdl.get(i)
                var items = parseInteractivityJson(el.interactivityJson)
                for (var j = 0; j < items.length; j++) {
                    var it = items[j]
                    if (it.itemCommand !== "sound") continue
                    result.push({
                        elementType: groups[g].elementType,
                        elementIdx: i,
                        itemIdx: j,
                        elementName: el.name || "",
                        filePath: it.itemSoundPath || "",
                        mixerTrackName: it.itemSoundTrackName || "",
                        mixerVolume: it.itemSoundVolume !== undefined ? it.itemSoundVolume : 1.0,
                        mixerPan: it.itemSoundPan !== undefined ? it.itemSoundPan : 0.0,
                        syncGroupId: it.itemSoundSyncGroupId !== undefined ? it.itemSoundSyncGroupId : -1
                    })
                }
            }
        }
        return result
    }

    // Writes an edited mixer field back into the owning element's interactivityJson
    // for a "sound" cue command descriptor produced by collectSoundCommandSources().
    function setSoundCommandSourceProp(elementType, elementIdx, itemIdx, key, value) {
        var modelMap = {
            area: areasModelInst, text: textBoxesModelInst, image: imagesModelInst,
            video: videosModelInst, shader: shadersModelInst
        }
        var mdl = modelMap[elementType]
        if (!mdl || elementIdx < 0 || elementIdx >= mdl.count) return
        var el = mdl.get(elementIdx)
        var items = parseInteractivityJson(el.interactivityJson)
        if (itemIdx < 0 || itemIdx >= items.length) return
        items[itemIdx][key] = value
        mdl.setProperty(elementIdx, "interactivityJson", JSON.stringify(items))
    }

    // Expose shader delegate for external code that needs to update live uniforms.
    function shaderDelegateAt(idx) { return shadersRepeater.itemAt(idx) }

    // Fire "click" interactivity on all areas whose template matches tpl.
    // Called by NodeWorkspace keyboard mapping when simulate mode is active.
    function fireAreasByTemplate(tpl) {
        for (var i = 0; i < areasModelInst.count; i++) {
            if (areasModelInst.get(i).template === tpl) {
                var item = areasRepeater.itemAt(i)
                if (item) item.fireByKeyboard()
            }
        }
    }

    // ── Repeaters ───────────────────────────────────────────────────────────
            Repeater {
                id: areasRepeater
                model: areasModel
                delegate: Item {
                    id: areaDelegate
                    // expanded 28px on all sides so 56x56 handle items stay within parent bounds
                    x: model.x1 - 28 / sceneContent.editorScaleFactor
                    y: model.y1 - 28 / sceneContent.editorScaleFactor
                    width: model.x2 - model.x1 + 56 / sceneContent.editorScaleFactor
                    height: model.y2 - model.y1 + 56 / sceneContent.editorScaleFactor
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedAreas.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "area" && viewportRef.relayerHoveredIndex === index
                    property var _cachedInteractivity: sceneContent.parseInteractivityJson(model.interactivityJson)
                    // Phase 7 Part 4: model.x1/y1/x2/y2/locked are live role
                    // bindings in this delegate scope (unlike a .get() snapshot),
                    // so this reacts correctly to both the move-MouseArea and any
                    // resize-handle drag mutating the same roles via setProperty.
                    readonly property string _trackedChromeKey: model.x1 + "," + model.y1 + "," + model.x2 + "," + model.y2 + "," + model.locked
                    on_TrackedChromeKeyChanged: {
                        sceneContent._scheduleNativeChromeRebuild()
                        // Phase 7 Part 4: nativeElementsJson's per-element rect was
                        // previously only ever set at loadScene() time -- never
                        // rebuilt live during a move/resize drag, since native
                        // rendering never ran during plain editing before this
                        // phase. Same x1/y1/x2/y2/locked key as the chrome rebuild
                        // above, just also driving the content (not just chrome).
                        sceneContent._scheduleNativeElementsRebuild()
                    }
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "area" && viewportRef.deleteTargetIndex === index

                    function fireByKeyboard() { areaSimulateMouseArea.fireInteractivity("click") }

                    // Visual border (inset by 28px to match model coordinates).
                    // Hidden during simulate mode, shader transitions, and thumbnail capture —
                    // areas are invisible hotspots in those contexts, not editor decorations.
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        visible: isInteractive &&
                                 buttonGridRef.selectedTool !== "simulate" &&
                                 !viewportRef.wiping && !viewportRef.sliding && !viewportRef.looking &&
                                 !viewportRef.capturingThumbnail
                        color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewportRef.deleteProgress * 0.6) : (areaDelegate.isActive && index === viewportRef.hoveredAreaIndex ? Qt.rgba(1, 1, 1, 0.15) : "transparent")
                        border.color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((areaDelegate.isActive || areaDelegate.isRelayerHovered) ? "white" : "#666666")
                        border.width: (areaDelegate.isActive && index === viewportRef.hoveredAreaIndex) || areaDelegate.isRelayerHovered ? 2 : 1
                        // Phase 7 Part 4: only the selected element's border+handles get a
                        // native equivalent (see _buildNativeChrome()) -- an unselected area's
                        // plain boundary outline is a deliberately deferred gap for now.
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        Behavior on color {
                            ColorAnimation {
                                duration: 80
                            }
                        }
                        Behavior on border.width {
                            NumberAnimation {
                                duration: 80
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: areaDelegate.isActive && index === viewportRef.hoveredAreaIndex ? 2 : 1
                            color: "transparent"
                            border.color: "black"
                            border.width: 1
                            Behavior on anchors.margins {
                                NumberAnimation {
                                    duration: 80
                                }
                            }
                        }
                    }

                    // Simulate: click/hover to trigger interactivity in preview mode
                    // Note: viewportCursorArea (z:999, hoverEnabled:true) consumes all hover events
                    // so onEntered never fires here. Hover is detected via viewportRef.hoveredAreaIndex
                    // which viewportCursorArea already maintains correctly.
                    MouseArea {
                        id: areaSimulateMouseArea
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            if (viewportRef.cueVideoActive) return
                            IE.fire(trigger, areaDelegate._cachedInteractivity, sceneContent._ieContext("area", index))
                        }

                        onClicked: fireInteractivity("click")
                    }

                    // Hover interactivity: triggered via hoveredAreaIndex since viewportCursorArea
                    // at z:999 owns all hover events and already tracks this correctly.
                    Connections {
                        target: viewport
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        function onHoveredAreaIndexChanged() {
                            if (viewportRef.hoveredAreaIndex === index)
                                areaSimulateMouseArea.fireInteractivity("hover")
                        }
                    }

                    // Move: covers shape interior only, leaving handle regions free
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: areaDelegate.isSelect
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: areaDelegate.isActive && !model.locked ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewportRef.tempDestroyMode = true;
                                viewportRef.deleteTargetType = "area";
                                viewportRef.deleteTargetIndex = index;
                                return;
                            }
                            viewportRef.selectArea(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragging = true;
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!model.locked && areaDelegate.isActive) {
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX1 = model.x1;
                                areaDelegate.origY1 = model.y1;
                                areaDelegate.origX2 = model.x2;
                                areaDelegate.origY2 = model.y2;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!areaDelegate.isActive || model.locked) return;
                            var dx = (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, dy = (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor;
                            var w = areaDelegate.origX2 - areaDelegate.origX1, h = areaDelegate.origY2 - areaDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + dx, viewportRef.contentWidth - w));
                            var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + dy, viewportRef.contentHeight - h));
                            areasModel.setProperty(index, "x1", nx1);
                            areasModel.setProperty(index, "y1", ny1);
                            areasModel.setProperty(index, "x2", nx1 + w);
                            areasModel.setProperty(index, "y2", ny1 + h);
                            viewportRef.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewportRef.deleteTargetType === "area" && viewportRef.deleteTargetIndex === index)
                                    viewportRef.cancelDelete();
                                return;
                            }
                            viewportRef.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewportRef.relayerHoveredType = "area";
                            viewportRef.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewportRef.relayerHoveredType === "area" && viewportRef.relayerHoveredIndex === index) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewportRef.relayerHoveredType = "area";
                            viewportRef.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            areasModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Delete (destroy tool): click-and-hold to remove
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: buttonGridRef.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewportRef.deleteTargetType = "area";
                            viewportRef.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewportRef.deleteTargetType === "area" && viewportRef.deleteTargetIndex === index)
                                viewportRef.cancelDelete();
                        }
                    }

                    // Resize handles — 56x56 hit area, 8x8 visual dot, centered on shape corners/midpoints
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX1 = model.x1;
                                areaDelegate.origY1 = model.y1;
                                areaDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = model.y2 - ny1;
                                    if (nW / nH > areaDelegate.origAspect) {
                                        nW = nH * areaDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / areaDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                areasModel.setProperty(index, "x1", nx1);
                                areasModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origY1 = model.y1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                areasModel.setProperty(index, "y1", Math.max(0, Math.min(areaDelegate.origY1 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX2 = model.x2;
                                areaDelegate.origY1 = model.y1;
                                areaDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(areaDelegate.origX2 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                    if (nW / nH > areaDelegate.origAspect) {
                                        nW = nH * areaDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / areaDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                areasModel.setProperty(index, "x2", nx2);
                                areasModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.origX2 = model.x2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                areasModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, Math.max(areaDelegate.origX2 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX2 = model.x2;
                                areaDelegate.origY2 = model.y2;
                                areaDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(areaDelegate.origX2 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(areaDelegate.origY2 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                    if (nW / nH > areaDelegate.origAspect) {
                                        nW = nH * areaDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / areaDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                areasModel.setProperty(index, "x2", nx2);
                                areasModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: parent.height - 42 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origY2 = model.y2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                areasModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, Math.max(areaDelegate.origY2 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX1 = model.x1;
                                areaDelegate.origY2 = model.y2;
                                areaDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(areaDelegate.origY2 + (pt.y - areaDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                    if (nW / nH > areaDelegate.origAspect) {
                                        nW = nH * areaDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / areaDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                areasModel.setProperty(index, "x1", nx1);
                                areasModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.origX1 = model.x1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                areasModel.setProperty(index, "x1", Math.max(0, Math.min(areaDelegate.origX1 + (pt.x - areaDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                }
            }

            // Completed text boxes
            Repeater {
                model: textBoxesModel
                delegate: Item {
                    id: tbDelegate
                    // expanded 28px on all sides so 56x56 handle items stay within parent bounds
                    x: model.x1 - 28 / sceneContent.editorScaleFactor
                    y: model.y1 - 28 / sceneContent.editorScaleFactor
                    width: model.x2 - model.x1 + 56 / sceneContent.editorScaleFactor
                    height: model.y2 - model.y1 + 56 / sceneContent.editorScaleFactor
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedTbs.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "tb" && viewportRef.relayerHoveredIndex === index
                    property var _cachedInteractivity: sceneContent.parseInteractivityJson(model.interactivityJson)
                    // Phase 7 Part 4: model.x1/y1/x2/y2/locked are live role
                    // bindings in this delegate scope (unlike a .get() snapshot),
                    // so this reacts correctly to both the move-MouseArea and any
                    // resize-handle drag mutating the same roles via setProperty.
                    readonly property string _trackedChromeKey: model.x1 + "," + model.y1 + "," + model.x2 + "," + model.y2 + "," + model.locked
                    on_TrackedChromeKeyChanged: {
                        sceneContent._scheduleNativeChromeRebuild()
                        // Phase 7 Part 4: nativeElementsJson's per-element rect was
                        // previously only ever set at loadScene() time -- never
                        // rebuilt live during a move/resize drag, since native
                        // rendering never ran during plain editing before this
                        // phase. Same x1/y1/x2/y2/locked key as the chrome rebuild
                        // above, just also driving the content (not just chrome).
                        sceneContent._scheduleNativeElementsRebuild()
                    }
                    property bool editing: false
                    onEditingChanged: viewportRef.textEditing = editing
                    onIsActiveChanged: if (!isActive && editing) {
                        editing = false;
                        tbTextEdit.focus = false;
                    }
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "tb" && viewportRef.deleteTargetIndex === index

                    // tbTextEdit sits inset from the model box (x: 34/editorScaleFactor
                    // vs the border's x: 28/editorScaleFactor -- a fixed 6-editor-pixel
                    // gap on each side), not flush with model.x1/y1/x2/y2. The native
                    // capture/positioning below must match this exactly or the
                    // rasterized text lands at a visibly different spot than Qt's.
                    readonly property real _tbPad: 6 / sceneContent.editorScaleFactor

                    // ── Native HDR preview pipeline (Phase 5 Stage C) ───────────────
                    // Text isn't rendered natively via real font shaping -- instead Qt
                    // rasterizes this box to a PNG (the same grabToImage/saveToFile
                    // pattern already used for scene thumbnails), and the native
                    // pipeline treats the result exactly like any other image element.
                    // Rasterization only ever needs to happen while editing (never
                    // during preview, since text is immutable then), so re-rasterizing
                    // on every keystroke is debounced; the very first rasterization on
                    // scene load fires immediately (not debounced) to minimize the
                    // window where preview would show stale/missing text.
                    property string _textStyleKey: model.content + "" + model.family + "" +
                        model.tbWeight + "" + model.size + "" + model.italic + "" +
                        model.underline + "" + model.textColor
                    on_TextStyleKeyChanged: {
                        if (tbDelegate._rasterizedOnce) tbRasterizeTimer.restart()
                    }
                    property bool _rasterizedOnce: false

                    function rasterizeText() {
                        tbDelegate._rasterizedOnce = true
                        var rev = (model.nativeTextureRev || 0) + 1
                        // SceneContent.qml has no id-scope access to mainWindow (a
                        // separate component file) for a scene-id-based name --
                        // Date.now() + index + rev is unique enough on its own.
                        var path = "/tmp/understory_text_" + Date.now() + "_" + index + "_" + rev + ".png"
                        tbCaptureText.grabToImage(function (result) {
                            result.saveToFile(path)
                            textBoxesModel.setProperty(index, "nativeTexturePath", path)
                            textBoxesModel.setProperty(index, "nativeTextureRev", rev)
                            sceneContent._buildNativeElements()
                        }, Qt.size(tbCaptureText.width, tbCaptureText.height))
                    }

                    Timer {
                        id: tbRasterizeTimer
                        interval: 250
                        repeat: false
                        onTriggered: tbDelegate.rasterizeText()
                    }


                    // Off-screen (not visible:false -- an invisible item isn't rendered
                    // at all, so grabToImage would just capture blank; layer.enabled
                    // forces Qt to render it to a texture despite being off-screen, the
                    // same technique already used for thumbnailCaptureSurface). Sized in
                    // story-space (matching model.size's units) so word-wrap breaks land
                    // exactly where the real box's story-space width would wrap them,
                    // independent of the editor's current zoom/scale.
                    Text {
                        id: tbCaptureText
                        x: -100000
                        y: -100000
                        width: Math.max(1, model.x2 - model.x1 - 2 * tbDelegate._tbPad)
                        height: Math.max(1, model.y2 - model.y1 - 2 * tbDelegate._tbPad)
                        layer.enabled: true
                        text: model.content
                        color: model.textColor
                        font.family: model.family
                        font.weight: model.tbWeight
                        font.pixelSize: model.size
                        font.italic: model.italic
                        font.underline: model.underline
                        wrapMode: Text.Wrap
                    }

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewportRef.deleteProgress * 0.6) : "transparent"
                        border.color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((tbDelegate.isActive || tbDelegate.isRelayerHovered) ? "white" : "#666666")
                        border.width: tbDelegate.isRelayerHovered ? 2 : 1
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: "black"
                            border.width: 1
                        }
                    }

                    TextEdit {
                        id: tbTextEdit
                        x: 34 / sceneContent.editorScaleFactor
                        y: 34 / sceneContent.editorScaleFactor
                        width: parent.width - 68 / sceneContent.editorScaleFactor
                        height: parent.height - 68 / sceneContent.editorScaleFactor
                        // Not interactive during preview anyway (typing/focus
                        // are editor-only); native text is a grab of the
                        // separate offscreen tbCaptureText twin above, so
                        // this on-screen editable widget is purely redundant
                        // to hide once the native overlay covers preview.
                        visible: !sceneContent.qtPresentationSuspended
                        text: model.content
                        color: model.textColor
                        font.family: model.family
                        font.weight: model.tbWeight
                        font.pixelSize: model.size
                        font.italic: model.italic
                        font.underline: model.underline
                        wrapMode: TextEdit.Wrap
                        clip: true
                        onTextChanged: textBoxesModel.setProperty(index, "content", text)
                        onActiveFocusChanged: if (!activeFocus)
                            tbDelegate.editing = false
                    }

                    // Interior MouseArea: disabled when editing so TextEdit handles its own mouse events.
                    // When not editing: double-click to enter edit mode, drag to move (select tool only).
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: !tbDelegate.editing
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: tbDelegate.isActive && !model.locked ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onDoubleClicked: {
                            if (tbDelegate.isActive && !model.locked) {
                                tbDelegate.editing = true;
                                tbTextEdit.forceActiveFocus();
                            }
                        }
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton && tbDelegate.isSelect) {
                                viewportRef.tempDestroyMode = true;
                                viewportRef.deleteTargetType = "tb";
                                viewportRef.deleteTargetIndex = index;
                                return;
                            }
                            viewportRef.selectTb(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragging = true;
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!model.locked && tbDelegate.isSelect) {
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX1 = model.x1;
                                tbDelegate.origY1 = model.y1;
                                tbDelegate.origX2 = model.x2;
                                tbDelegate.origY2 = model.y2;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (tbDelegate.isActive && tbDelegate.isSelect && !model.locked) {
                                var dx = (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, dy = (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor;
                                var w = tbDelegate.origX2 - tbDelegate.origX1, h = tbDelegate.origY2 - tbDelegate.origY1;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + dx, viewportRef.contentWidth - w));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + dy, viewportRef.contentHeight - h));
                                textBoxesModel.setProperty(index, "x1", nx1);
                                textBoxesModel.setProperty(index, "y1", ny1);
                                textBoxesModel.setProperty(index, "x2", nx1 + w);
                                textBoxesModel.setProperty(index, "y2", ny1 + h);
                                viewportRef.posRevision++;
                            }
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewportRef.deleteTargetType === "tb" && viewportRef.deleteTargetIndex === index)
                                    viewportRef.cancelDelete();
                                return;
                            }
                            viewportRef.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewportRef.relayerHoveredType = "tb";
                            viewportRef.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewportRef.relayerHoveredType === "tb" && viewportRef.relayerHoveredIndex === index) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewportRef.relayerHoveredType = "tb";
                            viewportRef.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            textBoxesModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Delete (destroy tool): click-and-hold to remove
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: buttonGridRef.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewportRef.deleteTargetType = "tb";
                            viewportRef.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewportRef.deleteTargetType === "tb" && viewportRef.deleteTargetIndex === index)
                                viewportRef.cancelDelete();
                        }
                    }

                    // Resize handles — 56x56 hit area, 8x8 visual dot, centered on shape corners/midpoints
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX1 = model.x1;
                                tbDelegate.origY1 = model.y1;
                                tbDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = model.y2 - ny1;
                                    if (nW / nH > tbDelegate.origAspect) {
                                        nW = nH * tbDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / tbDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                textBoxesModel.setProperty(index, "x1", nx1);
                                textBoxesModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origY1 = model.y1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                textBoxesModel.setProperty(index, "y1", Math.max(0, Math.min(tbDelegate.origY1 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX2 = model.x2;
                                tbDelegate.origY1 = model.y1;
                                tbDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(tbDelegate.origX2 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                    if (nW / nH > tbDelegate.origAspect) {
                                        nW = nH * tbDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / tbDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                textBoxesModel.setProperty(index, "x2", nx2);
                                textBoxesModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.origX2 = model.x2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                textBoxesModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, Math.max(tbDelegate.origX2 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX2 = model.x2;
                                tbDelegate.origY2 = model.y2;
                                tbDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(tbDelegate.origX2 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(tbDelegate.origY2 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                    if (nW / nH > tbDelegate.origAspect) {
                                        nW = nH * tbDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / tbDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                textBoxesModel.setProperty(index, "x2", nx2);
                                textBoxesModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: parent.height - 42 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origY2 = model.y2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                textBoxesModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, Math.max(tbDelegate.origY2 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX1 = model.x1;
                                tbDelegate.origY2 = model.y2;
                                tbDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(tbDelegate.origY2 + (pt.y - tbDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                    if (nW / nH > tbDelegate.origAspect) {
                                        nW = nH * tbDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / tbDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                textBoxesModel.setProperty(index, "x1", nx1);
                                textBoxesModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.origX1 = model.x1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                textBoxesModel.setProperty(index, "x1", Math.max(0, Math.min(tbDelegate.origX1 + (pt.x - tbDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: tbSimulateMouseArea
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            if (viewportRef.cueVideoActive) return
                            IE.fire(trigger, tbDelegate._cachedInteractivity, sceneContent._ieContext("text", index))
                        }

                        onClicked: fireInteractivity("click")
                    }

                    Connections {
                        target: viewport
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        function onHoveredTbIndexChanged() {
                            if (viewportRef.hoveredTbIndex === index)
                                tbSimulateMouseArea.fireInteractivity("hover")
                        }
                    }

                    Component.onCompleted: {
                        rasterizeText();
                        if (index === viewportRef.pendingFocusTextBox) {
                            tbDelegate.editing = true;
                            tbTextEdit.forceActiveFocus();
                            viewportRef.pendingFocusTextBox = -1;
                        }
                    }
                }
            }

            // Completed images
            Repeater {
                model: imagesModel
                delegate: Item {
                    id: imgDelegate
                    x: model.x1 - 28 / sceneContent.editorScaleFactor
                    y: model.y1 - 28 / sceneContent.editorScaleFactor
                    width: model.x2 - model.x1 + 56 / sceneContent.editorScaleFactor
                    height: model.y2 - model.y1 + 56 / sceneContent.editorScaleFactor
                    z: 100 + model.stackOrder
                    layer.enabled: !sceneContent.previewActive

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedImages.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "image" && viewportRef.relayerHoveredIndex === index
                    property var _cachedInteractivity: sceneContent.parseInteractivityJson(model.interactivityJson)
                    // Phase 7 Part 4: model.x1/y1/x2/y2/locked are live role
                    // bindings in this delegate scope (unlike a .get() snapshot),
                    // so this reacts correctly to both the move-MouseArea and any
                    // resize-handle drag mutating the same roles via setProperty.
                    readonly property string _trackedChromeKey: model.x1 + "," + model.y1 + "," + model.x2 + "," + model.y2 + "," + model.locked
                    on_TrackedChromeKeyChanged: {
                        sceneContent._scheduleNativeChromeRebuild()
                        // Phase 7 Part 4: nativeElementsJson's per-element rect was
                        // previously only ever set at loadScene() time -- never
                        // rebuilt live during a move/resize drag, since native
                        // rendering never ran during plain editing before this
                        // phase. Same x1/y1/x2/y2/locked key as the chrome rebuild
                        // above, just also driving the content (not just chrome).
                        sceneContent._scheduleNativeElementsRebuild()
                    }
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "image" && viewportRef.deleteTargetIndex === index

                    // Native HDR preview pipeline (Phase 5 Stage D): a "how condition"
                    // sourcesJson swap (evaluateAllSourcesForContent/completeVideoTransition
                    // in understoryui.qml) mutates model.filePath directly, with no
                    // loadScene() call involved at all -- nativeElementsJson was only ever
                    // built once at load time, so without this push it would silently keep
                    // referencing the old (now-wrong) image forever after a swap, exactly
                    // the same gap Phase 4 Stage 5 found and fixed for video. model.filePath
                    // bindings are reliably reactive in a delegate context (unlike
                    // ListModel.get(i).x snapshot reads used elsewhere in this codebase),
                    // so this catches every swap _buildNativeElements()'s own one-time
                    // build at loadScene() would otherwise miss.
                    readonly property string trackedFilePath: model.filePath
                    onTrackedFilePathChanged: sceneContent._scheduleNativeElementsRebuild()

                    // Image fill
                    Image {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        source: model.filePath
                        fillMode: Image.Stretch
                        clip: true
                        // Image loading/status is independent of visibility --
                        // already an established, relied-upon pattern in this
                        // codebase (the hidden dimension-probe Image items).
                        visible: !sceneContent.qtPresentationSuspended
                        onStatusChanged: {
                            if (status === Image.Ready || status === Image.Error)
                                imageLoadComplete()
                        }
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 1
                        color: "transparent"
                        border.color: imgDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: imgDelegate.isRelayerHovered ? 2 : 1
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: (imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "black" : "transparent"
                            border.width: 1
                        }
                    }

                    // Red delete overlay
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 2
                        color: Qt.rgba(1, 0, 0, imgDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: imgDelegate.isSelect
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: imgDelegate.isActive && !model.locked ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewportRef.tempDestroyMode = true;
                                viewportRef.deleteTargetType = "image";
                                viewportRef.deleteTargetIndex = index;
                                return;
                            }
                            viewportRef.selectImage(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragging = true;
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!model.locked && imgDelegate.isActive) {
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX1 = model.x1;
                                imgDelegate.origY1 = model.y1;
                                imgDelegate.origX2 = model.x2;
                                imgDelegate.origY2 = model.y2;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!imgDelegate.isActive || model.locked) return;
                            var dx = (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, dy = (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor;
                            var w = imgDelegate.origX2 - imgDelegate.origX1, h = imgDelegate.origY2 - imgDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + dx, viewportRef.contentWidth - w));
                            var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + dy, viewportRef.contentHeight - h));
                            imagesModel.setProperty(index, "x1", nx1);
                            imagesModel.setProperty(index, "y1", ny1);
                            imagesModel.setProperty(index, "x2", nx1 + w);
                            imagesModel.setProperty(index, "y2", ny1 + h);
                            viewportRef.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewportRef.deleteTargetType === "image" && viewportRef.deleteTargetIndex === index)
                                    viewportRef.cancelDelete();
                                return;
                            }
                            viewportRef.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewportRef.relayerHoveredType = "image";
                            viewportRef.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewportRef.relayerHoveredType === "image" && viewportRef.relayerHoveredIndex === index) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewportRef.relayerHoveredType = "image";
                            viewportRef.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            imagesModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Delete (destroy tool): click-and-hold to remove
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: buttonGridRef.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewportRef.deleteTargetType = "image";
                            viewportRef.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewportRef.deleteTargetType === "image" && viewportRef.deleteTargetIndex === index)
                                viewportRef.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX1 = model.x1;
                                imgDelegate.origY1 = model.y1;
                                imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (!(mouse.modifiers & Qt.ShiftModifier)) {
                                    var nW = model.x2 - nx1, nH = model.y2 - ny1;
                                    if (nW / nH > imgDelegate.origAspect) {
                                        nW = nH * imgDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / imgDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                imagesModel.setProperty(index, "x1", nx1);
                                imagesModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origY1 = model.y1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                imagesModel.setProperty(index, "y1", Math.max(0, Math.min(imgDelegate.origY1 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX2 = model.x2;
                                imgDelegate.origY1 = model.y1;
                                imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(imgDelegate.origX2 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (!(mouse.modifiers & Qt.ShiftModifier)) {
                                    var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                    if (nW / nH > imgDelegate.origAspect) {
                                        nW = nH * imgDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / imgDelegate.origAspect;
                                        ny1 = model.y2 - nH;
                                    }
                                }
                                imagesModel.setProperty(index, "x2", nx2);
                                imagesModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.origX2 = model.x2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                imagesModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, Math.max(imgDelegate.origX2 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX2 = model.x2;
                                imgDelegate.origY2 = model.y2;
                                imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(imgDelegate.origX2 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(imgDelegate.origY2 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (!(mouse.modifiers & Qt.ShiftModifier)) {
                                    var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                    if (nW / nH > imgDelegate.origAspect) {
                                        nW = nH * imgDelegate.origAspect;
                                        nx2 = model.x1 + nW;
                                    } else {
                                        nH = nW / imgDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                imagesModel.setProperty(index, "x2", nx2);
                                imagesModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: parent.height - 42 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origY2 = model.y2;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                imagesModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, Math.max(imgDelegate.origY2 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX1 = model.x1;
                                imgDelegate.origY2 = model.y2;
                                imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(imgDelegate.origY2 + (pt.y - imgDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (!(mouse.modifiers & Qt.ShiftModifier)) {
                                    var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                    if (nW / nH > imgDelegate.origAspect) {
                                        nW = nH * imgDelegate.origAspect;
                                        nx1 = model.x2 - nW;
                                    } else {
                                        nH = nW / imgDelegate.origAspect;
                                        ny2 = model.y1 + nH;
                                    }
                                }
                                imagesModel.setProperty(index, "x1", nx1);
                                imagesModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.origX1 = model.x1;
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                imagesModel.setProperty(index, "x1", Math.max(0, Math.min(imgDelegate.origX1 + (pt.x - imgDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: imgSimulateMouseArea
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            if (viewportRef.cueVideoActive) return
                            IE.fire(trigger, imgDelegate._cachedInteractivity, sceneContent._ieContext("image", index))
                        }

                        onClicked: fireInteractivity("click")
                    }

                    Connections {
                        target: viewport
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        function onHoveredImageIndexChanged() {
                            if (viewportRef.hoveredImageIndex === index)
                                imgSimulateMouseArea.fireInteractivity("hover")
                        }
                    }
                }
            }

            // Completed videos
            Repeater {
                id: videosRepeater
                model: videosModel
                delegate: Item {
                    id: vidDelegate
                    x: model.x1 - 28 / sceneContent.editorScaleFactor
                    y: model.y1 - 28 / sceneContent.editorScaleFactor
                    width: model.x2 - model.x1 + 56 / sceneContent.editorScaleFactor
                    height: model.y2 - model.y1 + 56 / sceneContent.editorScaleFactor
                    z: 100 + model.stackOrder
                    layer.enabled: !sceneContent.previewActive

                    // Exposed so sceneContent._bindNativeVideoPlayer() can hand this
                    // MediaPlayer's `position` to the native HDR pipeline for sync.
                    readonly property var player: vidPlayer

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedVideos.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "video" && viewportRef.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "video" && viewportRef.deleteTargetIndex === index

                    property var _cachedInteractivity: sceneContent.parseInteractivityJson(model.interactivityJson)
                    // Phase 7 Part 4: model.x1/y1/x2/y2/locked are live role
                    // bindings in this delegate scope (unlike a .get() snapshot),
                    // so this reacts correctly to both the move-MouseArea and any
                    // resize-handle drag mutating the same roles via setProperty.
                    readonly property string _trackedChromeKey: model.x1 + "," + model.y1 + "," + model.x2 + "," + model.y2 + "," + model.locked
                    on_TrackedChromeKeyChanged: {
                        sceneContent._scheduleNativeChromeRebuild()
                        // Phase 7 Part 4: nativeElementsJson's per-element rect was
                        // previously only ever set at loadScene() time -- never
                        // rebuilt live during a move/resize drag, since native
                        // rendering never ran during plain editing before this
                        // phase. Same x1/y1/x2/y2/locked key as the chrome rebuild
                        // above, just also driving the content (not just chrome).
                        sceneContent._scheduleNativeElementsRebuild()
                    }

                    // Tracks whether imageLoadComplete() has been called for this delegate.
                    // Guards against duplicate calls if both the frame path and fallback path fire.
                    property bool videoReadySignaled: false
                    property int videoFrameCount: 0

                    // Source-swap freeze-frame state. liveFilePath must NOT bind to model.filePath
                    // — it is initialized by onTrackedFilePathChanged and then managed manually.
                    property string liveFilePath: ""
                    property string trackedFilePath: model.filePath
                    property bool swapping: false
                    property int swapFrameCount: 0
                    property string queuedFilePath: ""
                    property string pendingSwapPath: ""
                    property bool pendingTransitionComplete: false
                    property bool freezePreCaptured: false
                    property bool transitionCapturing: false
                    property bool transitionGrabDone: false
                    property bool transitionFreezeReady: false
                    property bool vidCfAIsPrimary: true   // player A (vidPlayer) is currently primary
                    property bool vidCfActive: false       // a crossfade opacity animation is running
                    property bool vidCfPrerolling: false  // secondary player started early; fade not yet begun

                    // Stop the secondary crossfade player the instant a scene transition begins
                    // rather than waiting for the next onPositionChanged tick (~33 ms at 30 fps).
                    // This frees the decoder slot immediately so the transition video can start.
                    readonly property bool _inTransitionWatcher: model.inTransition
                    on_InTransitionWatcherChanged: {
                        if (model.inTransition &&
                                (vidDelegate.vidCfActive || vidDelegate.vidCfPrerolling ||
                                 vidOutputB.opacity > 0 || !vidDelegate.vidCfAIsPrimary)) {
                            vidOutputBFadeIn.stop()
                            vidOutputBFadeOut.stop()
                            vidPlayerB.stop()
                            vidOutputB.opacity = 0.0
                            vidDelegate.vidCfAIsPrimary = true
                            vidDelegate.vidCfActive = false
                            vidDelegate.vidCfPrerolling = false
                        }
                    }

                    // Safety net: when this layer becomes the foreground, repair any degenerate
                    // crossfade state that built up in staging. This happens when A reaches
                    // EndOfMedia while in staging — the handoff to B fires but B was never
                    // started (pre-roll requires isInteractive), leaving A invisible and B
                    // showing a blank texture. Detect that state here and restart from A.
                    readonly property bool _isInteractiveWatcher: sceneContent.isInteractive
                    on_IsInteractiveWatcherChanged: {
                        if (sceneContent.isInteractive && !vidDelegate.vidCfAIsPrimary &&
                                vidOutputB.opacity > 0 &&
                                vidPlayerB.playbackState !== MediaPlayer.PlayingState) {
                            vidOutputBFadeIn.stop()
                            vidOutputBFadeOut.stop()
                            vidOutputB.opacity = 0.0
                            vidDelegate.vidCfAIsPrimary = true
                            vidDelegate.vidCfActive = false
                            vidDelegate.vidCfPrerolling = false
                            vidOutput.opacity = 1.0
                            vidPlayer.play()
                        }
                    }

                    onTrackedFilePathChanged: {
                        // nativeVideoPath is only set once inside loadScene() -- without this,
                        // a mid-clip source swap (evaluateAllSourcesForContent/
                        // completeVideoTransition mutating model.filePath directly, no
                        // loadScene() call involved) would leave the native pipeline
                        // silently stuck on the old file forever, not just flash once.
                        // model.filePath bindings are reliably reactive in a delegate
                        // context (unlike ListModel.get(i).x snapshot reads elsewhere in
                        // this file), so pushing from here catches every case loadScene()
                        // itself would otherwise miss.
                        if (sceneContent.nativeEligible) sceneContent.nativeVideoPath = trackedFilePath
                        if (!vidDelegate.videoReadySignaled) {
                            // Still in initial load — follow model directly, no freeze needed
                            vidDelegate.liveFilePath = trackedFilePath
                            return
                        }
                        if (trackedFilePath === vidDelegate.liveFilePath) return
                        vidDelegate.startSourceSwap(trackedFilePath)
                    }

                    function startSourceSwap(newPath) {
                        if (vidDelegate.swapping) { vidDelegate.queuedFilePath = newPath; return }
                        vidNoLoopFadeOut.stop()
                        vidOutputBFadeIn.stop()
                        vidOutputBFadeOut.stop()
                        vidPlayerB.stop()
                        vidOutputB.opacity = 0.0
                        vidDelegate.vidCfAIsPrimary = true
                        vidDelegate.vidCfActive = false
                        vidDelegate.vidCfPrerolling = false
                        vidOutput.opacity = 1.0
                        vidFreezeFrameFadeOut.stop()
                        vidDelegate.transitionCapturing = false
                        vidDelegate.transitionGrabDone = false
                        vidDelegate.transitionFreezeReady = false
                        // Transition-clip path: freeze was captured at EndOfMedia, already showing
                        if (vidDelegate.freezePreCaptured) {
                            vidDelegate.freezePreCaptured = false
                            vidDelegate.swapping = true
                            vidDelegate.queuedFilePath = ""
                            vidDelegate.swapFrameCount = 0
                            vidDelegate.pendingSwapPath = ""
                            vidDelegate.liveFilePath = newPath
                            return
                        }
                        vidDelegate.swapping = true
                        vidDelegate.queuedFilePath = ""
                        vidDelegate.swapFrameCount = 0
                        vidDelegate.pendingSwapPath = newPath
                        vidOutput.grabToImage(function(result) {
                            vidFreezeFrame.source = result.url
                        })
                    }

                    // Video fill
                    MediaPlayer {
                        id: vidPlayer
                        source: vidDelegate.liveFilePath
                        autoPlay: true
                        loops: model.inTransition ? 1 : (model.vidLoop && !model.vidCrossfade ? MediaPlayer.Infinite : 1)
                        videoOutput: vidOutput
                        // Silenced permanently — real audible output now comes from the
                        // panner's private QAudioSink (see _levelMeter below), since
                        // AudioOutput has no pan control at all.
                        audioOutput: AudioOutput {
                            volume: 0.0
                        }
                        // QAudioBufferOutput isn't a QML type — Python creates it and hands
                        // back a per-player meter+panner object with its own levelChanged
                        // signal, plus setPan()/setVolume() this file calls below.
                        property var _levelMeter: null
                        Component.onCompleted: _levelMeter = audioMeterFactory.createLevelMeter(vidPlayer)
                        onPositionChanged: {
                            // True self-crossfade: B pre-rolls invisibly 300 ms before the fade
                            // zone so its first decoded frame is ready when the fade starts.
                            // vidPlayerB.play() after EndOfMedia restarts from position 0 in Qt6;
                            // no stop() is called here, which avoids the null-frame videoFrameChanged
                            // signal that would otherwise make the fade start against black pixels.
                            if (!model.inTransition && model.vidLoop && model.vidCrossfade &&
                                    vidDelegate.vidCfAIsPrimary && vidPlayer.duration > 0) {
                                var xfDur = vidPlayer.duration * Math.max(0, Math.min(50, model.vidCrossfadePct || 5)) / 100
                                var remA = vidPlayer.duration - vidPlayer.position
                                if (xfDur > 0 && remA > xfDur + 350) {
                                    // well outside the crossfade zone — nothing to do this tick
                                } else if (xfDur > 0 && remA > 0) {
                                    if (!vidDelegate.vidCfPrerolling && !vidDelegate.vidCfActive &&
                                            remA <= xfDur + 300 && sceneContent.isInteractive) {
                                        vidOutputB.opacity = 0
                                        if (vidPlayerB.source !== vidDelegate.liveFilePath)
                                            vidPlayerB.source = vidDelegate.liveFilePath
                                        vidPlayerB.play()
                                        vidDelegate.vidCfPrerolling = true
                                    }
                                    if (vidDelegate.vidCfPrerolling && !vidDelegate.vidCfActive && remA <= xfDur) {
                                        vidDelegate.vidCfPrerolling = false
                                        vidDelegate.vidCfActive = true
                                        vidOutputBFadeIn.duration = Math.max(1, Math.round(remA))
                                        vidOutputBFadeIn.start()
                                    }
                                }
                            } else if ((model.inTransition || !model.vidLoop || !model.vidCrossfade) &&
                                       (vidDelegate.vidCfActive || vidDelegate.vidCfPrerolling ||
                                        vidOutputB.opacity > 0 || !vidDelegate.vidCfAIsPrimary)) {
                                // Stop B when a scene transition starts (frees the decoder slot) or
                                // when crossfade is disabled mid-cycle.
                                vidOutputBFadeIn.stop()
                                vidOutputBFadeOut.stop()
                                vidPlayerB.stop()
                                vidOutputB.opacity = 0.0
                                if (!model.inTransition) {
                                    // Restore A opacity and restart it only outside transitions;
                                    // transition logic owns vidOutput.opacity during a transition.
                                    vidOutput.opacity = 1.0
                                    if (!vidDelegate.vidCfAIsPrimary && model.vidLoop) {
                                        vidPlayer.stop()
                                        vidPlayer.play()
                                    }
                                }
                                vidDelegate.vidCfAIsPrimary = true
                                vidDelegate.vidCfActive = false
                                vidDelegate.vidCfPrerolling = false
                            }
                            // Grab a freeze frame ~200ms before end so Image.Ready fires while
                            // the clip is still playing. We then show it in Image.Ready — before
                            // EndOfMedia — so the freeze is definitely visible when the VideoOutput
                            // texture clears. Setting opacity=1 at or after EndOfMedia is too late:
                            // the render thread can display a black frame before the JS handler runs.
                            if (!model.inTransition || vidDelegate.pendingTransitionComplete ||
                                    vidDelegate.transitionCapturing || vidDelegate.transitionGrabDone) return
                            var rem = vidPlayer.duration - vidPlayer.position
                            if (rem > 0 && rem <= 200) {
                                vidDelegate.transitionCapturing = true
                                vidOutput.grabToImage(function(result) {
                                    vidDelegate.transitionCapturing = false
                                    vidDelegate.transitionGrabDone = true
                                    if (!model.inTransition || vidDelegate.pendingTransitionComplete) return
                                    vidFreezeFrame.source = result.url
                                })
                            }
                        }
                        onMediaStatusChanged: {
                            if ((mediaStatus === MediaPlayer.InvalidMedia ||
                                 mediaStatus === MediaPlayer.EndOfMedia) &&
                                !vidDelegate.videoReadySignaled) {
                                vidDelegate.videoReadySignaled = true
                                imageLoadComplete()
                            }
                            if (mediaStatus === MediaPlayer.EndOfMedia && !model.inTransition && !model.vidLoop) {
                                vidNoLoopFadeOut.start()
                            }
                            if (mediaStatus === MediaPlayer.EndOfMedia && model.vidLoop && model.vidCrossfade &&
                                    !model.inTransition && vidDelegate.vidCfAIsPrimary) {
                                if (!sceneContent.isInteractive) {
                                    // Still in staging — B was never started (pre-roll requires
                                    // isInteractive). Restart A so the video keeps looping until
                                    // this layer becomes the foreground.
                                    vidPlayer.play()
                                } else {
                                    // A finished its cycle; B has been playing since the overlap zone.
                                    // Snap to a clean handoff: A invisible, B fully visible, B is primary.
                                    vidOutputBFadeIn.stop()
                                    vidDelegate.vidCfPrerolling = false
                                    vidOutput.opacity = 0.0
                                    vidOutputB.opacity = 1.0
                                    vidDelegate.vidCfAIsPrimary = false
                                    vidDelegate.vidCfActive = false
                                }
                            }
                            if (mediaStatus === MediaPlayer.EndOfMedia && model.inTransition) {
                                if (vidDelegate.transitionFreezeReady) {
                                    // Best case: freeze already showing (opacity=1 was set in
                                    // Image.Ready while the clip was still playing). Just complete.
                                    vidDelegate.transitionFreezeReady = false
                                    vidDelegate.freezePreCaptured = true
                                    viewportRef.videoTransitionCompleteIndex = index
                                    viewportRef.videoTransitionCompleteRevision++
                                } else {
                                    // Fallback: Image.Ready hasn't fired yet — let it handle opacity
                                    // and completion when it does.
                                    vidDelegate.pendingTransitionComplete = true
                                    if (!vidDelegate.transitionCapturing && !vidDelegate.transitionGrabDone) {
                                        // No grab in progress and none done — last resort for very
                                        // short clips. Texture is likely cleared on macOS already.
                                        vidOutput.grabToImage(function(result) {
                                            vidFreezeFrame.source = result.url
                                        })
                                    }
                                }
                            }
                        }
                    }

                    Connections {
                        target: vidPlayer._levelMeter
                        function onLevelChanged(rms) {
                            var effVol = sceneContent.globalMuted ? 0.0 : (sceneContent.isInteractive ? (model.mixerVolume !== undefined ? model.mixerVolume : 1.0) : 0.0)
                            if (sceneContent.nodeWorkspaceRef) sceneContent.nodeWorkspaceRef.setTrackLevel("video:" + index, rms * effVol)
                            vidPlayer._levelMeter.setVolume(effVol)
                            vidPlayer._levelMeter.setPan(model.mixerPan !== undefined ? model.mixerPan : 0.0)
                        }
                    }

                    // Secondary player for crossfade loops — starts from position 0 as A
                    // nears its end, fading vidOutputB in over vidOutput for a seamless loop.
                    MediaPlayer {
                        id: vidPlayerB
                        source: ""
                        autoPlay: false
                        loops: 1
                        videoOutput: vidOutputB
                        // Silenced permanently — see vidPlayer above.
                        audioOutput: AudioOutput {
                            volume: 0.0
                        }
                        property var _levelMeter: null
                        Component.onCompleted: _levelMeter = audioMeterFactory.createLevelMeter(vidPlayerB)
                        onPositionChanged: {
                            // Mirror of vidPlayer's pre-roll logic: start A early so its first
                            // decoded frame is ready before B fades out and reveals A below.
                            if (!model.inTransition && model.vidLoop && model.vidCrossfade &&
                                    !vidDelegate.vidCfAIsPrimary && vidPlayerB.duration > 0) {
                                var xfDur = vidPlayerB.duration * Math.max(0, Math.min(50, model.vidCrossfadePct || 5)) / 100
                                var remB = vidPlayerB.duration - vidPlayerB.position
                                if (xfDur > 0 && remB > xfDur + 350) {
                                    // well outside the crossfade zone — nothing to do this tick
                                } else if (xfDur > 0 && remB > 0) {
                                    if (!vidDelegate.vidCfPrerolling && !vidDelegate.vidCfActive &&
                                            remB <= xfDur + 300 && sceneContent.isInteractive) {
                                        vidPlayer.play()  // after EndOfMedia restarts from 0 in Qt6; no stop() needed
                                        vidDelegate.vidCfPrerolling = true
                                    }
                                    if (vidDelegate.vidCfPrerolling && !vidDelegate.vidCfActive && remB <= xfDur) {
                                        vidDelegate.vidCfPrerolling = false
                                        vidDelegate.vidCfActive = true
                                        vidOutput.opacity = 1.0  // A has been decoding for ~300 ms
                                        vidOutputBFadeOut.duration = Math.max(1, Math.round(remB))
                                        vidOutputBFadeOut.start()
                                    }
                                }
                            }
                        }
                        onMediaStatusChanged: {
                            if (mediaStatus === MediaPlayer.EndOfMedia && model.vidLoop && model.vidCrossfade &&
                                    !model.inTransition && !vidDelegate.vidCfAIsPrimary) {
                                // B finished — A is now primary. Snap to clean state.
                                vidOutputBFadeOut.stop()
                                vidDelegate.vidCfPrerolling = false
                                vidOutputB.opacity = 0.0
                                vidDelegate.vidCfAIsPrimary = true
                                vidDelegate.vidCfActive = false
                            }
                        }
                    }
                    VideoOutput {
                        id: vidOutput
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        // Confirmed via direct testing: MediaPlayer keeps decoding and
                        // videoSink.videoFrameChanged keeps firing at the same rate
                        // regardless of this item's visible property -- decode/frame-
                        // delivery is independent of on-screen presentation in Qt
                        // Multimedia, so hiding this costs no functional behavior below,
                        // only the actual screen paint/composite (which is the point).
                        visible: !sceneContent.qtPresentationSuspended

                        // Wait for 2 real decoded frames before signaling readyForDisplay.
                        // videoSink.videoFrameChanged fires each time a frame arrives in the
                        // GPU texture — this is the earliest moment the frame is truly visible.
                        Connections {
                            target: vidOutput.videoSink
                            // frame parameter is not marshaled to QML — just count fires.
                            // Any videoFrameChanged emission means a real GPU frame arrived.
                            function onVideoFrameChanged() {
                                if (!vidDelegate.videoReadySignaled) {
                                    vidDelegate.videoFrameCount++
                                    if (vidDelegate.videoFrameCount >= 2) {
                                        vidDelegate.videoReadySignaled = true
                                        imageLoadComplete()
                                    }
                                }
                                // During a source swap, count new frames then reveal new video.
                                // Only count frames after pendingSwapPath is cleared — i.e. after
                                // Image.Ready has set liveFilePath to the new source. Frames that
                                // arrive while the freeze grab is in flight are from the old source
                                // and must not advance the counter, or swapping flips false before
                                // liveFilePath ever changes and the source never switches.
                                if (vidDelegate.swapping && vidDelegate.pendingSwapPath === "") {
                                    vidDelegate.swapFrameCount++
                                    if (vidDelegate.swapFrameCount >= 3) {
                                        vidFreezeFrameFadeOut.restart()
                                        vidDelegate.swapping = false
                                        if (vidDelegate.queuedFilePath !== "") {
                                            var next = vidDelegate.queuedFilePath
                                            vidDelegate.queuedFilePath = ""
                                            vidDelegate.startSourceSwap(next)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Connections {
                        target: vidPlayerB._levelMeter
                        function onLevelChanged(rms) {
                            var effVol = sceneContent.globalMuted ? 0.0 : vidOutputB.opacity * (sceneContent.isInteractive ? (model.mixerVolume !== undefined ? model.mixerVolume : 1.0) : 0.0)
                            if (sceneContent.nodeWorkspaceRef) sceneContent.nodeWorkspaceRef.setTrackLevel("video:" + index, rms * effVol)
                            vidPlayerB._levelMeter.setVolume(effVol)
                            vidPlayerB._levelMeter.setPan(model.mixerPan !== undefined ? model.mixerPan : 0.0)
                        }
                    }

                    // Crossfade secondary output — rendered above vidOutput (z:0.1) so B can
                    // dissolve in over A. Opacity starts at 0 and is animated by vidOutputBFadeIn/Out.
                    VideoOutput {
                        id: vidOutputB
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 0.1
                        opacity: 0
                        visible: !sceneContent.qtPresentationSuspended
                    }

                    // Freeze-frame overlay: holds the last rendered frame while a new source loads,
                    // preventing the black flash between source changes.
                    // opacity MUST snap to 1 instantly (no Behavior) — animating in while VideoOutput
                    // is already black would defeat the purpose. Fade-out is handled explicitly below.
                    Image {
                        id: vidFreezeFrame
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 0.5
                        opacity: 0
                        visible: !sceneContent.qtPresentationSuspended
                        fillMode: Image.Stretch
                        cache: false
                        NumberAnimation {
                            id: vidFreezeFrameFadeOut
                            target: vidFreezeFrame
                            property: "opacity"
                            to: 0
                            duration: 80
                        }
                        onStatusChanged: {
                            if (status === Image.Ready && vidDelegate.swapping && vidDelegate.pendingSwapPath !== "") {
                                opacity = 1
                                vidDelegate.liveFilePath = vidDelegate.pendingSwapPath
                                vidDelegate.swapFrameCount = 0
                                vidDelegate.pendingSwapPath = ""
                            }
                            // Pre-cache path: freeze loaded while clip is still playing.
                            // Set opacity=1 NOW — before EndOfMedia — so the freeze is visible
                            // before the render thread clears the VideoOutput texture. Reacting
                            // at or after EndOfMedia is too late: the render thread can display
                            // a black frame before the JS handler runs.
                            if (status === Image.Ready && model.inTransition &&
                                    !vidDelegate.pendingTransitionComplete && !vidDelegate.swapping) {
                                opacity = 1
                                vidDelegate.transitionFreezeReady = true
                            }
                            // Fallback path: EndOfMedia already fired before Image was ready.
                            if (status === Image.Ready && vidDelegate.pendingTransitionComplete) {
                                opacity = 1
                                vidDelegate.pendingTransitionComplete = false
                                vidDelegate.freezePreCaptured = true
                                viewportRef.videoTransitionCompleteIndex = index
                                viewportRef.videoTransitionCompleteRevision++
                            }
                        }
                    }

                    // Fades vidOutput to transparent when loop=false and playback ends.
                    NumberAnimation {
                        id: vidNoLoopFadeOut
                        target: vidOutput
                        property: "opacity"
                        to: 0.0
                        duration: 500
                        easing.type: Easing.InQuad
                    }
                    // Crossfade animations — duration set dynamically before start() is called.
                    NumberAnimation { id: vidOutputBFadeIn;  target: vidOutputB; property: "opacity"; to: 1.0 }
                    NumberAnimation { id: vidOutputBFadeOut; target: vidOutputB; property: "opacity"; to: 0.0 }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 1
                        color: "transparent"
                        border.color: vidDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: vidDelegate.isRelayerHovered ? 2 : 1
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: (vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "black" : "transparent"
                            border.width: 1
                        }
                    }

                    // Red delete overlay
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 2
                        color: Qt.rgba(1, 0, 0, vidDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: vidDelegate.isSelect
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: vidDelegate.isActive && !model.locked ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewportRef.tempDestroyMode = true;
                                viewportRef.deleteTargetType = "video";
                                viewportRef.deleteTargetIndex = index;
                                return;
                            }
                            viewportRef.selectVideo(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragging = true;
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!model.locked && vidDelegate.isActive) {
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origY2 = model.y2;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!vidDelegate.isActive || model.locked) return;
                            var dx = (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, dy = (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor;
                            var w = vidDelegate.origX2 - vidDelegate.origX1, h = vidDelegate.origY2 - vidDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + dx, viewportRef.contentWidth - w));
                            var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + dy, viewportRef.contentHeight - h));
                            videosModel.setProperty(index, "x1", nx1);
                            videosModel.setProperty(index, "y1", ny1);
                            videosModel.setProperty(index, "x2", nx1 + w);
                            videosModel.setProperty(index, "y2", ny1 + h);
                            viewportRef.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewportRef.deleteTargetType === "video" && viewportRef.deleteTargetIndex === index)
                                    viewportRef.cancelDelete();
                                return;
                            }
                            viewportRef.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewportRef.relayerHoveredType = "video";
                            viewportRef.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewportRef.relayerHoveredType === "video" && viewportRef.relayerHoveredIndex === index) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewportRef.relayerHoveredType = "video";
                            viewportRef.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            videosModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Delete (destroy tool): click-and-hold to remove
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: buttonGridRef.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewportRef.deleteTargetType = "video";
                            viewportRef.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewportRef.deleteTargetType === "video" && viewportRef.deleteTargetIndex === index)
                                viewportRef.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                var nW = model.x2 - nx1, nH = model.y2 - ny1;
                                if (nW / nH > vidDelegate.origAspect) {
                                    nW = nH * vidDelegate.origAspect;
                                    nx1 = model.x2 - nW;
                                } else {
                                    nH = nW / vidDelegate.origAspect;
                                    ny1 = model.y2 - nH;
                                }
                                videosModel.setProperty(index, "x1", nx1);
                                videosModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                var nH = model.y2 - ny1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, cx + nW / 2));
                                videosModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: 0
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(vidDelegate.origX2 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                if (nW / nH > vidDelegate.origAspect) {
                                    nW = nH * vidDelegate.origAspect;
                                    nx2 = model.x1 + nW;
                                } else {
                                    nH = nW / vidDelegate.origAspect;
                                    ny1 = model.y2 - nH;
                                }
                                videosModel.setProperty(index, "x2", nx2);
                                videosModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origY2 = model.y2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(vidDelegate.origX2 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var nW = nx2 - model.x1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, cy + nH / 2));
                                videosModel.setProperty(index, "x2", nx2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origY2 = model.y2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(vidDelegate.origX2 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(vidDelegate.origY2 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                if (nW / nH > vidDelegate.origAspect) {
                                    nW = nH * vidDelegate.origAspect;
                                    nx2 = model.x1 + nW;
                                } else {
                                    nH = nW / vidDelegate.origAspect;
                                    ny2 = model.y1 + nH;
                                }
                                videosModel.setProperty(index, "x2", nx2);
                                videosModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor
                        y: parent.height - 42 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origY2 = model.y2;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(vidDelegate.origY2 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                var nH = ny2 - model.y1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, cx + nW / 2));
                                videosModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56 / sceneContent.editorScaleFactor
                        width: 56 / sceneContent.editorScaleFactor
                        height: 56 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origY2 = model.y2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(vidDelegate.origY2 + (pt.y - vidDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                if (nW / nH > vidDelegate.origAspect) {
                                    nW = nH * vidDelegate.origAspect;
                                    nx1 = model.x2 - nW;
                                } else {
                                    nH = nW / vidDelegate.origAspect;
                                    ny2 = model.y1 + nH;
                                }
                                videosModel.setProperty(index, "x1", nx1);
                                videosModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14 / sceneContent.editorScaleFactor
                        y: parent.height / 2 - 14 / sceneContent.editorScaleFactor
                        width: 28 / sceneContent.editorScaleFactor
                        height: 28 / sceneContent.editorScaleFactor
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8 / sceneContent.editorScaleFactor
                            height: 8 / sceneContent.editorScaleFactor
                            radius: 4 / sceneContent.editorScaleFactor
                            color: "white"
                            border.color: "black"
                            border.width: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origY2 = model.y2;
                                vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true;
                                viewportRef.elementDragX = pt.x;
                                viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + (pt.x - vidDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var nW = model.x2 - nx1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, cy + nH / 2));
                                videosModel.setProperty(index, "x1", nx1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: vidSimulateMouseArea
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            if (viewportRef.cueVideoActive) return
                            IE.fire(trigger, vidDelegate._cachedInteractivity, sceneContent._ieContext("video", index))
                        }

                        onClicked: fireInteractivity("click")
                    }

                    Connections {
                        target: viewport
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        function onHoveredVideoIndexChanged() {
                            if (viewportRef.hoveredVideoIndex === index)
                                vidSimulateMouseArea.fireInteractivity("hover")
                        }
                    }
                }
            }

            // Completed shaders
            Repeater {
                id: shadersRepeater
                model: shadersModel
                delegate: Item {
                    id: shaderDelegate
                    x: model.x1 - 28 / sceneContent.editorScaleFactor
                    y: model.y1 - 28 / sceneContent.editorScaleFactor
                    width: model.x2 - model.x1 + 56 / sceneContent.editorScaleFactor
                    height: model.y2 - model.y1 + 56 / sceneContent.editorScaleFactor
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedShaders.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "shader" && viewportRef.relayerHoveredIndex === index
                    property var _cachedInteractivity: sceneContent.parseInteractivityJson(model.interactivityJson)
                    // Phase 7 Part 4: model.x1/y1/x2/y2/locked are live role
                    // bindings in this delegate scope (unlike a .get() snapshot),
                    // so this reacts correctly to both the move-MouseArea and any
                    // resize-handle drag mutating the same roles via setProperty.
                    readonly property string _trackedChromeKey: model.x1 + "," + model.y1 + "," + model.x2 + "," + model.y2 + "," + model.locked
                    on_TrackedChromeKeyChanged: {
                        sceneContent._scheduleNativeChromeRebuild()
                        // Phase 7 Part 4: nativeElementsJson's per-element rect was
                        // previously only ever set at loadScene() time -- never
                        // rebuilt live during a move/resize drag, since native
                        // rendering never ran during plain editing before this
                        // phase. Same x1/y1/x2/y2/locked key as the chrome rebuild
                        // above, just also driving the content (not just chrome).
                        sceneContent._scheduleNativeElementsRebuild()
                    }
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "shader" && viewportRef.deleteTargetIndex === index

                    // Expose the dynamic ShaderEffect and texture helpers so select-settings can update uniforms.
                    property var dynamicShaderEffect: shaderEffectContainer.dynamicEffect
                    function applyTextureSource(name, path) { shaderEffectContainer.applyTextureSource(name, path); }

                    // Phase 7 Part 2: pushes nativeElementsJson rebuilds for
                    // any shader mutation reached from outside loadScene()
                    // (a "how condition" swap, or a live uniform/frag/vert
                    // edit from the property panel) -- same reactive-
                    // tracking pattern the image/video delegates already
                    // use, since model.* bindings are reliably reactive in
                    // a delegate context regardless of which code path did
                    // the mutation.
                    readonly property string _trackedShaderKey:
                        model.fragPath + "\x01" + model.vertPath + "\x01" + model.uniformsJson
                    on_TrackedShaderKeyChanged: sceneContent._scheduleNativeElementsRebuild()


                    // Shader fill — recreated via Qt.createQmlObject() whenever the frag path
                    // changes, so per-shader uniform properties are correctly declared.
                    Item {
                        id: shaderEffectContainer
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        visible: model.fragPath !== ""

                        property var dynamicEffect: null
                        // Each entry: { wrapper: Item|Image, provider: Image|VideoOutput }
                        property var textureSlots: ({})

                        function createTextureSlot(name, path) {
                            var wrapper, provider;
                            if (path && path !== "" && viewportRef.isVideoPath(path)) {
                                var vQml = "import QtQuick 2.15\nimport QtMultimedia\nItem {\n" +
                                    "    visible: false; width: parent.width; height: parent.height\n" +
                                    "    property alias textureProvider: vo\n" +
                                    "    MediaPlayer { id: mp; source: \"" + path + "\"; videoOutput: vo; loops: MediaPlayer.Infinite }\n" +
                                    "    VideoOutput { id: vo; anchors.fill: parent; layer.enabled: true }\n" +
                                    "    Component.onCompleted: mp.play()\n" +
                                    "}";
                                wrapper = Qt.createQmlObject(vQml, shaderEffectContainer, "tex_" + name);
                                provider = wrapper.textureProvider;
                            } else {
                                var iQml = "import QtQuick 2.15\nImage { visible: false; fillMode: Image.Stretch; width: parent.width; height: parent.height; source: \"" + (path || "") + "\" }";
                                wrapper = Qt.createQmlObject(iQml, shaderEffectContainer, "tex_" + name);
                                provider = wrapper;
                            }
                            return { wrapper: wrapper, provider: provider };
                        }

                        function rebuild() {
                            // Destroy old texture slots.
                            var oldNames = Object.keys(textureSlots);
                            for (var ti = 0; ti < oldNames.length; ti++) {
                                if (textureSlots[oldNames[ti]].wrapper) textureSlots[oldNames[ti]].wrapper.destroy();
                            }
                            textureSlots = {};
                            if (dynamicEffect) { dynamicEffect.destroy(); dynamicEffect = null; }
                            if (model.fragPath === "") return;
                            var qmlStr = viewportRef.buildShaderQml(model.fragPath, model.vertPath, model.uniformsJson);
                            try {
                                dynamicEffect = Qt.createQmlObject(qmlStr, shaderEffectContainer, "dynShader");
                            } catch(e) {
                                console.warn("ShaderEffect build failed:", e.message);
                                return;
                            }
                            var uniforms;
                            try { uniforms = JSON.parse(model.uniformsJson || "[]"); } catch(e) { uniforms = []; }
                            var newSlots = {};
                            for (var i = 0; i < uniforms.length; i++) {
                                var u = uniforms[i];
                                if (u.type !== "sampler2D") continue;
                                try {
                                    var slot = createTextureSlot(u.name, u.value || "");
                                    newSlots[u.name] = slot;
                                    dynamicEffect[u.name] = slot.provider;
                                } catch(e) { console.warn("Texture slot creation failed:", e.message); }
                            }
                            textureSlots = newSlots;
                        }

                        function applyUniformValues() {
                            if (!dynamicEffect) return;
                            var uniforms;
                            try { uniforms = JSON.parse(model.uniformsJson || "[]"); } catch(e) { return; }
                            for (var i = 0; i < uniforms.length; i++) {
                                var u = uniforms[i];
                                if (u.name === "time") continue;
                                if (u.type === "sampler2D") {
                                    if (u.value && u.value !== "") applyTextureSource(u.name, u.value);
                                } else {
                                    var textVal = Array.isArray(u.value) ? u.value.join(", ") :
                                                  (u.value !== null && u.value !== undefined ? u.value.toString() : "1");
                                    try { dynamicEffect[u.name] = viewportRef.parseUniformToQml(u.type, textVal); } catch(e) {}
                                }
                            }
                        }

                        function applyTextureSource(name, path) {
                            if (!dynamicEffect) return;
                            var slot = textureSlots[name];
                            // Rebuild the slot if the type changed (image→video or vice versa) or it doesn't exist yet.
                            var needRebuild = !slot ||
                                (viewportRef.isVideoPath(path) && !(slot.wrapper !== slot.provider)) ||
                                (!viewportRef.isVideoPath(path) && slot.wrapper !== slot.provider);
                            if (needRebuild) {
                                if (slot && slot.wrapper) slot.wrapper.destroy();
                                try {
                                    slot = createTextureSlot(name, path);
                                    var newSlots = textureSlots;
                                    newSlots[name] = slot;
                                    textureSlots = newSlots;
                                } catch(e) { return; }
                            } else {
                                // Same type — just update the source.
                                if (slot.wrapper !== slot.provider) {
                                    // video: recreate so MediaPlayer gets new source
                                    slot.wrapper.destroy();
                                    try {
                                        slot = createTextureSlot(name, path);
                                        var ns = textureSlots;
                                        ns[name] = slot;
                                        textureSlots = ns;
                                    } catch(e) { return; }
                                } else {
                                    slot.provider.source = path;
                                }
                            }
                            dynamicEffect[name] = slot.provider;
                        }

                        // Full rebuild when the shader file changes.
                        property string watchedFragPath: model.fragPath
                        onWatchedFragPathChanged: rebuildTimer.restart()

                        // Live-update uniforms without restarting the animation when only values change.
                        property string watchedUniformsJson: model.uniformsJson
                        onWatchedUniformsJsonChanged: {
                            if (dynamicEffect)
                                applyUniformValues();
                            else
                                rebuildTimer.restart();
                        }

                        Timer {
                            id: rebuildTimer
                            interval: 0
                            onTriggered: shaderEffectContainer.rebuild()
                        }

                        Component.onCompleted: rebuild()
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 1
                        color: "transparent"
                        border.color: shaderDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((shaderDelegate.isActive || shaderDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: shaderDelegate.isRelayerHovered ? 2 : 1
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: (shaderDelegate.isActive || shaderDelegate.isRelayerHovered) ? "black" : "transparent"
                            border.width: 1
                        }
                    }

                    // Red delete overlay
                    Rectangle {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        z: 2
                        color: Qt.rgba(1, 0, 0, shaderDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: shaderDelegate.isSelect
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: shaderDelegate.isActive && !model.locked ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewportRef.tempDestroyMode = true;
                                viewportRef.deleteTargetType = "shader";
                                viewportRef.deleteTargetIndex = index;
                                return;
                            }
                            viewportRef.selectShader(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragging = true;
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!model.locked && shaderDelegate.isActive) {
                                shaderDelegate.pressVpX = pt.x;
                                shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX1 = model.x1;
                                shaderDelegate.origY1 = model.y1;
                                shaderDelegate.origX2 = model.x2;
                                shaderDelegate.origY2 = model.y2;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewportRef.elementDragX = pt.x;
                            viewportRef.elementDragY = pt.y;
                            if (!shaderDelegate.isActive || model.locked) return;
                            var dx = (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, dy = (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor;
                            var w = shaderDelegate.origX2 - shaderDelegate.origX1, h = shaderDelegate.origY2 - shaderDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + dx, viewportRef.contentWidth - w));
                            var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + dy, viewportRef.contentHeight - h));
                            shadersModel.setProperty(index, "x1", nx1);
                            shadersModel.setProperty(index, "y1", ny1);
                            shadersModel.setProperty(index, "x2", nx1 + w);
                            shadersModel.setProperty(index, "y2", ny1 + h);
                            viewportRef.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewportRef.deleteTargetType === "shader" && viewportRef.deleteTargetIndex === index)
                                    viewportRef.cancelDelete();
                                return;
                            }
                            viewportRef.elementDragging = false;
                        }
                    }

                    // Relayer
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewportRef.relayerHoveredType = "shader";
                            viewportRef.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewportRef.relayerHoveredType === "shader" && viewportRef.relayerHoveredIndex === index) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewportRef.relayerHoveredType = "shader";
                            viewportRef.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewportRef.relayerHoveredType = "";
                                viewportRef.relayerHoveredIndex = -1;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            shadersModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Delete (destroy tool)
                    MouseArea {
                        x: 28 / sceneContent.editorScaleFactor
                        y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: buttonGridRef.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewportRef.deleteTargetType = "shader";
                            viewportRef.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewportRef.deleteTargetType === "shader" && viewportRef.deleteTargetIndex === index)
                                viewportRef.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0; y: 0; width: 56 / sceneContent.editorScaleFactor; height: 56 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX1 = model.x1; shaderDelegate.origY1 = model.y1;
                                shaderDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = model.y2 - ny1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx1 = model.x2 - nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny1 = model.y2 - nH; }
                                }
                                shadersModel.setProperty(index, "x1", nx1);
                                shadersModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor; y: 14 / sceneContent.editorScaleFactor; width: 28 / sceneContent.editorScaleFactor; height: 28 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpY = pt.y; shaderDelegate.origY1 = model.y1;
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                shadersModel.setProperty(index, "y1", Math.max(0, Math.min(shaderDelegate.origY1 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor; y: 0; width: 56 / sceneContent.editorScaleFactor; height: 56 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX2 = model.x2; shaderDelegate.origY1 = model.y1;
                                shaderDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(shaderDelegate.origX2 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y2 - 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx2 = model.x1 + nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny1 = model.y2 - nH; }
                                }
                                shadersModel.setProperty(index, "x2", nx2);
                                shadersModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42 / sceneContent.editorScaleFactor; y: parent.height / 2 - 14 / sceneContent.editorScaleFactor; width: 28 / sceneContent.editorScaleFactor; height: 28 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.origX2 = model.x2;
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                shadersModel.setProperty(index, "x2", Math.min(viewportRef.contentWidth, Math.max(shaderDelegate.origX2 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56 / sceneContent.editorScaleFactor; y: parent.height - 56 / sceneContent.editorScaleFactor; width: 56 / sceneContent.editorScaleFactor; height: 56 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX2 = model.x2; shaderDelegate.origY2 = model.y2;
                                shaderDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                                var nx2 = Math.min(viewportRef.contentWidth, Math.max(shaderDelegate.origX2 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x1 + 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(shaderDelegate.origY2 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx2 = model.x1 + nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny2 = model.y1 + nH; }
                                }
                                shadersModel.setProperty(index, "x2", nx2);
                                shadersModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14 / sceneContent.editorScaleFactor; y: parent.height - 42 / sceneContent.editorScaleFactor; width: 28 / sceneContent.editorScaleFactor; height: 28 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpY = pt.y; shaderDelegate.origY2 = model.y2;
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragY = pt.y;
                                shadersModel.setProperty(index, "y2", Math.min(viewportRef.contentHeight, Math.max(shaderDelegate.origY2 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0; y: parent.height - 56 / sceneContent.editorScaleFactor; width: 56 / sceneContent.editorScaleFactor; height: 56 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX1 = model.x1; shaderDelegate.origY2 = model.y2;
                                shaderDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1);
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor));
                                var ny2 = Math.min(viewportRef.contentHeight, Math.max(shaderDelegate.origY2 + (pt.y - shaderDelegate.pressVpY) / sceneContent.editorScaleFactor, model.y1 + 20 / sceneContent.editorScaleFactor));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx1 = model.x2 - nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny2 = model.y1 + nH; }
                                }
                                shadersModel.setProperty(index, "x1", nx1);
                                shadersModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14 / sceneContent.editorScaleFactor; y: parent.height / 2 - 14 / sceneContent.editorScaleFactor; width: 28 / sceneContent.editorScaleFactor; height: 28 / sceneContent.editorScaleFactor
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        opacity: sceneContent.qtPresentationSuspended ? 0 : 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8 / sceneContent.editorScaleFactor; height: 8 / sceneContent.editorScaleFactor; radius: 4 / sceneContent.editorScaleFactor; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.origX1 = model.x1;
                                viewportRef.elementDragging = true; viewportRef.elementDragX = pt.x; viewportRef.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewportRef.elementDragX = pt.x;
                                shadersModel.setProperty(index, "x1", Math.max(0, Math.min(shaderDelegate.origX1 + (pt.x - shaderDelegate.pressVpX) / sceneContent.editorScaleFactor, model.x2 - 20 / sceneContent.editorScaleFactor)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: shaderSimulateMouseArea
                        x: 28 / sceneContent.editorScaleFactor; y: 28 / sceneContent.editorScaleFactor
                        width: parent.width - 56 / sceneContent.editorScaleFactor
                        height: parent.height - 56 / sceneContent.editorScaleFactor
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            if (viewportRef.cueVideoActive) return
                            IE.fire(trigger, shaderDelegate._cachedInteractivity, sceneContent._ieContext("shader", index))
                        }

                        onClicked: fireInteractivity("click")
                    }

                    Connections {
                        target: viewport
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        function onHoveredShaderIndexChanged() {
                            if (viewportRef.hoveredShaderIndex === index)
                                shaderSimulateMouseArea.fireInteractivity("hover")
                        }
                    }
                }
            }

            // Manually-added mixer tracks ("+" button / drop-on-mixer). Non-visual —
            // loop continuously unless assigned to a sync group, in which case the
            // group's start timecode + end behavior (loop/freeze/hide) drive playback.
            Repeater {
                id: audioTracksRepeater
                model: audioTracksModel
                delegate: Item {
                    readonly property var syncGroup: (model.syncGroupId !== undefined && model.syncGroupId >= 0 && sceneContent.nodeWorkspaceRef)
                        ? sceneContent.nodeWorkspaceRef.syncGroupById(model.syncGroupId) : null
                    readonly property real syncStartSeconds: syncGroup ? sceneContent.nodeWorkspaceRef.timecodeToSeconds(syncGroup.startTimecode) : 0
                    readonly property bool syncShouldLoop: syncGroup ? (syncGroup.endBehavior === "loop") : true

                    MediaPlayer {
                        id: audioTrackPlayer
                        source: (sceneContent.isInteractive && model.filePath) ? model.filePath : ""
                        loops: syncShouldLoop ? MediaPlayer.Infinite : 1
                        // Silenced permanently — see vidPlayer in the video repeater above.
                        audioOutput: AudioOutput {
                            volume: 0.0
                        }
                        property var _levelMeter: null
                        Component.onCompleted: _levelMeter = audioMeterFactory.createLevelMeter(audioTrackPlayer)

                        readonly property bool shouldBePlaying: {
                            if (!sceneContent.isInteractive || !model.filePath) return false;
                            if (!syncGroup) return true;
                            var elapsed = sceneContent.chapterPlayheadTime - syncStartSeconds;
                            if (elapsed < 0) return false;
                            if (!syncShouldLoop && duration > 0 && elapsed * 1000 >= duration) return false;
                            return true;
                        }

                        function syncPosition() {
                            if (!syncGroup || duration <= 0) return 0;
                            var elapsedMs = (sceneContent.chapterPlayheadTime - syncStartSeconds) * 1000;
                            return syncShouldLoop ? (elapsedMs % duration) : Math.min(elapsedMs, duration);
                        }

                        onShouldBePlayingChanged: {
                            if (shouldBePlaying) {
                                if (playbackState !== MediaPlayer.PlayingState) {
                                    if (duration > 0) position = syncPosition();
                                    play();
                                }
                            } else {
                                stop();
                            }
                        }

                        onMediaStatusChanged: {
                            if (mediaStatus === MediaPlayer.LoadedMedia && shouldBePlaying) {
                                if (duration > 0) position = syncPosition();
                                play();
                            }
                        }
                    }

                    Connections {
                        target: audioTrackPlayer._levelMeter
                        function onLevelChanged(rms) {
                            var effVol = sceneContent.globalMuted ? 0.0 : (sceneContent.isInteractive ? (model.mixerVolume !== undefined ? model.mixerVolume : 1.0) : 0.0)
                            if (sceneContent.nodeWorkspaceRef) sceneContent.nodeWorkspaceRef.setTrackLevel("audioTrack:" + index, rms * effVol)
                            audioTrackPlayer._levelMeter.setVolume(effVol)
                            audioTrackPlayer._levelMeter.setPan(model.mixerPan !== undefined ? model.mixerPan : 0.0)
                        }
                    }
                }
            }

}
