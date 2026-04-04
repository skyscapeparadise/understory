import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

Item {
    id: root

    //
    // MODELS
    //
    // nodesModel rows: { id:int, x:real, y:real, name:string, nodeColor:string }
    // linksModel rows: { a:int, b:int } where a,b are node indices in nodesModel
    //
    ListModel {
        id: nodesModel
    }
    ListModel {
        id: linksModel
    }

    property int nextNodeId: 0
    property real nodeRadius: 16

    // Zoom and Pan state
    property real zoom: 1.0
    property real panX: 0.0
    property real panY: 0.0

    // Playback and timeline state
    property real playheadTime: 0
    property real timelineScrollOffset: 0
    property bool isPlaying: false
    property real pixelsPerSecond: 60
    property bool draggingPlayhead: false
    property bool playheadHovered: false

    onZoomChanged: requestRedraw()
    onPanXChanged: requestRedraw()
    onPanYChanged: requestRedraw()

    // linking preview state
    property bool linking: false
    property int linkingFromIndex: -1
    property real linkToX: 0
    property real linkToY: 0

    // link wobble state
    property int wobblingLinkIndex: -1
    property real wobblePhase: 0.0
    property real wobbleAmplitude: 0.0

    function showAll() {
        if (nodesModel.count === 0) return

        var minX = Infinity, maxX = -Infinity
        var minY = Infinity, maxY = -Infinity

        for (var i = 0; i < nodesModel.count; i++) {
            var n = nodesModel.get(i)
            minX = Math.min(minX, n.x)
            maxX = Math.max(maxX, n.x)
            minY = Math.min(minY, n.y)
            maxY = Math.max(maxY, n.y)
        }

        var margin = 60
        var contentW = (maxX - minX) + margin * 2
        var contentH = (maxY - minY) + margin * 2
        var sw = stage.width
        var sh = stage.height

        var targetZoom
        if (nodesModel.count === 1 || contentW <= margin * 2 || contentH <= margin * 2) {
            targetZoom = 1.0
        } else {
            targetZoom = Math.min(sw / contentW, sh / contentH)
            targetZoom = Math.max(0.1, Math.min(targetZoom, 10.0))
        }

        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        zoomAnim.to = targetZoom
        panXAnim.to = sw / 2 - cx * targetZoom
        panYAnim.to = sh / 2 - cy * targetZoom
        showAllAnimation.start()
    }

    ParallelAnimation {
        id: showAllAnimation
        NumberAnimation { id: zoomAnim; target: root; property: "zoom"; duration: 380; easing.type: Easing.InOutCubic }
        NumberAnimation { id: panXAnim; target: root; property: "panX"; duration: 380; easing.type: Easing.InOutCubic }
        NumberAnimation { id: panYAnim; target: root; property: "panY"; duration: 380; easing.type: Easing.InOutCubic }
    }

    Timer {
        id: playbackTimer
        interval: 16
        repeat: true
        running: root.isPlaying
        onTriggered: {
            root.playheadTime += 0.016
            if (!root.draggingPlayhead) {
                var playheadPx = root.playheadTime * root.pixelsPerSecond
                var midpoint = timelineSection.width / 2
                if (playheadPx > root.timelineScrollOffset + midpoint) {
                    root.timelineScrollOffset = playheadPx - midpoint
                }
            }
            timelineCanvas.requestPaint()
        }
    }

    Timer {
        id: wobbleTimer
        interval: 16
        repeat: true
        running: root.wobblingLinkIndex !== -1
        onTriggered: {
            root.wobblePhase += 1.0;
            root.wobbleAmplitude += (15.0 / (600 / 16)); // Max amplitude 15 over 0.6 second
            if (root.wobbleAmplitude >= 15.0) {
                var toDelete = root.wobblingLinkIndex;
                root.cancelWobble();
                root.deleteLink(toDelete);
            } else {
                root.requestRedraw();
            }
        }
    }

    function requestRedraw() {
        canvas.requestPaint();
    }

    //
    // MODEL HELPERS
    //
    function addNode(x, y) {
        var defaultName = "Node " + nextNodeId;
        nodesModel.append({
            id: nextNodeId,
            x: x,
            y: y,
            name: defaultName,
            nodeColor: "#2e2e33"
        });
        nextNodeId += 1;
        requestRedraw();
    }

    function renameNode(idx, newName) {
        if (idx >= 0 && idx < nodesModel.count) {
            nodesModel.setProperty(idx, "name", newName);
            requestRedraw();
        }
    }

    function changeNodeColor(idx, newColor) {
        if (idx >= 0 && idx < nodesModel.count) {
            nodesModel.setProperty(idx, "nodeColor", newColor);
            requestRedraw();
        }
    }

    function beginWobble(idx) {
        wobblingLinkIndex = idx;
        wobblePhase = 0;
        wobbleAmplitude = 0;
        requestRedraw();
    }

    function cancelWobble() {
        wobblingLinkIndex = -1;
        wobbleAmplitude = 0;
        requestRedraw();
    }

    function deleteLink(idx) {
        if (idx >= 0 && idx < linksModel.count) {
            linksModel.remove(idx);
            requestRedraw();
        }
    }

    function deleteNode(idx) {
        if (idx < 0 || idx >= nodesModel.count)
            return;

        // Cancel active linking and wobbling just to be safe
        linking = false;
        linkingFromIndex = -1;
        cancelWobble();

        // First, cleanly remove all links connected to this node,
        // and shift down the indices of any nodes that come AFTER the deleted one.
        for (var i = linksModel.count - 1; i >= 0; --i) {
            var L = linksModel.get(i);
            if (L.a === idx || L.b === idx) {
                linksModel.remove(i);
            } else {
                var newA = L.a > idx ? L.a - 1 : L.a;
                var newB = L.b > idx ? L.b - 1 : L.b;
                if (newA !== L.a || newB !== L.b) {
                    linksModel.setProperty(i, "a", newA);
                    linksModel.setProperty(i, "b", newB);
                }
            }
        }

        // Now remove the node
        nodesModel.remove(idx);
        requestRedraw();
    }

    // hit test in scene coords (now handles variable-width pill shapes)
    function findNodeAt(sceneX, sceneY) {
        for (var i = nodesModel.count - 1; i >= 0; --i) {
            var nx = nodesModel.get(i).x * root.zoom + root.panX;
            var ny = nodesModel.get(i).y * root.zoom + root.panY;

            var item = nodeRepeater.itemAt(i);
            var w = item ? item.width / 2 : nodeRadius;
            var h = item ? item.height / 2 : nodeRadius;

            var dx = Math.abs(sceneX - nx);
            var dy = Math.abs(sceneY - ny);

            // Bounding box hit test
            if (dx <= w && dy <= h) {
                return i;
            }
        }
        return -1;
    }

    // hit test in scene coords for links
    function findLinkAt(sceneX, sceneY) {
        for (var i = 0; i < linksModel.count; ++i) {
            var linkRec = linksModel.get(i);
            var aIdx = linkRec.a;
            var bIdx = linkRec.b;
            if (aIdx >= 0 && aIdx < nodesModel.count && bIdx >= 0 && bIdx < nodesModel.count) {
                var nA = nodesModel.get(aIdx);
                var nB = nodesModel.get(bIdx);

                var ax = nA.x * root.zoom + root.panX;
                var ay = nA.y * root.zoom + root.panY;
                var bx = nB.x * root.zoom + root.panX;
                var by = nB.y * root.zoom + root.panY;

                var abx = bx - ax;
                var aby = by - ay;
                var apx = sceneX - ax;
                var apy = sceneY - ay;

                var len_sq = abx * abx + aby * aby;
                var param = -1;
                if (len_sq !== 0)
                    param = (apx * abx + apy * aby) / len_sq;

                var xx, yy;
                if (param < 0) {
                    xx = ax;
                    yy = ay;
                } else if (param > 1) {
                    xx = bx;
                    yy = by;
                } else {
                    xx = ax + param * abx;
                    yy = ay + param * aby;
                }

                var dx = sceneX - xx;
                var dy = sceneY - yy;
                var dist = Math.sqrt(dx * dx + dy * dy);

                if (dist <= 15) {
                    // 15px radius for grabbing the line
                    return i;
                }
            }
        }
        return -1;
    }

    function moveNode(idx, newSceneX, newSceneY) {
        // write directly to the model; this becomes truth
        if (idx >= 0 && idx < nodesModel.count) {
            nodesModel.setProperty(idx, "x", newSceneX);
            nodesModel.setProperty(idx, "y", newSceneY);
            requestRedraw();
        }
    }

    function beginLink(fromIdx, sceneX, sceneY) {
        linking = true;
        linkingFromIndex = fromIdx;
        linkToX = sceneX;
        linkToY = sceneY;
        requestRedraw();
    }

    function updateLink(sceneX, sceneY) {
        if (!linking)
            return;
        linkToX = sceneX;
        linkToY = sceneY;
        requestRedraw();
    }

    function endLink(sceneX, sceneY) {
        if (!linking)
            return;
        let targetIdx = findNodeAt(sceneX, sceneY);
        if (targetIdx !== -1 && targetIdx !== linkingFromIndex) {
            // check if we already have this link
            var exists = false;
            for (var i = 0; i < linksModel.count; ++i) {
                var L = linksModel.get(i);
                if ((L.a === linkingFromIndex && L.b === targetIdx) || (L.a === targetIdx && L.b === linkingFromIndex)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                linksModel.append({
                    a: linkingFromIndex,
                    b: targetIdx
                });
            }
        }

        linking = false;
        linkingFromIndex = -1;
        requestRedraw();
    }

    Rectangle {
        id: stage
        x: 0
        y: 0
        width: parent.width
        height: parent.height - 50
        color: "#1a1a1d"
        clip: true
        focus: true // Allows the background to take focus and defocus inputs

        //
        // LAYER 0: background interaction
        //
        PinchArea {
            id: pinchArea
            anchors.fill: parent
            z: 0

            onPinchUpdated: pinch => {
                var oldZoom = root.zoom;
                var zf = pinch.scale / pinch.previousScale;

                root.zoom *= zf;
                root.zoom = Math.max(0.1, Math.min(root.zoom, 10.0));

                var targetX = (pinch.center.x - root.panX) / oldZoom;
                var targetY = (pinch.center.y - root.panY) / oldZoom;
                root.panX = pinch.center.x - targetX * root.zoom;
                root.panY = pinch.center.y - targetY * root.zoom;
            }

            MouseArea {
                id: createArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                property real lastPanX: 0
                property real lastPanY: 0
                property bool isPanning: false

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        var hitLink = root.findLinkAt(mouse.x, mouse.y);
                        if (hitLink !== -1) {
                            root.beginWobble(hitLink);
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        isPanning = true;
                        lastPanX = mouse.x;
                        lastPanY = mouse.y;
                    } else {
                        stage.forceActiveFocus(); // Defocus any editing nodes
                    }
                }

                onPositionChanged: mouse => {
                    if (isPanning) {
                        root.panX += mouse.x - lastPanX;
                        root.panY += mouse.y - lastPanY;
                        lastPanX = mouse.x;
                        lastPanY = mouse.y;
                    } else if (root.wobblingLinkIndex !== -1) {
                        var hitLink = root.findLinkAt(mouse.x, mouse.y);
                        if (hitLink !== root.wobblingLinkIndex) {
                            root.cancelWobble();
                        }
                    }
                }

                onReleased: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (root.wobblingLinkIndex !== -1) {
                            root.cancelWobble();
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        isPanning = false;
                    }
                }

                onDoubleClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        var hit = root.findNodeAt(mouse.x, mouse.y);
                        if (hit === -1) {
                            var mX = (mouse.x - root.panX) / root.zoom;
                            var mY = (mouse.y - root.panY) / root.zoom;
                            root.addNode(mX, mY);
                        }
                    }
                }

                onWheel: wheel => {
                    if (wheel.modifiers & Qt.ControlModifier) {
                        // Zoom (Ctrl+Scroll or trackpad pinch fallback)
                        var delta = wheel.angleDelta.y;
                        if (delta === 0)
                            delta = wheel.angleDelta.x;
                        var oldZoom = root.zoom;

                        var zf = 1.0 + (delta / 1200.0);
                        if (zf < 0.1)
                            zf = 0.1;

                        root.zoom *= zf;
                        root.zoom = Math.max(0.1, Math.min(root.zoom, 10.0));

                        // Zoom around cursor position to keep it pinned
                        var targetX = (wheel.x - root.panX) / oldZoom;
                        var targetY = (wheel.y - root.panY) / oldZoom;
                        root.panX = wheel.x - targetX * root.zoom;
                        root.panY = wheel.y - targetY * root.zoom;
                    } else {
                        // Pan (standard two-finger scroll)
                        if (wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0) {
                            // Precise pixel scroll from trackpad
                            root.panX += wheel.pixelDelta.x;
                            root.panY += wheel.pixelDelta.y;
                        } else {
                            // Fallback for standard mouse scroll wheels
                            root.panX += wheel.angleDelta.x;
                            root.panY += wheel.angleDelta.y;
                        }
                    }
                    wheel.accepted = true;
                }
            }
        }

        //
        // LAYER 1: Canvas → draw all permanent links + current temp link
        //
        Canvas {
            id: canvas
            anchors.fill: parent
            antialiasing: true
            z: 1

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();

                // draw permanent links
                ctx.save();
                for (var i = 0; i < linksModel.count; ++i) {
                    var linkRec = linksModel.get(i);
                    var aIdx = linkRec.a;
                    var bIdx = linkRec.b;
                    if (aIdx >= 0 && aIdx < nodesModel.count && bIdx >= 0 && bIdx < nodesModel.count) {
                        var nA = nodesModel.get(aIdx);
                        var nB = nodesModel.get(bIdx);

                        var ax = nA.x * root.zoom + root.panX;
                        var ay = nA.y * root.zoom + root.panY;
                        var bx = nB.x * root.zoom + root.panX;
                        var by = nB.y * root.zoom + root.panY;

                        ctx.beginPath();

                        if (root.wobblingLinkIndex === i) {
                            var abx = bx - ax;
                            var aby = by - ay;
                            var len = Math.sqrt(abx * abx + aby * aby);

                            if (len > 0) {
                                var nx = -aby / len;
                                var ny = abx / len;
                                ctx.moveTo(ax, ay);
                                var segments = Math.floor(len / 4);
                                for (var j = 1; j <= segments; j++) {
                                    var t = j / segments;
                                    var cx = ax + abx * t;
                                    var cy = ay + aby * t;
                                    var wave = Math.sin(t * len * 0.1 - root.wobblePhase) * root.wobbleAmplitude;
                                    var damp = Math.sin(t * Math.PI);
                                    wave *= damp;
                                    ctx.lineTo(cx + nx * wave, cy + ny * wave);
                                }
                            } else {
                                ctx.moveTo(ax, ay);
                                ctx.lineTo(bx, by);
                            }

                            var dangerFactor = Math.min(1.0, root.wobbleAmplitude / 15.0);
                            var hue = Math.floor(220 - dangerFactor * 220);
                            ctx.strokeStyle = "hsl(" + hue + ", 100%, 70%)";
                            ctx.lineWidth = 2 + dangerFactor * 3;
                        } else {
                            ctx.moveTo(ax, ay);
                            ctx.lineTo(bx, by);
                            ctx.strokeStyle = "#99aaff";
                            ctx.lineWidth = 2;
                        }

                        ctx.stroke();
                    }
                }
                ctx.restore();

                // draw magenta dashed temp link
                if (root.linking && root.linkingFromIndex >= 0 && root.linkingFromIndex < nodesModel.count) {
                    var fromNode = nodesModel.get(root.linkingFromIndex);
                    var fnX = fromNode.x * root.zoom + root.panX;
                    var fnY = fromNode.y * root.zoom + root.panY;

                    ctx.save();
                    ctx.lineWidth = 2;
                    ctx.setLineDash([4, 4]);
                    ctx.strokeStyle = "#ff80ff";
                    ctx.beginPath();
                    ctx.moveTo(fnX, fnY);
                    ctx.lineTo(root.linkToX, root.linkToY);
                    ctx.stroke();
                    ctx.restore();
                }
            }
        }

        //
        // LAYER 2: node visuals, interactable
        //
        Repeater {
            id: nodeRepeater
            model: nodesModel

            delegate: NodeItem {
                z: 2
                nodeIndex: index
                radius: root.nodeRadius
                nodeColor: model.nodeColor !== undefined ? model.nodeColor : "#2e2e33"

                // Signal handlers bubble events up to the root
                onDragMove: (sceneX, sceneY) => {
                    root.moveNode(nodeIndex, sceneX, sceneY);
                }
                onBeginLinkDrag: (idx, sceneX, sceneY) => {
                    root.beginLink(idx, sceneX, sceneY);
                }
                onContinueLinkDrag: (sceneX, sceneY) => {
                    root.updateLink(sceneX, sceneY);
                }
                onEndLinkDrag: (sceneX, sceneY) => {
                    root.endLink(sceneX, sceneY);
                }
            }
        }

        //
        // HUD / instructions
        //
        Rectangle {
            id: helpBox
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 8
            radius: 4
            color: "#00000088"
            border.color: "#444"
            border.width: 1
            z: 10

            width: helpText.paintedWidth + 16
            height: helpText.paintedHeight + 16

            Text {
                id: helpText
                anchors.centerIn: parent
                color: "#ddd"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                text: "Pinch or Ctrl+Scroll: zoom in/out\n2-Finger / Mid-Click Drag: pan\nDouble-click empty space: new node\nDrag node (center): move\nDrag node (edge): connect\nDouble-click node: rename or color\nRight-click & hold link: delete"
            }
        }

        Item {
            id: showAllBtn
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 36
            height: 36
            z: 10

            property bool hovered: false

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: showAllBtn.hovered ? "#80cfff" : "white"
                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }
            }

            Image {
                id: showAllIcon
                anchors.centerIn: parent
                width: 22
                height: 22
                fillMode: Image.PreserveAspectFit
                source: "icons/showall.svg"
                visible: false
            }

            ColorOverlay {
                anchors.fill: showAllIcon
                source: showAllIcon
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: showAllBtn.hovered = true
                onExited: showAllBtn.hovered = false
                onClicked: root.showAll()
            }
        }
    }

    //
    // Timeline section
    //
    Rectangle {
        id: timelineSection
        x: 0
        y: parent.height - 50
        width: parent.width - 240
        height: 50
        color: "#141417"
        clip: true

        Rectangle {
            width: parent.width
            height: 1
            color: "#333"
            anchors.top: parent.top
        }

        Canvas {
            id: timelineCanvas
            anchors.fill: parent
            antialiasing: true

            function formatTime(totalSeconds) {
                var s = Math.floor(totalSeconds)
                var m = Math.floor(s / 60)
                var sec = s % 60
                return m + ":" + (sec < 10 ? "0" + sec : sec)
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()

                var pps = root.pixelsPerSecond
                var offset = root.timelineScrollOffset
                var w = width
                var h = height

                var startTime = offset / pps
                var endTime = (offset + w) / pps + 1
                var firstSecond = Math.floor(Math.max(0, startTime))

                for (var s = firstSecond; s <= endTime; s++) {
                    var x = s * pps - offset

                    if (s % 10 === 0) {
                        ctx.beginPath()
                        ctx.moveTo(x, h)
                        ctx.lineTo(x, h - 12)
                        ctx.strokeStyle = "#777"
                        ctx.lineWidth = 1.5
                        ctx.stroke()

                        ctx.fillStyle = "#999"
                        ctx.font = "10px sans-serif"
                        ctx.textAlign = "left"
                        ctx.fillText(timelineCanvas.formatTime(s), x + 3, h - 14)
                    } else if (s % 5 === 0) {
                        ctx.beginPath()
                        ctx.moveTo(x, h)
                        ctx.lineTo(x, h - 7)
                        ctx.strokeStyle = "#555"
                        ctx.lineWidth = 1
                        ctx.stroke()
                    } else {
                        ctx.beginPath()
                        ctx.moveTo(x, h)
                        ctx.lineTo(x, h - 4)
                        ctx.strokeStyle = "#444"
                        ctx.lineWidth = 1
                        ctx.stroke()
                    }
                }

                // Playhead
                var playheadX = root.playheadTime * pps - offset
                if (playheadX >= 0 && playheadX <= w) {
                    var active = root.draggingPlayhead || root.playheadHovered
                    ctx.beginPath()
                    ctx.moveTo(playheadX, 0)
                    ctx.lineTo(playheadX, h)
                    ctx.strokeStyle = active ? "#ff6666" : "#ff4444"
                    ctx.lineWidth = active ? 2.5 : 2
                    ctx.stroke()

                    var tipW = active ? 8 : 6
                    ctx.beginPath()
                    ctx.moveTo(playheadX - tipW, 0)
                    ctx.lineTo(playheadX + tipW, 0)
                    ctx.lineTo(playheadX, tipW + 4)
                    ctx.closePath()
                    ctx.fillStyle = active ? "#ff6666" : "#ff4444"
                    ctx.fill()
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (root.draggingPlayhead || root.playheadHovered) ? Qt.SizeHorCursor : Qt.ArrowCursor

            function nearPlayhead(mouseX) {
                var playheadX = root.playheadTime * root.pixelsPerSecond - root.timelineScrollOffset
                return Math.abs(mouseX - playheadX) <= 8
            }

            onPressed: mouse => {
                if (nearPlayhead(mouse.x)) {
                    root.draggingPlayhead = true
                    mouse.accepted = true
                }
            }

            onPositionChanged: mouse => {
                if (root.draggingPlayhead) {
                    root.playheadTime = Math.max(0, (mouse.x + root.timelineScrollOffset) / root.pixelsPerSecond)
                    timelineCanvas.requestPaint()
                } else {
                    root.playheadHovered = nearPlayhead(mouse.x)
                    timelineCanvas.requestPaint()
                }
            }

            onReleased: {
                root.draggingPlayhead = false
            }

            onExited: {
                root.playheadHovered = false
                timelineCanvas.requestPaint()
            }

            onWheel: wheel => {
                if (wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0) {
                    root.timelineScrollOffset = Math.max(0, root.timelineScrollOffset - wheel.pixelDelta.x)
                } else {
                    root.timelineScrollOffset = Math.max(0, root.timelineScrollOffset - wheel.angleDelta.x / 2)
                }
                timelineCanvas.requestPaint()
                wheel.accepted = true
            }
        }
    }

    //
    // Transport controls
    //
    Rectangle {
        id: transportControls
        x: parent.width - 240
        y: parent.height - 50
        width: 240
        height: 50
        color: "#141417"

        Rectangle {
            width: parent.width
            height: 1
            color: "#333"
            anchors.top: parent.top
        }

        Rectangle {
            width: 1
            height: parent.height
            color: "#333"
            anchors.left: parent.left
        }

        Row {
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: ["previous", "stop", "play", "pause", "next"]

                delegate: Item {
                    id: transportBtn
                    width: 36
                    height: 36

                    property bool hovered: false
                    property bool isDummy: modelData === "previous" || modelData === "next"
                    property bool toggled: {
                        if (modelData === "play") return root.isPlaying
                        if (modelData === "pause") return !root.isPlaying && root.playheadTime > 0
                        return false
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: transportBtn.toggled ? "white" : "transparent"
                        border.width: 2
                        border.color: transportBtn.hovered ? "#80cfff" : "white"
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }

                    Image {
                        id: transportIcon
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        fillMode: Image.PreserveAspectFit
                        source: "icons/" + modelData + ".svg"
                        visible: false
                    }

                    ColorOverlay {
                        anchors.fill: transportIcon
                        source: transportIcon
                        color: transportBtn.toggled ? "#477B78" : (transportBtn.isDummy ? "#555555" : "white")
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: transportBtn.hovered = true
                        onExited: transportBtn.hovered = false
                        onClicked: {
                            if (modelData === "play") {
                                root.isPlaying = true
                            } else if (modelData === "pause") {
                                root.isPlaying = false
                            } else if (modelData === "stop") {
                                root.isPlaying = false
                                root.playheadTime = 0
                                root.timelineScrollOffset = 0
                                timelineCanvas.requestPaint()
                            }
                            // previous and next are dummy buttons — no action yet
                        }
                    }
                }
            }
        }
    }

    //
    // Node component
    //
    component NodeItem: Item {
        id: node

        property int nodeIndex: -1
        property real radius: 16
        property bool isEditing: false
        property bool isDeleting: false
        property string nodeColor: "#2e2e33"

        // We do NOT keep our own stored copy of x/y.
        // We "pull" position from the model every frame.
        function modelX() {
            return nodesModel.get(nodeIndex) ? nodesModel.get(nodeIndex).x : 0;
        }
        function modelY() {
            return nodesModel.get(nodeIndex) ? nodesModel.get(nodeIndex).y : 0;
        }

        function screenX() {
            return modelX() * root.zoom + root.panX;
        }
        function screenY() {
            return modelY() * root.zoom + root.panY;
        }

        // Dynamic size calculation based on text width
        property real baseWidth: Math.max(radius * 2, nameInput.contentWidth + 24)
        property real baseHeight: radius * 2

        // Draw this node centered at its mapped screen coords
        x: screenX() - width / 2
        y: screenY() - height / 2

        // Expand with padding when editing. We add extra height to fit the delete button.
        width: isEditing ? baseWidth + 40 : baseWidth
        height: isEditing ? baseHeight + 46 : baseHeight

        Behavior on width {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // Scale the entire node up slightly on hover (disabled while editing)
        scale: ma.containsMouse && !isEditing ? 1.15 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // local drag state
        property bool draggingNode: false
        property bool draggingLink: false
        property real grabOffsetX: 0
        property real grabOffsetY: 0

        // signals that bubble up to root through the Repeater delegate bindings
        signal dragMove(real modelX, real modelY)
        signal beginLinkDrag(int idx, real sceneX, real sceneY)
        signal continueLinkDrag(real sceneX, real sceneY)
        signal endLinkDrag(real sceneX, real sceneY)

        // Color Wheel Ring
        Canvas {
            id: colorRing
            // We make the canvas exactly 40px larger than the node in both directions
            // This gives a 20px padding on all sides.
            // 4px for gap, 16px for ring width.
            x: -20
            y: -20
            width: parent.width + 40
            height: parent.height + 40
            z: -1

            opacity: node.isEditing ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();

                var cw = width;
                var ch = height;

                ctx.beginPath();
                // Create a compound path using two concentric pill shapes in opposite winding directions
                // Outer pill (clockwise)
                var rOut = ch / 2;
                ctx.moveTo(rOut, 0);
                ctx.lineTo(cw - rOut, 0);
                ctx.arc(cw - rOut, rOut, rOut, -Math.PI / 2, 0);
                ctx.lineTo(cw, ch - rOut);
                ctx.arc(cw - rOut, ch - rOut, rOut, 0, Math.PI / 2);
                ctx.lineTo(rOut, ch);
                ctx.arc(rOut, ch - rOut, rOut, Math.PI / 2, Math.PI);
                ctx.lineTo(0, rOut);
                ctx.arc(rOut, rOut, rOut, Math.PI, -Math.PI / 2);

                // Inner pill (counter-clockwise)
                // ix, iy = 16, so the inner hole is inset 16px from canvas edge.
                // Since canvas is 20px from node edge, the inner hole is 4px away from the node edge.
                var ix = 16;
                var iy = 16;
                var iw = cw - 32;
                var ih = ch - 32;
                var rIn = ih / 2;

                ctx.moveTo(ix + rIn, iy);
                ctx.arc(ix + rIn, iy + rIn, rIn, -Math.PI / 2, Math.PI, true);
                ctx.lineTo(ix, iy + ih - rIn);
                ctx.arc(ix + rIn, iy + ih - rIn, rIn, Math.PI, Math.PI / 2, true);
                ctx.lineTo(ix + iw - rIn, iy + ih);
                ctx.arc(ix + iw - rIn, iy + ih - rIn, rIn, Math.PI / 2, 0, true);
                ctx.lineTo(ix + iw, iy + rIn);
                ctx.arc(ix + iw - rIn, iy + rIn, rIn, 0, -Math.PI / 2, true);
                ctx.closePath();

                // Clip to the ring shape we just defined
                ctx.clip();

                // Draw the rainbow gradients
                var cx = cw / 2;
                var cy = ch / 2;
                var maxR = Math.max(cw, ch);
                ctx.translate(cx, cy);

                for (var i = 0; i < 360; i += 3) {
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(maxR * Math.cos(i * Math.PI / 180), maxR * Math.sin(i * Math.PI / 180));
                    // Add 0.5 to overlap slightly and prevent antialiasing gaps
                    ctx.lineTo(maxR * Math.cos((i + 3.5) * Math.PI / 180), maxR * Math.sin((i + 3.5) * Math.PI / 180));
                    ctx.closePath();
                    ctx.fillStyle = "hsl(" + i + ", 100%, 50%)";
                    ctx.fill();
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: node.isEditing
                acceptedButtons: Qt.LeftButton

                onClicked: mouse => {
                    var cx = width / 2;
                    var cy = height / 2;
                    var dx = mouse.x - cx;
                    var dy = mouse.y - cy;

                    var angle = Math.atan2(dy, dx) * 180 / Math.PI;
                    if (angle < 0)
                        angle += 360;

                    var newColor = Qt.hsla(angle / 360.0, 1.0, 0.5, 1.0).toString();
                    root.changeNodeColor(node.nodeIndex, newColor);
                }
            }
        }

        Rectangle {
            id: bgRect
            anchors.fill: parent
            radius: height / 2 // Dynamic radius to stay pill-shaped
            color: node.nodeColor
            border.width: ma.containsMouse || node.isEditing ? 8 : 2
            border.color: "#ffffff"

            // Animate the border, color and radius changes for a smoother feel
            Behavior on border.width {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
            Behavior on radius {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            drag.axis: Drag.XAndYAxis

            onPressed: mouse => {
                if (node.isDeleting)
                    return;
                if (mouse.button === Qt.RightButton) {
                    mouse.accepted = true;
                    return;
                }

                var scenePoint = ma.mapToItem(stage, mouse.x, mouse.y);

                // Use an elliptical distance formula to support variable-width pill shapes
                var cx = node.width / 2;
                var cy = node.height / 2;
                var dx = mouse.x - cx;
                var dy = mouse.y - cy;

                var normX = dx / (node.width / 2);
                var normY = dy / (node.height / 2);
                var dist = Math.sqrt(normX * normX + normY * normY);

                if (dist > 0.6) {
                    // start linking
                    node.draggingLink = true;
                    node.draggingNode = false;
                    node.beginLinkDrag(node.nodeIndex, scenePoint.x, scenePoint.y);
                } else {
                    // start moving
                    node.draggingNode = true;
                    node.draggingLink = false;
                    node.grabOffsetX = scenePoint.x - screenX();
                    node.grabOffsetY = scenePoint.y - screenY();
                }

                mouse.accepted = true;
            }

            onPositionChanged: mouse => {
                if (node.isDeleting)
                    return;
                var scenePoint = ma.mapToItem(stage, mouse.x, mouse.y);

                if (node.draggingNode) {
                    var newScreenCenterX = scenePoint.x - node.grabOffsetX;
                    var newScreenCenterY = scenePoint.y - node.grabOffsetY;
                    // Map back to model coordinates
                    var newModelX = (newScreenCenterX - root.panX) / root.zoom;
                    var newModelY = (newScreenCenterY - root.panY) / root.zoom;
                    node.dragMove(newModelX, newModelY);
                } else if (node.draggingLink) {
                    node.continueLinkDrag(scenePoint.x, scenePoint.y);
                }
            }

            onReleased: mouse => {
                if (node.isDeleting)
                    return;
                if (node.draggingNode) {
                    node.draggingNode = false;
                } else if (node.draggingLink) {
                    var scenePoint = ma.mapToItem(stage, mouse.x, mouse.y);
                    node.draggingLink = false;
                    node.endLinkDrag(scenePoint.x, scenePoint.y);
                }
            }

            onDoubleClicked: mouse => {
                if (node.isDeleting || mouse.button === Qt.RightButton)
                    return;
                node.draggingNode = false;
                node.draggingLink = false;
                node.isEditing = true;
                nameInput.forceActiveFocus();
                nameInput.selectAll();
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 6
            z: 10 // sits above the mouse area

            TextInput {
                id: nameInput
                anchors.horizontalCenter: parent.horizontalCenter

                // initialize from model safely
                text: {
                    var m = nodesModel.get(nodeIndex);
                    return m ? (m.name !== undefined ? m.name : m.id.toString()) : "";
                }

                // Dynamically change text color based on background luminance
                color: {
                    var r = bgRect.color.r;
                    var g = bgRect.color.g;
                    var b = bgRect.color.b;
                    var luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
                    return luminance > 0.5 ? "#1a1a1d" : "#ffffff";
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                font.pixelSize: 12
                enabled: node.isEditing
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true

                // Focus loss or hitting enter
                onEditingFinished: {
                    if (!node.isDeleting) {
                        node.isEditing = false;
                        root.renameNode(node.nodeIndex, text);
                    }
                }
            }

            Rectangle {
                id: deleteBtn
                width: 24
                height: 24
                radius: 12
                color: deleteBtnArea.containsMouse ? "#cccccc" : "#ffffff"
                visible: node.isEditing
                opacity: node.isEditing ? 1.0 : 0.0
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }

                Text {
                    text: "🗑️"
                    anchors.centerIn: parent
                    font.pixelSize: 12
                }

                MouseArea {
                    id: deleteBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onPressed: mouse => {
                        mouse.accepted = true;
                        node.isDeleting = true;
                        root.deleteNode(node.nodeIndex);
                    }
                }
            }
        }
    }
}
