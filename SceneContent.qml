import QtQuick
import QtMultimedia
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import QtQuick.Dialogs
import Qt.labs.platform as Platform

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
    property var viewportRef:   null
    property var buttonGridRef: null

    // ── Layer mode ──────────────────────────────────────────────────────────
    // false = staging: all mouse events suppressed, tool overlays hidden.
    property bool isInteractive: true

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

    // ── Scene management ────────────────────────────────────────────────────

    function clear() {
        areasModelInst.clear()
        textBoxesModelInst.clear()
        imagesModelInst.clear()
        videosModelInst.clear()
        shadersModelInst.clear()
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
                    locked: el.locked || false
                })
            } else if (el.type === "image") {
                imagesModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    filePath: el.filePath || "",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            } else if (el.type === "video") {
                videosModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    filePath: el.filePath || "",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            } else if (el.type === "shader") {
                shadersModelInst.append({
                    x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                    fragPath:     el.fragPath     || "",
                    vertPath:     el.vertPath     || "",
                    uniformsJson: el.uniformsJson || "[]",
                    name: el.name || "", stackOrder: z,
                    cursor: el.cursor || "select", cursorPath: el.cursorPath || "",
                    interactivityJson: el.interactivityJson || "[]",
                    template: el.template || "none",
                    locked: el.locked || false
                })
            }
            if (z >= nextStackOrder) nextStackOrder = z + 1
        }
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
                name: m.name || "", z_order: m.stackOrder, filePath: m.filePath,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < videosModelInst.count; i++) {
            m = videosModelInst.get(i)
            elements.push({ type: "video",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                name: m.name || "", z_order: m.stackOrder, filePath: m.filePath,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
        }
        for (i = 0; i < shadersModelInst.count; i++) {
            m = shadersModelInst.get(i)
            elements.push({ type: "shader",
                x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                name: m.name || "", z_order: m.stackOrder,
                fragPath: m.fragPath, vertPath: m.vertPath,
                uniformsJson: m.uniformsJson,
                cursor: m.cursor || "select", cursorPath: m.cursorPath || "",
                interactivityJson: m.interactivityJson || "[]",
                template: m.template || "none",
                locked: m.locked || false })
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
                itemWipeFeather: e.itemWipeFeather, itemWipeDirection: e.itemWipeDirection,
                itemPushDirection: e.itemPushDirection,
                itemLookYaw: e.itemLookYaw, itemLookPitch: e.itemLookPitch,
                itemLookFovMM: e.itemLookFovMM, itemLookOvershoot: e.itemLookOvershoot, itemLookShutter: e.itemLookShutter,
                itemTargetSceneId: e.itemTargetSceneId, itemTargetSceneName: e.itemTargetSceneName,
                itemConditionVar: e.itemConditionVar, itemConditionOp: e.itemConditionOp,
                itemConditionVal: e.itemConditionVal, itemSoundPath: e.itemSoundPath,
                itemVideoPath: e.itemVideoPath, itemVideoTarget: e.itemVideoTarget,
                itemUpdateVar: e.itemUpdateVar, itemUpdateOp: e.itemUpdateOp, itemUpdateVal: e.itemUpdateVal,
                itemWhereNetworkId: e.itemWhereNetworkId, itemWhereCharName: e.itemWhereCharName,
                itemWhereOp: e.itemWhereOp, itemWhereNodeName: e.itemWhereNodeName
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
                itemVideoPath:       e.itemVideoPath       || "",
                itemVideoTarget:     e.itemVideoTarget     || "fill",
                itemUpdateVar:       e.itemUpdateVar       || "",
                itemUpdateOp:        e.itemUpdateOp        || "=",
                itemUpdateVal:       e.itemUpdateVal       || "",
                itemWhereNetworkId:  e.itemWhereNetworkId  !== undefined ? e.itemWhereNetworkId : -1,
                itemWhereCharName:   e.itemWhereCharName   || "",
                itemWhereOp:         e.itemWhereOp         || "is at",
                itemWhereNodeName:   e.itemWhereNodeName   || ""
            })
        }
    }

    // Expose shader delegate for external code that needs to update live uniforms.
    function shaderDelegateAt(idx) { return shadersRepeater.itemAt(idx) }

    // ── Repeaters ───────────────────────────────────────────────────────────
            Repeater {
                model: areasModel
                delegate: Item {
                    id: areaDelegate
                    // expanded 28px on all sides so 56x56 handle items stay within parent bounds
                    x: model.x1 - 28
                    y: model.y1 - 28
                    width: model.x2 - model.x1 + 56
                    height: model.y2 - model.y1 + 56
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedAreas.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "area" && viewportRef.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "area" && viewportRef.deleteTargetIndex === index

                    // Visual border (inset by 28px to match model coordinates).
                    // Hidden during simulate mode, shader transitions, and thumbnail capture —
                    // areas are invisible hotspots in those contexts, not editor decorations.
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        visible: isInteractive &&
                                 buttonGridRef.selectedTool !== "simulate" &&
                                 !viewportRef.wiping && !viewportRef.sliding && !viewportRef.looking &&
                                 !viewportRef.capturingThumbnail
                        color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewportRef.deleteProgress * 0.6) : (areaDelegate.isActive && index === viewportRef.hoveredAreaIndex ? Qt.rgba(1, 1, 1, 0.15) : "transparent")
                        border.color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((areaDelegate.isActive || areaDelegate.isRelayerHovered) ? "white" : "#666666")
                        border.width: (areaDelegate.isActive && index === viewportRef.hoveredAreaIndex) || areaDelegate.isRelayerHovered ? 2 : 1
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
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            var json = areasModel.get(index).interactivityJson || "[]"
                            var items = []
                            try { items = JSON.parse(json) } catch(e) {}
                            var pendingJump = null
                            var hasCueVideo = false
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i]
                                if (it.itemTrigger !== trigger) continue
                                if (it.itemAction !== "cue") continue
                                if (it.itemCommand === "video" && it.itemVideoTarget === "fill" && it.itemVideoPath) {
                                    viewportRef.playCueVideo(it.itemVideoPath)
                                    hasCueVideo = true
                                } else if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0) {
                                    if (!pendingJump) pendingJump = it
                                }
                            }
                            if (pendingJump) {
                                // itemTransitionSpeed is in seconds; convert to ms
                                var ms = Math.round((pendingJump.itemTransitionSpeed || 1.0) * 1000)
                                if (hasCueVideo) viewportRef.cueVideoHasJump = true
                                viewportRef.jumpToScene(pendingJump.itemTargetSceneId,
                                                        pendingJump.itemTransition    || "cut",
                                                        ms,
                                                        pendingJump.itemWipeFeather   || 0.0,
                                                        pendingJump.itemWipeDirection || "right",
                                                        pendingJump.itemPushDirection || "right",
                                                        pendingJump.itemLookYaw         !== undefined ? pendingJump.itemLookYaw       : 90.0,
                                                        pendingJump.itemLookPitch       !== undefined ? pendingJump.itemLookPitch     : 0.0,
                                                        pendingJump.itemLookFovMM       !== undefined ? pendingJump.itemLookFovMM     : 24.0,
                                                        pendingJump.itemLookOvershoot   !== undefined ? pendingJump.itemLookOvershoot : 1.0,
                                                        pendingJump.itemLookShutter     !== undefined ? pendingJump.itemLookShutter   : 0.10)
                            }
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                            var dx = pt.x - areaDelegate.pressVpX, dy = pt.y - areaDelegate.pressVpY;
                            var w = areaDelegate.origX2 - areaDelegate.origX1, h = areaDelegate.origY2 - areaDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + dx, viewportRef.width - w));
                            var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + dy, viewportRef.height - h));
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + pt.x - areaDelegate.pressVpX, model.x2 - 20));
                                var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + pt.y - areaDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                areasModel.setProperty(index, "y1", Math.max(0, Math.min(areaDelegate.origY1 + pt.y - areaDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + pt.y - areaDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                areasModel.setProperty(index, "x2", Math.min(viewportRef.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20));
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
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                areasModel.setProperty(index, "y2", Math.min(viewportRef.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + pt.x - areaDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20));
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
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                areasModel.setProperty(index, "x1", Math.max(0, Math.min(areaDelegate.origX1 + pt.x - areaDelegate.pressVpX, model.x2 - 20)));
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
                    x: model.x1 - 28
                    y: model.y1 - 28
                    width: model.x2 - model.x1 + 56
                    height: model.y2 - model.y1 + 56
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedTbs.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "tb" && viewportRef.relayerHoveredIndex === index
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

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewportRef.deleteProgress * 0.6) : "transparent"
                        border.color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((tbDelegate.isActive || tbDelegate.isRelayerHovered) ? "white" : "#666666")
                        border.width: tbDelegate.isRelayerHovered ? 2 : 1
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
                        x: 34
                        y: 34
                        width: parent.width - 68
                        height: parent.height - 68
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                                var dx = pt.x - tbDelegate.pressVpX, dy = pt.y - tbDelegate.pressVpY;
                                var w = tbDelegate.origX2 - tbDelegate.origX1, h = tbDelegate.origY2 - tbDelegate.origY1;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + dx, viewportRef.width - w));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + dy, viewportRef.height - h));
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + pt.x - tbDelegate.pressVpX, model.x2 - 20));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + pt.y - tbDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                textBoxesModel.setProperty(index, "y1", Math.max(0, Math.min(tbDelegate.origY1 + pt.y - tbDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + pt.y - tbDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                textBoxesModel.setProperty(index, "x2", Math.min(viewportRef.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20));
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
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                textBoxesModel.setProperty(index, "y2", Math.min(viewportRef.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + pt.x - tbDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20));
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
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                textBoxesModel.setProperty(index, "x1", Math.max(0, Math.min(tbDelegate.origX1 + pt.x - tbDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: tbSimulateMouseArea
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            var json = textBoxesModel.get(index).interactivityJson || "[]"
                            var items = []
                            try { items = JSON.parse(json) } catch(e) {}
                            var pendingJump = null
                            var hasCueVideo = false
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i]
                                if (it.itemTrigger !== trigger) continue
                                if (it.itemAction !== "cue") continue
                                if (it.itemCommand === "video" && it.itemVideoTarget === "fill" && it.itemVideoPath) {
                                    viewportRef.playCueVideo(it.itemVideoPath)
                                    hasCueVideo = true
                                } else if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0) {
                                    if (!pendingJump) pendingJump = it
                                }
                            }
                            if (pendingJump) {
                                var ms = Math.round((pendingJump.itemTransitionSpeed || 1.0) * 1000)
                                if (hasCueVideo) viewportRef.cueVideoHasJump = true
                                viewportRef.jumpToScene(pendingJump.itemTargetSceneId,
                                                        pendingJump.itemTransition    || "cut",
                                                        ms,
                                                        pendingJump.itemWipeFeather   || 0.0,
                                                        pendingJump.itemWipeDirection || "right",
                                                        pendingJump.itemPushDirection || "right",
                                                        pendingJump.itemLookYaw         !== undefined ? pendingJump.itemLookYaw       : 90.0,
                                                        pendingJump.itemLookPitch       !== undefined ? pendingJump.itemLookPitch     : 0.0,
                                                        pendingJump.itemLookFovMM       !== undefined ? pendingJump.itemLookFovMM     : 24.0,
                                                        pendingJump.itemLookOvershoot   !== undefined ? pendingJump.itemLookOvershoot : 1.0,
                                                        pendingJump.itemLookShutter     !== undefined ? pendingJump.itemLookShutter   : 0.10)
                            }
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
                    x: model.x1 - 28
                    y: model.y1 - 28
                    width: model.x2 - model.x1 + 56
                    height: model.y2 - model.y1 + 56
                    z: 100 + model.stackOrder
                    layer.enabled: true

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedImages.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "image" && viewportRef.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: isInteractive && (buttonGridRef.selectedTool === "destroy" || viewportRef.tempDestroyMode) && viewportRef.deleteTargetType === "image" && viewportRef.deleteTargetIndex === index

                    // Image fill
                    Image {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        source: model.filePath
                        fillMode: Image.Stretch
                        clip: true
                        onStatusChanged: {
                            if (status === Image.Ready || status === Image.Error)
                                imageLoadComplete()
                        }
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: imgDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: imgDelegate.isRelayerHovered ? 2 : 1
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 2
                        color: Qt.rgba(1, 0, 0, imgDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                            var dx = pt.x - imgDelegate.pressVpX, dy = pt.y - imgDelegate.pressVpY;
                            var w = imgDelegate.origX2 - imgDelegate.origX1, h = imgDelegate.origY2 - imgDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + dx, viewportRef.width - w));
                            var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + dy, viewportRef.height - h));
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        width: 56
                        height: 56
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20));
                                var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                imagesModel.setProperty(index, "y1", Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                imagesModel.setProperty(index, "x2", Math.min(viewportRef.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20));
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
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                imagesModel.setProperty(index, "y2", Math.min(viewportRef.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20));
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
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                imagesModel.setProperty(index, "x1", Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: imgSimulateMouseArea
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            var json = imagesModel.get(index).interactivityJson || "[]"
                            var items = []
                            try { items = JSON.parse(json) } catch(e) {}
                            var pendingJump = null
                            var hasCueVideo = false
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i]
                                if (it.itemTrigger !== trigger) continue
                                if (it.itemAction !== "cue") continue
                                if (it.itemCommand === "video" && it.itemVideoTarget === "fill" && it.itemVideoPath) {
                                    viewportRef.playCueVideo(it.itemVideoPath)
                                    hasCueVideo = true
                                } else if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0) {
                                    if (!pendingJump) pendingJump = it
                                }
                            }
                            if (pendingJump) {
                                var ms = Math.round((pendingJump.itemTransitionSpeed || 1.0) * 1000)
                                if (hasCueVideo) viewportRef.cueVideoHasJump = true
                                viewportRef.jumpToScene(pendingJump.itemTargetSceneId,
                                                        pendingJump.itemTransition    || "cut",
                                                        ms,
                                                        pendingJump.itemWipeFeather   || 0.0,
                                                        pendingJump.itemWipeDirection || "right",
                                                        pendingJump.itemPushDirection || "right",
                                                        pendingJump.itemLookYaw         !== undefined ? pendingJump.itemLookYaw       : 90.0,
                                                        pendingJump.itemLookPitch       !== undefined ? pendingJump.itemLookPitch     : 0.0,
                                                        pendingJump.itemLookFovMM       !== undefined ? pendingJump.itemLookFovMM     : 24.0,
                                                        pendingJump.itemLookOvershoot   !== undefined ? pendingJump.itemLookOvershoot : 1.0,
                                                        pendingJump.itemLookShutter     !== undefined ? pendingJump.itemLookShutter   : 0.10)
                            }
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
                model: videosModel
                delegate: Item {
                    id: vidDelegate
                    x: model.x1 - 28
                    y: model.y1 - 28
                    width: model.x2 - model.x1 + 56
                    height: model.y2 - model.y1 + 56
                    z: 100 + model.stackOrder
                    layer.enabled: true

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

                    // Tracks whether imageLoadComplete() has been called for this delegate.
                    // Guards against duplicate calls if both the frame path and fallback path fire.
                    property bool videoReadySignaled: false
                    property int videoFrameCount: 0

                    // Video fill
                    MediaPlayer {
                        id: vidPlayer
                        source: model.filePath
                        autoPlay: true
                        loops: MediaPlayer.Infinite
                        videoOutput: vidOutput
                        // Mute while staging so audio doesn't bleed through during pre-buffering.
                        audioOutput: AudioOutput {
                            volume: sceneContent.isInteractive ? 1.0 : 0.0
                        }
                        onMediaStatusChanged: {
                            // Release the counter for broken files (no frames will ever arrive)
                            // and for end-of-media on very short single-frame videos.
                            if ((mediaStatus === MediaPlayer.InvalidMedia ||
                                 mediaStatus === MediaPlayer.EndOfMedia) &&
                                !vidDelegate.videoReadySignaled) {
                                vidDelegate.videoReadySignaled = true
                                imageLoadComplete()
                            }
                        }
                    }
                    VideoOutput {
                        id: vidOutput
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56

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
                            }
                        }
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: vidDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: vidDelegate.isRelayerHovered ? 2 : 1
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 2
                        color: Qt.rgba(1, 0, 0, vidDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                            var dx = pt.x - vidDelegate.pressVpX, dy = pt.y - vidDelegate.pressVpY;
                            var w = vidDelegate.origX2 - vidDelegate.origX1, h = vidDelegate.origY2 - vidDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + dx, viewportRef.width - w));
                            var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + dy, viewportRef.height - h));
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        width: 56
                        height: 56
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20));
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20));
                                var nH = model.y2 - ny1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewportRef.width, cx + nW / 2));
                                videosModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
                                var nW = nx2 - model.x1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewportRef.height, cy + nH / 2));
                                videosModel.setProperty(index, "x2", nx2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx2 = Math.min(viewportRef.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
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
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var ny2 = Math.min(viewportRef.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
                                var nH = ny2 - model.y1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewportRef.width, cx + nW / 2));
                                videosModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
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
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
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
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20));
                                var nW = model.x2 - nx1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewportRef.height, cy + nH / 2));
                                videosModel.setProperty(index, "x1", nx1);
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: vidSimulateMouseArea
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            var json = videosModel.get(index).interactivityJson || "[]"
                            var items = []
                            try { items = JSON.parse(json) } catch(e) {}
                            var pendingJump = null
                            var hasCueVideo = false
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i]
                                if (it.itemTrigger !== trigger) continue
                                if (it.itemAction !== "cue") continue
                                if (it.itemCommand === "video" && it.itemVideoTarget === "fill" && it.itemVideoPath) {
                                    viewportRef.playCueVideo(it.itemVideoPath)
                                    hasCueVideo = true
                                } else if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0) {
                                    if (!pendingJump) pendingJump = it
                                }
                            }
                            if (pendingJump) {
                                var ms = Math.round((pendingJump.itemTransitionSpeed || 1.0) * 1000)
                                if (hasCueVideo) viewportRef.cueVideoHasJump = true
                                viewportRef.jumpToScene(pendingJump.itemTargetSceneId,
                                                        pendingJump.itemTransition    || "cut",
                                                        ms,
                                                        pendingJump.itemWipeFeather   || 0.0,
                                                        pendingJump.itemWipeDirection || "right",
                                                        pendingJump.itemPushDirection || "right",
                                                        pendingJump.itemLookYaw         !== undefined ? pendingJump.itemLookYaw       : 90.0,
                                                        pendingJump.itemLookPitch       !== undefined ? pendingJump.itemLookPitch     : 0.0,
                                                        pendingJump.itemLookFovMM       !== undefined ? pendingJump.itemLookFovMM     : 24.0,
                                                        pendingJump.itemLookOvershoot   !== undefined ? pendingJump.itemLookOvershoot : 1.0,
                                                        pendingJump.itemLookShutter     !== undefined ? pendingJump.itemLookShutter   : 0.10)
                            }
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

            // In-progress text box rubber-band
            Rectangle {
                visible: viewportRef.textBoxDragging
                x: Math.min(viewportRef.tbX1, viewportRef.tbX2)
                y: Math.min(viewportRef.tbY1, viewportRef.tbY2)
                width: Math.abs(viewportRef.tbX2 - viewportRef.tbX1)
                height: Math.abs(viewportRef.tbY2 - viewportRef.tbY1)
                color: "transparent"
                border.color: "white"
                border.width: 1
                z: 998

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    color: "transparent"
                    border.color: "black"
                    border.width: 1
                }
            }

            // In-progress image rubber-band
            Rectangle {
                visible: viewportRef.imageDragging
                x: Math.min(viewportRef.imgX1, viewportRef.imgX2)
                y: Math.min(viewportRef.imgY1, viewportRef.imgY2)
                width: Math.abs(viewportRef.imgX2 - viewportRef.imgX1)
                height: Math.abs(viewportRef.imgY2 - viewportRef.imgY1)
                color: "transparent"
                border.color: "white"
                border.width: 1
                z: 998
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    color: "transparent"
                    border.color: "black"
                    border.width: 1
                }
            }

            // In-progress video rubber-band
            Rectangle {
                visible: viewportRef.videoDragging
                x: Math.min(viewportRef.vidX1, viewportRef.vidX2)
                y: Math.min(viewportRef.vidY1, viewportRef.vidY2)
                width: Math.abs(viewportRef.vidX2 - viewportRef.vidX1)
                height: Math.abs(viewportRef.vidY2 - viewportRef.vidY1)
                color: "transparent"
                border.color: "white"
                border.width: 1
                z: 998
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    color: "transparent"
                    border.color: "black"
                    border.width: 1
                }
            }

            // Completed shaders
            Repeater {
                id: shadersRepeater
                model: shadersModel
                delegate: Item {
                    id: shaderDelegate
                    x: model.x1 - 28
                    y: model.y1 - 28
                    width: model.x2 - model.x1 + 56
                    height: model.y2 - model.y1 + 56
                    z: 100 + model.stackOrder

                    property bool isSelect: isInteractive && buttonGridRef.selectedTool === "select"
                    property bool isActive: isSelect && (viewportRef.selectionRevision >= 0) && viewportRef.selectedShaders.indexOf(index) !== -1 && !viewportRef.capturingThumbnail
                    property bool isRelayerHovered: isInteractive && buttonGridRef.selectedTool === "relayer" && viewportRef.relayerHoveredType === "shader" && viewportRef.relayerHoveredIndex === index
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


                    // Shader fill — recreated via Qt.createQmlObject() whenever the frag path
                    // changes, so per-shader uniform properties are correctly declared.
                    Item {
                        id: shaderEffectContainer
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: shaderDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewportRef.deleteProgress * 0.6) : ((shaderDelegate.isActive || shaderDelegate.isRelayerHovered) ? "white" : "transparent")
                        border.width: shaderDelegate.isRelayerHovered ? 2 : 1
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 2
                        color: Qt.rgba(1, 0, 0, shaderDelegate.isBeingDeleted ? viewportRef.deleteProgress * 0.6 : 0)
                    }

                    // Move
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                            var dx = pt.x - shaderDelegate.pressVpX, dy = pt.y - shaderDelegate.pressVpY;
                            var w = shaderDelegate.origX2 - shaderDelegate.origX1, h = shaderDelegate.origY2 - shaderDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + dx, viewportRef.width - w));
                            var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + dy, viewportRef.height - h));
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
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
                        x: 0; y: 0; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + pt.x - shaderDelegate.pressVpX, model.x2 - 20));
                                var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + pt.y - shaderDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width / 2 - 14; y: 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                shadersModel.setProperty(index, "y1", Math.max(0, Math.min(shaderDelegate.origY1 + pt.y - shaderDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56; y: 0; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                var nx2 = Math.min(viewportRef.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + pt.y - shaderDelegate.pressVpY, model.y2 - 20));
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
                        x: parent.width - 42; y: parent.height / 2 - 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                shadersModel.setProperty(index, "x2", Math.min(viewportRef.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56; y: parent.height - 56; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                var nx2 = Math.min(viewportRef.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20));
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
                        x: parent.width / 2 - 14; y: parent.height - 42; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                shadersModel.setProperty(index, "y2", Math.min(viewportRef.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0; y: parent.height - 56; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + pt.x - shaderDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewportRef.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20));
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
                        x: 14; y: parent.height / 2 - 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewportRef.selectionCount === 1 && !model.locked
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
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
                                shadersModel.setProperty(index, "x1", Math.max(0, Math.min(shaderDelegate.origX1 + pt.x - shaderDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewportRef.elementDragging = false
                        }
                    }

                    MouseArea {
                        id: shaderSimulateMouseArea
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: isInteractive && buttonGridRef.selectedTool === "simulate"
                        hoverEnabled: false
                        z: 3
                        cursorShape: Qt.PointingHandCursor

                        function fireInteractivity(trigger) {
                            var json = shadersModel.get(index).interactivityJson || "[]"
                            var items = []
                            try { items = JSON.parse(json) } catch(e) {}
                            var pendingJump = null
                            var hasCueVideo = false
                            for (var i = 0; i < items.length; i++) {
                                var it = items[i]
                                if (it.itemTrigger !== trigger) continue
                                if (it.itemAction !== "cue") continue
                                if (it.itemCommand === "video" && it.itemVideoTarget === "fill" && it.itemVideoPath) {
                                    viewportRef.playCueVideo(it.itemVideoPath)
                                    hasCueVideo = true
                                } else if (it.itemCommand === "jump" && it.itemTargetSceneId >= 0) {
                                    if (!pendingJump) pendingJump = it
                                }
                            }
                            if (pendingJump) {
                                var ms = Math.round((pendingJump.itemTransitionSpeed || 1.0) * 1000)
                                if (hasCueVideo) viewportRef.cueVideoHasJump = true
                                viewportRef.jumpToScene(pendingJump.itemTargetSceneId,
                                                        pendingJump.itemTransition    || "cut",
                                                        ms,
                                                        pendingJump.itemWipeFeather   || 0.0,
                                                        pendingJump.itemWipeDirection || "right",
                                                        pendingJump.itemPushDirection || "right",
                                                        pendingJump.itemLookYaw         !== undefined ? pendingJump.itemLookYaw       : 90.0,
                                                        pendingJump.itemLookPitch       !== undefined ? pendingJump.itemLookPitch     : 0.0,
                                                        pendingJump.itemLookFovMM       !== undefined ? pendingJump.itemLookFovMM     : 24.0,
                                                        pendingJump.itemLookOvershoot   !== undefined ? pendingJump.itemLookOvershoot : 1.0,
                                                        pendingJump.itemLookShutter     !== undefined ? pendingJump.itemLookShutter   : 0.10)
                            }
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

}
