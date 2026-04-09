import QtQuick
import QtQuick.Window
import QtMultimedia
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Dialogs

Window {
    id: mainWindow
    visible: true
    width: 960
    height: 540
    title: qsTr("understory")
    color: "black"

    FontLoader {
        id: monaSans
        source: "headings/MonaSans-VariableFont_wdth,wght.ttf"
    }
    FontLoader {
        id: monaSansItalic
        source: "headings/MonaSans-Italic-VariableFont_wdth,wght.ttf"
    }

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

            ListModel {
                id: areasModel
            }
            property real areaX1: 0
            property real areaY1: 0
            property real areaX2: 0
            property real areaY2: 0

            property bool textBoxDragging: false
            property real tbX1: 0
            property real tbY1: 0
            property real tbX2: 0
            property real tbY2: 0
            property int pendingFocusTextBox: -1

            property bool elementDragging: false
            property real elementDragX: 0
            property real elementDragY: 0

            property bool textEditing: false

            // Selection state
            property var selectedAreas: []
            property var selectedTbs: []
            property var selectedImages: []
            property var selectedVideos: []
            property int selectionRevision: 0
            readonly property int selectionCount: selectedAreas.length + selectedTbs.length + selectedImages.length + selectedVideos.length

            // Stack/z-order state
            property int nextStackOrder: 0
            property string relayerHoveredType: ""
            property int relayerHoveredIndex: -1

            property bool boxSelecting: false
            property real boxSelectX1: 0
            property real boxSelectY1: 0
            property real boxSelectX2: 0
            property real boxSelectY2: 0

            function clearSelection() {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [];
                selectionRevision++;
            }
            function selectArea(idx) {
                selectedAreas = [idx];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [];
                selectionRevision++;
            }
            function selectTb(idx) {
                selectedAreas = [];
                selectedTbs = [idx];
                selectedImages = [];
                selectedVideos = [];
                selectionRevision++;
            }
            function selectImage(idx) {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [idx];
                selectedVideos = [];
                selectionRevision++;
            }
            function selectVideo(idx) {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [idx];
                selectionRevision++;
            }
            function applyBoxSelect(rx1, ry1, rx2, ry2) {
                var bx1 = Math.min(rx1, rx2), bx2 = Math.max(rx1, rx2);
                var by1 = Math.min(ry1, ry2), by2 = Math.max(ry1, ry2);
                var newAreas = [], newTbs = [], newImgs = [], newVids = [];
                for (var i = 0; i < areasModel.count; i++) {
                    var a = areasModel.get(i);
                    if (a.x2 > bx1 && a.x1 < bx2 && a.y2 > by1 && a.y1 < by2)
                        newAreas.push(i);
                }
                for (var j = 0; j < textBoxesModel.count; j++) {
                    var t = textBoxesModel.get(j);
                    if (t.x2 > bx1 && t.x1 < bx2 && t.y2 > by1 && t.y1 < by2)
                        newTbs.push(j);
                }
                for (var k = 0; k < imagesModel.count; k++) {
                    var im = imagesModel.get(k);
                    if (im.x2 > bx1 && im.x1 < bx2 && im.y2 > by1 && im.y1 < by2)
                        newImgs.push(k);
                }
                for (var l = 0; l < videosModel.count; l++) {
                    var v = videosModel.get(l);
                    if (v.x2 > bx1 && v.x1 < bx2 && v.y2 > by1 && v.y1 < by2)
                        newVids.push(l);
                }
                selectedAreas = newAreas;
                selectedTbs = newTbs;
                selectedImages = newImgs;
                selectedVideos = newVids;
                selectionRevision++;
            }
            function groupBounds() {
                if (selectionCount === 0)
                    return null;
                var gx1 = Infinity, gy1 = Infinity, gx2 = -Infinity, gy2 = -Infinity;
                for (var i = 0; i < selectedAreas.length; i++) {
                    var a = areasModel.get(selectedAreas[i]);
                    gx1 = Math.min(gx1, a.x1);
                    gy1 = Math.min(gy1, a.y1);
                    gx2 = Math.max(gx2, a.x2);
                    gy2 = Math.max(gy2, a.y2);
                }
                for (var j = 0; j < selectedTbs.length; j++) {
                    var t = textBoxesModel.get(selectedTbs[j]);
                    gx1 = Math.min(gx1, t.x1);
                    gy1 = Math.min(gy1, t.y1);
                    gx2 = Math.max(gx2, t.x2);
                    gy2 = Math.max(gy2, t.y2);
                }
                for (var k = 0; k < selectedImages.length; k++) {
                    var im = imagesModel.get(selectedImages[k]);
                    gx1 = Math.min(gx1, im.x1);
                    gy1 = Math.min(gy1, im.y1);
                    gx2 = Math.max(gx2, im.x2);
                    gy2 = Math.max(gy2, im.y2);
                }
                for (var l = 0; l < selectedVideos.length; l++) {
                    var v = videosModel.get(selectedVideos[l]);
                    gx1 = Math.min(gx1, v.x1);
                    gy1 = Math.min(gy1, v.y1);
                    gx2 = Math.max(gx2, v.x2);
                    gy2 = Math.max(gy2, v.y2);
                }
                return {
                    x1: gx1,
                    y1: gy1,
                    x2: gx2,
                    y2: gy2
                };
            }

            ListModel {
                id: textBoxesModel
            }

            ListModel {
                id: imagesModel
            }
            property real imgX1: 0
            property real imgY1: 0
            property real imgX2: 0
            property real imgY2: 0
            property bool imageDragging: false

            ListModel {
                id: videosModel
            }
            property real vidX1: 0
            property real vidY1: 0
            property real vidX2: 0
            property real vidY2: 0
            property bool videoDragging: false

            function findHoveredArea(px, py) {
                if (buttonGrid.selectedTool !== "select")
                    return -1;
                for (var i = 0; i < areasModel.count; i++) {
                    var a = areasModel.get(i);
                    var ax = Math.min(a.x1, a.x2), ay = Math.min(a.y1, a.y2);
                    var aw = Math.abs(a.x2 - a.x1), ah = Math.abs(a.y2 - a.y1);
                    if (px >= ax && px <= ax + aw && py >= ay && py <= ay + ah)
                        return i;
                }
                return -1;
            }

            function snapX(val) {
                var clamped = Math.max(0, Math.min(val, width));
                if (clamped <= 10)
                    return 0;
                if (clamped >= width - 10)
                    return width;
                return clamped;
            }
            function snapY(val) {
                var clamped = Math.max(0, Math.min(val, height));
                if (clamped <= 10)
                    return 0;
                if (clamped >= height - 10)
                    return height;
                return clamped;
            }

            Image {
                anchors.fill: parent
                source: "file:stairwell.jpg"
            }

            // Defocus text boxes + clear selection when clicking empty viewport
            MouseArea {
                anchors.fill: parent
                z: 1
                onPressed: function (mouse) {
                    viewport.forceActiveFocus();
                    mouse.accepted = false;
                }
                onClicked: function (mouse) {
                    if (buttonGrid.selectedTool === "select")
                        viewport.clearSelection();
                }
            }

            // Box-select drag on empty viewport background (select tool only)
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "select" && !viewport.elementDragging
                z: 2
                onPressed: function (mouse) {
                    viewport.boxSelectX1 = mouse.x;
                    viewport.boxSelectY1 = mouse.y;
                    viewport.boxSelectX2 = mouse.x;
                    viewport.boxSelectY2 = mouse.y;
                    viewport.boxSelecting = true;
                    viewport.clearSelection();
                }
                onPositionChanged: function (mouse) {
                    viewport.boxSelectX2 = mouse.x;
                    viewport.boxSelectY2 = mouse.y;
                }
                onReleased: function (mouse) {
                    viewport.boxSelecting = false;
                    viewport.applyBoxSelect(viewport.boxSelectX1, viewport.boxSelectY1, viewport.boxSelectX2, viewport.boxSelectY2);
                }
            }

            // New area drag: click and drag to define a rectangular area
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newarea"
                z: 998

                onPressed: {
                    viewport.areaX1 = viewport.snapX(mouseX);
                    viewport.areaY1 = viewport.snapY(mouseY);
                    viewport.areaX2 = viewport.areaX1;
                    viewport.areaY2 = viewport.areaY1;
                    viewport.areaDragging = true;
                }
                onPositionChanged: {
                    viewport.areaX2 = viewport.snapX(mouseX);
                    viewport.areaY2 = viewport.snapY(mouseY);
                }
                onReleased: {
                    viewport.areaDragging = false;
                    var w = Math.abs(viewport.areaX2 - viewport.areaX1);
                    var h = Math.abs(viewport.areaY2 - viewport.areaY1);
                    if (w > 2 && h > 2) {
                        areasModel.append({
                            x1: Math.min(viewport.areaX1, viewport.areaX2),
                            y1: Math.min(viewport.areaY1, viewport.areaY2),
                            x2: Math.max(viewport.areaX1, viewport.areaX2),
                            y2: Math.max(viewport.areaY1, viewport.areaY2),
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectArea(areasModel.count - 1);
                        buttonGrid.selectedTool = "select";
                    }
                }
            }

            // New text box drag: click and drag to define a text box
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newtext"
                z: 998

                onPressed: {
                    viewport.tbX1 = viewport.snapX(mouseX);
                    viewport.tbY1 = viewport.snapY(mouseY);
                    viewport.tbX2 = viewport.tbX1;
                    viewport.tbY2 = viewport.tbY1;
                    viewport.textBoxDragging = true;
                }
                onPositionChanged: {
                    viewport.tbX2 = viewport.snapX(mouseX);
                    viewport.tbY2 = viewport.snapY(mouseY);
                }
                onReleased: {
                    viewport.textBoxDragging = false;
                    var w = Math.abs(viewport.tbX2 - viewport.tbX1);
                    var h = Math.abs(viewport.tbY2 - viewport.tbY1);
                    if (w > 2 && h > 2) {
                        viewport.pendingFocusTextBox = textBoxesModel.count;
                        textBoxesModel.append({
                            x1: Math.min(viewport.tbX1, viewport.tbX2),
                            y1: Math.min(viewport.tbY1, viewport.tbY2),
                            x2: Math.max(viewport.tbX1, viewport.tbX2),
                            y2: Math.max(viewport.tbY1, viewport.tbY2),
                            family: textSettings.txtFamily,
                            tbWeight: textSettings.txtBold ? Font.Bold : textSettings.txtWeight,
                            size: textSettings.txtSize,
                            italic: textSettings.txtItalic,
                            underline: textSettings.txtUnderline,
                            textColor: textSettings.txtColor.toString(),
                            content: "",
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectTb(textBoxesModel.count - 1);
                        buttonGrid.selectedTool = "select";
                    }
                }
            }

            // New image drag: click and drag to define an image box
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newimage" && imageSettings.selectedFilePath !== ""
                z: 998

                onPressed: {
                    viewport.imgX1 = viewport.snapX(mouseX);
                    viewport.imgY1 = viewport.snapY(mouseY);
                    viewport.imgX2 = viewport.imgX1;
                    viewport.imgY2 = viewport.imgY1;
                    viewport.imageDragging = true;
                }
                onPositionChanged: {
                    viewport.imgX2 = viewport.snapX(mouseX);
                    viewport.imgY2 = viewport.snapY(mouseY);
                }
                onReleased: {
                    viewport.imageDragging = false;
                    var w = Math.abs(viewport.imgX2 - viewport.imgX1);
                    var h = Math.abs(viewport.imgY2 - viewport.imgY1);
                    if (w > 2 && h > 2) {
                        imagesModel.append({
                            x1: Math.min(viewport.imgX1, viewport.imgX2),
                            y1: Math.min(viewport.imgY1, viewport.imgY2),
                            x2: Math.max(viewport.imgX1, viewport.imgX2),
                            y2: Math.max(viewport.imgY1, viewport.imgY2),
                            filePath: imageSettings.selectedFilePath,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectImage(imagesModel.count - 1);
                        buttonGrid.selectedTool = "select";
                    }
                }
            }

            // New video drag: click and drag to define a video box
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newvideo" && videoSettings.selectedFilePath !== ""
                z: 998

                onPressed: {
                    viewport.vidX1 = viewport.snapX(mouseX);
                    viewport.vidY1 = viewport.snapY(mouseY);
                    viewport.vidX2 = viewport.vidX1;
                    viewport.vidY2 = viewport.vidY1;
                    viewport.videoDragging = true;
                }
                onPositionChanged: {
                    viewport.vidX2 = viewport.snapX(mouseX);
                    viewport.vidY2 = viewport.snapY(mouseY);
                }
                onReleased: {
                    viewport.videoDragging = false;
                    var w = Math.abs(viewport.vidX2 - viewport.vidX1);
                    var h = Math.abs(viewport.vidY2 - viewport.vidY1);
                    if (w > 2 && h > 2) {
                        videosModel.append({
                            x1: Math.min(viewport.vidX1, viewport.vidX2),
                            y1: Math.min(viewport.vidY1, viewport.vidY2),
                            x2: Math.max(viewport.vidX1, viewport.vidX2),
                            y2: Math.max(viewport.vidY1, viewport.vidY2),
                            filePath: videoSettings.selectedFilePath,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectVideo(videosModel.count - 1);
                        buttonGrid.selectedTool = "select";
                    }
                }
            }

            // Completed areas
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedAreas.indexOf(index) !== -1
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "area" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        color: areaDelegate.isActive && index === viewport.hoveredAreaIndex ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        border.color: (areaDelegate.isActive || areaDelegate.isRelayerHovered) ? "white" : "#666666"
                        border.width: (areaDelegate.isActive && index === viewport.hoveredAreaIndex) || areaDelegate.isRelayerHovered ? 2 : 1
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
                            anchors.margins: areaDelegate.isActive && index === viewport.hoveredAreaIndex ? 2 : 1
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

                    // Move: covers shape interior only, leaving handle regions free
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: areaDelegate.isSelect
                        z: 2
                        cursorShape: areaDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            viewport.selectArea(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            if (areaDelegate.isActive) {
                                areaDelegate.pressVpX = pt.x;
                                areaDelegate.pressVpY = pt.y;
                                areaDelegate.origX1 = model.x1;
                                areaDelegate.origY1 = model.y1;
                                areaDelegate.origX2 = model.x2;
                                areaDelegate.origY2 = model.y2;
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            if (!areaDelegate.isActive)
                                return;
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var dx = pt.x - areaDelegate.pressVpX, dy = pt.y - areaDelegate.pressVpY;
                            var w = areaDelegate.origX2 - areaDelegate.origX1, h = areaDelegate.origY2 - areaDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + dx, viewport.width - w));
                            var ny1 = Math.max(0, Math.min(areaDelegate.origY1 + dy, viewport.height - h));
                            areasModel.setProperty(index, "x1", nx1);
                            areasModel.setProperty(index, "y1", ny1);
                            areasModel.setProperty(index, "x2", nx1 + w);
                            areasModel.setProperty(index, "y2", ny1 + h);
                        }
                        onReleased: viewport.elementDragging = false
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: { viewport.relayerHoveredType = "area"; viewport.relayerHoveredIndex = index; }
                        onExited: { if (!pressed && viewport.relayerHoveredType === "area" && viewport.relayerHoveredIndex === index) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPressed: function(mouse) { viewport.relayerHoveredType = "area"; viewport.relayerHoveredIndex = index; pressX = mouse.x; pressY = mouse.y; pressStack = model.stackOrder; }
                        onReleased: function(mouse) { if (!containsMouse) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPositionChanged: function(mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            areasModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Resize handles — 56x56 hit area, 8x8 visual dot, centered on shape corners/midpoints
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                areasModel.setProperty(index, "y1", Math.max(0, Math.min(areaDelegate.origY1 + pt.y - areaDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                areasModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(areaDelegate.origX2 + pt.x - areaDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewport.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                areasModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(areaDelegate.origX1 + pt.x - areaDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewport.height, Math.max(areaDelegate.origY2 + pt.y - areaDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: areaDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                areasModel.setProperty(index, "x1", Math.max(0, Math.min(areaDelegate.origX1 + pt.x - areaDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedTbs.indexOf(index) !== -1
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "tb" && viewport.relayerHoveredIndex === index
                    property bool editing: false
                    onEditingChanged: viewport.textEditing = editing
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

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        color: "transparent"
                        border.color: (tbDelegate.isActive || tbDelegate.isRelayerHovered) ? "white" : "#666666"
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
                        z: 2
                        cursorShape: tbDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onDoubleClicked: {
                            if (tbDelegate.isActive) {
                                tbDelegate.editing = true;
                                tbTextEdit.forceActiveFocus();
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.selectTb(index);
                            if (tbDelegate.isSelect) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                tbDelegate.pressVpX = pt.x;
                                tbDelegate.pressVpY = pt.y;
                                tbDelegate.origX1 = model.x1;
                                tbDelegate.origY1 = model.y1;
                                tbDelegate.origX2 = model.x2;
                                tbDelegate.origY2 = model.y2;
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            if (tbDelegate.isActive && tbDelegate.isSelect) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var dx = pt.x - tbDelegate.pressVpX, dy = pt.y - tbDelegate.pressVpY;
                                var w = tbDelegate.origX2 - tbDelegate.origX1, h = tbDelegate.origY2 - tbDelegate.origY1;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + dx, viewport.width - w));
                                var ny1 = Math.max(0, Math.min(tbDelegate.origY1 + dy, viewport.height - h));
                                textBoxesModel.setProperty(index, "x1", nx1);
                                textBoxesModel.setProperty(index, "y1", ny1);
                                textBoxesModel.setProperty(index, "x2", nx1 + w);
                                textBoxesModel.setProperty(index, "y2", ny1 + h);
                            }
                        }
                        onReleased: viewport.elementDragging = false
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: { viewport.relayerHoveredType = "tb"; viewport.relayerHoveredIndex = index; }
                        onExited: { if (!pressed && viewport.relayerHoveredType === "tb" && viewport.relayerHoveredIndex === index) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPressed: function(mouse) { viewport.relayerHoveredType = "tb"; viewport.relayerHoveredIndex = index; pressX = mouse.x; pressY = mouse.y; pressStack = model.stackOrder; }
                        onReleased: function(mouse) { if (!containsMouse) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPositionChanged: function(mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            textBoxesModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Resize handles — 56x56 hit area, 8x8 visual dot, centered on shape corners/midpoints
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                textBoxesModel.setProperty(index, "y1", Math.max(0, Math.min(tbDelegate.origY1 + pt.y - tbDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56
                        y: 0
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                textBoxesModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(tbDelegate.origX2 + pt.x - tbDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewport.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                textBoxesModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0
                        y: parent.height - 56
                        width: 56
                        height: 56
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(tbDelegate.origX1 + pt.x - tbDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewport.height, Math.max(tbDelegate.origY2 + pt.y - tbDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: tbDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                textBoxesModel.setProperty(index, "x1", Math.max(0, Math.min(tbDelegate.origX1 + pt.x - tbDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }

                    Component.onCompleted: {
                        if (index === viewport.pendingFocusTextBox) {
                            tbDelegate.editing = true;
                            tbTextEdit.forceActiveFocus();
                            viewport.pendingFocusTextBox = -1;
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedImages.indexOf(index) !== -1
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "image" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1

                    // Image fill
                    Image {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        source: model.filePath
                        fillMode: Image.Stretch
                        clip: true
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: (imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "white" : "transparent"
                        border.width: imgDelegate.isRelayerHovered ? 2 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: (imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "black" : "transparent"
                            border.width: 1
                        }
                    }

                    // Move
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: imgDelegate.isSelect
                        z: 2
                        cursorShape: imgDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            viewport.selectImage(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            if (imgDelegate.isActive) {
                                imgDelegate.pressVpX = pt.x;
                                imgDelegate.pressVpY = pt.y;
                                imgDelegate.origX1 = model.x1;
                                imgDelegate.origY1 = model.y1;
                                imgDelegate.origX2 = model.x2;
                                imgDelegate.origY2 = model.y2;
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            if (!imgDelegate.isActive) return;
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var dx = pt.x - imgDelegate.pressVpX, dy = pt.y - imgDelegate.pressVpY;
                            var w = imgDelegate.origX2 - imgDelegate.origX1, h = imgDelegate.origY2 - imgDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + dx, viewport.width - w));
                            var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + dy, viewport.height - h));
                            imagesModel.setProperty(index, "x1", nx1);
                            imagesModel.setProperty(index, "y1", ny1);
                            imagesModel.setProperty(index, "x2", nx1 + w);
                            imagesModel.setProperty(index, "y2", ny1 + h);
                        }
                        onReleased: viewport.elementDragging = false
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: { viewport.relayerHoveredType = "image"; viewport.relayerHoveredIndex = index; }
                        onExited: { if (!pressed && viewport.relayerHoveredType === "image" && viewport.relayerHoveredIndex === index) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPressed: function(mouse) { viewport.relayerHoveredType = "image"; viewport.relayerHoveredIndex = index; pressX = mouse.x; pressY = mouse.y; pressStack = model.stackOrder; }
                        onReleased: function(mouse) { if (!containsMouse) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPositionChanged: function(mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            imagesModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item { x: 0; y: 0; width: 56; height: 56; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.pressVpY = pt.y; imgDelegate.origX1 = model.x1; imgDelegate.origY1 = model.y1; imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20)); var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = model.x2 - nx1, nH = model.y2 - ny1; if (nW / nH > imgDelegate.origAspect) { nW = nH * imgDelegate.origAspect; nx1 = model.x2 - nW; } else { nH = nW / imgDelegate.origAspect; ny1 = model.y2 - nH; } } imagesModel.setProperty(index, "x1", nx1); imagesModel.setProperty(index, "y1", ny1); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Top-mid
                    Item { x: parent.width / 2 - 14; y: 14; width: 28; height: 28; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpY = pt.y; imgDelegate.origY1 = model.y1; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragY = pt.y; imagesModel.setProperty(index, "y1", Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Top-right
                    Item { x: parent.width - 56; y: 0; width: 56; height: 56; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.pressVpY = pt.y; imgDelegate.origX2 = model.x2; imgDelegate.origY1 = model.y1; imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx2 = Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20)); var ny1 = Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = nx2 - model.x1, nH = model.y2 - ny1; if (nW / nH > imgDelegate.origAspect) { nW = nH * imgDelegate.origAspect; nx2 = model.x1 + nW; } else { nH = nW / imgDelegate.origAspect; ny1 = model.y2 - nH; } } imagesModel.setProperty(index, "x2", nx2); imagesModel.setProperty(index, "y1", ny1); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Right-mid
                    Item { x: parent.width - 42; y: parent.height / 2 - 14; width: 28; height: 28; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.origX2 = model.x2; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; imagesModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-right
                    Item { x: parent.width - 56; y: parent.height - 56; width: 56; height: 56; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.pressVpY = pt.y; imgDelegate.origX2 = model.x2; imgDelegate.origY2 = model.y2; imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx2 = Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20)); var ny2 = Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = nx2 - model.x1, nH = ny2 - model.y1; if (nW / nH > imgDelegate.origAspect) { nW = nH * imgDelegate.origAspect; nx2 = model.x1 + nW; } else { nH = nW / imgDelegate.origAspect; ny2 = model.y1 + nH; } } imagesModel.setProperty(index, "x2", nx2); imagesModel.setProperty(index, "y2", ny2); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-mid
                    Item { x: parent.width / 2 - 14; y: parent.height - 42; width: 28; height: 28; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpY = pt.y; imgDelegate.origY2 = model.y2; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragY = pt.y; imagesModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-left
                    Item { x: 0; y: parent.height - 56; width: 56; height: 56; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.pressVpY = pt.y; imgDelegate.origX1 = model.x1; imgDelegate.origY2 = model.y2; imgDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20)); var ny2 = Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = model.x2 - nx1, nH = ny2 - model.y1; if (nW / nH > imgDelegate.origAspect) { nW = nH * imgDelegate.origAspect; nx1 = model.x2 - nW; } else { nH = nW / imgDelegate.origAspect; ny2 = model.y1 + nH; } } imagesModel.setProperty(index, "x1", nx1); imagesModel.setProperty(index, "y2", ny2); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Left-mid
                    Item { x: 14; y: parent.height / 2 - 14; width: 28; height: 28; visible: imgDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); imgDelegate.pressVpX = pt.x; imgDelegate.origX1 = model.x1; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; imagesModel.setProperty(index, "x1", Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20))); }
                            onReleased: viewport.elementDragging = false }
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedVideos.indexOf(index) !== -1
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "video" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1

                    // Video fill
                    MediaPlayer {
                        id: vidPlayer
                        source: model.filePath
                        autoPlay: true
                        loops: MediaPlayer.Infinite
                        videoOutput: vidOutput
                    }
                    VideoOutput {
                        id: vidOutput
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: (vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "white" : "transparent"
                        border.width: vidDelegate.isRelayerHovered ? 2 : 1
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            color: "transparent"
                            border.color: (vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "black" : "transparent"
                            border.width: 1
                        }
                    }

                    // Move
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: vidDelegate.isSelect
                        z: 2
                        cursorShape: vidDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            viewport.selectVideo(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            if (vidDelegate.isActive) {
                                vidDelegate.pressVpX = pt.x;
                                vidDelegate.pressVpY = pt.y;
                                vidDelegate.origX1 = model.x1;
                                vidDelegate.origY1 = model.y1;
                                vidDelegate.origX2 = model.x2;
                                vidDelegate.origY2 = model.y2;
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            if (!vidDelegate.isActive) return;
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var dx = pt.x - vidDelegate.pressVpX, dy = pt.y - vidDelegate.pressVpY;
                            var w = vidDelegate.origX2 - vidDelegate.origX1, h = vidDelegate.origY2 - vidDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + dx, viewport.width - w));
                            var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + dy, viewport.height - h));
                            videosModel.setProperty(index, "x1", nx1);
                            videosModel.setProperty(index, "y1", ny1);
                            videosModel.setProperty(index, "x2", nx1 + w);
                            videosModel.setProperty(index, "y2", ny1 + h);
                        }
                        onReleased: viewport.elementDragging = false
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28; y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: { viewport.relayerHoveredType = "video"; viewport.relayerHoveredIndex = index; }
                        onExited: { if (!pressed && viewport.relayerHoveredType === "video" && viewport.relayerHoveredIndex === index) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPressed: function(mouse) { viewport.relayerHoveredType = "video"; viewport.relayerHoveredIndex = index; pressX = mouse.x; pressY = mouse.y; pressStack = model.stackOrder; }
                        onReleased: function(mouse) { if (!containsMouse) { viewport.relayerHoveredType = ""; viewport.relayerHoveredIndex = -1; } }
                        onPositionChanged: function(mouse) {
                            var delta = (mouse.x - pressX) - (mouse.y - pressY);
                            videosModel.setProperty(index, "stackOrder", Math.max(-99, Math.min(890, pressStack + Math.round(delta / 20))));
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item { x: 0; y: 0; width: 56; height: 56; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.pressVpY = pt.y; vidDelegate.origX1 = model.x1; vidDelegate.origY1 = model.y1; vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20)); var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = model.x2 - nx1, nH = model.y2 - ny1; if (nW / nH > vidDelegate.origAspect) { nW = nH * vidDelegate.origAspect; nx1 = model.x2 - nW; } else { nH = nW / vidDelegate.origAspect; ny1 = model.y2 - nH; } } videosModel.setProperty(index, "x1", nx1); videosModel.setProperty(index, "y1", ny1); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Top-mid
                    Item { x: parent.width / 2 - 14; y: 14; width: 28; height: 28; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpY = pt.y; vidDelegate.origY1 = model.y1; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragY = pt.y; videosModel.setProperty(index, "y1", Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Top-right
                    Item { x: parent.width - 56; y: 0; width: 56; height: 56; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.pressVpY = pt.y; vidDelegate.origX2 = model.x2; vidDelegate.origY1 = model.y1; vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx2 = Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20)); var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = nx2 - model.x1, nH = model.y2 - ny1; if (nW / nH > vidDelegate.origAspect) { nW = nH * vidDelegate.origAspect; nx2 = model.x1 + nW; } else { nH = nW / vidDelegate.origAspect; ny1 = model.y2 - nH; } } videosModel.setProperty(index, "x2", nx2); videosModel.setProperty(index, "y1", ny1); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Right-mid
                    Item { x: parent.width - 42; y: parent.height / 2 - 14; width: 28; height: 28; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.origX2 = model.x2; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; videosModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-right
                    Item { x: parent.width - 56; y: parent.height - 56; width: 56; height: 56; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeFDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.pressVpY = pt.y; vidDelegate.origX2 = model.x2; vidDelegate.origY2 = model.y2; vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx2 = Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20)); var ny2 = Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = nx2 - model.x1, nH = ny2 - model.y1; if (nW / nH > vidDelegate.origAspect) { nW = nH * vidDelegate.origAspect; nx2 = model.x1 + nW; } else { nH = nW / vidDelegate.origAspect; ny2 = model.y1 + nH; } } videosModel.setProperty(index, "x2", nx2); videosModel.setProperty(index, "y2", ny2); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-mid
                    Item { x: parent.width / 2 - 14; y: parent.height - 42; width: 28; height: 28; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpY = pt.y; vidDelegate.origY2 = model.y2; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragY = pt.y; videosModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Bottom-left
                    Item { x: 0; y: parent.height - 56; width: 56; height: 56; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeBDiagCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.pressVpY = pt.y; vidDelegate.origX1 = model.x1; vidDelegate.origY2 = model.y2; vidDelegate.origAspect = (model.x2 - model.x1) / (model.y2 - model.y1); viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20)); var ny2 = Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20)); if (mouse.modifiers & Qt.ShiftModifier) { var nW = model.x2 - nx1, nH = ny2 - model.y1; if (nW / nH > vidDelegate.origAspect) { nW = nH * vidDelegate.origAspect; nx1 = model.x2 - nW; } else { nH = nW / vidDelegate.origAspect; ny2 = model.y1 + nH; } } videosModel.setProperty(index, "x1", nx1); videosModel.setProperty(index, "y2", ny2); }
                            onReleased: viewport.elementDragging = false }
                    }
                    // Left-mid
                    Item { x: 14; y: parent.height / 2 - 14; width: 28; height: 28; visible: vidDelegate.isActive && viewport.selectionCount === 1; z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); vidDelegate.pressVpX = pt.x; vidDelegate.origX1 = model.x1; viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y; }
                            onPositionChanged: function (mouse) { var pt = mapToItem(viewport, mouse.x, mouse.y); viewport.elementDragX = pt.x; videosModel.setProperty(index, "x1", Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20))); }
                            onReleased: viewport.elementDragging = false }
                    }
                }
            }

            // In-progress text box rubber-band
            Rectangle {
                visible: viewport.textBoxDragging
                x: Math.min(viewport.tbX1, viewport.tbX2)
                y: Math.min(viewport.tbY1, viewport.tbY2)
                width: Math.abs(viewport.tbX2 - viewport.tbX1)
                height: Math.abs(viewport.tbY2 - viewport.tbY1)
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
                visible: viewport.imageDragging
                x: Math.min(viewport.imgX1, viewport.imgX2)
                y: Math.min(viewport.imgY1, viewport.imgY2)
                width: Math.abs(viewport.imgX2 - viewport.imgX1)
                height: Math.abs(viewport.imgY2 - viewport.imgY1)
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
                visible: viewport.videoDragging
                x: Math.min(viewport.vidX1, viewport.vidX2)
                y: Math.min(viewport.vidY1, viewport.vidY2)
                width: Math.abs(viewport.vidX2 - viewport.vidX1)
                height: Math.abs(viewport.vidY2 - viewport.vidY1)
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

            // Box-select rubber band
            Rectangle {
                visible: viewport.boxSelecting
                x: Math.min(viewport.boxSelectX1, viewport.boxSelectX2)
                y: Math.min(viewport.boxSelectY1, viewport.boxSelectY2)
                width: Math.abs(viewport.boxSelectX2 - viewport.boxSelectX1)
                height: Math.abs(viewport.boxSelectY2 - viewport.boxSelectY1)
                color: Qt.rgba(0.5, 0.7, 1.0, 0.08)
                border.color: Qt.rgba(0.5, 0.7, 1.0, 0.9)
                border.width: 1
                z: 998
            }

            // Group bounding box — shown when 2+ elements are selected
            Item {
                id: groupBBox
                visible: buttonGrid.selectedTool === "select" && viewport.selectionCount > 1
                z: 998

                // Own-position properties, updated imperatively
                property real gbX1: 0
                property real gbY1: 0
                property real gbX2: 0
                property real gbY2: 0

                x: gbX1 - 28
                y: gbY1 - 28
                width: gbX2 - gbX1 + 56
                height: gbY2 - gbY1 + 56

                // Drag snapshot state
                property real pressVpX: 0
                property real pressVpY: 0
                property var snapshots: []
                property var snapGroupBounds: null
                property real origAspect: 1

                function refreshBounds() {
                    var b = viewport.groupBounds();
                    if (b) {
                        gbX1 = b.x1;
                        gbY1 = b.y1;
                        gbX2 = b.x2;
                        gbY2 = b.y2;
                    }
                }

                Connections {
                    target: viewport
                    function onSelectionRevisionChanged() {
                        groupBBox.refreshBounds();
                    }
                }
                onVisibleChanged: if (visible)
                    refreshBounds()

                function snapshotAll() {
                    var snaps = [];
                    for (var i = 0; i < viewport.selectedAreas.length; i++) {
                        var a = areasModel.get(viewport.selectedAreas[i]);
                        snaps.push({
                            type: "area",
                            idx: viewport.selectedAreas[i],
                            x1: a.x1,
                            y1: a.y1,
                            x2: a.x2,
                            y2: a.y2
                        });
                    }
                    for (var j = 0; j < viewport.selectedTbs.length; j++) {
                        var t = textBoxesModel.get(viewport.selectedTbs[j]);
                        snaps.push({
                            type: "tb",
                            idx: viewport.selectedTbs[j],
                            x1: t.x1,
                            y1: t.y1,
                            x2: t.x2,
                            y2: t.y2
                        });
                    }
                    for (var k = 0; k < viewport.selectedImages.length; k++) {
                        var im = imagesModel.get(viewport.selectedImages[k]);
                        snaps.push({
                            type: "image",
                            idx: viewport.selectedImages[k],
                            x1: im.x1,
                            y1: im.y1,
                            x2: im.x2,
                            y2: im.y2
                        });
                    }
                    for (var l = 0; l < viewport.selectedVideos.length; l++) {
                        var v = videosModel.get(viewport.selectedVideos[l]);
                        snaps.push({
                            type: "video",
                            idx: viewport.selectedVideos[l],
                            x1: v.x1,
                            y1: v.y1,
                            x2: v.x2,
                            y2: v.y2
                        });
                    }
                    snapshots = snaps;
                    snapGroupBounds = {
                        x1: gbX1,
                        y1: gbY1,
                        x2: gbX2,
                        y2: gbY2
                    };
                }

                function applyMove(dx, dy) {
                    var sgb = snapGroupBounds;
                    var cdx = Math.max(-sgb.x1, Math.min(dx, viewport.width - sgb.x2));
                    var cdy = Math.max(-sgb.y1, Math.min(dy, viewport.height - sgb.y2));
                    gbX1 = sgb.x1 + cdx;
                    gbY1 = sgb.y1 + cdy;
                    gbX2 = sgb.x2 + cdx;
                    gbY2 = sgb.y2 + cdy;
                    for (var i = 0; i < snapshots.length; i++) {
                        var s = snapshots[i];
                        if (s.type === "area") {
                            areasModel.setProperty(s.idx, "x1", s.x1 + cdx);
                            areasModel.setProperty(s.idx, "y1", s.y1 + cdy);
                            areasModel.setProperty(s.idx, "x2", s.x2 + cdx);
                            areasModel.setProperty(s.idx, "y2", s.y2 + cdy);
                        } else if (s.type === "tb") {
                            textBoxesModel.setProperty(s.idx, "x1", s.x1 + cdx);
                            textBoxesModel.setProperty(s.idx, "y1", s.y1 + cdy);
                            textBoxesModel.setProperty(s.idx, "x2", s.x2 + cdx);
                            textBoxesModel.setProperty(s.idx, "y2", s.y2 + cdy);
                        } else if (s.type === "image") {
                            imagesModel.setProperty(s.idx, "x1", s.x1 + cdx);
                            imagesModel.setProperty(s.idx, "y1", s.y1 + cdy);
                            imagesModel.setProperty(s.idx, "x2", s.x2 + cdx);
                            imagesModel.setProperty(s.idx, "y2", s.y2 + cdy);
                        } else if (s.type === "video") {
                            videosModel.setProperty(s.idx, "x1", s.x1 + cdx);
                            videosModel.setProperty(s.idx, "y1", s.y1 + cdy);
                            videosModel.setProperty(s.idx, "x2", s.x2 + cdx);
                            videosModel.setProperty(s.idx, "y2", s.y2 + cdy);
                        }
                    }
                }

                function applyScale(newGx1, newGy1, newGx2, newGy2) {
                    var sgb = snapGroupBounds;
                    var ogw = sgb.x2 - sgb.x1, ogh = sgb.y2 - sgb.y1;
                    if (ogw <= 0 || ogh <= 0)
                        return;
                    var ngw = Math.max(20, newGx2 - newGx1);
                    var ngh = Math.max(20, newGy2 - newGy1);
                    gbX1 = newGx1;
                    gbY1 = newGy1;
                    gbX2 = newGx1 + ngw;
                    gbY2 = newGy1 + ngh;
                    for (var i = 0; i < snapshots.length; i++) {
                        var s = snapshots[i];
                        var nx1 = Math.round(newGx1 + (s.x1 - sgb.x1) / ogw * ngw);
                        var ny1 = Math.round(newGy1 + (s.y1 - sgb.y1) / ogh * ngh);
                        var nx2 = Math.round(newGx1 + (s.x2 - sgb.x1) / ogw * ngw);
                        var ny2 = Math.round(newGy1 + (s.y2 - sgb.y1) / ogh * ngh);
                        if (s.type === "area") {
                            areasModel.setProperty(s.idx, "x1", nx1);
                            areasModel.setProperty(s.idx, "y1", ny1);
                            areasModel.setProperty(s.idx, "x2", nx2);
                            areasModel.setProperty(s.idx, "y2", ny2);
                        } else if (s.type === "tb") {
                            textBoxesModel.setProperty(s.idx, "x1", nx1);
                            textBoxesModel.setProperty(s.idx, "y1", ny1);
                            textBoxesModel.setProperty(s.idx, "x2", nx2);
                            textBoxesModel.setProperty(s.idx, "y2", ny2);
                        } else if (s.type === "image") {
                            imagesModel.setProperty(s.idx, "x1", nx1);
                            imagesModel.setProperty(s.idx, "y1", ny1);
                            imagesModel.setProperty(s.idx, "x2", nx2);
                            imagesModel.setProperty(s.idx, "y2", ny2);
                        } else if (s.type === "video") {
                            videosModel.setProperty(s.idx, "x1", nx1);
                            videosModel.setProperty(s.idx, "y1", ny1);
                            videosModel.setProperty(s.idx, "x2", nx2);
                            videosModel.setProperty(s.idx, "y2", ny2);
                        }
                    }
                }

                // Visual border
                Rectangle {
                    x: 28
                    y: 28
                    width: parent.width - 56
                    height: parent.height - 56
                    color: "transparent"
                    border.color: "white"
                    border.width: 1
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: "transparent"
                        border.color: "black"
                        border.width: 1
                    }
                }

                // Move: drag interior
                MouseArea {
                    x: 28
                    y: 28
                    width: parent.width - 56
                    height: parent.height - 56
                    z: 2
                    cursorShape: Qt.SizeAllCursor
                    onPressed: function (mouse) {
                        var pt = mapToItem(viewport, mouse.x, mouse.y);
                        groupBBox.pressVpX = pt.x;
                        groupBBox.pressVpY = pt.y;
                        groupBBox.snapshotAll();
                        viewport.elementDragging = true;
                        viewport.elementDragX = pt.x;
                        viewport.elementDragY = pt.y;
                    }
                    onPositionChanged: function (mouse) {
                        var pt = mapToItem(viewport, mouse.x, mouse.y);
                        viewport.elementDragX = pt.x;
                        viewport.elementDragY = pt.y;
                        groupBBox.applyMove(pt.x - groupBBox.pressVpX, pt.y - groupBBox.pressVpY);
                    }
                    onReleased: viewport.elementDragging = false
                }

                // Resize handles — corners 56×56, midpoints 28×28
                // Top-left
                Item {
                    x: 0
                    y: 0
                    width: 56
                    height: 56
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            groupBBox.origAspect = (groupBBox.gbX2 - groupBBox.gbX1) / (groupBBox.gbY2 - groupBBox.gbY1);
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            var nx1 = Math.max(0, Math.min(gb.x1 + pt.x - groupBBox.pressVpX, gb.x2 - 20));
                            var ny1 = Math.max(0, Math.min(gb.y1 + pt.y - groupBBox.pressVpY, gb.y2 - 20));
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                var nW = gb.x2 - nx1, nH = gb.y2 - ny1;
                                if (nW / nH > groupBBox.origAspect) {
                                    nW = nH * groupBBox.origAspect;
                                    nx1 = gb.x2 - nW;
                                } else {
                                    nH = nW / groupBBox.origAspect;
                                    ny1 = gb.y2 - nH;
                                }
                            }
                            groupBBox.applyScale(nx1, ny1, gb.x2, gb.y2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Top-mid
                Item {
                    x: parent.width / 2 - 14
                    y: 14
                    width: 28
                    height: 28
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
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            groupBBox.applyScale(gb.x1, Math.max(0, Math.min(gb.y1 + pt.y - groupBBox.pressVpY, gb.y2 - 20)), gb.x2, gb.y2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Top-right
                Item {
                    x: parent.width - 56
                    y: 0
                    width: 56
                    height: 56
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            groupBBox.origAspect = (groupBBox.gbX2 - groupBBox.gbX1) / (groupBBox.gbY2 - groupBBox.gbY1);
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            var nx2 = Math.min(viewport.width, Math.max(gb.x2 + pt.x - groupBBox.pressVpX, gb.x1 + 20));
                            var ny1 = Math.max(0, Math.min(gb.y1 + pt.y - groupBBox.pressVpY, gb.y2 - 20));
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                var nW = nx2 - gb.x1, nH = gb.y2 - ny1;
                                if (nW / nH > groupBBox.origAspect) {
                                    nW = nH * groupBBox.origAspect;
                                    nx2 = gb.x1 + nW;
                                } else {
                                    nH = nW / groupBBox.origAspect;
                                    ny1 = gb.y2 - nH;
                                }
                            }
                            groupBBox.applyScale(gb.x1, ny1, nx2, gb.y2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Right-mid
                Item {
                    x: parent.width - 42
                    y: parent.height / 2 - 14
                    width: 28
                    height: 28
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.snapshotAll();
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            var gb = groupBBox.snapGroupBounds;
                            groupBBox.applyScale(gb.x1, gb.y1, Math.min(viewport.width, Math.max(gb.x2 + pt.x - groupBBox.pressVpX, gb.x1 + 20)), gb.y2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Bottom-right
                Item {
                    x: parent.width - 56
                    y: parent.height - 56
                    width: 56
                    height: 56
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            groupBBox.origAspect = (groupBBox.gbX2 - groupBBox.gbX1) / (groupBBox.gbY2 - groupBBox.gbY1);
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            var nx2 = Math.min(viewport.width, Math.max(gb.x2 + pt.x - groupBBox.pressVpX, gb.x1 + 20));
                            var ny2 = Math.min(viewport.height, Math.max(gb.y2 + pt.y - groupBBox.pressVpY, gb.y1 + 20));
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                var nW = nx2 - gb.x1, nH = ny2 - gb.y1;
                                if (nW / nH > groupBBox.origAspect) {
                                    nW = nH * groupBBox.origAspect;
                                    nx2 = gb.x1 + nW;
                                } else {
                                    nH = nW / groupBBox.origAspect;
                                    ny2 = gb.y1 + nH;
                                }
                            }
                            groupBBox.applyScale(gb.x1, gb.y1, nx2, ny2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Bottom-mid
                Item {
                    x: parent.width / 2 - 14
                    y: parent.height - 42
                    width: 28
                    height: 28
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
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            groupBBox.applyScale(gb.x1, gb.y1, gb.x2, Math.min(viewport.height, Math.max(gb.y2 + pt.y - groupBBox.pressVpY, gb.y1 + 20)));
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Bottom-left
                Item {
                    x: 0
                    y: parent.height - 56
                    width: 56
                    height: 56
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.pressVpY = pt.y;
                            groupBBox.snapshotAll();
                            groupBBox.origAspect = (groupBBox.gbX2 - groupBBox.gbX1) / (groupBBox.gbY2 - groupBBox.gbY1);
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var gb = groupBBox.snapGroupBounds;
                            var nx1 = Math.max(0, Math.min(gb.x1 + pt.x - groupBBox.pressVpX, gb.x2 - 20));
                            var ny2 = Math.min(viewport.height, Math.max(gb.y2 + pt.y - groupBBox.pressVpY, gb.y1 + 20));
                            if (mouse.modifiers & Qt.ShiftModifier) {
                                var nW = gb.x2 - nx1, nH = ny2 - gb.y1;
                                if (nW / nH > groupBBox.origAspect) {
                                    nW = nH * groupBBox.origAspect;
                                    nx1 = gb.x2 - nW;
                                } else {
                                    nH = nW / groupBBox.origAspect;
                                    ny2 = gb.y1 + nH;
                                }
                            }
                            groupBBox.applyScale(nx1, gb.y1, gb.x2, ny2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
                // Left-mid
                Item {
                    x: 14
                    y: parent.height / 2 - 14
                    width: 28
                    height: 28
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
                            groupBBox.pressVpX = pt.x;
                            groupBBox.snapshotAll();
                            viewport.elementDragging = true;
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                        }
                        onPositionChanged: function (mouse) {
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            var gb = groupBBox.snapGroupBounds;
                            groupBBox.applyScale(Math.max(0, Math.min(gb.x1 + pt.x - groupBBox.pressVpX, gb.x2 - 20)), gb.y1, gb.x2, gb.y2);
                        }
                        onReleased: viewport.elementDragging = false
                    }
                }
            }

            FileDialog {
                id: imageFileDialog
                title: "Select image file"
                nameFilters: ["Image files (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.svg)"]
                onAccepted: imageSettings.selectedFilePath = selectedFile.toString()
            }

            FileDialog {
                id: videoFileDialog
                title: "Select video file"
                nameFilters: ["Video files (*.mp4 *.mov *.avi *.mkv *.webm *.m4v)"]
                onAccepted: videoSettings.selectedFilePath = selectedFile.toString()
            }

            // Tool cursor
            MouseArea {
                id: viewportCursorArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: viewport.textEditing ? Qt.IBeamCursor : (["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1 ? Qt.BlankCursor : Qt.ArrowCursor)
                z: 999
                onPositionChanged: viewport.hoveredAreaIndex = viewport.findHoveredArea(mouseX, mouseY)
                onExited: viewport.hoveredAreaIndex = -1
            }

            Image {
                x: (viewport.areaDragging ? viewport.areaX2 : (viewport.textBoxDragging ? viewport.tbX2 : (viewport.imageDragging ? viewport.imgX2 : (viewport.videoDragging ? viewport.vidX2 : (viewport.elementDragging ? viewport.elementDragX : (viewport.boxSelecting ? viewport.boxSelectX2 : viewportCursorArea.mouseX)))))) + (buttonGrid.selectedTool === "select" ? -8 : 0)
                y: (viewport.areaDragging ? viewport.areaY2 : (viewport.textBoxDragging ? viewport.tbY2 : (viewport.imageDragging ? viewport.imgY2 : (viewport.videoDragging ? viewport.vidY2 : (viewport.elementDragging ? viewport.elementDragY : (viewport.boxSelecting ? viewport.boxSelectY2 : viewportCursorArea.mouseY)))))) + (buttonGrid.selectedTool === "select" ? -1 : 0)
                width: 36
                height: 36
                source: viewport.elementDragging ? "icons/pinch.svg" : (["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1 ? "icons/" + buttonGrid.selectedTool + ".svg" : "")
                visible: !viewport.textEditing && viewportCursorArea.containsMouse && (viewport.elementDragging || ["select", "newlink", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo"].indexOf(buttonGrid.selectedTool) !== -1)
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
                z: 998

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

                    property string selectedFilePath: ""

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

                    Column {
                        anchors.top: imageSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 8

                        // Image drop zone
                        Rectangle {
                            width: parent.width
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                id: dropImageIcon
                                anchors.centerIn: parent
                                width: 48; height: 48
                                source: "icons/dropimage.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: imageSettings.selectedFilePath === ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: imageSettings.selectedFilePath !== "" ? imageSettings.selectedFilePath.replace(/.*\//, "") : ""
                                color: "#aaa"
                                font.pixelSize: 11
                                elide: Text.ElideLeft
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                visible: imageSettings.selectedFilePath !== ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: imageFileDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (drop.hasUrls)
                                        imageSettings.selectedFilePath = drop.urls[0].toString()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: videoSettings
                    visible: buttonGrid.selectedTool === "newvideo"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string selectedFilePath: ""

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

                    Column {
                        anchors.top: videoSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 8

                        // Video drop zone
                        Rectangle {
                            width: parent.width
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                id: dropVideoIcon
                                anchors.centerIn: parent
                                width: 48; height: 48
                                source: "icons/dropvideo.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: videoSettings.selectedFilePath === ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: videoSettings.selectedFilePath !== "" ? videoSettings.selectedFilePath.replace(/.*\//, "") : ""
                                color: "#aaa"
                                font.pixelSize: 11
                                elide: Text.ElideLeft
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                visible: videoSettings.selectedFilePath !== ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: videoFileDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (drop.hasUrls)
                                        videoSettings.selectedFilePath = drop.urls[0].toString()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: textSettings
                    visible: buttonGrid.selectedTool === "newtext"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    // Formatting settings applied to each new text box at creation time
                    readonly property var fontFamilies: Qt.fontFamilies()
                    property int txtFamilyIndex: 0
                    property string txtFamily: fontFamilies.length > 0 ? fontFamilies[txtFamilyIndex] : "Mona Sans"

                    Component.onCompleted: {
                        var idx = fontFamilies.indexOf("Mona Sans");
                        if (idx !== -1)
                            txtFamilyIndex = idx;
                    }
                    readonly property var weightNames: ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"]
                    readonly property var weightValues: [Font.Thin, Font.ExtraLight, Font.Light, Font.Normal, Font.Medium, Font.DemiBold, Font.Bold, Font.ExtraBold, Font.Black]
                    property int txtWeightIndex: 3
                    property int txtWeight: weightValues[txtWeightIndex]
                    property int txtSize: 16
                    property bool txtBold: false
                    property bool txtItalic: false
                    property bool txtUnderline: false
                    property color txtColor: "white"

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

                    Column {
                        anchors.top: textSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 8

                        // Font family
                        ComboBox {
                            id: familyCombo
                            width: parent.width
                            height: 26
                            model: textSettings.fontFamilies
                            currentIndex: textSettings.txtFamilyIndex
                            onCurrentIndexChanged: textSettings.txtFamilyIndex = currentIndex

                            contentItem: Text {
                                leftPadding: 6
                                rightPadding: 24
                                text: familyCombo.displayText
                                font.pixelSize: 11
                                color: "white"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            indicator: Text {
                                x: familyCombo.width - width - 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                font.pixelSize: 10
                                color: "white"
                            }
                            background: Rectangle {
                                radius: 4
                                color: "transparent"
                                border.color: "white"
                                border.width: 1
                            }
                            popup: Popup {
                                y: familyCombo.height + 2
                                width: familyCombo.width
                                height: Math.min(familyListView.contentHeight, 180)
                                padding: 1
                                background: Rectangle {
                                    color: "#162020"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4
                                }
                                contentItem: ListView {
                                    id: familyListView
                                    clip: true
                                    model: familyCombo.delegateModel
                                    currentIndex: familyCombo.currentIndex
                                    ScrollBar.vertical: ScrollBar {}
                                }
                            }
                            delegate: ItemDelegate {
                                width: familyCombo.width
                                height: 22
                                padding: 0
                                highlighted: familyCombo.highlightedIndex === index
                                contentItem: Text {
                                    text: modelData
                                    font.pixelSize: 11
                                    color: "white"
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 6
                                }
                                background: Rectangle {
                                    color: familyCombo.highlightedIndex === index ? "#477B78" : "transparent"
                                }
                            }
                        }

                        // Weight + size
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            ComboBox {
                                id: weightCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                model: textSettings.weightNames
                                currentIndex: textSettings.txtWeightIndex
                                onCurrentIndexChanged: textSettings.txtWeightIndex = currentIndex

                                contentItem: Text {
                                    leftPadding: 6
                                    rightPadding: 24
                                    text: weightCombo.displayText
                                    font.pixelSize: 11
                                    color: "white"
                                    verticalAlignment: Text.AlignVCenter
                                }
                                indicator: Text {
                                    x: weightCombo.width - width - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "▾"
                                    font.pixelSize: 10
                                    color: "white"
                                }
                                background: Rectangle {
                                    radius: 4
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 1
                                }
                                popup: Popup {
                                    y: weightCombo.height + 2
                                    width: weightCombo.width
                                    height: Math.min(weightListView.contentHeight, 220)
                                    padding: 1
                                    background: Rectangle {
                                        color: "#162020"
                                        border.color: "white"
                                        border.width: 1
                                        radius: 4
                                    }
                                    contentItem: ListView {
                                        id: weightListView
                                        clip: true
                                        model: weightCombo.delegateModel
                                        currentIndex: weightCombo.currentIndex
                                    }
                                }
                                delegate: ItemDelegate {
                                    width: weightCombo.width
                                    height: 22
                                    padding: 0
                                    highlighted: weightCombo.highlightedIndex === index
                                    contentItem: Text {
                                        text: modelData
                                        font.pixelSize: 11
                                        color: "white"
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 6
                                    }
                                    background: Rectangle {
                                        color: weightCombo.highlightedIndex === index ? "#477B78" : "transparent"
                                    }
                                }
                            }

                            // Size (px)
                            Rectangle {
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 26
                                color: "transparent"
                                border.color: "white"
                                border.width: 1
                                radius: 4

                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: "white"
                                    font.pixelSize: 11
                                    horizontalAlignment: TextInput.AlignHCenter
                                    text: textSettings.txtSize.toString()
                                    validator: IntValidator {
                                        bottom: 6
                                        top: 999
                                    }
                                    selectByMouse: true
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: textSettings.txtSize = parseInt(text) || 16
                                }
                            }
                        }

                        // Bold / Italic / Underline + color
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: textSettings.txtBold
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "B"
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: textSettings.txtBold = !textSettings.txtBold
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: textSettings.txtItalic
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "I"
                                    font.pixelSize: 13
                                    font.italic: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: textSettings.txtItalic = !textSettings.txtItalic
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: textSettings.txtUnderline
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "U"
                                    font.pixelSize: 13
                                    font.underline: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: textSettings.txtUnderline = !textSettings.txtUnderline
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            // Color swatch
                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                color: textSettings.txtColor
                                border.color: "white"
                                border.width: 1
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: txtColorDialog.open()
                                }
                            }
                        }
                    }

                    ColorDialog {
                        id: txtColorDialog
                        selectedColor: textSettings.txtColor
                        onAccepted: textSettings.txtColor = selectedColor
                    }
                }

                Rectangle {
                    id: selectSettings
                    visible: buttonGrid.selectedTool === "select"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    readonly property bool hasActiveArea: (viewport.selectionRevision >= 0) && viewport.selectedAreas.length === 1 && viewport.selectedTbs.length === 0
                    readonly property bool hasActiveTb: (viewport.selectionRevision >= 0) && viewport.selectedTbs.length === 1

                    // Local state for editing the active text box's formatting
                    readonly property var fontFamilies: Qt.fontFamilies()
                    property int tbFamilyIndex: 0
                    property int tbWeightIndex: 3
                    property int tbSize: 16
                    property bool tbBold: false
                    property bool tbItalic: false
                    property bool tbUnderline: false
                    property color tbColor: "white"

                    // Helper to write current formatting back to the active text box
                    function applyTbFormatting() {
                        if (!hasActiveTb)
                            return;
                        var idx = viewport.selectedTbs[0];
                        textBoxesModel.setProperty(idx, "family", fontFamilies[tbFamilyIndex] || "Mona Sans");
                        textBoxesModel.setProperty(idx, "tbWeight", tbBold ? Font.Bold : textSettings.weightValues[tbWeightIndex]);
                        textBoxesModel.setProperty(idx, "size", tbSize);
                        textBoxesModel.setProperty(idx, "italic", tbItalic);
                        textBoxesModel.setProperty(idx, "underline", tbUnderline);
                        textBoxesModel.setProperty(idx, "textColor", tbColor.toString());
                    }

                    // Sync from model whenever the selection changes
                    Connections {
                        target: viewport
                        function onSelectionRevisionChanged() {
                            if (!selectSettings.hasActiveTb)
                                return;
                            var tb = textBoxesModel.get(viewport.selectedTbs[0]);
                            var fi = selectSettings.fontFamilies.indexOf(tb.family);
                            selectSettings.tbFamilyIndex = fi !== -1 ? fi : 0;
                            var wi = textSettings.weightValues.indexOf(tb.tbWeight);
                            selectSettings.tbWeightIndex = wi !== -1 ? wi : 3;
                            selectSettings.tbSize = tb.size;
                            selectSettings.tbBold = tb.tbWeight === Font.Bold;
                            selectSettings.tbItalic = tb.italic;
                            selectSettings.tbUnderline = tb.underline;
                            selectSettings.tbColor = tb.textColor;
                        }
                    }

                    Text {
                        id: selectSettingsHeading
                        text: selectSettings.hasActiveArea ? "area" : (selectSettings.hasActiveTb ? "text" : "select")
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }

                    // Text formatting controls — visible when a text box is active
                    Column {
                        visible: selectSettings.hasActiveTb
                        anchors.top: selectSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 8

                        // Font family
                        ComboBox {
                            id: selFamilyCombo
                            width: parent.width
                            height: 26
                            model: selectSettings.fontFamilies
                            currentIndex: selectSettings.tbFamilyIndex
                            onCurrentIndexChanged: {
                                selectSettings.tbFamilyIndex = currentIndex;
                                selectSettings.applyTbFormatting();
                            }
                            contentItem: Text {
                                leftPadding: 6
                                rightPadding: 24
                                text: selFamilyCombo.displayText
                                font.pixelSize: 11
                                color: "white"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            indicator: Text {
                                x: selFamilyCombo.width - width - 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                font.pixelSize: 10
                                color: "white"
                            }
                            background: Rectangle {
                                radius: 4
                                color: "transparent"
                                border.color: "white"
                                border.width: 1
                            }
                            popup: Popup {
                                y: selFamilyCombo.height + 2
                                width: selFamilyCombo.width
                                height: Math.min(selFamilyListView.contentHeight, 180)
                                padding: 1
                                background: Rectangle {
                                    color: "#162020"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4
                                }
                                contentItem: ListView {
                                    id: selFamilyListView
                                    clip: true
                                    model: selFamilyCombo.delegateModel
                                    currentIndex: selFamilyCombo.currentIndex
                                    ScrollBar.vertical: ScrollBar {}
                                }
                            }
                            delegate: ItemDelegate {
                                width: selFamilyCombo.width
                                height: 22
                                padding: 0
                                highlighted: selFamilyCombo.highlightedIndex === index
                                contentItem: Text {
                                    text: modelData
                                    font.pixelSize: 11
                                    color: "white"
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 6
                                }
                                background: Rectangle {
                                    color: selFamilyCombo.highlightedIndex === index ? "#477B78" : "transparent"
                                }
                            }
                        }

                        // Weight + size
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            ComboBox {
                                id: selWeightCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                model: textSettings.weightNames
                                currentIndex: selectSettings.tbWeightIndex
                                onCurrentIndexChanged: {
                                    selectSettings.tbWeightIndex = currentIndex;
                                    selectSettings.applyTbFormatting();
                                }
                                contentItem: Text {
                                    leftPadding: 6
                                    rightPadding: 24
                                    text: selWeightCombo.displayText
                                    font.pixelSize: 11
                                    color: "white"
                                    verticalAlignment: Text.AlignVCenter
                                }
                                indicator: Text {
                                    x: selWeightCombo.width - width - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "▾"
                                    font.pixelSize: 10
                                    color: "white"
                                }
                                background: Rectangle {
                                    radius: 4
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 1
                                }
                                popup: Popup {
                                    y: selWeightCombo.height + 2
                                    width: selWeightCombo.width
                                    height: Math.min(selWeightListView.contentHeight, 220)
                                    padding: 1
                                    background: Rectangle {
                                        color: "#162020"
                                        border.color: "white"
                                        border.width: 1
                                        radius: 4
                                    }
                                    contentItem: ListView {
                                        id: selWeightListView
                                        clip: true
                                        model: selWeightCombo.delegateModel
                                        currentIndex: selWeightCombo.currentIndex
                                    }
                                }
                                delegate: ItemDelegate {
                                    width: selWeightCombo.width
                                    height: 22
                                    padding: 0
                                    highlighted: selWeightCombo.highlightedIndex === index
                                    contentItem: Text {
                                        text: modelData
                                        font.pixelSize: 11
                                        color: "white"
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 6
                                    }
                                    background: Rectangle {
                                        color: selWeightCombo.highlightedIndex === index ? "#477B78" : "transparent"
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 52
                                Layout.preferredHeight: 26
                                color: "transparent"
                                border.color: "white"
                                border.width: 1
                                radius: 4
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: "white"
                                    font.pixelSize: 11
                                    horizontalAlignment: TextInput.AlignHCenter
                                    text: selectSettings.tbSize.toString()
                                    validator: IntValidator {
                                        bottom: 6
                                        top: 999
                                    }
                                    selectByMouse: true
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: {
                                        selectSettings.tbSize = parseInt(text) || 16;
                                        selectSettings.applyTbFormatting();
                                    }
                                }
                            }
                        }

                        // Bold / Italic / Underline + color
                        RowLayout {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: selectSettings.tbBold
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "B"
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        selectSettings.tbBold = !selectSettings.tbBold;
                                        selectSettings.applyTbFormatting();
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: selectSettings.tbItalic
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "I"
                                    font.pixelSize: 13
                                    font.italic: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        selectSettings.tbItalic = !selectSettings.tbItalic;
                                        selectSettings.applyTbFormatting();
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                property bool on: selectSettings.tbUnderline
                                color: on ? "white" : "transparent"
                                border.color: "white"
                                border.width: 1
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 0
                                    anchors.horizontalCenterOffset: -0.5
                                    text: "U"
                                    font.pixelSize: 13
                                    font.underline: true
                                    color: parent.on ? "darkslategrey" : "white"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        selectSettings.tbUnderline = !selectSettings.tbUnderline;
                                        selectSettings.applyTbFormatting();
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 4
                                color: selectSettings.tbColor
                                border.color: "white"
                                border.width: 1
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: selTxtColorDialog.open()
                                }
                            }
                        }
                    }

                    ColorDialog {
                        id: selTxtColorDialog
                        selectedColor: selectSettings.tbColor
                        onAccepted: {
                            selectSettings.tbColor = selectedColor;
                            selectSettings.applyTbFormatting();
                        }
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
                                                    anchors.verticalCenterOffset: 0
                                                    anchors.horizontalCenterOffset: -0.5
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
                                        anchors.verticalCenterOffset: 0
                                        anchors.horizontalCenterOffset: -0.5
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
