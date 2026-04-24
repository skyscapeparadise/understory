import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property alias nodesModel: nodesModel
    property alias networksModel: networksModel
    property alias orbitsModel: orbitsModel
    property alias soundsModel: soundsModel
    property alias charactersModel: charactersModel

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
    // networksModel rows: { netId:int, netName:string, netColor:string }
    ListModel {
        id: networksModel
    }
    // orbitsModel rows: { circleType:string ("char"|"sound"), itemIdx:int, nodeId:int }
    ListModel {
        id: orbitsModel
    }

    property int nextNodeId: 0

    // Drag-circle state (character/sound circle dragged from list onto canvas)
    property bool   isDraggingCircle:      false
    property string draggingCircleType:    ""
    property int    draggingCircleItemIdx: -1
    property string draggingCircleLabel:   ""
    property string draggingCircleImage:   ""
    property real   draggingCircleX:       0
    property real   draggingCircleY:       0

    // Snap animation state — plays after a circle is dropped on a node
    property bool   snappingCircle:        false
    property string snappingCircleType:    ""
    property int    snappingCircleItemIdx: -1
    property int    snappingCircleNodeId:  -1
    property real   snappingFromX:         0   // stage coords
    property real   snappingFromY:         0
    property real   snappingProgress:      0.0
    onSnappingProgressChanged: { if (snappingCircle) requestRedraw() }

    NumberAnimation {
        id: snapCircleAnim
        target: root
        property: "snappingProgress"
        from: 0.0; to: 1.0
        duration: 280
        easing.type: Easing.OutCubic
        onFinished: { root.snappingCircle = false; root.requestRedraw() }
    }

    // Removes orbit circles belonging to a deleted list item and shifts down higher indices.
    function removeOrbitCirclesForItem(circleType, itemIdx) {
        for (var i = orbitsModel.count - 1; i >= 0; i--) {
            var o = orbitsModel.get(i)
            if (o.circleType === circleType) {
                if (o.itemIdx === itemIdx)
                    orbitsModel.remove(i)
                else if (o.itemIdx > itemIdx)
                    orbitsModel.setProperty(i, "itemIdx", o.itemIdx - 1)
            }
        }
        requestRedraw()
    }

    // Appends the circle to orbitsModel and plays the snap animation from (fromStageX, fromStageY).
    function startSnapAnimation(fromStageX, fromStageY, circleType, itemIdx, nodeId) {
        orbitsModel.append({ circleType: circleType, itemIdx: itemIdx, nodeId: nodeId })
        root.snappingCircle        = true
        root.snappingCircleType    = circleType
        root.snappingCircleItemIdx = itemIdx
        root.snappingCircleNodeId  = nodeId
        root.snappingFromX         = fromStageX
        root.snappingFromY         = fromStageY
        root.snappingProgress      = 0.0
        snapCircleAnim.restart()
    }
    property real nodeRadius: 16
    property int networkId: -1

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
    property bool timelineAreaHovered: timelineMouseArea.containsMouse || transportHoverHandler.hovered
    onTimelineAreaHoveredChanged: if (timelineAreaHovered) root.forceActiveFocus()

    onPixelsPerSecondChanged: timelineCanvas.requestPaint()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space && root.timelineAreaHovered) {
            root.isPlaying = !root.isPlaying
            event.accepted = true
        }
    }

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
    property real wobbleClickX: 0.0
    property real wobbleClickY: 0.0

    // link snap (retract) state — runs after wobble completes
    property bool snapping: false
    property int snappingLinkIndex: -1
    property real snapProgress: 0.0
    property real snapX: 0.0
    property real snapY: 0.0
    property real snapAX: 0.0
    property real snapAY: 0.0
    property real snapBX: 0.0
    property real snapBY: 0.0

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
                // Record node screen positions for the snap animation
                var lnk = linksModel.get(toDelete);
                var nA = nodesModel.get(lnk.a);
                var nB = nodesModel.get(lnk.b);
                root.snapAX = nA.x * root.zoom + root.panX;
                root.snapAY = nA.y * root.zoom + root.panY;
                root.snapBX = nB.x * root.zoom + root.panX;
                root.snapBY = nB.y * root.zoom + root.panY;
                root.snapX = root.wobbleClickX;
                root.snapY = root.wobbleClickY;
                root.snappingLinkIndex = toDelete;
                root.snapProgress = 0.0;
                root.snapping = true;
                root.cancelWobble();
                // Deletion happens in snapTimer once retraction completes
            } else {
                root.requestRedraw();
            }
        }
    }

    Timer {
        id: snapTimer
        interval: 16
        repeat: true
        running: root.snapping
        onTriggered: {
            root.snapProgress += 16.0 / 250.0;
            if (root.snapProgress >= 1.0) {
                var toDelete = root.snappingLinkIndex;
                root.snapping = false;
                root.snappingLinkIndex = -1;
                root.snapProgress = 0.0;
                root.deleteLink(toDelete);
            } else {
                root.requestRedraw();
            }
        }
    }

    // ------------------------------------------------------------------ persistence

    Connections {
        target: storyManager
        function onStoryOpened() {
            var netId = storyManager.ensureDefaultNetwork()
            var nets = storyManager.getNetworks()
            networksModel.clear()
            for (var i = 0; i < nets.length; i++)
                networksModel.append({ netId: nets[i].id, netName: nets[i].name, netColor: nets[i].color })
            root.networkId = netId
            root.loadFromDb(netId)
        }
    }

    function collectNetworkData() {
        var nodes = []
        for (var i = 0; i < nodesModel.count; i++) {
            var n = nodesModel.get(i)
            nodes.push({ id: n.id, x: n.x, y: n.y, name: n.name, nodeColor: n.nodeColor })
        }
        var links = []
        for (var i = 0; i < linksModel.count; i++) {
            var l = linksModel.get(i)
            links.push({ a: l.a, b: l.b })
        }
        var characters = []
        for (var i = 0; i < charactersModel.count; i++) {
            var c = charactersModel.get(i)
            characters.push({ enabled: c.enabled, charName: c.charName, charRole: c.charRole, charImagePath: c.charImagePath })
        }
        var sounds = []
        for (var i = 0; i < soundsModel.count; i++) {
            var s = soundsModel.get(i)
            sounds.push({ enabled: s.enabled, soundName: s.soundName, filePath: s.filePath, soundType: s.soundType || "loop" })
        }
        var orbits = []
        for (var i = 0; i < orbitsModel.count; i++) {
            var o = orbitsModel.get(i)
            orbits.push({ circleType: o.circleType, itemIdx: o.itemIdx, nodeId: o.nodeId })
        }
        return JSON.stringify({
            nodes: nodes,
            links: links,
            characters: characters,
            sounds: sounds,
            orbits: orbits,
            zoom: root.zoom,
            panX: root.panX,
            panY: root.panY,
            nextNodeId: root.nextNodeId
        })
    }

    function saveToDb() {
        if (root.networkId !== -1)
            storyManager.saveNetworkData(root.networkId, root.collectNetworkData())
    }

    function loadFromDb(netId) {
        var raw = storyManager.loadNetworkData(netId)
        var data
        try { data = JSON.parse(raw) } catch(e) { data = {} }

        nodesModel.clear()
        linksModel.clear()
        charactersModel.clear()
        soundsModel.clear()
        orbitsModel.clear()

        var nodes = data.nodes || []
        for (var i = 0; i < nodes.length; i++)
            nodesModel.append(nodes[i])

        var links = data.links || []
        for (var i = 0; i < links.length; i++)
            linksModel.append(links[i])

        var chars = data.characters || []
        for (var i = 0; i < chars.length; i++)
            charactersModel.append(chars[i])

        var snds = data.sounds || []
        for (var i = 0; i < snds.length; i++)
            soundsModel.append(snds[i])

        var orbs = data.orbits || []
        for (var i = 0; i < orbs.length; i++)
            orbitsModel.append(orbs[i])

        root.zoom = (data.zoom !== undefined) ? data.zoom : 1.0
        root.panX = (data.panX !== undefined) ? data.panX : 0.0
        root.panY = (data.panY !== undefined) ? data.panY : 0.0
        root.nextNodeId = (data.nextNodeId !== undefined) ? data.nextNodeId : 0

        root.requestRedraw()
    }

    function switchToNetwork(newNetId) {
        if (newNetId === root.networkId) return
        root.saveToDb()
        root.networkId = newNetId
        root.loadFromDb(newNetId)
    }

    function renameActiveNetworkInModel(name) {
        if (root.networkId === -1) return
        storyManager.renameNetwork(root.networkId, name)
        for (var i = 0; i < networksModel.count; i++) {
            if (networksModel.get(i).netId === root.networkId) {
                networksModel.setProperty(i, "netName", name)
                break
            }
        }
    }

    function changeActiveNetworkColor(color) {
        if (root.networkId === -1) return
        storyManager.saveNetworkColor(root.networkId, color)
        for (var i = 0; i < networksModel.count; i++) {
            if (networksModel.get(i).netId === root.networkId) {
                networksModel.setProperty(i, "netColor", color)
                break
            }
        }
    }

    function deleteOrClearNetwork(netId, idx) {
        if (idx === 0) {
            // Index 0 is never deleted — just cleared back to blank state
            storyManager.renameNetwork(netId, "")
            storyManager.saveNetworkColor(netId, "#2e2e33")
            storyManager.saveNetworkData(netId, "{}")
            networksModel.setProperty(0, "netName", "")
            networksModel.setProperty(0, "netColor", "#2e2e33")
            if (root.networkId === netId) {
                nodesModel.clear(); linksModel.clear()
                charactersModel.clear(); soundsModel.clear()
                root.zoom = 1.0; root.panX = 0.0; root.panY = 0.0; root.nextNodeId = 0
                root.requestRedraw()
            }
        } else {
            var wasActive  = (root.networkId === netId)
            var fallbackId = networksModel.get(0).netId
            storyManager.deleteNetwork(netId)
            networksModel.remove(idx)
            if (wasActive) {
                root.networkId = fallbackId
                root.loadFromDb(fallbackId)
            }
        }
    }

    function createNewNetwork() {
        root.saveToDb()
        var newId = storyManager.createNetwork("")
        if (newId !== -1) {
            networksModel.append({ netId: newId, netName: "", netColor: "#2e2e33" })
            root.networkId = newId
            nodesModel.clear()
            linksModel.clear()
            charactersModel.clear()
            soundsModel.clear()
            root.zoom = 1.0
            root.panX = 0.0
            root.panY = 0.0
            root.nextNodeId = 0
            root.requestRedraw()
        }
    }

    // ------------------------------------------------------------------

    function requestRedraw() {
        canvas.requestPaint();
    }

    //
    // MODEL HELPERS
    //
    function addNode(x, y) {
        var defaultName = nextNodeId === 0 ? "place" : "place " + nextNodeId;
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

    function beginWobble(idx, clickX, clickY) {
        wobblingLinkIndex = idx;
        wobblePhase = 0;
        wobbleAmplitude = 0;
        wobbleClickX = clickX;
        wobbleClickY = clickY;
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

        // Remove any orbiting circles attached to this node
        var deletedNodeId = nodesModel.get(idx).id
        for (var oi = orbitsModel.count - 1; oi >= 0; oi--) {
            if (orbitsModel.get(oi).nodeId === deletedNodeId)
                orbitsModel.remove(oi)
        }

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

    // Returns the index of the node closest to (sceneX, sceneY) within maxDist scene-units, or -1.
    function findNearestNode(sceneX, sceneY, maxDist) {
        var best = -1
        var bestDist = maxDist
        for (var i = 0; i < nodesModel.count; i++) {
            var n = nodesModel.get(i)
            var dx = sceneX - n.x
            var dy = sceneY - n.y
            var dist = Math.sqrt(dx * dx + dy * dy)
            if (dist < bestDist) { bestDist = dist; best = i }
        }
        return best
    }

    // Returns the orbitsModel index whose drawn circle contains (stageX, stageY), or -1.
    // Uses the same geometry as the canvas onPaint orbit drawing.
    function findOrbitCircleAt(stageX, stageY) {
        for (var oi = 0; oi < orbitsModel.count; oi++) {
            var orb = orbitsModel.get(oi)
            var nodeIdx = -1
            for (var j = 0; j < nodesModel.count; j++) {
                if (nodesModel.get(j).id === orb.nodeId) { nodeIdx = j; break }
            }
            if (nodeIdx < 0) continue
            var nd  = nodesModel.get(nodeIdx)
            var nx  = nd.x * root.zoom + root.panX
            var ny  = nd.y * root.zoom + root.panY
            var orbCount = 0, orbPos = 0
            for (var k = 0; k < orbitsModel.count; k++) {
                if (orbitsModel.get(k).nodeId === orb.nodeId) {
                    if (k < oi) orbPos++
                    orbCount++
                }
            }
            var cr   = 10
            var step = 22
            var cx   = nx + (orbPos - (orbCount - 1) / 2.0) * step
            var cy   = ny + root.nodeRadius + 3 + cr
            cr = 14            // widen hit radius slightly
            var dx = stageX - cx
            var dy = stageY - cy
            if (dx * dx + dy * dy <= cr * cr) return oi
        }
        return -1
    }

    //
    // Left panel
    //
    Rectangle {
        id: leftPanel
        x: 0
        y: 0
        width: 360
        height: parent.height - 50
        color: "#151518"
        clip: true

        property string activeTab: "characters"
        property int activeDialogIndex: -1

        // Right border divider
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: "#2a2a30"
        }

        // Tab bar
        Row {
            id: tabBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36

            Repeater {
                model: ["characters", "sound"]
                delegate: Item {
                    width: leftPanel.width / 2
                    height: 36
                    property bool active: leftPanel.activeTab === modelData

                    Text {
                        text: modelData
                        color: parent.active ? "white" : "#555"
                        font.pixelSize: 12
                        anchors.centerIn: parent
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        color: parent.active ? "#5DA9A4" : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: leftPanel.activeTab = modelData
                    }
                }
            }
        }

        Rectangle {
            id: tabSeparator
            anchors.top: tabBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#2a2a30"
        }

        ListModel { id: charactersModel }
        ListModel { id: soundsModel }

        FileDialog {
            id: charImageFileDialog
            title: "Select character image"
            nameFilters: ["Image files (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg)"]
            onAccepted: {
                if (leftPanel.activeDialogIndex >= 0)
                    charactersModel.setProperty(leftPanel.activeDialogIndex, "charImagePath", selectedFile.toString())
            }
        }

        FileDialog {
            id: soundFileDialog
            title: "Select audio file"
            nameFilters: ["Audio files (*.mp3 *.wav *.ogg *.flac *.aac *.m4a *.opus *.wma)"]
            onAccepted: {
                if (leftPanel.activeDialogIndex >= 0)
                    soundsModel.setProperty(leftPanel.activeDialogIndex, "filePath", selectedFile.toString())
            }
        }

        Text {
            id: leftPanelHeading
            text: leftPanel.activeTab
            font.pixelSize: 24
            font.bold: true
            color: "white"
            anchors.top: tabSeparator.bottom
            anchors.topMargin: 20
            anchors.left: parent.left
            anchors.leftMargin: 20
        }

        //
        // Characters list
        //
        ScrollView {
            id: charsScrollView
            visible: leftPanel.activeTab === "characters"
            anchors.top: leftPanelHeading.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottomMargin: 8
            clip: true

            Column {
                width: charsScrollView.availableWidth
                spacing: 4

                Repeater {
                    model: charactersModel

                    delegate: Item {
                        id: charDelegate
                        width: parent.width
                        height: 26
                        property int idx: index
                        property bool on: model.enabled
                        property real deleteProgress: 0.0

                        NumberAnimation {
                            id: charDeleteAnim
                            target: charDelegate
                            property: "deleteProgress"
                            to: 1.0
                            duration: 1200
                            easing.type: Easing.Linear
                            onFinished: {
                                if (charDelegate.deleteProgress >= 1.0) {
                                    root.removeOrbitCirclesForItem("char", charDelegate.idx)
                                    charactersModel.remove(charDelegate.idx)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            z: 10
                            onPressed: mouse => {
                                charDelegate.deleteProgress = 0
                                charDeleteAnim.start()
                            }
                            onReleased: mouse => {
                                charDeleteAnim.stop()
                                charDelegate.deleteProgress = 0
                            }
                            onExited: {
                                charDeleteAnim.stop()
                                charDelegate.deleteProgress = 0
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "#ff4444"
                            opacity: charDelegate.deleteProgress * 0.75
                            visible: charDelegate.deleteProgress > 0
                            z: 9
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 4

                            // Toggle icon button
                            Item {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "transparent"
                                    border.color: charDelegate.on ? "white" : "#3a3a3a"
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Image {
                                        id: charIconImg
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: "icons/character.svg"
                                        fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: charIconImg
                                        source: charIconImg
                                        color: charDelegate.on ? "white" : "#555"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: charactersModel.setProperty(charDelegate.idx, "enabled", !model.enabled)
                                    }
                                }
                            }

                            // Name field
                            Rectangle {
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 26
                                color: "transparent"
                                border.color: charDelegate.on ? "white" : "#3a3a3a"
                                border.width: 1
                                radius: 4
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                TextInput {
                                    id: charNameInput
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: charDelegate.on ? "white" : "#666"
                                    font.pixelSize: 11
                                    clip: true
                                    selectByMouse: true
                                    text: model.charName
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: charactersModel.setProperty(charDelegate.idx, "charName", text)
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: "name"
                                    color: charDelegate.on ? "#60ffffff" : "#44666666"
                                    font.pixelSize: 11
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: charNameInput.text === "" && !charNameInput.activeFocus
                                }
                            }

                            // Role radio buttons
                            Item {
                                Layout.preferredWidth: roleRow.childrenRect.width
                                Layout.preferredHeight: 26

                                Row {
                                    id: roleRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Rectangle {
                                        id: performButton
                                        property bool isActive: model.charRole === "perform"
                                        width: performLabel.implicitWidth + 12
                                        height: 26
                                        radius: 4
                                        color: isActive ? (charDelegate.on ? "white" : "#666") : "transparent"
                                        border.color: charDelegate.on ? "white" : "#3a3a3a"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            id: performLabel
                                            anchors.centerIn: parent
                                            text: "perform"
                                            font.pixelSize: 9
                                            color: performButton.isActive ? (charDelegate.on ? "#477B78" : "#151518") : (charDelegate.on ? "white" : "#666")
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: if (charDelegate.on) charactersModel.setProperty(charDelegate.idx, "charRole", "perform")
                                        }
                                    }

                                    Rectangle {
                                        id: wildButton
                                        property bool isActive: model.charRole === "wild"
                                        width: wildLabel.implicitWidth + 12
                                        height: 26
                                        radius: 4
                                        color: isActive ? (charDelegate.on ? "white" : "#666") : "transparent"
                                        border.color: charDelegate.on ? "white" : "#3a3a3a"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            id: wildLabel
                                            anchors.centerIn: parent
                                            text: "wild"
                                            font.pixelSize: 9
                                            color: wildButton.isActive ? (charDelegate.on ? "#477B78" : "#151518") : (charDelegate.on ? "white" : "#666")
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: if (charDelegate.on) charactersModel.setProperty(charDelegate.idx, "charRole", "wild")
                                        }
                                    }
                                }
                            }

                            // Image drop zone
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                color: "black"
                                radius: 4

                                Image {
                                    id: dropCharImg
                                    anchors.centerIn: parent
                                    width: 28; height: 28
                                    source: "icons/dropimage.svg"
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: dropCharImg
                                    source: dropCharImg
                                    color: "#666"
                                    opacity: model.charImagePath ? 0.2 : 1.0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: model.charImagePath ? model.charImagePath.replace(/.*\//, "") : ""
                                    color: "white"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    visible: !!model.charImagePath
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        leftPanel.activeDialogIndex = charDelegate.idx
                                        charImageFileDialog.open()
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.hasUrls)
                                            charactersModel.setProperty(charDelegate.idx, "charImagePath", drop.urls[0].toString())
                                    }
                                }
                            }

                            // Character circle — drag onto a node to attach
                            Item {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26

                                property bool isBeingDragged: root.isDraggingCircle
                                    && root.draggingCircleType === "char"
                                    && root.draggingCircleItemIdx === charDelegate.idx
                                property bool isAttached: {
                                    var _ = orbitsModel.count
                                    for (var i = 0; i < orbitsModel.count; i++) {
                                        var o = orbitsModel.get(i)
                                        if (o.circleType === "char" && o.itemIdx === charDelegate.idx) return true
                                    }
                                    return false
                                }

                                // Grey placeholder dot — always present underneath
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 7
                                    color: "#2a2a30"
                                    border.color: "#3a3a40"
                                    border.width: 1
                                }

                                // White circle (visual only)
                                Rectangle {
                                    id: charListCircle
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "white"
                                    visible: !parent.isAttached && !parent.isBeingDragged
                                    clip: true
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: charListCircle.width
                                            height: charListCircle.height
                                            radius: charListCircle.radius
                                        }
                                    }

                                    Image {
                                        anchors.fill: parent
                                        source: model.charImagePath || ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: !!model.charImagePath
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: (model.charName || "").charAt(0).toUpperCase()
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#1a1a1d"
                                        visible: !model.charImagePath
                                    }
                                }

                                // MouseArea on the outer Item — never hidden, retains capture
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !parent.isAttached
                                    onPressed: mouse => {
                                        var pos = mapToItem(root, mouse.x, mouse.y)
                                        root.isDraggingCircle      = true
                                        root.draggingCircleType    = "char"
                                        root.draggingCircleItemIdx = charDelegate.idx
                                        root.draggingCircleLabel   = (model.charName || "").charAt(0).toUpperCase()
                                        root.draggingCircleImage   = model.charImagePath || ""
                                        root.draggingCircleX       = pos.x
                                        root.draggingCircleY       = pos.y
                                        mouse.accepted = true
                                    }
                                    onPositionChanged: mouse => {
                                        if (root.isDraggingCircle) {
                                            var pos = mapToItem(root, mouse.x, mouse.y)
                                            root.draggingCircleX = pos.x
                                            root.draggingCircleY = pos.y
                                        }
                                    }
                                    onReleased: mouse => {
                                        if (root.isDraggingCircle) {
                                            var stageX  = root.draggingCircleX - stage.x
                                            var stageY  = root.draggingCircleY - stage.y
                                            var sceneX  = (stageX - root.panX) / root.zoom
                                            var sceneY  = (stageY - root.panY) / root.zoom
                                            var nearest = root.findNearestNode(sceneX, sceneY, 80)
                                            root.isDraggingCircle = false
                                            if (nearest >= 0)
                                                root.startSnapAnimation(stageX, stageY, "char", charDelegate.idx, nodesModel.get(nearest).id)
                                        }
                                    }
                                }
                            }

                        }
                    }
                }

                Item { width: parent.width; height: 4 }

                Item {
                    width: parent.width
                    height: 26
                    property bool hovered: false

                    Rectangle {
                        width: 26
                        height: 26
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        radius: 4
                        color: parent.hovered ? "white" : "transparent"
                        border.color: "white"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 0; anchors.horizontalCenterOffset: -0.5
                            text: "+"
                            font.pixelSize: 18
                            font.bold: true
                            color: parent.parent.hovered ? "darkslategrey" : "white"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                        onClicked: charactersModel.append({ enabled: true, charName: "", charRole: "perform", charImagePath: "" })
                    }
                }
            }
        }

        //
        // Sound list
        //
        ScrollView {
            id: soundsScrollView
            visible: leftPanel.activeTab === "sound"
            anchors.top: leftPanelHeading.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottomMargin: 8
            clip: true

            Column {
                width: soundsScrollView.availableWidth
                spacing: 4

                Repeater {
                    model: soundsModel

                    delegate: Item {
                        id: soundDelegate
                        width: parent.width
                        height: 26
                        property int idx: index
                        property bool on: model.enabled
                        property real deleteProgress: 0.0

                        NumberAnimation {
                            id: soundDeleteAnim
                            target: soundDelegate
                            property: "deleteProgress"
                            to: 1.0
                            duration: 1200
                            easing.type: Easing.Linear
                            onFinished: {
                                if (soundDelegate.deleteProgress >= 1.0) {
                                    root.removeOrbitCirclesForItem("sound", soundDelegate.idx)
                                    soundsModel.remove(soundDelegate.idx)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            z: 10
                            onPressed: mouse => {
                                soundDelegate.deleteProgress = 0
                                soundDeleteAnim.start()
                            }
                            onReleased: mouse => {
                                soundDeleteAnim.stop()
                                soundDelegate.deleteProgress = 0
                            }
                            onExited: {
                                soundDeleteAnim.stop()
                                soundDelegate.deleteProgress = 0
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "#ff4444"
                            opacity: soundDelegate.deleteProgress * 0.75
                            visible: soundDelegate.deleteProgress > 0
                            z: 9
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 4

                            // Toggle icon button
                            Item {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "transparent"
                                    border.color: soundDelegate.on ? "white" : "#3a3a3a"
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    Image {
                                        id: soundIconImg
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: "icons/sound.svg"
                                        fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: soundIconImg
                                        source: soundIconImg
                                        color: soundDelegate.on ? "white" : "#555"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: soundsModel.setProperty(soundDelegate.idx, "enabled", !model.enabled)
                                    }
                                }
                            }

                            // Name field
                            Rectangle {
                                Layout.preferredWidth: 90
                                Layout.preferredHeight: 26
                                color: "transparent"
                                border.color: soundDelegate.on ? "white" : "#3a3a3a"
                                border.width: 1
                                radius: 4
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                TextInput {
                                    id: soundNameInput
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: soundDelegate.on ? "white" : "#666"
                                    font.pixelSize: 11
                                    clip: true
                                    selectByMouse: true
                                    text: model.soundName
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: soundsModel.setProperty(soundDelegate.idx, "soundName", text)
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                Text {
                                    text: "name"
                                    color: soundDelegate.on ? "#60ffffff" : "#44666666"
                                    font.pixelSize: 11
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: soundNameInput.text === "" && !soundNameInput.activeFocus
                                }
                            }


                            // Sound type toggle buttons
                            Item {
                                Layout.preferredWidth: soundTypeRow.childrenRect.width
                                Layout.preferredHeight: 26

                                Row {
                                    id: soundTypeRow
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Rectangle {
                                        id: loopButton
                                        property bool isActive: (model.soundType || "loop") === "loop"
                                        width: loopLabel.implicitWidth + 12
                                        height: 26
                                        radius: 4
                                        color: isActive ? (soundDelegate.on ? "white" : "#666") : "transparent"
                                        border.color: soundDelegate.on ? "white" : "#3a3a3a"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            id: loopLabel
                                            anchors.centerIn: parent
                                            text: "loop"
                                            font.pixelSize: 9
                                            color: loopButton.isActive ? (soundDelegate.on ? "#477B78" : "#151518") : (soundDelegate.on ? "white" : "#666")
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: if (soundDelegate.on) soundsModel.setProperty(soundDelegate.idx, "soundType", "loop")
                                        }
                                    }

                                    Rectangle {
                                        id: syncButton
                                        property bool isActive: model.soundType === "sync"
                                        width: syncLabel.implicitWidth + 12
                                        height: 26
                                        radius: 4
                                        color: isActive ? (soundDelegate.on ? "white" : "#666") : "transparent"
                                        border.color: soundDelegate.on ? "white" : "#3a3a3a"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            id: syncLabel
                                            anchors.centerIn: parent
                                            text: "sync"
                                            font.pixelSize: 9
                                            color: syncButton.isActive ? (soundDelegate.on ? "#477B78" : "#151518") : (soundDelegate.on ? "white" : "#666")
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: if (soundDelegate.on) soundsModel.setProperty(soundDelegate.idx, "soundType", "sync")
                                        }
                                    }
                                }
                            }
                            // File drop zone
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                color: "black"
                                radius: 4

                                Image {
                                    id: dropSoundImg
                                    anchors.centerIn: parent
                                    width: 28; height: 28
                                    source: "icons/dropsound.svg"
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: dropSoundImg
                                    source: dropSoundImg
                                    color: "#666"
                                    opacity: model.filePath ? 0.2 : 1.0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: model.filePath ? model.filePath.replace(/.*\//, "") : ""
                                    color: "white"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    visible: !!model.filePath
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        leftPanel.activeDialogIndex = soundDelegate.idx
                                        soundFileDialog.open()
                                    }
                                }

                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.hasUrls)
                                            soundsModel.setProperty(soundDelegate.idx, "filePath", drop.urls[0].toString())
                                    }
                                }
                            }

                            // Sound circle — drag onto a node to attach
                            Item {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26

                                property bool isBeingDragged: root.isDraggingCircle
                                    && root.draggingCircleType === "sound"
                                    && root.draggingCircleItemIdx === soundDelegate.idx
                                property bool isAttached: {
                                    var _ = orbitsModel.count
                                    for (var i = 0; i < orbitsModel.count; i++) {
                                        var o = orbitsModel.get(i)
                                        if (o.circleType === "sound" && o.itemIdx === soundDelegate.idx) return true
                                    }
                                    return false
                                }

                                // Grey placeholder dot
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 14; height: 14; radius: 7
                                    color: "#2a2a30"
                                    border.color: "#3a3a40"
                                    border.width: 1
                                }

                                // White circle (visual only)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "white"
                                    visible: !parent.isAttached && !parent.isBeingDragged

                                    Text {
                                        anchors.centerIn: parent
                                        text: (model.soundName || "").charAt(0).toUpperCase()
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#1a1a1d"
                                    }
                                }

                                // MouseArea on the outer Item — never hidden, retains capture
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !parent.isAttached
                                    onPressed: mouse => {
                                        var pos = mapToItem(root, mouse.x, mouse.y)
                                        root.isDraggingCircle      = true
                                        root.draggingCircleType    = "sound"
                                        root.draggingCircleItemIdx = soundDelegate.idx
                                        root.draggingCircleLabel   = (model.soundName || "").charAt(0).toUpperCase()
                                        root.draggingCircleX       = pos.x
                                        root.draggingCircleY       = pos.y
                                        mouse.accepted = true
                                    }
                                    onPositionChanged: mouse => {
                                        if (root.isDraggingCircle) {
                                            var pos = mapToItem(root, mouse.x, mouse.y)
                                            root.draggingCircleX = pos.x
                                            root.draggingCircleY = pos.y
                                        }
                                    }
                                    onReleased: mouse => {
                                        if (root.isDraggingCircle) {
                                            var stageX  = root.draggingCircleX - stage.x
                                            var stageY  = root.draggingCircleY - stage.y
                                            var sceneX  = (stageX - root.panX) / root.zoom
                                            var sceneY  = (stageY - root.panY) / root.zoom
                                            var nearest = root.findNearestNode(sceneX, sceneY, 80)
                                            root.isDraggingCircle = false
                                            if (nearest >= 0)
                                                root.startSnapAnimation(stageX, stageY, "sound", soundDelegate.idx, nodesModel.get(nearest).id)
                                        }
                                    }
                                }
                            }

                        }
                    }
                }

                Item { width: parent.width; height: 4 }

                Item {
                    width: parent.width
                    height: 26
                    property bool hovered: false

                    Rectangle {
                        width: 26
                        height: 26
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        radius: 4
                        color: parent.hovered ? "white" : "transparent"
                        border.color: "white"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 0; anchors.horizontalCenterOffset: -0.5
                            text: "+"
                            font.pixelSize: 18
                            font.bold: true
                            color: parent.parent.hovered ? "darkslategrey" : "white"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                        onClicked: soundsModel.append({ enabled: true, soundName: "", filePath: "", soundType: "loop" })
                    }
                }
            }
        }
    }

    Rectangle {
        id: stage
        x: 360
        y: 0
        width: parent.width - 360
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
                            root.beginWobble(hitLink, mouse.x, mouse.y);
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
                    if (i === root.snappingLinkIndex) continue; // drawn separately as retraction stubs
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
                            var pr = Math.floor(0x99 + dangerFactor * (0xff - 0x99));
                            var pg = Math.floor(0xaa + dangerFactor * (0x44 - 0xaa));
                            var pb = Math.floor(0xff + dangerFactor * (0x44 - 0xff));
                            ctx.strokeStyle = "rgb(" + pr + "," + pg + "," + pb + ")";
                            ctx.lineWidth = 2 + dangerFactor * 1;
                        } else {
                            ctx.moveTo(ax, ay);
                            ctx.lineTo(bx, by);
                            ctx.strokeStyle = "#99aaff";
                            ctx.lineWidth = 2;
                        }

                        ctx.stroke();
                    }
                }

                // draw snap retraction stubs
                if (root.snapping) {
                    var eased = 1.0 - Math.pow(1.0 - root.snapProgress, 2.0); // ease-out: fast start, decelerates into nodes
                    ctx.strokeStyle = "#ff4444";
                    ctx.lineWidth = 2;
                    // Stub A: tip starts at snap point, retracts toward node A
                    var tipAX = root.snapX + (root.snapAX - root.snapX) * eased;
                    var tipAY = root.snapY + (root.snapAY - root.snapY) * eased;
                    ctx.beginPath();
                    ctx.moveTo(root.snapAX, root.snapAY);
                    ctx.lineTo(tipAX, tipAY);
                    ctx.stroke();
                    // Stub B: tip starts at snap point, retracts toward node B
                    var tipBX = root.snapX + (root.snapBX - root.snapX) * eased;
                    var tipBY = root.snapY + (root.snapBY - root.snapY) * eased;
                    ctx.beginPath();
                    ctx.moveTo(root.snapBX, root.snapBY);
                    ctx.lineTo(tipBX, tipBY);
                    ctx.stroke();
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



        // Orbit circles layer
        Repeater {
            model: orbitsModel
            delegate: Item {
                id: orbDelegate
                z: 1
                
                property var nodeModelItem: {
                    for (var i = 0; i < nodesModel.count; i++) {
                        if (nodesModel.get(i).id === model.nodeId) return nodesModel.get(i)
                    }
                    return null
                }
                property int orbPos: {
                    var count = 0
                    for (var i = 0; i < index; i++) {
                        if (orbitsModel.get(i).nodeId === model.nodeId) count++
                    }
                    return count
                }
                property int orbCount: {
                    var count = 0
                    for (var i = 0; i < orbitsModel.count; i++) {
                        if (orbitsModel.get(i).nodeId === model.nodeId) count++
                    }
                    return count
                }
                
                property real cr: 10
                property real step: 22
                
                visible: nodeModelItem !== null
                         && !(root.isDraggingCircle && model.circleType === root.draggingCircleType && model.itemIdx === root.draggingCircleItemIdx)
                         && !(root.snappingCircle && model.circleType === root.snappingCircleType && model.itemIdx === root.snappingCircleItemIdx)

                x: nodeModelItem ? (nodeModelItem.x * root.zoom + root.panX + (orbPos - (orbCount - 1) / 2.0) * step - cr) : 0
                y: nodeModelItem ? (nodeModelItem.y * root.zoom + root.panY + root.nodeRadius + 3) : 0
                width: cr * 2
                height: cr * 2

                Rectangle {
                    id: orbInnerCircle
                    anchors.fill: parent
                    radius: width / 2
                    color: "white"
                    clip: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: orbInnerCircle.width
                            height: orbInnerCircle.height
                            radius: orbInnerCircle.radius
                        }
                    }
                    
                    Image {
                        anchors.fill: parent
                        source: (model.circleType === "char" && model.itemIdx >= 0 && model.itemIdx < charactersModel.count) 
                                ? (charactersModel.get(model.itemIdx).charImagePath || "") 
                                : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: !!source.toString()
                    }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (model.circleType === "char" && model.itemIdx >= 0 && model.itemIdx < charactersModel.count) {
                                var c = charactersModel.get(model.itemIdx)
                                return c ? (c.charName || "").charAt(0).toUpperCase() : ""
                            } else if (model.circleType === "sound" && model.itemIdx >= 0 && model.itemIdx < soundsModel.count) {
                                var s = soundsModel.get(model.itemIdx)
                                return s ? (s.soundName || "").charAt(0).toUpperCase() : ""
                            }
                            return ""
                        }
                        font.pixelSize: 10
                        font.bold: true
                        color: "#1a1a1d"
                        visible: (model.circleType === "sound") || (model.circleType === "char" && (model.itemIdx < 0 || model.itemIdx >= charactersModel.count || !charactersModel.get(model.itemIdx) || !charactersModel.get(model.itemIdx).charImagePath))
                    }
                }
            }
        }

        // Snap animation circle
        Item {
            id: snappingCircleItem
            z: 1
            visible: root.snappingCircle
            
            property var snapOrb: {
                if (!root.snappingCircle) return null
                for (var i = 0; i < orbitsModel.count; i++) {
                    var o = orbitsModel.get(i)
                    if (o.circleType === root.snappingCircleType && o.itemIdx === root.snappingCircleItemIdx) return { orb: o, idx: i }
                }
                return null
            }
            
            property var nodeModelItem: {
                if (!snapOrb) return null
                for (var i = 0; i < nodesModel.count; i++) {
                    if (nodesModel.get(i).id === snapOrb.orb.nodeId) return nodesModel.get(i)
                }
                return null
            }
            
            property int sPos: {
                if (!snapOrb) return 0
                var count = 0
                for (var i = 0; i < snapOrb.idx; i++) {
                    if (orbitsModel.get(i).nodeId === snapOrb.orb.nodeId) count++
                }
                return count
            }
            
            property int sCount: {
                if (!snapOrb) return 0
                var count = 0
                for (var i = 0; i < orbitsModel.count; i++) {
                    if (orbitsModel.get(i).nodeId === snapOrb.orb.nodeId) count++
                }
                return count
            }

            property real scr: 10
            property real sStep: 22
            
            property real tgtX: nodeModelItem ? (nodeModelItem.x * root.zoom + root.panX + (sPos - (sCount - 1) / 2.0) * sStep) : 0
            property real tgtY: nodeModelItem ? (nodeModelItem.y * root.zoom + root.panY + root.nodeRadius + 3 + scr) : 0
            
            x: root.snappingFromX + (tgtX - root.snappingFromX) * root.snappingProgress - width / 2
            y: root.snappingFromY + (tgtY - root.snappingFromY) * root.snappingProgress - height / 2
            width: scr * 2
            height: scr * 2
            
            Rectangle {
                id: snapInnerCircle
                anchors.fill: parent
                radius: width / 2
                color: "white"
                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: snapInnerCircle.width
                        height: snapInnerCircle.height
                        radius: snapInnerCircle.radius
                    }
                }
                
                Image {
                    anchors.fill: parent
                    source: (root.snappingCircleType === "char" && root.snappingCircleItemIdx >= 0 && root.snappingCircleItemIdx < charactersModel.count) 
                            ? (charactersModel.get(root.snappingCircleItemIdx).charImagePath || "") 
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: !!source.toString()
                }

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (root.snappingCircleType === "char" && root.snappingCircleItemIdx >= 0 && root.snappingCircleItemIdx < charactersModel.count) {
                            var c = charactersModel.get(root.snappingCircleItemIdx)
                            return c ? (c.charName || "").charAt(0).toUpperCase() : ""
                        } else if (root.snappingCircleType === "sound" && root.snappingCircleItemIdx >= 0 && root.snappingCircleItemIdx < soundsModel.count) {
                            var s = soundsModel.get(root.snappingCircleItemIdx)
                            return s ? (s.soundName || "").charAt(0).toUpperCase() : ""
                        }
                        return ""
                    }
                    font.pixelSize: Math.max(7, Math.round(10 * root.zoom))
                    font.bold: true
                    color: "#1a1a1d"
                    visible: (root.snappingCircleType === "sound") || (root.snappingCircleType === "char") && (root.snappingCircleItemIdx < 0 || root.snappingCircleItemIdx >= charactersModel.count || !charactersModel.get(root.snappingCircleItemIdx) || !charactersModel.get(root.snappingCircleItemIdx).charImagePath)
                }
            }
        }        //
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

        // LAYER 3: orbit circle drag — must be above nodes (z:2) so it gets first pick,
        // but sets mouse.accepted = false for non-orbit presses so NodeItems still work.
        // IMPORTANT: we do NOT mutate orbitsModel during onPressed — doing so disrupts
        // the mouse grab. We record the index and defer the remove/append to onReleased.
        MouseArea {
            anchors.fill: parent
            z: 3
            acceptedButtons: Qt.LeftButton
            property bool draggingFromCanvas: false
            property int  draggingOrbitIdx:   -1

            onPressed: mouse => {
                var hitIdx = root.findOrbitCircleAt(mouse.x, mouse.y)
                if (hitIdx < 0) { mouse.accepted = false; return }

                var orb   = orbitsModel.get(hitIdx)
                var label = "", img = ""
                if (orb.circleType === "char" && orb.itemIdx >= 0 && orb.itemIdx < charactersModel.count) {
                    var c = charactersModel.get(orb.itemIdx)
                    label = (c.charName || "").charAt(0).toUpperCase()
                    img = c.charImagePath || ""
                } else if (orb.circleType === "sound" && orb.itemIdx < soundsModel.count) {
                    label = (soundsModel.get(orb.itemIdx).soundName || "").charAt(0).toUpperCase()
                }

                // Record orbit; canvas onPaint will skip drawing it so the floating circle
                // takes over visually. orbitsModel is NOT mutated here.
                draggingOrbitIdx           = hitIdx
                draggingFromCanvas         = true

                var pos = mapToItem(root, mouse.x, mouse.y)
                root.isDraggingCircle      = true
                root.draggingCircleType    = orb.circleType
                root.draggingCircleItemIdx = orb.itemIdx
                root.draggingCircleLabel   = label
                root.draggingCircleImage   = img
                root.draggingCircleX       = pos.x
                root.draggingCircleY       = pos.y
                root.requestRedraw()
                mouse.accepted             = true
            }

            onPositionChanged: mouse => {
                if (draggingFromCanvas) {
                    var pos = mapToItem(root, mouse.x, mouse.y)
                    root.draggingCircleX = pos.x
                    root.draggingCircleY = pos.y
                }
            }

            onReleased: mouse => {
                if (draggingFromCanvas) {
                    // Now it's safe to mutate the model
                    var idx = draggingOrbitIdx
                    if (idx >= 0 && idx < orbitsModel.count) {
                        var ct  = orbitsModel.get(idx).circleType
                        var ii  = orbitsModel.get(idx).itemIdx
                        orbitsModel.remove(idx)
                        var sceneX  = (mouse.x - root.panX) / root.zoom
                        var sceneY  = (mouse.y - root.panY) / root.zoom
                        var nearest = root.findNearestNode(sceneX, sceneY, 80)
                        root.isDraggingCircle = false
                        if (nearest >= 0) {
                            root.startSnapAnimation(mouse.x, mouse.y, ct, ii, nodesModel.get(nearest).id)
                        } else {
                            root.requestRedraw()
                        }
                    } else {
                        root.isDraggingCircle = false
                    }
                    draggingFromCanvas = false
                    draggingOrbitIdx   = -1
                }
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

        PinchArea {
            anchors.fill: parent

            property real startPps: root.pixelsPerSecond
            property real startOffset: root.timelineScrollOffset

            onPinchStarted: {
                startPps = root.pixelsPerSecond
                startOffset = root.timelineScrollOffset
            }

            onPinchUpdated: pinch => {
                var newPps = Math.max(10, Math.min(startPps * pinch.scale, 500))
                var centerTime = (pinch.center.x + startOffset) / startPps
                root.pixelsPerSecond = newPps
                root.timelineScrollOffset = Math.max(0, centerTime * newPps - pinch.center.x)
            }

            MouseArea {
                id: timelineMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.draggingPlayhead || root.playheadHovered) ? Qt.SizeHorCursor : Qt.ArrowCursor

                function nearPlayhead(mouseX) {
                    var playheadX = root.playheadTime * root.pixelsPerSecond - root.timelineScrollOffset
                    return Math.abs(mouseX - playheadX) <= 8
                }

                onExited: {
                    root.playheadHovered = false
                    timelineCanvas.requestPaint()
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

        HoverHandler {
            id: transportHoverHandler
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

    // ------------------------------------------------------------------ Network switcher bar
    //
    // Lives at root level (not inside stage) so its color-ring Canvas can
    // overflow without being clipped by stage's clip:true.
    //
    // Normally sits flush with the showAll button (8px from top, 8px from
    // the left-panel edge).  When a network button enters edit mode the
    // whole bar floats: 20px down (ring clears the NodeWorkspace top edge)
    // and 12px right (ring clears the left-panel right edge), then slides
    // back when editing ends.
    //
    Item {
        id: networkBar

        // Float from rest position (8,8) to editing position (20,28)
        property bool anyEditing: false
        x: anyEditing ? leftPanel.width + 20 : leftPanel.width + 8
        y: anyEditing ? 28 : 8
        z: 20

        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            id: networkBtnRow
            spacing: 4

            Repeater {
                id: networkBtnRepeater
                model: networksModel

                delegate: Item {
                    id: netBtn

                    property bool isActive:  model.netId === root.networkId
                    property bool editMode:  false
                    property bool isEditing: isActive && editMode
                    property bool isHovered: false

                    // Float the whole bar when this button enters edit mode
                    onEditModeChanged: networkBar.anyEditing = editMode

                    // Raise above the "+" button so the ring canvas renders in front of it
                    z: isEditing ? 1 : 0

                    // ── Computed style helpers ───────────────────────────────────
                    // Active with default dark color → show white fill (like tool palette).
                    // Active with custom color → show that color.
                    // Inactive → transparent.
                    property string fillColor: {
                        if (!isActive) return "transparent"
                        return model.netColor !== "#2e2e33" ? model.netColor : "white"
                    }
                    // Content (icon / text) color derived from actual fill luminance.
                    property string contentColor: {
                        if (!isActive) return model.netColor !== "#2e2e33" ? model.netColor : "white"
                        var fill = model.netColor !== "#2e2e33" ? model.netColor : "white"
                        var c = Qt.color(fill)
                        var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
                        return lum > 0.5 ? "#1a1a1d" : "white"
                    }

                    // ── Right-click-hold delete ──────────────────────────────────
                    property real deleteProgress: 0.0

                    NumberAnimation {
                        id: deleteAnim
                        target: netBtn
                        property: "deleteProgress"
                        to: 1.0
                        duration: 1200
                        easing.type: Easing.Linear
                        onFinished: {
                            if (netBtn.deleteProgress >= 1.0)
                                root.deleteOrClearNetwork(model.netId, index)
                        }
                    }

                    // ── Size helpers ─────────────────────────────────────────────
                    Text {
                        id: netNameMeasure
                        visible: false
                        text: model.netName
                        font.pixelSize: 12
                    }

                    property real labelW: Math.max(36, netNameMeasure.contentWidth + 24)

                    width:  isEditing ? Math.max(80, labelW) : (model.netName !== "" ? labelW : 36)
                    height: 36

                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    // ── Color wheel ring ─────────────────────────────────────────
                    Canvas {
                        id: netColorRing
                        x: -20; y: -20
                        width:  netBtn.width  + 40
                        height: netBtn.height + 40
                        z: -1
                        opacity: netBtn.isEditing ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                        onWidthChanged:  requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            var cw = width, ch = height
                            ctx.beginPath()
                            var rOut = ch / 2
                            ctx.moveTo(rOut, 0); ctx.lineTo(cw - rOut, 0)
                            ctx.arc(cw - rOut, rOut, rOut, -Math.PI / 2, 0)
                            ctx.lineTo(cw, ch - rOut)
                            ctx.arc(cw - rOut, ch - rOut, rOut, 0, Math.PI / 2)
                            ctx.lineTo(rOut, ch)
                            ctx.arc(rOut, ch - rOut, rOut, Math.PI / 2, Math.PI)
                            ctx.lineTo(0, rOut)
                            ctx.arc(rOut, rOut, rOut, Math.PI, -Math.PI / 2)
                            var ix = 16, iy = 16
                            var iw = cw - 32, ih = ch - 32, rIn = ih / 2
                            ctx.moveTo(ix + rIn, iy)
                            ctx.arc(ix + rIn, iy + rIn, rIn, -Math.PI / 2, Math.PI, true)
                            ctx.lineTo(ix, iy + ih - rIn)
                            ctx.arc(ix + rIn, iy + ih - rIn, rIn, Math.PI, Math.PI / 2, true)
                            ctx.lineTo(ix + iw - rIn, iy + ih)
                            ctx.arc(ix + iw - rIn, iy + ih - rIn, rIn, Math.PI / 2, 0, true)
                            ctx.lineTo(ix + iw, iy + rIn)
                            ctx.arc(ix + iw - rIn, iy + rIn, rIn, 0, -Math.PI / 2, true)
                            ctx.closePath(); ctx.clip()
                            var cx = cw / 2, cy = ch / 2, maxR = Math.max(cw, ch)
                            ctx.translate(cx, cy)
                            for (var i = 0; i < 360; i += 3) {
                                ctx.beginPath(); ctx.moveTo(0, 0)
                                ctx.lineTo(maxR * Math.cos(i * Math.PI / 180),
                                           maxR * Math.sin(i * Math.PI / 180))
                                ctx.lineTo(maxR * Math.cos((i + 3.5) * Math.PI / 180),
                                           maxR * Math.sin((i + 3.5) * Math.PI / 180))
                                ctx.closePath()
                                ctx.fillStyle = "hsl(" + i + ", 100%, 50%)"
                                ctx.fill()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: netBtn.isEditing
                            acceptedButtons: Qt.LeftButton
                            onClicked: mouse => {
                                var cx = width / 2, cy = height / 2
                                var angle = Math.atan2(mouse.y - cy, mouse.x - cx) * 180 / Math.PI
                                if (angle < 0) angle += 360
                                root.changeActiveNetworkColor(
                                    Qt.hsla(angle / 360.0, 1.0, 0.5, 1.0).toString())
                            }
                        }
                    }

                    // ── Button background ────────────────────────────────────────
                    Rectangle {
                        id: netBtnBg
                        anchors.fill: parent
                        radius: 12
                        color: netBtn.fillColor
                        // Border bleeds toward red as deleteProgress increases
                        border.width: 2
                        border.color: netBtn.deleteProgress > 0
                            ? Qt.rgba(1, 1 - netBtn.deleteProgress, 1 - netBtn.deleteProgress, 1)
                            : (netBtn.isHovered ? "#80cfff" : "white")
                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 80  } }
                    }

                    // ── Delete-progress red overlay ──────────────────────────────
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "#ff4444"
                        opacity: netBtn.deleteProgress * 0.75
                        visible: netBtn.deleteProgress > 0
                    }

                    // ── Icon (unnamed, not editing) ──────────────────────────────
                    Image {
                        id: netIcon
                        anchors.centerIn: parent
                        width: 22; height: 22
                        fillMode: Image.PreserveAspectFit
                        source: "icons/nodenetwork.svg"
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: netIcon
                        source: netIcon
                        visible: model.netName === "" && !netBtn.isEditing
                        color: netBtn.contentColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    // ── Name label (named, not editing) ─────────────────────────
                    Text {
                        id: netNameLabel
                        anchors.centerIn: parent
                        text: model.netName
                        font.pixelSize: 12
                        visible: model.netName !== "" && !netBtn.isEditing
                        color: netBtn.contentColor
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    // ── Name text input (editing) ────────────────────────────────
                    TextInput {
                        id: netNameEdit
                        anchors.centerIn: parent
                        text: model.netName
                        font.pixelSize: 12
                        color: netBtn.contentColor
                        visible: netBtn.isEditing
                        enabled: netBtn.isEditing
                        selectByMouse: true
                        horizontalAlignment: TextInput.AlignHCenter
                        Keys.onReturnPressed: focus = false
                        Keys.onEscapePressed: { netBtn.editMode = false; focus = false }
                        onEditingFinished: {
                            root.renameActiveNetworkInModel(text)
                            netBtn.editMode = false
                        }
                    }

                    // ── Interaction ──────────────────────────────────────────────
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: netBtn.isHovered = true
                        onExited: {
                            netBtn.isHovered = false
                            // Cancel any in-progress delete if cursor leaves
                            deleteAnim.stop()
                            netBtn.deleteProgress = 0
                        }
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                netBtn.deleteProgress = 0
                                deleteAnim.start()
                                mouse.accepted = true
                            }
                        }
                        onReleased: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                deleteAnim.stop()
                                netBtn.deleteProgress = 0
                            }
                        }
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton && !netBtn.isActive)
                                root.switchToNetwork(model.netId)
                        }
                        onDoubleClicked: mouse => {
                            if (mouse.button === Qt.LeftButton
                                    && netBtn.isActive && !netBtn.editMode) {
                                netBtn.editMode = true
                                netNameEdit.forceActiveFocus()
                                netNameEdit.selectAll()
                            }
                        }
                    }
                }
            }

            // ── "+" button — add a new node network ──────────────────────────
            Item {
                id: addNetworkBtn
                width: 36; height: 36
                property bool isHovered: false

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: "transparent"
                    border.width: 2
                    border.color: addNetworkBtn.isHovered ? "#80cfff" : "white"
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        text: "+"
                        font.pixelSize: 20
                        color: "white"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: addNetworkBtn.isHovered = true
                    onExited:  addNetworkBtn.isHovered = false
                    onClicked: root.createNewNetwork()
                }
            }
        }
    }

    // ── Floating character/sound circle (root-level, escapes leftPanel clip) ──
    Rectangle {
        id: floatingCircle
        visible: root.isDraggingCircle
        x: root.draggingCircleX - width / 2
        y: root.draggingCircleY - height / 2
        width: 22; height: 22; radius: 11
        color: "white"
        z: 200
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: floatingCircle.width
                height: floatingCircle.height
                radius: floatingCircle.radius
            }
        }

        Image {
            anchors.fill: parent
            source: root.draggingCircleImage
            fillMode: Image.PreserveAspectCrop
            visible: !!root.draggingCircleImage
        }

        Text {
            anchors.centerIn: parent
            text: root.draggingCircleLabel
            font.pixelSize: 10
            font.bold: true
            color: "#1a1a1d"
            visible: !root.draggingCircleImage
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
        property real deleteProgress: 0.0

        Timer {
            id: deleteTimer
            interval: 16
            repeat: true
            onTriggered: {
                deleteProgress += 16.0 / 1200.0
                if (deleteProgress >= 1.0) {
                    running = false
                    node.isDeleting = true
                    root.deleteNode(node.nodeIndex)
                }
            }
        }

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
        height: isEditing ? baseHeight + 20 : baseHeight

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

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: '#ff3333'
                opacity: node.deleteProgress
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
                    deleteTimer.start();
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

                if (mouse.button === Qt.RightButton) {
                    deleteTimer.stop();
                    deleteProgress = 0.0;
                    return;
                }

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


        }
    }
}
