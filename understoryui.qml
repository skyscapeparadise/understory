import QtQuick
import QtQuick.Window
import QtMultimedia
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Window {
    id: mainWindow
    visible: true
    width: 960
    height: 540
    title: qsTr("understory")
    color: "black"

    property int xanimationduration: 0
    property int yanimationduration: 0
    property real sceneEditorEntryX: 0

    // animate any change to `width`
    Behavior on width {
        SequentialAnimation {
            NumberAnimation {
                duration: 1000
                easing.type: Easing.InOutQuad
            }

            ScriptAction {
                script: {
                    if (sceneEditor2sceneMenu.windowSizeCompleteTrigger) {
                        console.log("ScriptAction triggered");
                        sceneEditor2sceneMenu.visible = true;
                        sceneEditor2sceneMenuPlayer.play();
                    }
                }
            }
        }
    }

    // animate any change to `x`
    Behavior on x {
        NumberAnimation {
            duration: xanimationduration
            easing.type: Easing.InOutQuad
        }
    }

    // animate any change to `height`
    Behavior on height {
        NumberAnimation {
            duration: 1000
            easing.type: Easing.InOutQuad
        }
    }

    // animate any change to `y`
    Behavior on y {
        NumberAnimation {
            duration: yanimationduration
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: splashScreen
        width: parent.width
        height: parent.height
        visible: true

        Image {
            id: introstill
            anchors.fill: parent
            source: "file:introstill.jpg"
            fillMode: Image.PreserveAspectFit
        }

        MediaPlayer {
            id: player
            source: "file:intro.mp4"
            autoPlay: true
            videoOutput: splashVideoOutput

            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia) {
                    storyMenu.visible = true;
                    splashScreen.visible = false;
                }
            }
        }

        VideoOutput {
            id: splashVideoOutput
            anchors.fill: parent
        }
    }

    Rectangle {
        id: storyMenu
        width: parent.width
        height: parent.height
        visible: false

        Image {
            id: storyMenuImage
            anchors.fill: parent
            source: "file:storymenu.jpg"
            fillMode: Image.PreserveAspectFit
        }

        ListModel {
            id: projectsRectModel
            ListElement {
                placeholder: ""
            }
        }

        ScrollView {
            visible: storyMenuButtons.selectedButton !== "settings" && storyMenuButtons.selectedButton !== "credits"

            x: 29
            y: 28
            height: 398
            width: 900

            Behavior on opacity {
                NumberAnimation {
                    duration: 1000
                    easing.type: Easing.InOutQuad
                }
            }

            GridLayout {
                id: projectgrid
                anchors.fill: parent
                anchors.margins: 20
                columns: 3
                rowSpacing: 20
                columnSpacing: 25

                Repeater {
                    model: projectsRectModel
                    delegate: Rectangle {
                        width: 270
                        height: 150
                        radius: 30
                        color: "transparent"
                        border.color: "white"
                        border.width: 4

                        property bool hovered: false
                        property bool isLast: index === projectsRectModel.count - 1

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hovered = true
                            onExited: hovered = false
                            onClicked: {
                                if (isLast) {
                                    projectsRectModel.append({});
                                } else {
                                    console.log("object number " + index + " clicked!");
                                    story2sceneMenu.visible = true;
                                    story2sceneMenuPlayer.play();
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 64
                            color: "white"
                            visible: hovered && isLast
                        }
                    }
                }
            }
        }

        ScrollView {
            id: storySettingsView
            x: 29
            y: 28
            height: 398
            width: 900
            visible: storyMenuButtons.selectedButton === "settings"
            clip: true

            topPadding: 20
            leftPadding: 20
            rightPadding: 20

            ColumnLayout {
                width: storySettingsView.availableWidth
                spacing: 20

                Text {
                    text: "settings"
                    font.pixelSize: 48
                    font.bold: true
                    color: "white"
                }

                Text {
                    text: "this is where the body text goes"
                    font.pixelSize: 16
                    color: "white"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            id: storyCreditsView
            x: 29
            y: 28
            height: 398
            width: 900
            color: "transparent"
            clip: true
            visible: storyMenuButtons.selectedButton === "credits"

            ColumnLayout {
                id: creditsContent
                anchors.right: parent.right
                anchors.rightMargin: 20
                y: parent.height
                spacing: 10

                Image {
                    source: "file:headings/understorylogo.svg"
                    Layout.preferredWidth: 450
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignRight
                }

                Item {
                    Layout.preferredHeight: 0
                }

                Text {
                    text: "design and development"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                    wrapMode: Text.WordWrap
                    Layout.alignment: Qt.AlignRight
                }

                Text {
                    text: "kady everpetal"
                    font.pixelSize: 20
                    color: "white"
                    wrapMode: Text.WordWrap
                    Layout.alignment: Qt.AlignRight
                }

                Text {
                    text: "  "
                    font.pixelSize: 20
                    color: "white"
                    wrapMode: Text.WordWrap
                    Layout.alignment: Qt.AlignRight
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60

                    Image {
                        source: "file:headings/rainlogo.svg"
                        height: parent.height
                        anchors.right: parent.right
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }

            SequentialAnimation {
                id: creditsAnimation
                running: storyCreditsView.visible
                loops: 1

                NumberAnimation {
                    target: creditsContent
                    property: "y"
                    from: storyCreditsView.height
                    to: -creditsContent.height
                    duration: 15000
                    easing.type: Easing.Linear
                }

                onStopped: {
                    if (storyMenuButtons.selectedButton === "credits") {
                        storyMenuButtons.selectedButton = "";
                    }
                    creditsContent.y = storyCreditsView.height;
                }
            }
        }

        GridLayout {
            id: storyMenuButtons
            x: 23
            y: 449
            columns: 2
            rowSpacing: 4
            columnSpacing: 4

            property string selectedButton: ""
            property color activeIconColor: "#477B78"

            Repeater {
                model: ["getting started", "settings", "update", "credits"]
                delegate: Item {
                    id: storyBtn
                    width: 138
                    height: 28

                    property bool hovered: false
                    property bool togglable: modelData === "settings" || modelData === "credits"
                    property bool toggled: togglable && storyMenuButtons.selectedButton === modelData
                    property bool pressed: !togglable && storyMouseArea.pressed

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: toggled ? "white" : (storyBtn.pressed ? "white" : "transparent")
                        border.width: 2
                        border.color: hovered ? "#80cfff" : "white"
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                        Behavior on border.color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 14
                        color: toggled ? storyMenuButtons.activeIconColor : (storyBtn.pressed ? storyMenuButtons.activeIconColor : "white")
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }

                    MouseArea {
                        id: storyMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        onPressed: if (!togglable)
                            storyBtn.pressed = true
                        onReleased: if (!togglable)
                            storyBtn.pressed = false
                        onClicked: {
                            if (togglable) {
                                storyMenuButtons.selectedButton = toggled ? "" : modelData;
                            } else {
                                console.log("button", modelData, "clicked!");
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            x: 900
            y: 482
            width: 45
            height: 30
            color: "transparent"

            Text {
                text: "v" + versionnumber
                font.pointSize: 16
                horizontalAlignment: Text.AlignRight
                color: "white"
            }
        }
    }

    Rectangle {
        id: sceneMenu
        width: parent.width
        height: parent.height
        visible: false

        Image {
            id: sceneMenuImage
            anchors.fill: parent
            source: "file:scenemenu.jpg"
            fillMode: Image.PreserveAspectFit
        }

        ListModel {
            id: scenesRectModel
            ListElement {
                placeholder: ""
            }
        }

        ScrollView {
            visible: sceneMenuButtons.selectedButton !== "settings"

            x: 29
            y: 28
            height: 398
            width: 900

            Behavior on opacity {
                NumberAnimation {
                    duration: 1000
                    easing.type: Easing.InOutQuad
                }
            }

            GridLayout {
                id: scenegrid
                anchors.fill: parent
                anchors.margins: 20
                columns: 3
                rowSpacing: 20
                columnSpacing: 25

                Repeater {
                    model: scenesRectModel
                    delegate: Rectangle {
                        width: 270
                        height: 150
                        radius: 30
                        color: "transparent"
                        border.color: "white"
                        border.width: 4

                        property bool hovered: false
                        property bool isLast: index === scenesRectModel.count - 1

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hovered = true
                            onExited: hovered = false
                            onClicked: {
                                if (isLast) {
                                    scenesRectModel.append({});
                                } else {
                                    console.log("object number " + index + " clicked!");
                                    sceneMenu2sceneEditor.visible = true;
                                    sceneMenu2sceneEditorPlayer.play();
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 64
                            color: "white"
                            visible: hovered && isLast
                        }
                    }
                }
            }
        }

        ScrollView {
            id: sceneSettingsView
            x: 29
            y: 28
            height: 398
            width: 900

            visible: sceneMenuButtons.selectedButton === "settings"
            clip: true
            topPadding: 20
            leftPadding: 20
            rightPadding: 20

            ColumnLayout {
                width: sceneSettingsView.availableWidth
                spacing: 20

                Text {
                    text: "settings"
                    font.pixelSize: 48
                    font.bold: true
                    color: "white"
                }

                Text {
                    text: "this is where the body text goes"
                    font.pixelSize: 16
                    color: "white"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        GridLayout {
            id: sceneMenuButtons
            x: 23
            y: 449
            columns: 2
            rowSpacing: 4
            columnSpacing: 4

            property string selectedButton: ""
            property color activeIconColor: "#477B78"

            Repeater {
                model: ["publish", "delete", "settings", "exit story"]
                delegate: Item {
                    id: sceneBtn
                    width: 138
                    height: 28

                    property bool hovered: false
                    property bool togglable: modelData === "settings"
                    property bool toggled: togglable && sceneMenuButtons.selectedButton === modelData
                    property bool pressed: !togglable && sceneMouseArea.pressed

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: toggled ? "white" : (sceneBtn.pressed ? "white" : "transparent")
                        border.width: 2
                        border.color: hovered ? "#80cfff" : "white"
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                        Behavior on border.color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 14
                        color: toggled ? sceneMenuButtons.activeIconColor : (sceneBtn.pressed ? sceneMenuButtons.activeIconColor : "white")
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }

                    MouseArea {
                        id: sceneMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        onPressed: if (!togglable)
                            sceneBtn.pressed = true
                        onReleased: if (!togglable)
                            sceneBtn.pressed = false
                        onClicked: {
                            if (togglable) {
                                sceneMenuButtons.selectedButton = toggled ? "" : modelData;
                            } else {
                                console.log("button", modelData, "clicked!");
                                if (modelData === "exit story") {
                                    scene2storyMenu.visible = true;
                                    scene2storyMenuPlayer.play();
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: storyLogo2
            radius: 14
            y: 449
            width: 400
            height: 60
            color: "transparent"
            anchors.right: parent.right
            anchors.rightMargin: 23

            Image {
                id: svgIcon2
                anchors.right: parent.right
                height: parent.height
                fillMode: Image.PreserveAspectFit
                source: "file:welcomelogo.svg"
                visible: true
            }
        }
    }

    Rectangle {
        id: sceneEditor
        visible: false
        width: 1365
        height: 540
        anchors.left: parent.left

        Rectangle {
            id: viewport
            objectName: "viewport"
            width: 960
            height: 540
            color: "black"

            property bool areaDragging: false
            property int hoveredAreaIndex: -1

            ListModel { id: areasModel }
            property real areaX1: 0
            property real areaY1: 0
            property real areaX2: 0
            property real areaY2: 0

            function findHoveredArea(px, py) {
                if (buttonGrid.selectedTool !== "select") return -1
                for (var i = 0; i < areasModel.count; i++) {
                    var a = areasModel.get(i)
                    var ax = Math.min(a.x1, a.x2), ay = Math.min(a.y1, a.y2)
                    var aw = Math.abs(a.x2 - a.x1), ah = Math.abs(a.y2 - a.y1)
                    if (px >= ax && px <= ax + aw && py >= ay && py <= ay + ah)
                        return i
                }
                return -1
            }

            function snapX(val) {
                var clamped = Math.max(0, Math.min(val, width))
                if (clamped <= 10) return 0
                if (clamped >= width - 10) return width
                return clamped
            }
            function snapY(val) {
                var clamped = Math.max(0, Math.min(val, height))
                if (clamped <= 10) return 0
                if (clamped >= height - 10) return height
                return clamped
            }

            Image {
                anchors.fill: parent
                source: "file:stairwell.jpg"
            }

            // New area drag: click and drag to define a rectangular area
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newarea"
                z: 998

                onPressed: {
                    viewport.areaX1 = viewport.snapX(mouseX)
                    viewport.areaY1 = viewport.snapY(mouseY)
                    viewport.areaX2 = viewport.areaX1
                    viewport.areaY2 = viewport.areaY1
                    viewport.areaDragging = true
                }
                onPositionChanged: {
                    viewport.areaX2 = viewport.snapX(mouseX)
                    viewport.areaY2 = viewport.snapY(mouseY)
                }
                onReleased: {
                    viewport.areaDragging = false
                    var w = Math.abs(viewport.areaX2 - viewport.areaX1)
                    var h = Math.abs(viewport.areaY2 - viewport.areaY1)
                    if (w > 2 && h > 2)
                        areasModel.append({ x1: viewport.areaX1, y1: viewport.areaY1,
                                            x2: viewport.areaX2, y2: viewport.areaY2 })
                }
            }

            // Completed areas
            Repeater {
                model: areasModel
                delegate: Rectangle {
                    x: Math.min(model.x1, model.x2)
                    y: Math.min(model.y1, model.y2)
                    width: Math.abs(model.x2 - model.x1)
                    height: Math.abs(model.y2 - model.y1)
                    color: index === viewport.hoveredAreaIndex ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                    border.color: "white"
                    border.width: index === viewport.hoveredAreaIndex ? 2 : 1
                    z: 997

                    Behavior on color { ColorAnimation { duration: 80 } }
                    Behavior on border.width { NumberAnimation { duration: 80 } }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: index === viewport.hoveredAreaIndex ? 2 : 1
                        color: "transparent"
                        border.color: "black"
                        border.width: 1

                        Behavior on anchors.margins { NumberAnimation { duration: 80 } }
                    }
                }
            }

            // In-progress rubber-band (only visible while dragging)
            Rectangle {
                visible: viewport.areaDragging
                x: Math.min(viewport.areaX1, viewport.areaX2)
                y: Math.min(viewport.areaY1, viewport.areaY2)
                width: Math.abs(viewport.areaX2 - viewport.areaX1)
                height: Math.abs(viewport.areaY2 - viewport.areaY1)
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

            // Tool cursor: tracks mouse position to drive the custom cursor image below.
            // acceptedButtons: Qt.NoButton means this area never consumes clicks —
            // all pointer events pass through to viewport content underneath.
            MouseArea {
                id: viewportCursorArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: ["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1 ? Qt.BlankCursor : Qt.ArrowCursor
                z: 999
                onPositionChanged: viewport.hoveredAreaIndex = viewport.findHoveredArea(mouseX, mouseY)
                onExited: viewport.hoveredAreaIndex = -1
            }

            Image {
                x: viewport.areaDragging ? viewport.areaX2 : viewportCursorArea.mouseX
                y: viewport.areaDragging ? viewport.areaY2 : viewportCursorArea.mouseY
                width: 36
                height: 36
                source: ["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1 ? "icons/" + buttonGrid.selectedTool + ".svg" : ""
                visible: viewportCursorArea.containsMouse && ["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1
                fillMode: Image.PreserveAspectFit
                z: 1000
            }

            Rectangle {
                id: navigationViewportOverlay
                visible: buttonGrid.selectedTool === "navigation"
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.6)
                opacity: buttonGrid.selectedTool === "navigation" ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.InOutQuad
                    }
                }

                ScrollView {
                    id: navScroll
                    anchors.top: parent.top
                    anchors.topMargin: 30
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 900
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    GridLayout {
                        id: navSceneGrid
                        columns: 3
                        rowSpacing: 30
                        columnSpacing: 30

                        Repeater {
                            model: scenesRectModel
                            delegate: Rectangle {
                                Layout.preferredWidth: 280
                                Layout.preferredHeight: Layout.preferredWidth * 0.625
                                Layout.minimumWidth: 120
                                Layout.minimumHeight: 70
                                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                radius: 30
                                color: "transparent"
                                border.color: "white"
                                border.width: 4

                                property bool hovered: false
                                property bool isLast: index === scenesRectModel.count - 1

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: hovered = true
                                    onExited: hovered = false
                                    onClicked: {
                                        if (isLast) {
                                            scenesRectModel.append({});
                                            console.log("Appended new scene from viewport preview");
                                        } else {
                                            console.log("Viewport preview clicked scene index", index);
                                            navigationViewportSelectionFlash.running = true;
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: "white"
                                    font.pixelSize: 32
                                    visible: hovered && isLast
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: navigationViewportSelectionFlash
                    anchors.fill: parent
                    color: "white"
                    opacity: 0.0
                    visible: false

                    SequentialAnimation on opacity {
                        running: false
                        PropertyAnimation {
                            to: 0.18
                            duration: 120
                        }
                        PauseAnimation {
                            duration: 80
                        }
                        PropertyAnimation {
                            to: 0.0
                            duration: 120
                        }
                        onStarted: navigationViewportSelectionFlash.visible = true
                        onStopped: navigationViewportSelectionFlash.visible = false
                        onRunningChanged: {
                            if (running)
                                navigationViewportSelectionFlash.visible = true;
                            else
                                navigationViewportSelectionFlash.visible = false;
                        }
                    }
                }
            }
        }

        Rectangle {
            width: 405
            height: 540
            anchors.right: parent.right

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0.00
                        color: "#477B78"
                    }
                    GradientStop {
                        position: 0.40
                        color: "#5DA9A4"
                    }
                    GradientStop {
                        position: 0.70
                        color: "#2C4948"
                    }
                    GradientStop {
                        position: 1.00
                        color: "#0B1D1D"
                    }
                }
            }

            Canvas {
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.clearRect(0, 0, width, height);

                    var cx = width * 0.5, cy = height * 0.15, r1 = width * 0.9;
                    var glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, r1);
                    glow.addColorStop(0.0, "#6DBFBA");
                    glow.addColorStop(1.0, "rgba(0,0,0,0)");
                    ctx.fillStyle = glow;
                    ctx.fillRect(0, 0, width, height);

                    var cx2 = width * 0.5, cy2 = height * 0.5, r2 = width;
                    var vign = ctx.createRadialGradient(cx2, cy2, 0, cx2, cy2, r2);
                    vign.addColorStop(0.5, "rgba(0,0,0,0)");
                    vign.addColorStop(1.0, "rgba(0,0,0,0.7)");
                    ctx.fillStyle = vign;
                    ctx.fillRect(0, 0, width, height);
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            Rectangle {
                width: 405
                height: 200
                color: "transparent"

                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter

                GridLayout {
                    id: buttonGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 4
                    rowSpacing: 8
                    columnSpacing: 8

                    property string selectedTool: ""
                    property color activeIconColor: "#477B78"

                    Repeater {
                        model: ["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"]

                        delegate: Item {
                            id: buttonRoot
                            width: 88
                            height: 88

                            property bool hovered: false
                            property bool toggled: buttonGrid.selectedTool === modelData
                            property string iconSource: "icons/" + modelData + ".svg"

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: toggled ? "white" : "transparent"
                                border.width: 2
                                border.color: hovered ? "#80cfff" : "white"
                                Behavior on border.color {
                                    ColorAnimation {
                                        duration: 150
                                    }
                                }
                            }

                            Image {
                                id: svgIcon
                                anchors.centerIn: parent
                                width: 70
                                height: 70
                                fillMode: Image.PreserveAspectFit
                                source: iconSource
                                visible: false
                            }

                            ColorOverlay {
                                anchors.fill: svgIcon
                                source: svgIcon
                                color: toggled ? buttonGrid.activeIconColor : "white"
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                onClicked: {
                                    buttonGrid.selectedTool = (buttonGrid.selectedTool === modelData) ? "" : modelData;
                                }
                                onEntered: hovered = true
                                onExited: hovered = false
                            }
                        }
                    }
                }
            }

            GridLayout {
                id: sceneEditorButtons
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                columns: 2
                rowSpacing: 4
                columnSpacing: 4

                property bool timelineOpen: false

                Repeater {
                    model: ["conditions", "variables", "timeline", "close scene"]

                    delegate: Item {
                        id: editorBtn
                        width: 138
                        height: 28

                        property bool hovered: false
                        property bool togglable: modelData === "conditions" || modelData === "variables"
                        property bool toggled: modelData === "timeline" ? sceneEditorButtons.timelineOpen : (togglable && buttonGrid.selectedTool === modelData)
                        property bool pressed: false

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: toggled ? "white" : (editorBtn.pressed ? "white" : "transparent")
                            border.width: 2
                            border.color: hovered ? "#80cfff" : "white"
                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 14
                            color: toggled ? buttonGrid.activeIconColor : (editorBtn.pressed ? buttonGrid.activeIconColor : "white")
                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hovered = true
                            onExited: hovered = false
                            onPressed: editorBtn.pressed = true
                            onReleased: editorBtn.pressed = false

                            onClicked: {
                                if (togglable) {
                                    buttonGrid.selectedTool = editorBtn.toggled ? "" : modelData;
                                } else if (modelData === "timeline") {
                                    var opening = !sceneEditorButtons.timelineOpen;
                                    sceneEditorButtons.timelineOpen = opening;
                                    yanimationduration = 1000;
                                    if (opening) {
                                        mainWindow.height = mainWindow.height + 300;
                                        mainWindow.y = mainWindow.y - 150;
                                    } else {
                                        mainWindow.height = mainWindow.height - 300;
                                        mainWindow.y = mainWindow.y + 150;
                                    }
                                } else if (modelData === "close scene") {
                                    console.log("Closing scene…");
                                    if (sceneEditorButtons.timelineOpen) {
                                        sceneEditorButtons.timelineOpen = false;
                                        yanimationduration = 1000;
                                        mainWindow.height = 540;
                                        mainWindow.y = mainWindow.y + 150;
                                        closeSceneTimer.start();
                                    } else {
                                        xanimationduration = 1000;
                                        mainWindow.width = 960;
                                        mainWindow.x = sceneEditorEntryX;
                                        sceneEditor2sceneMenu.windowSizeCompleteTrigger = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: toolSettingsArea
                x: 0
                y: 0
                radius: 12
                height: 240
                width: 377
                color: "transparent"
                border.color: "white"
                border.width: navigationSettings.visible ? 0 : 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 86
                anchors.left: parent.left
                anchors.leftMargin: 14

                Rectangle {
                    id: areaSettings
                    visible: buttonGrid.selectedTool === "newarea"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: areaSettingsHeading
                        text: "new area"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: imageSettings
                    visible: buttonGrid.selectedTool === "newimage"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: imageSettingsHeading
                        text: "new image"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: videoSettings
                    visible: buttonGrid.selectedTool === "newvideo"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: videoSettingsHeading
                        text: "new video"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: textSettings
                    visible: buttonGrid.selectedTool === "newtext"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: textSettingsHeading
                        text: "new text"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: selectSettings
                    visible: buttonGrid.selectedTool === "select"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: selectSettingsHeading
                        text: "select"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: newlinkSettings
                    visible: buttonGrid.selectedTool === "newlink"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: newlinkSettingsHeading
                        text: "simulate"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: relayerSettings
                    visible: buttonGrid.selectedTool === "relayer"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: relayerSettingsHeading
                        text: "stack"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: destroySettings
                    visible: buttonGrid.selectedTool === "destroy"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: destroySettingsHeading
                        text: "delete"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: navigationSettings
                    visible: buttonGrid.selectedTool === "navigation"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Canvas {
                        id: cutoutCanvas
                        anchors.fill: parent

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();

                            ctx.fillStyle = "white";
                            ctx.beginPath();
                            ctx.moveTo(0, 12);
                            ctx.arcTo(0, 0, 12, 0, 12);
                            ctx.lineTo(parent.width - 12, 0);
                            ctx.arcTo(parent.width, 0, parent.width, 12, 12);
                            ctx.lineTo(parent.width, parent.height - 12);
                            ctx.arcTo(parent.width, parent.height, parent.width - 12, parent.height, 12);
                            ctx.lineTo(12, parent.height);
                            ctx.arcTo(0, parent.height, 0, parent.height - 12, 12);
                            ctx.closePath();
                            ctx.fill();

                            ctx.globalCompositeOperation = 'destination-out';
                            ctx.fillStyle = "black";

                            function drawRoundedRect(item) {
                                if (!item)
                                    return;
                                var x = item.x, y = item.y, w = item.width, h = item.height, r = item.radius;
                                ctx.beginPath();
                                ctx.moveTo(x + r, y);
                                ctx.arcTo(x + w, y, x + w, y + h, r);
                                ctx.arcTo(x + w, y + h, x, y + h, r);
                                ctx.arcTo(x, y + h, x, y, r);
                                ctx.arcTo(x, y, x + w, y, r);
                                ctx.closePath();
                                ctx.fill();
                            }

                            drawRoundedRect(nSettingsArea);
                            drawRoundedRect(sSettingsArea);
                            drawRoundedRect(eSettingsArea);
                            drawRoundedRect(wSettingsArea);
                            drawRoundedRect(navigationLayoutButton);
                        }

                        Component.onCompleted: {
                            function connectSignals(item) {
                                if (!item)
                                    return;
                                item.xChanged.connect(requestPaint);
                                item.yChanged.connect(requestPaint);
                                item.widthChanged.connect(requestPaint);
                                item.heightChanged.connect(requestPaint);
                            }
                            connectSignals(nSettingsArea);
                            connectSignals(sSettingsArea);
                            connectSignals(eSettingsArea);
                            connectSignals(wSettingsArea);
                            connectSignals(navigationLayoutButton);
                        }
                    }

                    Rectangle {
                        id: navigationLayoutButton
                        anchors.centerIn: parent
                        width: 100
                        height: 36
                        radius: height / 2

                        property bool hovered: false
                        property bool pressed: false

                        color: navigationLayoutButton.pressed ? "white" : "transparent"
                        border.width: 2
                        border.color: navigationLayoutButton.hovered ? "#80cfff" : "white"
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                        Behavior on border.color {
                            ColorAnimation {
                                duration: 150
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "layout areas"
                            color: navigationLayoutButton.pressed ? buttonGrid.activeIconColor : "white"
                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: navigationLayoutButton.hovered = true
                            onExited: navigationLayoutButton.hovered = false
                            onPressed: navigationLayoutButton.pressed = true
                            onReleased: navigationLayoutButton.pressed = false

                            onClicked: {
                                console.log("layout areas clicked");
                            }
                        }
                    }

                    Rectangle {
                        id: nSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: "white"
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 20

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"

                            Image {
                                id: nHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/n_heading.svg"
                            }
                        }
                    }

                    Rectangle {
                        id: sSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: "white"
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"

                            Image {
                                id: sHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/s_heading.svg"
                            }
                        }
                    }

                    Rectangle {
                        id: eSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: "white"
                        border.width: 2
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 20

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"

                            Image {
                                id: eHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/e_heading.svg"
                            }
                        }
                    }

                    Rectangle {
                        id: wSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: "white"
                        border.width: 2
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"

                            Image {
                                id: wHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/w_heading.svg"
                            }
                        }
                    }
                }

                Rectangle {
                    id: sceneSettings
                    visible: buttonGrid.selectedTool === "conditions"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "darkcyan"
                    border.color: "white"
                    border.width: 2

                    Text {
                        id: conditionsSettingsHeading
                        text: "scene conditions"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }
                }

                Rectangle {
                    id: sceneScript
                    visible: buttonGrid.selectedTool === "variables"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "darkslategrey"
                    border.color: "white"
                    border.width: 2

                    Text {
                        id: variablesSettingsHeading
                        text: "story variables"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }

                    // Clicking the panel background defocuses any active text field
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        onClicked: sceneScript.forceActiveFocus()
                    }

                    // Stores the list of user-defined story variables
                    ListModel {
                        id: variablesModel
                    }

                    // Remove unnamed variables when the user navigates away
                    onVisibleChanged: {
                        if (!visible) {
                            for (var i = variablesModel.count - 1; i >= 0; i--) {
                                if (variablesModel.get(i).varName === "")
                                    variablesModel.remove(i);
                            }
                        }
                    }

                    ScrollView {
                        id: variablesScrollView
                        anchors.top: variablesSettingsHeading.bottom
                        anchors.topMargin: 10
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            width: variablesScrollView.availableWidth
                            spacing: 4

                            Repeater {
                                model: variablesModel
                                delegate: Item {
                                    width: parent.width
                                    height: 26

                                    // Capture the Repeater index so it isn't shadowed by
                                    // signal parameters also named index
                                    property int delegateIndex: index

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 4

                                        // Type selector — square icon button
                                        // truefalsevariable.svg → stored as boolean
                                        // numbervariable.svg    → stored as float
                                        // textvariable.svg      → stored as string
                                        Item {
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
                                                color: "transparent"
                                                border.color: "white"
                                                border.width: 1

                                                Image {
                                                    anchors.centerIn: parent
                                                    width: 16
                                                    height: 16
                                                    source: {
                                                        if (varType === "true or false")
                                                            return "icons/truefalsevariable.svg";
                                                        if (varType === "number")
                                                            return "icons/numbervariable.svg";
                                                        return "icons/textvariable.svg";
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: typePickerPopup.open()
                                                }
                                            }

                                            // Type picker popup — padding: 0 so contentItem fills
                                            // the full declared size without any internal insets
                                            Popup {
                                                id: typePickerPopup
                                                y: -height - 4
                                                x: 0
                                                width: 94
                                                height: 34
                                                padding: 0
                                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                                                background: Rectangle {
                                                    color: "#162020"
                                                    border.color: "white"
                                                    border.width: 1
                                                    radius: 4
                                                }

                                                contentItem: Item {
                                                    Row {
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        // true or false option (boolean)
                                                        Rectangle {
                                                            width: 26
                                                            height: 26
                                                            radius: 4
                                                            color: varType === "true or false" ? "#477B78" : "transparent"
                                                            border.color: "white"
                                                            border.width: 1
                                                            Image {
                                                                anchors.centerIn: parent
                                                                width: 16
                                                                height: 16
                                                                source: "icons/truefalsevariable.svg"
                                                                fillMode: Image.PreserveAspectFit
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                onClicked: {
                                                                    variablesModel.setProperty(delegateIndex, "varType", "true or false");
                                                                    variablesModel.setProperty(delegateIndex, "varValue", "");
                                                                    numberInput.text = "";
                                                                    textValueInput.text = "";
                                                                    typePickerPopup.close();
                                                                }
                                                            }
                                                        }

                                                        // number option (float)
                                                        Rectangle {
                                                            width: 26
                                                            height: 26
                                                            radius: 4
                                                            color: varType === "number" ? "#477B78" : "transparent"
                                                            border.color: "white"
                                                            border.width: 1
                                                            Image {
                                                                anchors.centerIn: parent
                                                                width: 16
                                                                height: 16
                                                                source: "icons/numbervariable.svg"
                                                                fillMode: Image.PreserveAspectFit
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                onClicked: {
                                                                    variablesModel.setProperty(delegateIndex, "varType", "number");
                                                                    variablesModel.setProperty(delegateIndex, "varValue", "");
                                                                    numberInput.text = "";
                                                                    textValueInput.text = "";
                                                                    typePickerPopup.close();
                                                                }
                                                            }
                                                        }

                                                        // text option (string)
                                                        Rectangle {
                                                            width: 26
                                                            height: 26
                                                            radius: 4
                                                            color: varType === "text" ? "#477B78" : "transparent"
                                                            border.color: "white"
                                                            border.width: 1
                                                            Image {
                                                                anchors.centerIn: parent
                                                                width: 16
                                                                height: 16
                                                                source: "icons/textvariable.svg"
                                                                fillMode: Image.PreserveAspectFit
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                onClicked: {
                                                                    variablesModel.setProperty(delegateIndex, "varType", "text");
                                                                    variablesModel.setProperty(delegateIndex, "varValue", "");
                                                                    numberInput.text = "";
                                                                    textValueInput.text = "";
                                                                    typePickerPopup.close();
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Variable name field
                                        Rectangle {
                                            Layout.preferredWidth: 90
                                            Layout.preferredHeight: 26
                                            color: "transparent"
                                            border.color: "white"
                                            border.width: 1
                                            radius: 4

                                            TextInput {
                                                id: nameInput
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                color: "white"
                                                font.pixelSize: 11
                                                clip: true
                                                selectByMouse: true
                                                text: varName
                                                Keys.onReturnPressed: focus = false
                                                Keys.onEscapePressed: focus = false
                                                onEditingFinished: variablesModel.setProperty(delegateIndex, "varName", text)
                                            }
                                            Text {
                                                text: "name"
                                                color: "#60ffffff"
                                                font.pixelSize: 11
                                                anchors.left: parent.left
                                                anchors.leftMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: nameInput.text === "" && !nameInput.activeFocus
                                            }
                                        }

                                        // Value field — appearance changes based on selected type
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26

                                            // number type: accepts floats only
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: varType === "number"
                                                color: "transparent"
                                                border.color: "white"
                                                border.width: 1
                                                radius: 4

                                                TextInput {
                                                    id: numberInput
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    color: "white"
                                                    font.pixelSize: 11
                                                    clip: true
                                                    selectByMouse: true
                                                    validator: DoubleValidator {}
                                                    text: varType === "number" ? varValue : ""
                                                    Keys.onReturnPressed: focus = false
                                                    Keys.onEscapePressed: focus = false
                                                    onEditingFinished: variablesModel.setProperty(delegateIndex, "varValue", text)
                                                }
                                                Text {
                                                    text: "0"
                                                    color: "#60ffffff"
                                                    font.pixelSize: 11
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: numberInput.text === "" && !numberInput.activeFocus
                                                }
                                            }

                                            // text type: plain string input
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: varType === "text"
                                                color: "transparent"
                                                border.color: "white"
                                                border.width: 1
                                                radius: 4

                                                TextInput {
                                                    id: textValueInput
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    color: "white"
                                                    font.pixelSize: 11
                                                    clip: true
                                                    selectByMouse: true
                                                    text: varType === "text" ? varValue : ""
                                                    Keys.onReturnPressed: focus = false
                                                    Keys.onEscapePressed: focus = false
                                                    onEditingFinished: variablesModel.setProperty(delegateIndex, "varValue", text)
                                                }
                                                Text {
                                                    text: "value"
                                                    color: "#60ffffff"
                                                    font.pixelSize: 11
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: textValueInput.text === "" && !textValueInput.activeFocus
                                                }
                                            }

                                            // true or false type: toggleable radio buttons
                                            Row {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: varType === "true or false"
                                                spacing: 8

                                                // "true" radio option
                                                Row {
                                                    spacing: 4
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Rectangle {
                                                        width: 12
                                                        height: 12
                                                        radius: 6
                                                        border.color: "white"
                                                        border.width: 1
                                                        color: "transparent"
                                                        anchors.verticalCenter: parent.verticalCenter

                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 6
                                                            height: 6
                                                            radius: 3
                                                            color: "white"
                                                            visible: varValue === "true"
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: variablesModel.setProperty(delegateIndex, "varValue", "true")
                                                        }
                                                    }
                                                    Text {
                                                        text: "true"
                                                        color: "white"
                                                        font.pixelSize: 11
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }

                                                // "false" radio option
                                                Row {
                                                    spacing: 4
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Rectangle {
                                                        width: 12
                                                        height: 12
                                                        radius: 6
                                                        border.color: "white"
                                                        border.width: 1
                                                        color: "transparent"
                                                        anchors.verticalCenter: parent.verticalCenter

                                                        Rectangle {
                                                            anchors.centerIn: parent
                                                            width: 6
                                                            height: 6
                                                            radius: 3
                                                            color: "white"
                                                            visible: varValue === "false"
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: variablesModel.setProperty(delegateIndex, "varValue", "false")
                                                        }
                                                    }
                                                    Text {
                                                        text: "false"
                                                        color: "white"
                                                        font.pixelSize: 11
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }
                                        }

                                        // Delete button
                                        Item {
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26
                                            property bool hovered: false

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
                                                color: parent.hovered ? "white" : "transparent"
                                                border.color: "white"
                                                border.width: 1
                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 100
                                                    }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: -1
                                                    text: "×"
                                                    font.pixelSize: 18
                                                    font.bold: true
                                                    color: parent.parent.hovered ? "darkslategrey" : "white"
                                                    Behavior on color {
                                                        ColorAnimation {
                                                            duration: 100
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onEntered: parent.hovered = true
                                                onExited: parent.hovered = false
                                                onClicked: variablesModel.remove(delegateIndex)
                                            }
                                        }
                                    }
                                }
                            }

                            // Add a new variable to the list
                            Item {
                                width: parent.width
                                height: 4
                            }
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
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        text: "+"
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: parent.parent.hovered ? "darkslategrey" : "white"
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 100
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: parent.hovered = true
                                    onExited: parent.hovered = false
                                    onClicked: variablesModel.append({
                                        varType: "text",
                                        varName: "",
                                        varValue: ""
                                    })
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: sceneNameSettings
                    visible: buttonGrid.selectedTool === ""
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    // Measures text at full 48pt so we can compute scale without circular binding
                    Text {
                        id: sceneNameMeasurer
                        text: sceneNameInput.text
                        font.pixelSize: 48
                        font.bold: true
                        visible: false
                    }

                    property real targetFontSize: {
                        var available = width - 40;
                        if (sceneNameMeasurer.contentWidth <= 0 || sceneNameMeasurer.contentWidth <= available)
                            return 48;
                        return Math.max(12, 48 * available / sceneNameMeasurer.contentWidth);
                    }

                    property real computedFontSize: targetFontSize

                    Behavior on computedFontSize {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        onClicked: sceneNameInput.focus = false
                    }

                    TextInput {
                        id: sceneNameInput
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.bottom: sceneNameLine.top
                        anchors.bottomMargin: 2
                        text: "scene one"
                        color: "white"
                        font.bold: true
                        font.pixelSize: sceneNameSettings.computedFontSize
                        selectByMouse: true
                        clip: true
                        Keys.onReturnPressed: focus = false
                        Keys.onEscapePressed: focus = false
                    }

                    Rectangle {
                        id: sceneNameLine
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 32
                        height: 1
                        color: "white"
                    }

                    Text {
                        anchors.top: sceneNameLine.bottom
                        anchors.topMargin: 5
                        anchors.left: sceneNameLine.left
                        text: "scene name"
                        font.pixelSize: 14
                        color: "white"
                    }
                }
            }

            Item {
                id: navigationButton
                width: 88
                height: 60
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                anchors.left: parent.left
                anchors.leftMargin: 14

                property bool hovered: false
                property bool toggled: buttonGrid.selectedTool === "navigation"

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: navigationButton.toggled ? "white" : "transparent"
                    border.width: 2
                    border.color: navigationButton.hovered ? "#80cfff" : "white"
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                Image {
                    id: navToolSvgIcon
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    fillMode: Image.PreserveAspectFit
                    source: "icons/navigation.svg"
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: navToolSvgIcon
                    source: navToolSvgIcon
                    color: navigationButton.toggled ? buttonGrid.activeIconColor : "white"
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true

                    onEntered: navigationButton.hovered = true
                    onExited: navigationButton.hovered = false

                    onClicked: {
                        buttonGrid.selectedTool = navigationButton.toggled ? "" : "navigation";
                    }
                }
            }
        }
    }

    Timer {
        id: closeSceneTimer
        interval: 1000
        repeat: false
        onTriggered: {
            xanimationduration = 1000;
            mainWindow.width = 960;
            mainWindow.x = sceneEditorEntryX;
            sceneEditor2sceneMenu.windowSizeCompleteTrigger = true;
        }
    }

    NodeWorkspace {
        id: nodeWorkspace
        x: 0
        y: 540
        width: 1365
        height: 300
    }

    Rectangle {
        id: story2sceneMenu
        width: parent.width
        height: parent.height
        visible: false

        Image {
            id: storyMenuImage2
            anchors.fill: parent
            source: "file:storymenu.jpg"
            fillMode: Image.PreserveAspectFit
        }

        MediaPlayer {
            id: story2sceneMenuPlayer
            source: "file:storymenu2scenemenu.mp4"
            autoPlay: false
            videoOutput: story2sceneMenuVideoOutput

            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia) {
                    sceneMenu.visible = true;
                    story2sceneMenu.visible = false;
                    storyMenu.visible = false;
                }
            }
        }

        VideoOutput {
            id: story2sceneMenuVideoOutput
            anchors.fill: parent
        }
    }

    Rectangle {
        id: scene2storyMenu
        width: parent.width
        height: parent.height
        visible: false

        Image {
            id: sceneMenuImage2
            anchors.fill: parent
            source: "file:scenemenu.jpg"
            fillMode: Image.PreserveAspectFit
        }

        MediaPlayer {
            id: scene2storyMenuPlayer
            source: "file:scenemenu2storymenu.mp4"
            autoPlay: false
            videoOutput: scene2storyMenuVideoOutput

            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia) {
                    storyMenu.visible = true;
                    scene2storyMenu.visible = false;
                    sceneMenu.visible = false;
                }
            }
        }

        VideoOutput {
            id: scene2storyMenuVideoOutput
            anchors.fill: parent
        }
    }

    Rectangle {
        id: sceneMenu2sceneEditor
        width: parent.width
        height: parent.height
        visible: false

        Image {
            id: sceneMenuImage3
            anchors.fill: parent
            source: "file:scenemenu.jpg"
            fillMode: Image.PreserveAspectFit
        }

        MediaPlayer {
            id: sceneMenu2sceneEditorPlayer
            source: "file:scenemenu2sceneeditor.mp4"
            autoPlay: false
            videoOutput: sceneMenu2sceneEditorVideoOutput

            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia) {
                    sceneEditorEntryX = mainWindow.x;
                    xanimationduration = 1000;
                    mainWindow.width = 1365;
                    mainWindow.x = mainWindow.x - 202;
                    sceneEditor.visible = true;
                    sceneMenu2sceneEditor.visible = false;
                    sceneMenu.visible = false;
                }
            }
        }

        VideoOutput {
            id: sceneMenu2sceneEditorVideoOutput
            anchors.fill: parent
        }
    }

    Rectangle {
        id: sceneEditor2sceneMenu
        width: parent.width
        height: parent.height
        color: "black"
        visible: false

        property bool windowSizeCompleteTrigger: false

        MediaPlayer {
            id: sceneEditor2sceneMenuPlayer
            source: "file:sceneeditor2scenemenu.mp4"
            autoPlay: false
            videoOutput: sceneEditor2sceneMenuVideoOutput

            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.EndOfMedia) {
                    sceneEditor.visible = false;
                    sceneEditor2sceneMenu.visible = false;
                    sceneMenu.visible = true;
                    sceneEditor2sceneMenu.windowSizeCompleteTrigger = false;
                }
            }
        }

        VideoOutput {
            id: sceneEditor2sceneMenuVideoOutput
            anchors.fill: parent
        }
    }
}
