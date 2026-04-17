import QtQuick
import QtQuick.Window
import QtMultimedia
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import QtQuick.Dialogs
import Qt.labs.platform as Platform

Window {
    id: mainWindow
    visible: true
    width: 960
    height: 540
    title: storyManager.isOpen ? "understory — " + storyManager.storyTitle : qsTr("understory")
    color: "black"
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint | Qt.MSWindowsFixedSizeDialogHint

    FontLoader {
        id: monaSans
        source: "headings/MonaSans-VariableFont_wdth,wght.ttf"
    }
    FontLoader {
        id: monaSansItalic
        source: "headings/MonaSans-Italic-VariableFont_wdth,wght.ttf"
    }

    // Native macOS menu bar
    Platform.MenuBar {
        Platform.Menu {
            title: "File"

            Platform.MenuItem {
                text: "New Story"
                shortcut: StandardKey.New
                onTriggered: {
                    saveStoryDialog.pendingAction = "new";
                    saveStoryDialog.triggerTransition = false;
                    saveStoryDialog.open();
                }
            }
            Platform.MenuItem {
                text: "Open Story…"
                shortcut: StandardKey.Open
                onTriggered: {
                    openStoryDialog.open();
                }
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: "Save Story"
                shortcut: StandardKey.Save
                enabled: storyManager.isOpen
                onTriggered: {
                    nodeWorkspace.saveToDb()
                    storyManager.saveStory()
                }
            }
            Platform.MenuItem {
                text: "Save Story As…"
                shortcut: "Ctrl+Shift+S"
                enabled: storyManager.isOpen
                onTriggered: {
                    saveStoryDialog.pendingAction = "saveas";
                    saveStoryDialog.triggerTransition = false;
                    saveStoryDialog.open();
                }
            }
        }
    }

    property int xanimationduration: 0
    property int yanimationduration: 0
    property real sceneEditorEntryX: 0
    property int currentSceneId: -1

    // flags to distinguish programmatic animations from user resize attempts
    property bool widthAnimating: false
    property bool heightAnimating: false
    property bool snapBackWidth: false
    property bool snapBackHeight: false
    property int lockedWidth: 960
    property int lockedHeight: 540

    onWidthChanged: {
        if (!widthAnimating && !snapBackWidth) {
            snapBackWidth = true
            width = lockedWidth
            snapBackWidth = false
        }
    }

    onHeightChanged: {
        if (!heightAnimating && !snapBackHeight) {
            snapBackHeight = true
            height = lockedHeight
            snapBackHeight = false
        }
    }

    // animate any change to `width`
    Behavior on width {
        enabled: !mainWindow.snapBackWidth
        SequentialAnimation {
            PropertyAction { target: mainWindow; property: "widthAnimating"; value: true }
            NumberAnimation {
                duration: 1000
                easing.type: Easing.InOutQuad
            }
            ScriptAction {
                script: {
                    mainWindow.lockedWidth = mainWindow.width
                    mainWindow.widthAnimating = false
                    if (sceneEditor2sceneMenu.windowSizeCompleteTrigger) {
                        console.log("ScriptAction triggered");
                        sceneEditor2sceneMenu.visible = true;
                        sceneEditor2sceneMenuPlayer.play();
                    } else if (mainWindow.width === 1365 && mainWindow.currentSceneId !== -1) {
                        // Just finished opening the scene editor — auto-open timeline if it was open last time
                        var tlState = storyManager.getEditorState("scene_" + mainWindow.currentSceneId + "_timeline_open");
                        if (tlState === "1") {
                            sceneEditorButtons.timelineOpen = true;
                            yanimationduration = 1000;
                            mainWindow.height = mainWindow.height + 300;
                            mainWindow.y = mainWindow.y - 150;
                        }
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
        enabled: !mainWindow.snapBackHeight
        SequentialAnimation {
            PropertyAction { target: mainWindow; property: "heightAnimating"; value: true }
            NumberAnimation {
                duration: 1000
                easing.type: Easing.InOutQuad
            }
            ScriptAction {
                script: {
                    mainWindow.lockedHeight = mainWindow.height
                    mainWindow.heightAnimating = false
                }
            }
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
                    // recentStories entries + 1 "+" card at the end
                    model: storyManager.recentStories.length + 1
                    delegate: Rectangle {
                        width: 270
                        height: 150
                        radius: 30
                        color: "black"
                        // border drawn as child overlay so it renders above the thumbnail
                        clip: true
                        layer.enabled: true

                        property bool hovered: false
                        property bool isLast: index === storyManager.recentStories.length
                        property var storyData: isLast ? null : storyManager.recentStories[index]
                        property string thumbPath: (!isLast && storyData && storyData.thumbPath) ? storyData.thumbPath : ""

                        // Thumbnail fill — clipped to rounded corners via OpacityMask
                        Item {
                            id: storyMenuStoryThumbClip
                            anchors.fill: parent
                            visible: parent.thumbPath !== ""
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: storyMenuStoryThumbClip.width
                                    height: storyMenuStoryThumbClip.height
                                    radius: 30
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: parent.parent.thumbPath !== "" ? ("file://" + parent.parent.thumbPath) : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        // Dimming overlay on hover
                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: parent.hovered && !parent.isLast ? 0.35 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: {
                                if (isLast) {
                                    saveStoryDialog.pendingAction = "new";
                                    saveStoryDialog.triggerTransition = true;
                                    saveStoryDialog.open();
                                } else {
                                    if (storyManager.openStory(storyData.path)) {
                                        story2sceneMenu.visible = true;
                                        story2sceneMenuPlayer.play();
                                    }
                                }
                            }
                        }

                        // "+" icon — only on the last (new story) card
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 64
                            color: "white"
                            visible: parent.isLast
                        }

                        // Filename label in lower third of existing-story cards
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width - 8
                            height: 60
                            visible: !isLast
                            layer.enabled: true
                            layer.effect: DropShadow {
                                horizontalOffset: 0
                                verticalOffset: 3
                                radius: 10
                                samples: 21
                                color: "#e0000000"
                                spread: 0.5
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 20
                                text: storyData ? storyData.filename : ""
                                font.pixelSize: 14
                                color: "white"
                                elide: Text.ElideMiddle
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Border overlay — rendered last so it always appears above the thumbnail
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: "white"
                            border.width: 4
                            radius: 30
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
            // Populated by reloadScenes(). Each entry: { sceneId, sceneName, thumbnailRev }.
            // The last entry always has sceneId: -1 (the "+" new-scene card).
            // ALL roles must appear here so they are registered before any append().
            ListElement { sceneId: -1; sceneName: ""; thumbnailRev: 0 }
        }

        function reloadScenes() {
            scenesRectModel.clear();
            var scenes = storyManager.getScenes();
            for (var i = 0; i < scenes.length; i++) {
                var rev = storyManager.hasThumbnail(scenes[i].id) ? 1 : 0;
                scenesRectModel.append({
                    sceneId: scenes[i].id,
                    sceneName: scenes[i].name,
                    thumbnailRev: rev
                });
            }
            scenesRectModel.append({ sceneId: -1, sceneName: "", thumbnailRev: 0 });
        }

        Connections {
            target: storyManager
            function onStoryChanged() { sceneMenu.reloadScenes(); }
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
                        color: "black"
                        // border is drawn as a child overlay so it renders above the thumbnail
                        clip: true
                        layer.enabled: true

                        property bool hovered: false
                        property bool isLast: model.sceneId === -1

                        // Thumbnail fill — wrapped in a layer+OpacityMask Item so the
                        // image is clipped to the card's rounded corners.
                        Item {
                            id: sceneMenuThumbClip
                            anchors.fill: parent
                            visible: !isLast && model.thumbnailRev > 0
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: sceneMenuThumbClip.width
                                    height: sceneMenuThumbClip.height
                                    radius: 30
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: (!isLast && model.thumbnailRev > 0)
                                    ? ("image://thumbnails/" + model.sceneId + "?rev=" + model.thumbnailRev)
                                    : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        // Dimming overlay on hover (existing scenes)
                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: hovered && !isLast ? 0.25 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: hovered = true
                            onExited: hovered = false
                            onClicked: {
                                if (isLast) {
                                    var newId = storyManager.createScene("new scene");
                                    if (newId !== -1) {
                                        scenesRectModel.insert(scenesRectModel.count - 1,
                                            { sceneId: newId, sceneName: "new scene", thumbnailRev: 0 });
                                        mainWindow.currentSceneId = newId;
                                        viewport.clearForNewScene();
                                        sceneMenu2sceneEditor.visible = true;
                                        sceneMenu2sceneEditorPlayer.play();
                                    }
                                } else {
                                    mainWindow.currentSceneId = model.sceneId;
                                    viewport.loadSceneIntoViewport(model.sceneId);
                                    sceneMenu2sceneEditor.visible = true;
                                    sceneMenu2sceneEditorPlayer.play();
                                }
                            }
                        }

                        // "+" icon on the new-scene card
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 64
                            color: "white"
                            visible: isLast
                        }

                        // Scene name label in lower third of existing scene cards
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width - 8
                            height: 60
                            visible: !isLast
                            layer.enabled: true
                            layer.effect: DropShadow {
                                horizontalOffset: 0
                                verticalOffset: 3
                                radius: 10
                                samples: 21
                                color: "#e0000000"
                                spread: 0.5
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 20
                                text: model.sceneName || ""
                                font.pixelSize: 14
                                color: "white"
                                elide: Text.ElideMiddle
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Border overlay — rendered last so it always appears above the thumbnail
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: "white"
                            border.width: 4
                            radius: 30
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

        Text {
            id: storyTitleHeading
            y: 449
            height: 60
            anchors.right: parent.right
            anchors.rightMargin: 23
            anchors.left: sceneMenuButtons.right
            anchors.leftMargin: 16
            text: storyManager.storyTitle
            color: "white"
            font.bold: true
            font.pixelSize: 48
            fontSizeMode: Text.Fit
            minimumPixelSize: 12
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideLeft
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
            property var selectedShaders: []
            property int selectionRevision: 0
            readonly property int selectionCount: selectedAreas.length + selectedTbs.length + selectedImages.length + selectedVideos.length + selectedShaders.length

            // Stack/z-order state
            property int nextStackOrder: 0
            property string relayerHoveredType: ""
            property int relayerHoveredIndex: -1

            property bool capturingThumbnail: false
            property bool boxSelecting: false
            property real boxSelectX1: 0
            property real boxSelectY1: 0
            property real boxSelectX2: 0
            property real boxSelectY2: 0

            // Delete tool state
            property string deleteTargetType: ""
            property int deleteTargetIndex: -1
            property real deleteProgress: 0.0
            property bool tempDestroyMode: false
            readonly property string effectiveTool: tempDestroyMode ? "destroy" : buttonGrid.selectedTool

            property string dropPendingImagePath: ""
            property string dropPendingVideoPath: ""
            property real dropX: 0
            property real dropY: 0

            function cancelDelete() {
                deleteTargetType = "";
                deleteTargetIndex = -1;
                deleteProgress = 0.0;
                tempDestroyMode = false;
            }

            function removeIndexFromSelection(type, idx) {
                var arr, prop;
                if (type === "area")        { arr = selectedAreas.slice();   prop = "selectedAreas"; }
                else if (type === "tb")     { arr = selectedTbs.slice();     prop = "selectedTbs"; }
                else if (type === "image")  { arr = selectedImages.slice();  prop = "selectedImages"; }
                else if (type === "video")  { arr = selectedVideos.slice();  prop = "selectedVideos"; }
                else if (type === "shader") { arr = selectedShaders.slice(); prop = "selectedShaders"; }
                else return;
                var pos = arr.indexOf(idx);
                if (pos !== -1) arr.splice(pos, 1);
                for (var k = 0; k < arr.length; k++) {
                    if (arr[k] > idx) arr[k]--;
                }
                viewport[prop] = arr;
                selectionRevision++;
            }

            Timer {
                id: deleteTimer
                interval: 16
                repeat: true
                running: viewport.deleteTargetIndex !== -1
                onTriggered: {
                    viewport.deleteProgress += 16.0 / 600.0;
                    if (viewport.deleteProgress >= 1.0) {
                        var t = viewport.deleteTargetType;
                        var i = viewport.deleteTargetIndex;
                        viewport.cancelDelete();
                        viewport.removeIndexFromSelection(t, i);
                        if (t === "area")
                            areasModel.remove(i);
                        else if (t === "tb")
                            textBoxesModel.remove(i);
                        else if (t === "image")
                            imagesModel.remove(i);
                        else if (t === "video")
                            videosModel.remove(i);
                        else if (t === "shader")
                            shadersModel.remove(i);
                    }
                }
            }

            function clearSelection() {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [];
                selectedShaders = [];
                selectionRevision++;
            }
            function selectArea(idx) {
                selectedAreas = [idx];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [];
                selectedShaders = [];
                selectionRevision++;
            }
            function selectTb(idx) {
                selectedAreas = [];
                selectedTbs = [idx];
                selectedImages = [];
                selectedVideos = [];
                selectedShaders = [];
                selectionRevision++;
            }
            function selectImage(idx) {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [idx];
                selectedVideos = [];
                selectedShaders = [];
                selectionRevision++;
            }
            function selectVideo(idx) {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [idx];
                selectedShaders = [];
                selectionRevision++;
            }
            function selectShader(idx) {
                selectedAreas = [];
                selectedTbs = [];
                selectedImages = [];
                selectedVideos = [];
                selectedShaders = [idx];
                selectionRevision++;
            }
            function applyBoxSelect(rx1, ry1, rx2, ry2) {
                var bx1 = Math.min(rx1, rx2), bx2 = Math.max(rx1, rx2);
                var by1 = Math.min(ry1, ry2), by2 = Math.max(ry1, ry2);
                var newAreas = [], newTbs = [], newImgs = [], newVids = [], newShaders = [];
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
                for (var m = 0; m < shadersModel.count; m++) {
                    var sh = shadersModel.get(m);
                    if (sh.x2 > bx1 && sh.x1 < bx2 && sh.y2 > by1 && sh.y1 < by2)
                        newShaders.push(m);
                }
                selectedAreas = newAreas;
                selectedTbs = newTbs;
                selectedImages = newImgs;
                selectedVideos = newVids;
                selectedShaders = newShaders;
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
                for (var m = 0; m < selectedShaders.length; m++) {
                    var sh = shadersModel.get(selectedShaders[m]);
                    gx1 = Math.min(gx1, sh.x1);
                    gy1 = Math.min(gy1, sh.y1);
                    gx2 = Math.max(gx2, sh.x2);
                    gy2 = Math.max(gy2, sh.y2);
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

            ListModel {
                id: shadersModel
            }
            property real shaderX1: 0
            property real shaderY1: 0
            property real shaderX2: 0
            property real shaderY2: 0
            property bool shaderDragging: false
            property var pendingShaderBounds: null

            // Background occlusion tracking — pauses the shader when opaque
            // items fully cover the viewport, saving fragment shader cost.
            property bool bgOccluded: false
            // Increment this whenever an image or video is moved or resized
            // to trigger a fresh occlusion check.
            property int layoutRevision: 0
            onLayoutRevisionChanged: checkOcclusion()
            // Incremented on every move/resize position change so selectSettings can sync in real time.
            property int posRevision: 0

            function checkOcclusion() {
                var vw = viewport.width;
                var vh = viewport.height;
                var rects = [];

                // Images are opaque unless they're a format that supports alpha
                for (var i = 0; i < imagesModel.count; i++) {
                    var img = imagesModel.get(i);
                    var ext = img.filePath.toLowerCase();
                    var hasAlpha = ext.endsWith(".png") || ext.endsWith(".gif") || ext.endsWith(".webp");
                    if (!hasAlpha)
                        rects.push(img);
                }

                // Videos are assumed opaque — most codecs have no alpha channel
                for (var j = 0; j < videosModel.count; j++)
                    rects.push(videosModel.get(j));

                if (rects.length === 0) { bgOccluded = false; return; }

                // Coordinate compression: build a grid from all rect boundaries
                // clamped to the viewport, then check each cell for coverage.
                var xs = [0, vw], ys = [0, vh];
                for (var k = 0; k < rects.length; k++) {
                    var r = rects[k];
                    xs.push(Math.max(0, Math.min(vw, r.x1)), Math.max(0, Math.min(vw, r.x2)));
                    ys.push(Math.max(0, Math.min(vh, r.y1)), Math.max(0, Math.min(vh, r.y2)));
                }
                xs = xs.filter(function(v,i,a){return a.indexOf(v)===i;}).sort(function(a,b){return a-b;});
                ys = ys.filter(function(v,i,a){return a.indexOf(v)===i;}).sort(function(a,b){return a-b;});

                var coveredArea = 0;
                for (var xi = 0; xi < xs.length - 1; xi++) {
                    var cx = (xs[xi] + xs[xi+1]) * 0.5;
                    var cw = xs[xi+1] - xs[xi];
                    for (var yi = 0; yi < ys.length - 1; yi++) {
                        var cy = (ys[yi] + ys[yi+1]) * 0.5;
                        var ch = ys[yi+1] - ys[yi];
                        for (var ri = 0; ri < rects.length; ri++) {
                            var rc = rects[ri];
                            if (cx >= rc.x1 && cx < rc.x2 && cy >= rc.y1 && cy < rc.y2) {
                                coveredArea += cw * ch;
                                break;
                            }
                        }
                    }
                }
                bgOccluded = (coveredArea >= vw * vh);
            }

            Connections {
                target: imagesModel
                function onCountChanged() { viewport.checkOcclusion(); }
            }
            Connections {
                target: videosModel
                function onCountChanged() { viewport.checkOcclusion(); }
            }

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

            // --- Shader uniform helpers ---
            function buildUniformsList(rawUniforms) {
                var list = [];
                for (var i = 0; i < rawUniforms.length; i++) {
                    var u = rawUniforms[i];
                    list.push({name: u.name, type: u.type, value: uniformDefault(u.type)});
                }
                return list;
            }
            function uniformDefault(type) {
                if (type === "float" || type === "int") return 1.0;
                if (type === "vec2") return [1.0, 1.0];
                if (type === "vec3") return [1.0, 1.0, 1.0];
                if (type === "vec4") return [1.0, 1.0, 1.0, 1.0];
                return null;
            }
            function qmlTypeForUniform(type) {
                if (type === "float" || type === "int") return "real";
                if (type === "vec2") return "vector2d";
                if (type === "vec3") return "vector3d";
                if (type === "vec4") return "vector4d";
                return "var";
            }
            function qmlValueForUniform(type, value) {
                if (type === "float" || type === "int")
                    return (value !== null && value !== undefined) ? value : 0.0;
                var v2, v3, v4;
                if (type === "vec2") {
                    v2 = Array.isArray(value) ? value : [1.0, 1.0];
                    return "Qt.vector2d(" + v2[0] + ", " + v2[1] + ")";
                }
                if (type === "vec3") {
                    v3 = Array.isArray(value) ? value : [1.0, 1.0, 1.0];
                    return "Qt.vector3d(" + v3[0] + ", " + v3[1] + ", " + v3[2] + ")";
                }
                if (type === "vec4") {
                    v4 = Array.isArray(value) ? value : [1.0, 1.0, 1.0, 1.0];
                    return "Qt.vector4d(" + v4[0] + ", " + v4[1] + ", " + v4[2] + ", " + v4[3] + ")";
                }
                return "null";
            }
            // Build a QML ShaderEffect string with per-shader property declarations.
            function buildShaderQml(fragPath, vertPath, uniformsJson) {
                var uniforms;
                try { uniforms = JSON.parse(uniformsJson || "[]"); } catch(e) { uniforms = []; }
                var qml = "import QtQuick 2.15\nShaderEffect {\n";
                qml += "    anchors.fill: parent\n";
                qml += "    fragmentShader: \"" + fragPath + "\"\n";
                if (vertPath && vertPath !== "")
                    qml += "    vertexShader: \"" + vertPath + "\"\n";
                for (var i = 0; i < uniforms.length; i++) {
                    var u = uniforms[i];
                    if (u.name === "time") {
                        qml += "    property real time: 0\n";
                        qml += "    NumberAnimation on time { from: 0; to: 1000000; duration: 1000000000; loops: Animation.Infinite; running: true }\n";
                    } else if (u.type === "sampler2D") {
                        qml += "    property var " + u.name + ": null\n";
                    } else {
                        qml += "    property " + qmlTypeForUniform(u.type) + " " + u.name + ": " + qmlValueForUniform(u.type, u.value) + "\n";
                    }
                }
                qml += "}\n";
                return qml;
            }
            // Convert comma-separated text to a QML-typed value (for live ShaderEffect update).
            function parseUniformToQml(type, text) {
                var parts = text.toString().split(",").map(function(s) { return parseFloat(s.trim()) || 0; });
                if (type === "float" || type === "int") return parseFloat(text) || 0;
                if (type === "vec2") return Qt.vector2d(parts[0] || 0, parts[1] || 0);
                if (type === "vec3") return Qt.vector3d(parts[0] || 0, parts[1] || 0, parts[2] || 0);
                if (type === "vec4") return Qt.vector4d(parts[0] || 0, parts[1] || 0, parts[2] || 0, parts[3] || 0);
                return null;
            }
            function isVideoPath(path) {
                var p = path.toLowerCase();
                return p.endsWith(".mp4") || p.endsWith(".mov") || p.endsWith(".mkv") || p.endsWith(".avi") || p.endsWith(".webm");
            }

            // ------------------------------------------------------------------ scene persistence

            function clearForNewScene() {
                areasModel.clear();
                textBoxesModel.clear();
                imagesModel.clear();
                videosModel.clear();
                shadersModel.clear();
                nextStackOrder = 0;
                clearSelection();
            }

            function loadSceneIntoViewport(sceneId) {
                clearForNewScene();
                var raw = storyManager.loadSceneElements(sceneId);
                var elements;
                try { elements = JSON.parse(raw); } catch(e) { elements = []; }
                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    var z = el.z_order !== undefined ? el.z_order : nextStackOrder;
                    if (el.type === "area") {
                        areasModel.append({
                            x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                            name: el.name || "", stackOrder: z
                        });
                    } else if (el.type === "text") {
                        textBoxesModel.append({
                            x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                            family:    el.family    || "Mona Sans",
                            tbWeight:  el.tbWeight  !== undefined ? el.tbWeight : Font.Normal,
                            size:      el.size      || 16,
                            italic:    el.italic    || false,
                            underline: el.underline || false,
                            textColor: el.textColor || "#FFFFFF",
                            content:   el.content   || "",
                            name: el.name || "", stackOrder: z
                        });
                    } else if (el.type === "image") {
                        imagesModel.append({
                            x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                            filePath: el.filePath || "",
                            name: el.name || "", stackOrder: z
                        });
                    } else if (el.type === "video") {
                        videosModel.append({
                            x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                            filePath: el.filePath || "",
                            name: el.name || "", stackOrder: z
                        });
                    } else if (el.type === "shader") {
                        shadersModel.append({
                            x1: el.x, y1: el.y, x2: el.x + el.w, y2: el.y + el.h,
                            fragPath:     el.fragPath     || "",
                            vertPath:     el.vertPath     || "",
                            uniformsJson: el.uniformsJson || "[]",
                            name: el.name || "", stackOrder: z
                        });
                    }
                    if (z >= nextStackOrder) nextStackOrder = z + 1;
                }
            }

            function collectSceneElements() {
                var elements = [];
                var i, m;
                for (i = 0; i < areasModel.count; i++) {
                    m = areasModel.get(i);
                    elements.push({ type: "area",
                        x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                        w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                        name: m.name || "", z_order: m.stackOrder });
                }
                for (i = 0; i < textBoxesModel.count; i++) {
                    m = textBoxesModel.get(i);
                    elements.push({ type: "text",
                        x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                        w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                        z_order: m.stackOrder, name: m.name || "",
                        family: m.family, tbWeight: m.tbWeight, size: m.size,
                        italic: m.italic, underline: m.underline,
                        textColor: m.textColor, content: m.content });
                }
                for (i = 0; i < imagesModel.count; i++) {
                    m = imagesModel.get(i);
                    elements.push({ type: "image",
                        x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                        w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                        name: m.name || "", z_order: m.stackOrder, filePath: m.filePath });
                }
                for (i = 0; i < videosModel.count; i++) {
                    m = videosModel.get(i);
                    elements.push({ type: "video",
                        x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                        w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                        name: m.name || "", z_order: m.stackOrder, filePath: m.filePath });
                }
                for (i = 0; i < shadersModel.count; i++) {
                    m = shadersModel.get(i);
                    elements.push({ type: "shader",
                        x: Math.min(m.x1, m.x2), y: Math.min(m.y1, m.y2),
                        w: Math.abs(m.x2 - m.x1), h: Math.abs(m.y2 - m.y1),
                        name: m.name || "", z_order: m.stackOrder,
                        fragPath: m.fragPath, vertPath: m.vertPath,
                        uniformsJson: m.uniformsJson });
                }
                return JSON.stringify(elements);
            }

            // Capture a 540×300 thumbnail of the scene content with a black background.
            // Uses an off-screen ShaderEffectSource (thumbnailCaptureSurface) so the visible
            // viewport never changes — no flash. Saves to DB and updates the scene card model.
            // Calls onDone() when finished (or immediately if sceneId === -1).
            function captureAndSaveThumbnail(sceneId, onDone) {
                if (sceneId === -1) { onDone(); return; }
                var tempPath = "/tmp/understory_thumb_" + sceneId + ".png";
                viewport.capturingThumbnail = true;
                thumbnailCaptureSurface.grabToImage(function(result) {
                    result.saveToFile(tempPath);
                    storyManager.saveThumbnail(sceneId, tempPath);
                    storyManager.saveStoryThumbnail(tempPath);
                    for (var i = 0; i < scenesRectModel.count; i++) {
                        if (scenesRectModel.get(i).sceneId === sceneId) {
                            var rev = (scenesRectModel.get(i).thumbnailRev || 0) + 1;
                            scenesRectModel.setProperty(i, "thumbnailRev", rev);
                            break;
                        }
                    }
                    onDone();
                }, Qt.size(540, 300));
            }

            // Convert comma-separated text to a serialisable array/scalar (for storing in model).
            function parseUniformToArray(type, text) {
                var parts = text.toString().split(",").map(function(s) { return parseFloat(s.trim()) || 0; });
                if (type === "float" || type === "int") return parseFloat(text) || 0;
                if (type === "vec2") return [parts[0] || 0, parts[1] || 0];
                if (type === "vec3") return [parts[0] || 0, parts[1] || 0, parts[2] || 0];
                if (type === "vec4") return [parts[0] || 0, parts[1] || 0, parts[2] || 0, parts[3] || 0];
                return null;
            }

            ShaderEffect {
                id: viewportBgShader
                anchors.fill: parent
                visible: !viewport.bgOccluded
                fragmentShader: "cloudyeditorbg.frag.qsb"
                property real time: 0
                property real scale: 25.0         // feature size — lower = bigger clouds, higher = finer
                property real driftSpeed: 0.25   // how fast the noise evolves
                property real intensity: 0.10    // contrast/strength of the effect
                NumberAnimation on time {
                    running: sceneEditor.visible && !viewport.bgOccluded
                    from: 0
                    to: 1000
                    duration: 1000000
                    loops: Animation.Infinite
                }
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
                            name: areaSpatialProps.propName,
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
                            name: textSpatialProps.propName,
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
                enabled: buttonGrid.selectedTool === "newimage"
                z: 998

                onPressed: {
                    if (imageSettings.selectedFilePath === "") {
                        imageFileDialog.open();
                        return;
                    }
                    viewport.imgX1 = viewport.snapX(mouseX);
                    viewport.imgY1 = viewport.snapY(mouseY);
                    viewport.imgX2 = viewport.imgX1;
                    viewport.imgY2 = viewport.imgY1;
                    viewport.imageDragging = true;
                }
                onPositionChanged: function (mouse) {
                    if (!viewport.imageDragging) return;
                    var aspect = imageSettings.imageAspectRatio;
                    if (aspect > 0 && !(mouse.modifiers & Qt.ShiftModifier)) {
                        var dx = mouse.x - viewport.imgX1;
                        var dy = mouse.y - viewport.imgY1;
                        var w = Math.abs(dx);
                        var h = Math.abs(dy);
                        if (w === 0 && h === 0) return;
                        if (h === 0 || w / h > aspect) w = h * aspect;
                        else h = w / aspect;
                        // clamp to viewport edges, preserving aspect ratio
                        var maxW = dx >= 0 ? viewport.width  - viewport.imgX1 : viewport.imgX1;
                        var maxH = dy >= 0 ? viewport.height - viewport.imgY1 : viewport.imgY1;
                        if (w > maxW) { w = maxW; h = w / aspect; }
                        if (h > maxH) { h = maxH; w = h * aspect; }
                        viewport.imgX2 = viewport.snapX(viewport.imgX1 + (dx >= 0 ? w : -w));
                        viewport.imgY2 = viewport.snapY(viewport.imgY1 + (dy >= 0 ? h : -h));
                    } else {
                        viewport.imgX2 = viewport.snapX(mouse.x);
                        viewport.imgY2 = viewport.snapY(mouse.y);
                    }
                }
                onReleased: {
                    if (!viewport.imageDragging) return;
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
                            name: imageSpatialProps.propName,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectImage(imagesModel.count - 1);
                        buttonGrid.selectedTool = "select";
                        imageSettings.selectedFilePath = "";
                    }
                }
            }

            // New video drag: click and drag to define a video box
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newvideo"
                z: 998

                onPressed: {
                    if (videoSettings.selectedFilePath === "") {
                        videoFileDialog.open();
                        return;
                    }
                    viewport.vidX1 = viewport.snapX(mouseX);
                    viewport.vidY1 = viewport.snapY(mouseY);
                    viewport.vidX2 = viewport.vidX1;
                    viewport.vidY2 = viewport.vidY1;
                    viewport.videoDragging = true;
                }
                onPositionChanged: {
                    if (!viewport.videoDragging) return;
                    var aspect = videoSettings.videoAspectRatio;
                    if (aspect > 0) {
                        var dx = mouseX - viewport.vidX1;
                        var dy = mouseY - viewport.vidY1;
                        var w = Math.abs(dx);
                        var h = Math.abs(dy);
                        if (w === 0 && h === 0) return;
                        if (h === 0 || w / h > aspect) w = h * aspect;
                        else h = w / aspect;
                        // clamp to viewport edges, preserving aspect ratio
                        var maxW = dx >= 0 ? viewport.width  - viewport.vidX1 : viewport.vidX1;
                        var maxH = dy >= 0 ? viewport.height - viewport.vidY1 : viewport.vidY1;
                        if (w > maxW) { w = maxW; h = w / aspect; }
                        if (h > maxH) { h = maxH; w = h * aspect; }
                        viewport.vidX2 = viewport.snapX(viewport.vidX1 + (dx >= 0 ? w : -w));
                        viewport.vidY2 = viewport.snapY(viewport.vidY1 + (dy >= 0 ? h : -h));
                    } else {
                        viewport.vidX2 = viewport.snapX(mouseX);
                        viewport.vidY2 = viewport.snapY(mouseY);
                    }
                }
                onReleased: {
                    if (!viewport.videoDragging) return;
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
                            name: videoSpatialProps.propName,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectVideo(videosModel.count - 1);
                        buttonGrid.selectedTool = "select";
                        videoSettings.selectedFilePath = "";
                    }
                }
            }

            // New shader drag: click and drag to define a shader box
            MouseArea {
                anchors.fill: parent
                enabled: buttonGrid.selectedTool === "newshader"
                z: 998

                onPressed: function (mouse) {
                    viewport.shaderX1 = viewport.snapX(mouseX);
                    viewport.shaderY1 = viewport.snapY(mouseY);
                    viewport.shaderX2 = viewport.shaderX1;
                    viewport.shaderY2 = viewport.shaderY1;
                    viewport.shaderDragging = true;
                }
                onPositionChanged: function (mouse) {
                    if (!viewport.shaderDragging) return;
                    if (mouse.modifiers & Qt.ShiftModifier) {
                        // Shift: constrain to square
                        var dx = mouse.x - viewport.shaderX1;
                        var dy = mouse.y - viewport.shaderY1;
                        var side = Math.max(Math.abs(dx), Math.abs(dy));
                        viewport.shaderX2 = viewport.snapX(viewport.shaderX1 + (dx >= 0 ? side : -side));
                        viewport.shaderY2 = viewport.snapY(viewport.shaderY1 + (dy >= 0 ? side : -side));
                    } else {
                        viewport.shaderX2 = viewport.snapX(mouse.x);
                        viewport.shaderY2 = viewport.snapY(mouse.y);
                    }
                }
                onReleased: {
                    if (!viewport.shaderDragging) return;
                    viewport.shaderDragging = false;
                    var w = Math.abs(viewport.shaderX2 - viewport.shaderX1);
                    var h = Math.abs(viewport.shaderY2 - viewport.shaderY1);
                    if (w > 2 && h > 2) {
                        var bounds = {
                            x1: Math.min(viewport.shaderX1, viewport.shaderX2),
                            y1: Math.min(viewport.shaderY1, viewport.shaderY2),
                            x2: Math.max(viewport.shaderX1, viewport.shaderX2),
                            y2: Math.max(viewport.shaderY1, viewport.shaderY2)
                        };
                        if (newshaderSettings.fragFilePath === "") {
                            viewport.pendingShaderBounds = bounds;
                            shaderPickerDialog.open();
                        } else {
                            shadersModel.append({
                                x1: bounds.x1, y1: bounds.y1,
                                x2: bounds.x2, y2: bounds.y2,
                                fragPath: newshaderSettings.fragFilePath,
                                vertPath: newshaderSettings.vertFilePath,
                                name: newshaderSettings.propName,
                                stackOrder: viewport.nextStackOrder++,
                                uniformsJson: newshaderSettings.buildCurrentUniformsList()
                            });
                            viewport.selectShader(shadersModel.count - 1);
                            buttonGrid.selectedTool = "select";
                            newshaderSettings.fragFilePath = "";
                            newshaderSettings.vertFilePath = "";
                        }
                    }
                }
            }

            // Scene content layer — wraps all element Repeaters so a ShaderEffectSource
            // can capture them separately from the background shader (for thumbnails).
            Item {
                id: viewportSceneContent
                anchors.fill: parent
                // Must be above the box-select MouseArea (z:2) so element delegates
                // win mouse events; lower than tool overlay MouseAreas (z:998+).
                z: 10

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
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedAreas.indexOf(index) !== -1 && !viewport.capturingThumbnail
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "area" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: (buttonGrid.selectedTool === "destroy" || viewport.tempDestroyMode) && viewport.deleteTargetType === "area" && viewport.deleteTargetIndex === index

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewport.deleteProgress * 0.6) : (areaDelegate.isActive && index === viewport.hoveredAreaIndex ? Qt.rgba(1, 1, 1, 0.15) : "transparent")
                        border.color: areaDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewport.deleteProgress * 0.6) : ((areaDelegate.isActive || areaDelegate.isRelayerHovered) ? "white" : "#666666")
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        z: 2
                        cursorShape: areaDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewport.tempDestroyMode = true;
                                viewport.deleteTargetType = "area";
                                viewport.deleteTargetIndex = index;
                                return;
                            }
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
                            viewport.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewport.deleteTargetType === "area" && viewport.deleteTargetIndex === index)
                                    viewport.cancelDelete();
                                return;
                            }
                            viewport.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewport.relayerHoveredType = "area";
                            viewport.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewport.relayerHoveredType === "area" && viewport.relayerHoveredIndex === index) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.relayerHoveredType = "area";
                            viewport.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
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
                        enabled: buttonGrid.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewport.deleteTargetType = "area";
                            viewport.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewport.deleteTargetType === "area" && viewport.deleteTargetIndex === index)
                                viewport.cancelDelete();
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
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedTbs.indexOf(index) !== -1 && !viewport.capturingThumbnail
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
                    property bool isBeingDeleted: (buttonGrid.selectedTool === "destroy" || viewport.tempDestroyMode) && viewport.deleteTargetType === "tb" && viewport.deleteTargetIndex === index

                    // Visual border (inset by 28px to match model coordinates)
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, viewport.deleteProgress * 0.6) : "transparent"
                        border.color: tbDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewport.deleteProgress * 0.6) : ((tbDelegate.isActive || tbDelegate.isRelayerHovered) ? "white" : "#666666")
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
                        cursorShape: tbDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onDoubleClicked: {
                            if (tbDelegate.isActive) {
                                tbDelegate.editing = true;
                                tbTextEdit.forceActiveFocus();
                            }
                        }
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton && tbDelegate.isSelect) {
                                viewport.tempDestroyMode = true;
                                viewport.deleteTargetType = "tb";
                                viewport.deleteTargetIndex = index;
                                return;
                            }
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
                                viewport.posRevision++;
                            }
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewport.deleteTargetType === "tb" && viewport.deleteTargetIndex === index)
                                    viewport.cancelDelete();
                                return;
                            }
                            viewport.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewport.relayerHoveredType = "tb";
                            viewport.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewport.relayerHoveredType === "tb" && viewport.relayerHoveredIndex === index) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.relayerHoveredType = "tb";
                            viewport.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
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
                        enabled: buttonGrid.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewport.deleteTargetType = "tb";
                            viewport.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewport.deleteTargetType === "tb" && viewport.deleteTargetIndex === index)
                                viewport.cancelDelete();
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
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedImages.indexOf(index) !== -1 && !viewport.capturingThumbnail
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "image" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: (buttonGrid.selectedTool === "destroy" || viewport.tempDestroyMode) && viewport.deleteTargetType === "image" && viewport.deleteTargetIndex === index

                    // Image fill
                    Image {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        source: model.filePath
                        fillMode: Image.Stretch
                        clip: true
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: imgDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewport.deleteProgress * 0.6) : ((imgDelegate.isActive || imgDelegate.isRelayerHovered) ? "white" : "transparent")
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
                        color: Qt.rgba(1, 0, 0, imgDelegate.isBeingDeleted ? viewport.deleteProgress * 0.6 : 0)
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
                        cursorShape: imgDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewport.tempDestroyMode = true;
                                viewport.deleteTargetType = "image";
                                viewport.deleteTargetIndex = index;
                                return;
                            }
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
                            if (!imgDelegate.isActive)
                                return;
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
                            viewport.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewport.deleteTargetType === "image" && viewport.deleteTargetIndex === index)
                                    viewport.cancelDelete();
                                return;
                            }
                            viewport.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewport.relayerHoveredType = "image";
                            viewport.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewport.relayerHoveredType === "image" && viewport.relayerHoveredIndex === index) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.relayerHoveredType = "image";
                            viewport.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
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
                        enabled: buttonGrid.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewport.deleteTargetType = "image";
                            viewport.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewport.deleteTargetType === "image" && viewport.deleteTargetIndex === index)
                                viewport.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56
                        height: 56
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                imagesModel.setProperty(index, "y1", Math.max(0, Math.min(imgDelegate.origY1 + pt.y - imgDelegate.pressVpY, model.y2 - 20)));
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
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                imagesModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20)));
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
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(imgDelegate.origX2 + pt.x - imgDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                imagesModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20)));
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
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewport.height, Math.max(imgDelegate.origY2 + pt.y - imgDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: imgDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                imagesModel.setProperty(index, "x1", Math.max(0, Math.min(imgDelegate.origX1 + pt.x - imgDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedVideos.indexOf(index) !== -1 && !viewport.capturingThumbnail
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "video" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: (buttonGrid.selectedTool === "destroy" || viewport.tempDestroyMode) && viewport.deleteTargetType === "video" && viewport.deleteTargetIndex === index

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
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                    }

                    // Border — only when active/selected or relayer hovered
                    Rectangle {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        z: 1
                        color: "transparent"
                        border.color: vidDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewport.deleteProgress * 0.6) : ((vidDelegate.isActive || vidDelegate.isRelayerHovered) ? "white" : "transparent")
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
                        color: Qt.rgba(1, 0, 0, vidDelegate.isBeingDeleted ? viewport.deleteProgress * 0.6 : 0)
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
                        cursorShape: vidDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewport.tempDestroyMode = true;
                                viewport.deleteTargetType = "video";
                                viewport.deleteTargetIndex = index;
                                return;
                            }
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
                            if (!vidDelegate.isActive)
                                return;
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
                            viewport.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewport.deleteTargetType === "video" && viewport.deleteTargetIndex === index)
                                    viewport.cancelDelete();
                                return;
                            }
                            viewport.elementDragging = false;
                        }
                    }

                    // Relayer: hover to highlight, drag to change z-order
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewport.relayerHoveredType = "video";
                            viewport.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewport.relayerHoveredType === "video" && viewport.relayerHoveredIndex === index) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.relayerHoveredType = "video";
                            viewport.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
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
                        enabled: buttonGrid.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewport.deleteTargetType = "video";
                            viewport.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewport.deleteTargetType === "video" && viewport.deleteTargetIndex === index)
                                viewport.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0
                        y: 0
                        width: 56
                        height: 56
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                var ny1 = Math.max(0, Math.min(vidDelegate.origY1 + pt.y - vidDelegate.pressVpY, model.y2 - 20));
                                var nH = model.y2 - ny1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewport.width, cx + nW / 2));
                                videosModel.setProperty(index, "y1", ny1);
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
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                var nx2 = Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
                                var nW = nx2 - model.x1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewport.height, cy + nH / 2));
                                videosModel.setProperty(index, "x2", nx2);
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
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(vidDelegate.origX2 + pt.x - vidDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14
                        y: parent.height - 42
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                var ny2 = Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
                                var nH = ny2 - model.y1;
                                var nW = nH * vidDelegate.origAspect;
                                var cx = (vidDelegate.origX1 + vidDelegate.origX2) / 2;
                                videosModel.setProperty(index, "x1", Math.max(0, cx - nW / 2));
                                videosModel.setProperty(index, "x2", Math.min(viewport.width, cx + nW / 2));
                                videosModel.setProperty(index, "y2", ny2);
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
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewport.height, Math.max(vidDelegate.origY2 + pt.y - vidDelegate.pressVpY, model.y1 + 20));
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14
                        y: parent.height / 2 - 14
                        width: 28
                        height: 28
                        visible: vidDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                var nx1 = Math.max(0, Math.min(vidDelegate.origX1 + pt.x - vidDelegate.pressVpX, model.x2 - 20));
                                var nW = model.x2 - nx1;
                                var nH = nW / vidDelegate.origAspect;
                                var cy = (vidDelegate.origY1 + vidDelegate.origY2) / 2;
                                videosModel.setProperty(index, "y1", Math.max(0, cy - nH / 2));
                                videosModel.setProperty(index, "y2", Math.min(viewport.height, cy + nH / 2));
                                videosModel.setProperty(index, "x1", nx1);
                            }
                            onReleased: viewport.elementDragging = false
                        }
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

                    property bool isSelect: buttonGrid.selectedTool === "select"
                    property bool isActive: isSelect && (viewport.selectionRevision >= 0) && viewport.selectedShaders.indexOf(index) !== -1 && !viewport.capturingThumbnail
                    property bool isRelayerHovered: buttonGrid.selectedTool === "relayer" && viewport.relayerHoveredType === "shader" && viewport.relayerHoveredIndex === index
                    property real pressVpX: 0
                    property real pressVpY: 0
                    property real origX1: 0
                    property real origY1: 0
                    property real origX2: 0
                    property real origY2: 0
                    property real origAspect: 1
                    property bool isBeingDeleted: (buttonGrid.selectedTool === "destroy" || viewport.tempDestroyMode) && viewport.deleteTargetType === "shader" && viewport.deleteTargetIndex === index

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
                            if (path && path !== "" && viewport.isVideoPath(path)) {
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
                            var qmlStr = viewport.buildShaderQml(model.fragPath, model.vertPath, model.uniformsJson);
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
                                    try { dynamicEffect[u.name] = viewport.parseUniformToQml(u.type, textVal); } catch(e) {}
                                }
                            }
                        }

                        function applyTextureSource(name, path) {
                            if (!dynamicEffect) return;
                            var slot = textureSlots[name];
                            // Rebuild the slot if the type changed (image→video or vice versa) or it doesn't exist yet.
                            var needRebuild = !slot ||
                                (viewport.isVideoPath(path) && !(slot.wrapper !== slot.provider)) ||
                                (!viewport.isVideoPath(path) && slot.wrapper !== slot.provider);
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
                        border.color: shaderDelegate.isBeingDeleted ? Qt.rgba(1, 0, 0, 0.4 + viewport.deleteProgress * 0.6) : ((shaderDelegate.isActive || shaderDelegate.isRelayerHovered) ? "white" : "transparent")
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
                        color: Qt.rgba(1, 0, 0, shaderDelegate.isBeingDeleted ? viewport.deleteProgress * 0.6 : 0)
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
                        cursorShape: shaderDelegate.isActive ? Qt.SizeAllCursor : Qt.ArrowCursor
                        onPressed: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                viewport.tempDestroyMode = true;
                                viewport.deleteTargetType = "shader";
                                viewport.deleteTargetIndex = index;
                                return;
                            }
                            viewport.selectShader(index);
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            if (shaderDelegate.isActive) {
                                shaderDelegate.pressVpX = pt.x;
                                shaderDelegate.pressVpY = pt.y;
                                shaderDelegate.origX1 = model.x1;
                                shaderDelegate.origY1 = model.y1;
                                shaderDelegate.origX2 = model.x2;
                                shaderDelegate.origY2 = model.y2;
                                viewport.elementDragging = true;
                                viewport.elementDragX = pt.x;
                                viewport.elementDragY = pt.y;
                            }
                        }
                        onPositionChanged: function (mouse) {
                            if (!shaderDelegate.isActive) return;
                            var pt = mapToItem(viewport, mouse.x, mouse.y);
                            viewport.elementDragX = pt.x;
                            viewport.elementDragY = pt.y;
                            var dx = pt.x - shaderDelegate.pressVpX, dy = pt.y - shaderDelegate.pressVpY;
                            var w = shaderDelegate.origX2 - shaderDelegate.origX1, h = shaderDelegate.origY2 - shaderDelegate.origY1;
                            var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + dx, viewport.width - w));
                            var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + dy, viewport.height - h));
                            shadersModel.setProperty(index, "x1", nx1);
                            shadersModel.setProperty(index, "y1", ny1);
                            shadersModel.setProperty(index, "x2", nx1 + w);
                            shadersModel.setProperty(index, "y2", ny1 + h);
                            viewport.posRevision++;
                        }
                        onReleased: function (mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (viewport.deleteTargetType === "shader" && viewport.deleteTargetIndex === index)
                                    viewport.cancelDelete();
                                return;
                            }
                            viewport.elementDragging = false;
                        }
                    }

                    // Relayer
                    MouseArea {
                        x: 28
                        y: 28
                        width: parent.width - 56
                        height: parent.height - 56
                        enabled: buttonGrid.selectedTool === "relayer"
                        hoverEnabled: true
                        z: 2
                        property real pressX: 0
                        property real pressY: 0
                        property int pressStack: 0
                        onEntered: {
                            viewport.relayerHoveredType = "shader";
                            viewport.relayerHoveredIndex = index;
                        }
                        onExited: {
                            if (!pressed && viewport.relayerHoveredType === "shader" && viewport.relayerHoveredIndex === index) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
                            }
                        }
                        onPressed: function (mouse) {
                            viewport.relayerHoveredType = "shader";
                            viewport.relayerHoveredIndex = index;
                            pressX = mouse.x;
                            pressY = mouse.y;
                            pressStack = model.stackOrder;
                        }
                        onReleased: function (mouse) {
                            if (!containsMouse) {
                                viewport.relayerHoveredType = "";
                                viewport.relayerHoveredIndex = -1;
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
                        enabled: buttonGrid.selectedTool === "destroy"
                        z: 3
                        onPressed: {
                            viewport.deleteTargetType = "shader";
                            viewport.deleteTargetIndex = index;
                        }
                        onReleased: {
                            if (viewport.deleteTargetType === "shader" && viewport.deleteTargetIndex === index)
                                viewport.cancelDelete();
                        }
                    }

                    // Resize handles
                    // Top-left
                    Item {
                        x: 0; y: 0; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
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
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-mid
                    Item {
                        x: parent.width / 2 - 14; y: 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpY = pt.y; shaderDelegate.origY1 = model.y1;
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                shadersModel.setProperty(index, "y1", Math.max(0, Math.min(shaderDelegate.origY1 + pt.y - shaderDelegate.pressVpY, model.y2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Top-right
                    Item {
                        x: parent.width - 56; y: 0; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20));
                                var ny1 = Math.max(0, Math.min(shaderDelegate.origY1 + pt.y - shaderDelegate.pressVpY, model.y2 - 20));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = model.y2 - ny1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx2 = model.x1 + nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny1 = model.y2 - nH; }
                                }
                                shadersModel.setProperty(index, "x2", nx2);
                                shadersModel.setProperty(index, "y1", ny1);
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Right-mid
                    Item {
                        x: parent.width - 42; y: parent.height / 2 - 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.origX2 = model.x2;
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                shadersModel.setProperty(index, "x2", Math.min(viewport.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-right
                    Item {
                        x: parent.width - 56; y: parent.height - 56; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                                var nx2 = Math.min(viewport.width, Math.max(shaderDelegate.origX2 + pt.x - shaderDelegate.pressVpX, model.x1 + 20));
                                var ny2 = Math.min(viewport.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = nx2 - model.x1, nH = ny2 - model.y1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx2 = model.x1 + nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny2 = model.y1 + nH; }
                                }
                                shadersModel.setProperty(index, "x2", nx2);
                                shadersModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-mid
                    Item {
                        x: parent.width / 2 - 14; y: parent.height - 42; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpY = pt.y; shaderDelegate.origY2 = model.y2;
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragY = pt.y;
                                shadersModel.setProperty(index, "y2", Math.min(viewport.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Bottom-left
                    Item {
                        x: 0; y: parent.height - 56; width: 56; height: 56
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
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
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                                var nx1 = Math.max(0, Math.min(shaderDelegate.origX1 + pt.x - shaderDelegate.pressVpX, model.x2 - 20));
                                var ny2 = Math.min(viewport.height, Math.max(shaderDelegate.origY2 + pt.y - shaderDelegate.pressVpY, model.y1 + 20));
                                if (mouse.modifiers & Qt.ShiftModifier) {
                                    var nW = model.x2 - nx1, nH = ny2 - model.y1;
                                    if (nW / nH > shaderDelegate.origAspect) { nW = nH * shaderDelegate.origAspect; nx1 = model.x2 - nW; }
                                    else { nH = nW / shaderDelegate.origAspect; ny2 = model.y1 + nH; }
                                }
                                shadersModel.setProperty(index, "x1", nx1);
                                shadersModel.setProperty(index, "y2", ny2);
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                    // Left-mid
                    Item {
                        x: 14; y: parent.height / 2 - 14; width: 28; height: 28
                        visible: shaderDelegate.isActive && viewport.selectionCount === 1
                        z: 3
                        Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; border.color: "black"; border.width: 1 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            onPressed: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                shaderDelegate.pressVpX = pt.x; shaderDelegate.origX1 = model.x1;
                                viewport.elementDragging = true; viewport.elementDragX = pt.x; viewport.elementDragY = pt.y;
                            }
                            onPositionChanged: function (mouse) {
                                var pt = mapToItem(viewport, mouse.x, mouse.y);
                                viewport.elementDragX = pt.x;
                                shadersModel.setProperty(index, "x1", Math.max(0, Math.min(shaderDelegate.origX1 + pt.x - shaderDelegate.pressVpX, model.x2 - 20)));
                            }
                            onReleased: viewport.elementDragging = false
                        }
                    }
                }
            }

            } // end viewportSceneContent

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

            // In-progress shader rubber-band
            Rectangle {
                visible: viewport.shaderDragging
                x: Math.min(viewport.shaderX1, viewport.shaderX2)
                y: Math.min(viewport.shaderY1, viewport.shaderY2)
                width: Math.abs(viewport.shaderX2 - viewport.shaderX1)
                height: Math.abs(viewport.shaderY2 - viewport.shaderY1)
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
                visible: viewport.boxSelecting && !viewport.capturingThumbnail
                x: Math.max(0, Math.min(viewport.boxSelectX1, viewport.boxSelectX2))
                y: Math.max(0, Math.min(viewport.boxSelectY1, viewport.boxSelectY2))
                width: Math.max(0, Math.min(viewport.width,  Math.max(viewport.boxSelectX1, viewport.boxSelectX2)) - Math.max(0, Math.min(viewport.boxSelectX1, viewport.boxSelectX2)))
                height: Math.max(0, Math.min(viewport.height, Math.max(viewport.boxSelectY1, viewport.boxSelectY2)) - Math.max(0, Math.min(viewport.boxSelectY1, viewport.boxSelectY2)))
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
                    for (var m = 0; m < viewport.selectedShaders.length; m++) {
                        var sh = shadersModel.get(viewport.selectedShaders[m]);
                        snaps.push({
                            type: "shader",
                            idx: viewport.selectedShaders[m],
                            x1: sh.x1,
                            y1: sh.y1,
                            x2: sh.x2,
                            y2: sh.y2
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
                        } else if (s.type === "shader") {
                            shadersModel.setProperty(s.idx, "x1", s.x1 + cdx);
                            shadersModel.setProperty(s.idx, "y1", s.y1 + cdy);
                            shadersModel.setProperty(s.idx, "x2", s.x2 + cdx);
                            shadersModel.setProperty(s.idx, "y2", s.y2 + cdy);
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
                        } else if (s.type === "shader") {
                            shadersModel.setProperty(s.idx, "x1", nx1);
                            shadersModel.setProperty(s.idx, "y1", ny1);
                            shadersModel.setProperty(s.idx, "x2", nx2);
                            shadersModel.setProperty(s.idx, "y2", ny2);
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

            FileDialog {
                id: fragFileDialog
                title: "Select compiled fragment shader"
                nameFilters: ["Compiled fragment shaders (*.frag.qsb)"]
                onAccepted: newshaderSettings.fragFilePath = selectedFile.toString()
            }

            FileDialog {
                id: vertFileDialog
                title: "Select compiled vertex shader"
                nameFilters: ["Compiled vertex shaders (*.vert.qsb)"]
                onAccepted: newshaderSettings.vertFilePath = selectedFile.toString()
            }

            FileDialog {
                id: areaSoundFileDialog
                title: "Select sound file"
                nameFilters: ["Audio files (*.mp3 *.wav *.ogg *.aac *.m4a *.flac)"]
                property int targetIdx: -1
                onAccepted: {
                    if (targetIdx >= 0)
                        areaInteractivityModel.setProperty(targetIdx, "itemSoundPath", selectedFile.toString())
                }
            }

            FileDialog {
                id: selSoundFileDialog
                title: "Select sound file"
                nameFilters: ["Audio files (*.mp3 *.wav *.ogg *.aac *.m4a *.flac)"]
                property int targetIdx: -1
                onAccepted: {
                    if (targetIdx >= 0)
                        selectInteractivityModel.setProperty(targetIdx, "itemSoundPath", selectedFile.toString())
                }
            }

            FileDialog {
                id: selectTextureDialog
                title: "Select texture image or video"
                nameFilters: ["Image and video files (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.svg *.mp4 *.mov *.mkv *.avi *.webm)"]
                property string pendingUniformName: ""
                onAccepted: {
                    var path = selectedFile.toString();
                    var name = pendingUniformName;
                    if (name === "" || !selectSettings.hasActiveShader) return;
                    var idx = viewport.selectedShaders[0];
                    var uniforms;
                    try { uniforms = JSON.parse(shadersModel.get(idx).uniformsJson || "[]"); } catch(e) { uniforms = []; }
                    for (var i = 0; i < uniforms.length; i++) {
                        if (uniforms[i].name === name) { uniforms[i].value = path; break; }
                    }
                    shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(uniforms));
                    var del = shadersRepeater.itemAt(idx);
                    if (del) del.applyTextureSource(name, path);
                    selectSettings.refreshShaderUniforms();
                }
            }

            FileDialog {
                id: newShaderTextureDialog
                title: "Select texture image or video"
                nameFilters: ["Image and video files (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.svg *.mp4 *.mov *.mkv *.avi *.webm)"]
                property string pendingUniformName: ""
                property int pendingUniformIndex: -1
                onAccepted: {
                    if (pendingUniformIndex < 0) return;
                    uniformFieldsModel.setProperty(pendingUniformIndex, "uText", selectedFile.toString());
                }
            }

            FileDialog {
                id: shaderPickerDialog
                title: "Select shader file(s)"
                fileMode: FileDialog.OpenFiles
                nameFilters: ["Compiled shaders (*.frag.qsb *.vert.qsb)"]
                onAccepted: {
                    for (var i = 0; i < selectedFiles.length; i++) {
                        var path = selectedFiles[i].toString();
                        if (path.endsWith(".frag.qsb"))
                            newshaderSettings.fragFilePath = path;
                        else if (path.endsWith(".vert.qsb"))
                            newshaderSettings.vertFilePath = path;
                    }
                    if (viewport.pendingShaderBounds && newshaderSettings.fragFilePath !== "") {
                        var b = viewport.pendingShaderBounds;
                        shadersModel.append({
                            x1: b.x1, y1: b.y1,
                            x2: b.x2, y2: b.y2,
                            fragPath: newshaderSettings.fragFilePath,
                            vertPath: newshaderSettings.vertFilePath,
                            name: newshaderSettings.propName,
                            stackOrder: viewport.nextStackOrder++,
                            uniformsJson: newshaderSettings.buildCurrentUniformsList()
                        });
                        viewport.selectShader(shadersModel.count - 1);
                        buttonGrid.selectedTool = "select";
                        newshaderSettings.fragFilePath = "";
                        newshaderSettings.vertFilePath = "";
                    }
                    viewport.pendingShaderBounds = null;
                }
                onRejected: viewport.pendingShaderBounds = null
            }

            FileDialog {
                id: selectImageSwapDialog
                title: "Select image file"
                nameFilters: ["Image files (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.svg)"]
                onAccepted: {
                    if (selectSettings.hasActiveImage)
                        imagesModel.setProperty(viewport.selectedImages[0], "filePath", selectedFile.toString());
                }
            }

            FileDialog {
                id: selectVideoSwapDialog
                title: "Select video file"
                nameFilters: ["Video files (*.mp4 *.mov *.avi *.mkv *.webm *.m4v)"]
                onAccepted: {
                    if (selectSettings.hasActiveVideo)
                        videosModel.setProperty(viewport.selectedVideos[0], "filePath", selectedFile.toString());
                }
            }

            FileDialog {
                id: selectFragSwapDialog
                title: "Select compiled fragment shader"
                nameFilters: ["Compiled fragment shaders (*.frag.qsb)"]
                onAccepted: {
                    if (selectSettings.hasActiveShader) {
                        var path = selectedFile.toString();
                        var idx = viewport.selectedShaders[0];
                        shadersModel.setProperty(idx, "fragPath", path);
                        shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(viewport.buildUniformsList(shaderInspector.inspectShader(path))));
                        selectSettings.refreshShaderUniforms();
                    }
                }
            }

            FileDialog {
                id: selectVertSwapDialog
                title: "Select compiled vertex shader"
                nameFilters: ["Compiled vertex shaders (*.vert.qsb)"]
                onAccepted: {
                    if (selectSettings.hasActiveShader)
                        shadersModel.setProperty(viewport.selectedShaders[0], "vertPath", selectedFile.toString());
                }
            }

            // Probe: resolves natural dimensions of a drag-dropped image
            Image {
                id: viewportImageProbe
                source: viewport.dropPendingImagePath
                visible: false
                width: 0
                height: 0
                onStatusChanged: {
                    if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                        var aspect = implicitWidth / implicitHeight;
                        var defaultW = Math.min(320, viewport.width * 0.5);
                        var defaultH = defaultW / aspect;
                        if (defaultH > viewport.height * 0.5) {
                            defaultH = viewport.height * 0.5;
                            defaultW = defaultH * aspect;
                        }
                        var x1 = Math.max(0, Math.min(viewport.dropX - defaultW / 2, viewport.width - defaultW));
                        var y1 = Math.max(0, Math.min(viewport.dropY - defaultH / 2, viewport.height - defaultH));
                        imagesModel.append({
                            x1: x1, y1: y1,
                            x2: x1 + defaultW, y2: y1 + defaultH,
                            filePath: viewport.dropPendingImagePath,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectImage(imagesModel.count - 1);
                        buttonGrid.selectedTool = "select";
                        viewport.dropPendingImagePath = "";
                    } else if (status === Image.Error || status === Image.Null) {
                        viewport.dropPendingImagePath = "";
                    }
                }
            }

            // Probe: resolves natural dimensions of a drag-dropped video
            MediaPlayer {
                id: viewportVideoProbe
                source: viewport.dropPendingVideoPath
                onMediaStatusChanged: status => {
                    if (status === MediaPlayer.LoadedMedia || status === MediaPlayer.BufferedMedia) {
                        var res = metaData.value(MediaMetaData.Resolution);
                        var aspect = (res && res.width > 0 && res.height > 0) ? res.width / res.height : 16 / 9;
                        var defaultW = Math.min(320, viewport.width * 0.5);
                        var defaultH = defaultW / aspect;
                        if (defaultH > viewport.height * 0.5) {
                            defaultH = viewport.height * 0.5;
                            defaultW = defaultH * aspect;
                        }
                        var x1 = Math.max(0, Math.min(viewport.dropX - defaultW / 2, viewport.width - defaultW));
                        var y1 = Math.max(0, Math.min(viewport.dropY - defaultH / 2, viewport.height - defaultH));
                        videosModel.append({
                            x1: x1, y1: y1,
                            x2: x1 + defaultW, y2: y1 + defaultH,
                            filePath: viewport.dropPendingVideoPath,
                            stackOrder: viewport.nextStackOrder++
                        });
                        viewport.selectVideo(videosModel.count - 1);
                        buttonGrid.selectedTool = "select";
                        viewport.dropPendingVideoPath = "";
                    } else if (status === MediaPlayer.NoMedia || status === MediaPlayer.InvalidMedia) {
                        viewport.dropPendingVideoPath = "";
                    }
                }
            }

            // Drag-and-drop media files directly into the viewport
            DropArea {
                anchors.fill: parent
                z: 997

                Rectangle {
                    anchors.fill: parent
                    color: "white"
                    opacity: parent.containsDrag ? 0.06 : 0
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                }

                onDropped: drop => {
                    if (!drop.hasUrls) return;
                    var url = drop.urls[0].toString();
                    var lower = url.toLowerCase();
                    var imageExts = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".svg"];
                    var videoExts = [".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"];
                    var isImage = imageExts.some(ext => lower.endsWith(ext));
                    var isVideo = !isImage && videoExts.some(ext => lower.endsWith(ext));
                    if (isImage) {
                        viewport.dropX = drop.x;
                        viewport.dropY = drop.y;
                        viewport.dropPendingImagePath = url;
                    } else if (isVideo) {
                        viewport.dropX = drop.x;
                        viewport.dropY = drop.y;
                        viewport.dropPendingVideoPath = url;
                    }
                }
            }

            // Tool cursor
            MouseArea {
                id: viewportCursorArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: viewport.textEditing ? Qt.IBeamCursor : ((sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen || ["select", "simulate", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo", "newshader"].indexOf(viewport.effectiveTool) !== -1) ? Qt.BlankCursor : Qt.ArrowCursor)
                z: 999
                onPositionChanged: viewport.hoveredAreaIndex = viewport.findHoveredArea(mouseX, mouseY)
                onExited: viewport.hoveredAreaIndex = -1
            }

            Image {
                x: (viewport.areaDragging ? viewport.areaX2 : (viewport.textBoxDragging ? viewport.tbX2 : (viewport.imageDragging ? viewport.imgX2 : (viewport.videoDragging ? viewport.vidX2 : (viewport.shaderDragging ? viewport.shaderX2 : (viewport.elementDragging ? viewport.elementDragX : (viewport.boxSelecting ? viewport.boxSelectX2 : viewportCursorArea.mouseX))))))) + ((viewport.effectiveTool === "select" || sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen) ? -8 : 0)
                y: (viewport.areaDragging ? viewport.areaY2 : (viewport.textBoxDragging ? viewport.tbY2 : (viewport.imageDragging ? viewport.imgY2 : (viewport.videoDragging ? viewport.vidY2 : (viewport.shaderDragging ? viewport.shaderY2 : (viewport.elementDragging ? viewport.elementDragY : (viewport.boxSelecting ? viewport.boxSelectY2 : viewportCursorArea.mouseY))))))) + ((viewport.effectiveTool === "select" || sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen) ? -1 : 0)
                width: 36
                height: 36
                source: viewport.elementDragging ? "icons/pinch.svg" : ((sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen) ? "icons/select.svg" : (["select", "simulate", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo", "newshader"].indexOf(viewport.effectiveTool) !== -1 ? "icons/" + viewport.effectiveTool + ".svg" : ""))
                visible: !viewport.textEditing && viewportCursorArea.containsMouse && (viewport.elementDragging || sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen || ["select", "simulate", "relayer", "destroy", "newarea", "newtext", "newimage", "newvideo", "newshader"].indexOf(viewport.effectiveTool) !== -1)
                fillMode: Image.PreserveAspectFit
                z: 1000
            }

            // Off-screen capture surface for thumbnails.
            // Positioned to the left of the viewport (outside visible area).
            // ShaderEffectSource mirrors only the scene content (no bg shader),
            // over a black background — grabbed by captureAndSaveThumbnail().
            Item {
                id: thumbnailCaptureSurface
                x: -(viewport.width + 20)
                y: 0
                width: viewport.width
                height: viewport.height
                // layer.enabled forces Qt to render this item to a texture even when
                // positioned outside the visible window area, which is required for
                // grabToImage() to capture anything useful.
                layer.enabled: true

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                }
                ShaderEffectSource {
                    id: thumbnailShaderSource
                    anchors.fill: parent
                    sourceItem: viewportSceneContent
                    live: true
                    hideSource: false
                }
            }

            Rectangle {
                id: navigationViewportOverlay
                visible: sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen
                anchors.fill: parent
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.6)
                opacity: (sceneEditorButtons.navOverlayOpen || sceneEditorButtons.interactivityPickerOpen) ? 1 : 0
                z: 998

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.InOutQuad
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.ArrowCursor
                    hoverEnabled: true
                    propagateComposedEvents: true
                    onClicked: mouse.accepted = false
                    onPressed: mouse.accepted = false
                    onReleased: mouse.accepted = false
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
                                color: "black"
                                // border drawn as child overlay so it renders above the thumbnail
                                clip: true
                                layer.enabled: true

                                property bool hovered: false
                                property bool isLast: index === scenesRectModel.count - 1

                                // Thumbnail fill — wrapped in a layer+OpacityMask Item so the
                                // image is clipped to the card's rounded corners.
                                Item {
                                    id: navThumbClip
                                    anchors.fill: parent
                                    visible: !isLast && model.thumbnailRev > 0
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: navThumbClip.width
                                            height: navThumbClip.height
                                            radius: 30
                                            color: "white"
                                        }
                                    }
                                    Image {
                                        anchors.fill: parent
                                        source: (!isLast && model.thumbnailRev > 0)
                                            ? ("image://thumbnails/" + model.sceneId + "?rev=" + model.thumbnailRev)
                                            : ""
                                        fillMode: Image.PreserveAspectCrop
                                        cache: false
                                    }
                                }

                                // Dimming overlay on hover
                                Rectangle {
                                    anchors.fill: parent
                                    color: "black"
                                    radius: 30
                                    opacity: hovered && !isLast ? 0.25 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: sceneEditorButtons.navigationOpen && !isLast ? Qt.OpenHandCursor : Qt.ArrowCursor
                                    preventStealing: sceneEditorButtons.navigationOpen && !isLast

                                    property bool dragStarted: false
                                    property point pressPos

                                    onEntered: hovered = true
                                    onExited: hovered = false

                                    onPressed: {
                                        pressPos = Qt.point(mouseX, mouseY)
                                        dragStarted = false
                                    }

                                    onPositionChanged: {
                                        if (pressed && sceneEditorButtons.navigationOpen && !isLast) {
                                            var dx = mouseX - pressPos.x
                                            var dy = mouseY - pressPos.y
                                            if (Math.sqrt(dx * dx + dy * dy) > 8) {
                                                if (!dragStarted) {
                                                    dragStarted = true
                                                    navDragGhost.draggedSceneId = model.sceneId
                                                    navDragGhost.draggedSceneName = model.sceneName || ""
                                                    navDragGhost.draggedThumbnailRev = model.thumbnailRev || 0
                                                }
                                                var pos = mapToItem(sceneEditor, mouseX, mouseY)
                                                navDragGhost.x = pos.x - navDragGhost.width / 2
                                                navDragGhost.y = pos.y - navDragGhost.height / 2
                                                navDragGhost.visible = true
                                            }
                                        }
                                    }

                                    onReleased: {
                                        if (dragStarted) {
                                            navDragGhost.Drag.drop()
                                            navDragGhost.visible = false
                                            // dragStarted intentionally NOT reset here so onClicked can detect it
                                        }
                                    }

                                    onClicked: {
                                        if (dragStarted) {
                                            dragStarted = false
                                            return
                                        }
                                        if (isLast) {
                                            var newId = storyManager.createScene("new scene");
                                            if (newId !== -1) {
                                                scenesRectModel.insert(scenesRectModel.count - 1,
                                                    { sceneId: newId, sceneName: "new scene", thumbnailRev: 0 });
                                                if (mainWindow.currentSceneId !== -1) {
                                                    storyManager.updateSceneName(mainWindow.currentSceneId, sceneNameInput.text);
                                                    storyManager.saveSceneElements(mainWindow.currentSceneId, viewport.collectSceneElements());
                                                }
                                                nodeWorkspace.saveToDb();
                                                mainWindow.currentSceneId = newId;
                                                viewport.clearForNewScene();
                                                sceneNameInput.text = "new scene";
                                                sceneEditorButtons.navigationOpen = false;
                                                sceneEditorButtons.interactivityPickerOpen = false;
                                            }
                                        } else if (sceneEditorButtons.interactivityPickerOpen) {
                                            var pickedId = model.sceneId
                                            var pickedName = model.sceneName || storyManager.getSceneName(pickedId)
                                            var idx = sceneEditorButtons.interactivityPickerTargetIdx
                                            if (sceneEditorButtons.interactivityPickerTargetModel === "area") {
                                                areaInteractivityModel.setProperty(idx, "itemTargetSceneId", pickedId)
                                                areaInteractivityModel.setProperty(idx, "itemTargetSceneName", pickedName)
                                            } else if (sceneEditorButtons.interactivityPickerTargetModel === "select") {
                                                selectInteractivityModel.setProperty(idx, "itemTargetSceneId", pickedId)
                                                selectInteractivityModel.setProperty(idx, "itemTargetSceneName", pickedName)
                                            }
                                            sceneEditorButtons.interactivityPickerOpen = false
                                            sceneEditorButtons.interactivityPickerTargetIdx = -1
                                            sceneEditorButtons.interactivityPickerTargetModel = ""
                                        } else {
                                            var targetId = scenesRectModel.get(index).sceneId;
                                            if (targetId !== mainWindow.currentSceneId) {
                                                if (mainWindow.currentSceneId !== -1) {
                                                    viewport.captureAndSaveThumbnail(mainWindow.currentSceneId, function() {
                                                        storyManager.updateSceneName(mainWindow.currentSceneId, sceneNameInput.text);
                                                        storyManager.saveSceneElements(mainWindow.currentSceneId, viewport.collectSceneElements());
                                                        nodeWorkspace.saveToDb();
                                                        mainWindow.currentSceneId = targetId;
                                                        viewport.loadSceneIntoViewport(targetId);
                                                        sceneNameInput.text = storyManager.getSceneName(targetId);
                                                        navigationViewportSelectionFlash.running = true;
                                                        sceneEditorButtons.navigationOpen = false;
                                                        sceneEditorButtons.interactivityPickerOpen = false;
                                                    });
                                                    return;
                                                }
                                                mainWindow.currentSceneId = targetId;
                                                viewport.loadSceneIntoViewport(targetId);
                                                sceneNameInput.text = storyManager.getSceneName(targetId);
                                            }
                                            navigationViewportSelectionFlash.running = true;
                                            sceneEditorButtons.navigationOpen = false;
                                            sceneEditorButtons.interactivityPickerOpen = false;
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: "white"
                                    font.pixelSize: 32
                                    visible: isLast
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 12
                                    text: model.sceneId !== -1 ? (model.sceneName || "") : ""
                                    font.pixelSize: 11
                                    color: "white"
                                    visible: model.sceneId !== -1
                                    elide: Text.ElideMiddle
                                    width: parent.width - 16
                                    horizontalAlignment: Text.AlignHCenter
                                    style: Text.Outline
                                    styleColor: "black"
                                }

                                // Border overlay — rendered last so it always appears above the thumbnail
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 4
                                    radius: 30
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

            Rectangle {
                id: viewportBlackOverlay
                anchors.fill: parent
                color: "black"
                opacity: 1.0
                z: 1001

                NumberAnimation {
                    id: viewportFadeInAnim
                    target: viewportBlackOverlay
                    property: "opacity"
                    to: 1.0
                    duration: 800
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    id: viewportFadeOutAnim
                    target: viewportBlackOverlay
                    property: "opacity"
                    to: 0.0
                    duration: 800
                    easing.type: Easing.InOutQuad
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
                id: toolPalette
                width: 405
                height: 152
                color: "transparent"

                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter

                GridLayout {
                    id: buttonGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 5
                    rowSpacing: 8
                    columnSpacing: 4

                    property string selectedTool: "select"
                    property color activeIconColor: "#477B78"

                    Repeater {
                        model: ["select", "simulate", "relayer", "destroy", "preview", "newarea", "newtext", "newimage", "newvideo", "newshader"]

                        delegate: Item {
                            id: buttonRoot
                            width: 72
                            height: 72

                            property bool hovered: false
                            property bool flashing: false
                            property bool toggled: flashing || (modelData !== "preview" && viewport.effectiveTool === modelData)
                            property string iconSource: "icons/" + modelData + ".svg"

                            Timer {
                                id: flashTimer
                                interval: 150
                                onTriggered: buttonRoot.flashing = false
                            }

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
                                width: 56
                                height: 56
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
                                    if (modelData === "preview") {
                                        buttonRoot.flashing = true;
                                        flashTimer.restart();
                                        // TODO: launch preview
                                        return;
                                    }
                                    var nonCreation = ["select", "simulate", "relayer", "destroy"];
                                    if (buttonGrid.selectedTool !== modelData)
                                        buttonGrid.selectedTool = modelData;
                                    else if (nonCreation.indexOf(modelData) === -1)
                                        buttonGrid.selectedTool = "select";
                                    if (nonCreation.indexOf(modelData) === -1) {
                                        sceneEditorButtons.variablesOpen = false;
                                        sceneEditorButtons.conditionsOpen = false;
                                        sceneEditorButtons.navigationOpen = false;
                                        sceneEditorButtons.interactivityPickerOpen = false;
                                    }
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
                property bool conditionsOpen: false
                property bool variablesOpen: false
                property bool navigationOpen: false
                property bool navOverlayOpen: false
                property bool interactivityPickerOpen: false
                property int interactivityPickerTargetIdx: -1
                property string interactivityPickerTargetModel: ""

                onNavigationOpenChanged: { if (!navigationOpen) navOverlayOpen = false }

                Repeater {
                    model: ["conditions", "variables", "timeline", "close scene"]

                    delegate: Item {
                        id: editorBtn
                        width: 138
                        height: 28

                        property bool hovered: false
                        property bool togglable: modelData === "conditions" || modelData === "variables"
                        property bool toggled: modelData === "timeline" ? sceneEditorButtons.timelineOpen : (modelData === "conditions" ? sceneEditorButtons.conditionsOpen : (modelData === "variables" ? sceneEditorButtons.variablesOpen : false))
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
                                    if (modelData === "conditions")
                                        sceneEditorButtons.conditionsOpen = !sceneEditorButtons.conditionsOpen;
                                    else if (modelData === "variables")
                                        sceneEditorButtons.variablesOpen = !sceneEditorButtons.variablesOpen;
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
                                    // Capture thumbnail, save scene state, then initiate transition
                                    var savedSceneId = mainWindow.currentSceneId;
                                    viewport.captureAndSaveThumbnail(savedSceneId, function() {
                                        if (savedSceneId !== -1) {
                                            storyManager.updateSceneName(savedSceneId, sceneNameInput.text);
                                            storyManager.saveSceneElements(savedSceneId, viewport.collectSceneElements());
                                        }
                                        sceneScript.saveVariablesToDb();
                                        nodeWorkspace.saveToDb();
                                        if (savedSceneId !== -1)
                                            storyManager.setEditorState("scene_" + savedSceneId + "_timeline_open", sceneEditorButtons.timelineOpen ? "1" : "0");
                                        if (sceneEditorButtons.timelineOpen) {
                                            sceneEditorButtons.timelineOpen = false;
                                            yanimationduration = 1000;
                                            mainWindow.height = 540;
                                            mainWindow.y = mainWindow.y + 150;
                                            closeSceneTimer.start();
                                        } else {
                                            viewportFadeInAnim.start();
                                            xanimationduration = 1000;
                                            mainWindow.width = 960;
                                            mainWindow.x = sceneEditorEntryX;
                                            sceneEditor2sceneMenu.windowSizeCompleteTrigger = true;
                                        }
                                    });
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: toolSettingsArea
                radius: 12
                width: 377
                color: "transparent"
                border.color: "white"
                border.width: sceneEditorButtons.navigationOpen ? 0 : 2
                anchors.top: toolPalette.bottom
                anchors.topMargin: 14
                anchors.bottom: sceneEditorButtons.top
                anchors.bottomMargin: 14
                anchors.left: parent.left
                anchors.leftMargin: 14

                Rectangle {
                    id: areaSettings
                    visible: buttonGrid.selectedTool === "newarea" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"
                    property string interactivityTab: "click"

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

                    ListModel { id: areaInteractivityModel }

                    ScrollView {
                        id: areaPropsScroll
                        anchors.top: areaSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            id: areaSpatialProps
                            width: areaPropsScroll.availableWidth
                            spacing: 4

                            property real propX: 0
                            property real propY: 0
                            property real propW: 200
                            property real propH: 150
                            property bool propLock: false
                            property string propName: ""

                            Text {
                                text: "information"
                                font.pixelSize: 11
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 1
                                color: "white"
                                width: parent.width
                                bottomPadding: 6
                            }

                            Row {
                                width: areaSpatialProps.width; height: 26; spacing: 6
                                Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Rectangle {
                                    width: parent.width - 50; height: 26
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 3
                                        color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                        text: areaSpatialProps.propName
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: areaSpatialProps.propName = text
                                    }
                                }
                            }

                            Repeater {
                                model: [
                                    { lbl: "x",      key: "propX" },
                                    { lbl: "y",      key: "propY" },
                                    { lbl: "width",  key: "propW" },
                                    { lbl: "height", key: "propH" }
                                ]
                                delegate: Row {
                                    width: areaSpatialProps.width
                                    height: 26
                                    spacing: 6
                                    Text {
                                        text: modelData.lbl
                                        width: 44; color: "white"; font.pixelSize: 11
                                        height: parent.height; verticalAlignment: Text.AlignVCenter
                                    }
                                    Rectangle {
                                        width: parent.width - 50; height: 26
                                        color: "transparent"; border.color: "white"
                                        border.width: 1; radius: 4
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: 3
                                            color: "white"; font.pixelSize: 11
                                            clip: true; selectByMouse: true
                                            text: areaSpatialProps[modelData.key].toFixed(0)
                                            Keys.onReturnPressed: focus = false
                                            Keys.onEscapePressed: focus = false
                                            onEditingFinished: areaSpatialProps[modelData.key] = parseFloat(text) || 0
                                        }
                                    }
                                }
                            }

                            Row {
                                width: areaSpatialProps.width; height: 26; spacing: 6
                                Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Row {
                                    spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                        delegate: Row {
                                            spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                border.color: "white"; border.width: 1; color: "transparent"
                                                anchors.verticalCenter: parent.verticalCenter
                                                Rectangle {
                                                    anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                    color: "white"; visible: areaSpatialProps.propLock === modelData.val
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: areaSpatialProps.propLock = modelData.val }
                                            }
                                            Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                }
                            }

                            Item { width: 1; height: 12 }

                            RowLayout {
                                width: parent.width
                                height: 26
                                spacing: 4

                                Text {
                                    text: "interactivity"
                                    font.pixelSize: 11
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1
                                    color: "white"
                                    verticalAlignment: Text.AlignVCenter
                                    Layout.rightMargin: 4
                                }

                                Repeater {
                                    model: ["click", "hover"]
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 18
                                        radius: 3
                                        property bool active: areaSettings.interactivityTab === modelData
                                        color: active ? "white" : "transparent"
                                        border.color: "white"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.pixelSize: 10
                                            color: parent.active ? "#1a1a1d" : "white"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: areaSettings.interactivityTab = modelData
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 4
                                    property bool hovered: false
                                    color: hovered ? "white" : "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 0
                                        anchors.horizontalCenterOffset: -0.5
                                        text: "+"
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: parent.hovered ? "darkslategrey" : "white"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: parent.hovered = true
                                        onExited: parent.hovered = false
                                        onClicked: {
                                            var tab = areaSettings.interactivityTab
                                            var defaultAction = "cue"
                                            for (var i = 0; i < areaInteractivityModel.count; i++) {
                                                var e = areaInteractivityModel.get(i)
                                                if (e.itemTrigger !== tab) continue
                                                if ((e.itemAction === "cue" && e.itemCommand === "jump") ||
                                                    (e.itemAction === "else" && e.itemCommand === "jump")) {
                                                    defaultAction = "if"; break
                                                }
                                            }
                                            var firstVar = ""
                                            if (defaultAction === "if") {
                                                for (var i = 0; i < variablesModel.count; i++) {
                                                    if (variablesModel.get(i).varName !== "") { firstVar = variablesModel.get(i).varName; break }
                                                }
                                                if (firstVar === "") return
                                            }
                                            areaInteractivityModel.append({ itemTrigger: tab, itemAction: defaultAction, itemCommand: "jump", itemTransition: "cut", itemTransitionSpeed: 1.0, itemTargetSceneId: -1, itemTargetSceneName: "", itemConditionVar: firstVar, itemConditionOp: "is", itemConditionVal: "", itemSoundPath: "", itemUpdateVar: "", itemUpdateOp: "=", itemUpdateVal: "" })
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: areaInteractivityModel
                                delegate: Component {
                                    Item {
                                        id: areaInteractivityDelegate
                                        width: parent ? parent.width : 0
                                        height: itemTrigger === areaSettings.interactivityTab ? innerAreaCol.height : 0
                                        visible: itemTrigger === areaSettings.interactivityTab
                                        property int listIdx: index
                                        property real deleteProgress: 0.0
                                        property string condVarType: {
                                            var v = itemConditionVar
                                            if (!v || v === "") return ""
                                            for (var i = 0; i < variablesModel.count; i++) {
                                                if (variablesModel.get(i).varName === v) return variablesModel.get(i).varType
                                            }
                                            return ""
                                        }
                                        property string updateVarType: {
                                            var v = itemUpdateVar
                                            if (!v || v === "") return ""
                                            for (var i = 0; i < variablesModel.count; i++) {
                                                if (variablesModel.get(i).varName === v) return variablesModel.get(i).varType
                                            }
                                            return ""
                                        }

                                        NumberAnimation {
                                            id: areaDeleteAnim
                                            target: areaInteractivityDelegate
                                            property: "deleteProgress"
                                            to: 1.0
                                            duration: 1200
                                            easing.type: Easing.Linear
                                            onFinished: {
                                                if (areaInteractivityDelegate.deleteProgress >= 1.0) {
                                                    var item = areaInteractivityModel.get(areaInteractivityDelegate.listIdx)
                                                    var wasIf = item.itemAction === "if"
                                                    var trigger = item.itemTrigger
                                                    areaInteractivityModel.remove(areaInteractivityDelegate.listIdx)
                                                    if (wasIf) {
                                                        var hasIf = false
                                                        for (var i = 0; i < areaInteractivityModel.count; i++) {
                                                            var e = areaInteractivityModel.get(i)
                                                            if (e.itemTrigger === trigger && e.itemAction === "if") { hasIf = true; break }
                                                        }
                                                        if (!hasIf) {
                                                            for (var i = areaInteractivityModel.count - 1; i >= 0; i--) {
                                                                var e = areaInteractivityModel.get(i)
                                                                if (e.itemTrigger === trigger && e.itemAction === "else")
                                                                    areaInteractivityModel.remove(i)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            z: 10
                                            onPressed: mouse => { areaInteractivityDelegate.deleteProgress = 0; areaDeleteAnim.start() }
                                            onReleased: mouse => { areaDeleteAnim.stop(); areaInteractivityDelegate.deleteProgress = 0 }
                                            onExited: { areaDeleteAnim.stop(); areaInteractivityDelegate.deleteProgress = 0 }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 4
                                            color: "#ff4444"
                                            opacity: areaInteractivityDelegate.deleteProgress * 0.75
                                            visible: areaInteractivityDelegate.deleteProgress > 0
                                            z: 9
                                        }

                                        Column {
                                            id: innerAreaCol
                                            width: parent.width
                                            spacing: 4

                                        Item { width: 1; height: 2 }

                                        RowLayout {
                                            width: parent.width
                                            height: 26
                                            spacing: 4

                                            ComboBox {
                                                id: areaActionCombo
                                                Layout.preferredWidth: 62
                                                Layout.preferredHeight: 26
                                                model: {
                                                    var hasVars = false
                                                    for (var i = 0; i < variablesModel.count; i++) {
                                                        if (variablesModel.get(i).varName !== "") { hasVars = true; break }
                                                    }
                                                    if (!hasVars) return ["cue"]
                                                    var opts = ["cue", "if"]
                                                    var thisIdx = areaInteractivityDelegate.listIdx
                                                    var thisTrigger = itemTrigger
                                                    for (var i = 0; i < areaInteractivityModel.count; i++) {
                                                        var e = areaInteractivityModel.get(i)
                                                        if (i !== thisIdx && e.itemTrigger === thisTrigger && e.itemAction === "if") {
                                                            opts.push("else"); break
                                                        }
                                                    }
                                                    return opts
                                                }
                                                currentIndex: Math.max(0, model.indexOf(itemAction))
                                                onActivated: function(activatedIndex) {
                                                    var newAction = areaActionCombo.model[activatedIndex]
                                                    var itemIdx = areaInteractivityDelegate.listIdx
                                                    var revertIdx = Math.max(0, areaActionCombo.model.indexOf(itemAction))
                                                    var trigger = itemTrigger
                                                    if (newAction === "cue") {
                                                        for (var i = 0; i < areaInteractivityModel.count; i++) {
                                                            if (i === itemIdx) continue
                                                            var e = areaInteractivityModel.get(i)
                                                            if (e.itemTrigger !== trigger) continue
                                                            if ((e.itemAction === "cue" && e.itemCommand === "jump") ||
                                                                (e.itemAction === "else" && e.itemCommand === "jump")) {
                                                                currentIndex = revertIdx; return
                                                            }
                                                        }
                                                    } else if (newAction === "else") {
                                                        var hasIf = false
                                                        for (var i = 0; i < areaInteractivityModel.count; i++) {
                                                            if (i === itemIdx) continue
                                                            var e = areaInteractivityModel.get(i)
                                                            if (e.itemTrigger !== trigger) continue
                                                            if (e.itemAction === "else" || (e.itemAction === "cue" && e.itemCommand === "jump")) {
                                                                currentIndex = revertIdx; return
                                                            }
                                                            if (e.itemAction === "if") hasIf = true
                                                        }
                                                        if (!hasIf) { currentIndex = revertIdx; return }
                                                    }
                                                    areaInteractivityModel.setProperty(itemIdx, "itemAction", newAction)
                                                }
                                                contentItem: Text {
                                                    leftPadding: 6; rightPadding: 18
                                                    text: parent.displayText
                                                    font.pixelSize: 11; color: "white"
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                indicator: Text {
                                                    x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                    text: "▾"; font.pixelSize: 10; color: "white"
                                                }
                                                background: Rectangle {
                                                    radius: 4; color: "transparent"; border.color: "white"; border.width: 1
                                                }
                                                delegate: ItemDelegate {
                                                    width: parent ? parent.width : 62; height: 22; padding: 0
                                                    contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                    background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                }
                                                popup: Popup {
                                                    y: parent.height + 2; width: parent.width
                                                    height: areaActionCombo.model.length * 22 + 2; padding: 1
                                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                    contentItem: ListView { clip: true; model: areaActionCombo.delegateModel; currentIndex: areaActionCombo.currentIndex }
                                                }
                                            }

                                            // "if" condition — variable name
                                            ComboBox {
                                                id: areaCondVarCombo
                                                visible: itemAction === "if"
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 0
                                                Layout.minimumWidth: 0
                                                Layout.preferredHeight: 26
                                                model: {
                                                    var names = []
                                                    for (var i = 0; i < variablesModel.count; i++) {
                                                        var n = variablesModel.get(i).varName
                                                        if (n !== "") names.push(n)
                                                    }
                                                    return names
                                                }
                                                currentIndex: {
                                                    var v = itemConditionVar
                                                    if (!v || v === "") return 0
                                                    for (var i = 0; i < variablesModel.count; i++) {
                                                        if (variablesModel.get(i).varName === v) return i
                                                    }
                                                    return 0
                                                }
                                                onActivated: function(idx) {
                                                    var itemIdx = areaInteractivityDelegate.listIdx
                                                    var varName = variablesModel.get(idx).varName
                                                    var varType = variablesModel.get(idx).varType
                                                    areaInteractivityModel.setProperty(itemIdx, "itemConditionVar", varName)
                                                    var op = areaInteractivityModel.get(itemIdx).itemConditionOp
                                                    if (varType !== "number" && (op === ">" || op === "<"))
                                                        areaInteractivityModel.setProperty(itemIdx, "itemConditionOp", "is")
                                                    areaInteractivityModel.setProperty(itemIdx, "itemConditionVal", "")
                                                }
                                                contentItem: Text {
                                                    leftPadding: 4; rightPadding: 14
                                                    text: parent.displayText
                                                    font.pixelSize: 10; color: "white"
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                indicator: Text {
                                                    x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                    text: "▾"; font.pixelSize: 9; color: "white"
                                                }
                                                background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                delegate: ItemDelegate {
                                                    width: parent ? parent.width : 60; height: 20; padding: 0
                                                    contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                    background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                }
                                                popup: Popup {
                                                    y: parent.height + 2
                                                    width: Math.max(parent.width, 80)
                                                    height: Math.min(areaCondVarCombo.model.length * 20 + 2, 102); padding: 1
                                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                    contentItem: ListView { clip: true; model: areaCondVarCombo.delegateModel; currentIndex: areaCondVarCombo.currentIndex }
                                                }
                                            }

                                            // "if" condition — operator
                                            ComboBox {
                                                id: areaCondOpCombo
                                                visible: itemAction === "if"
                                                Layout.preferredWidth: 44
                                                Layout.preferredHeight: 26
                                                model: areaInteractivityDelegate.condVarType === "number" ? ["is","not",">","<"] : ["is","not"]
                                                currentIndex: Math.max(0, model.indexOf(itemConditionOp || "is"))
                                                onActivated: function(idx) {
                                                    areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemConditionOp", model[idx])
                                                }
                                                contentItem: Text {
                                                    leftPadding: 4; rightPadding: 14
                                                    text: parent.displayText
                                                    font.pixelSize: 10; color: "white"
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                indicator: Text {
                                                    x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                    text: "▾"; font.pixelSize: 9; color: "white"
                                                }
                                                background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                delegate: ItemDelegate {
                                                    width: parent ? parent.width : 44; height: 20; padding: 0
                                                    contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                    background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                }
                                                popup: Popup {
                                                    y: parent.height + 2; width: parent.width
                                                    height: (areaInteractivityDelegate.condVarType === "number" ? 4 : 2) * 20 + 2; padding: 1
                                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                    contentItem: ListView { clip: true; model: areaCondOpCombo.delegateModel; currentIndex: areaCondOpCombo.currentIndex }
                                                }
                                            }

                                            // "if" condition — value
                                            Item {
                                                visible: itemAction === "if"
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 0
                                                Layout.minimumWidth: 0
                                                Layout.preferredHeight: 26

                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: areaInteractivityDelegate.condVarType === "text"
                                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                    TextInput {
                                                        anchors.left: parent.left; anchors.right: parent.right
                                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                        text: areaInteractivityDelegate.condVarType === "text" ? (itemConditionVal || "") : ""
                                                        Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                        onEditingFinished: areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemConditionVal", text)
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: areaInteractivityDelegate.condVarType === "number"
                                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                    TextInput {
                                                        anchors.left: parent.left; anchors.right: parent.right
                                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                        validator: DoubleValidator {}
                                                        text: areaInteractivityDelegate.condVarType === "number" ? (itemConditionVal || "") : ""
                                                        Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                        onEditingFinished: areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemConditionVal", text)
                                                    }
                                                }
                                                ComboBox {
                                                    id: areaBoolValCombo
                                                    anchors.fill: parent
                                                    visible: areaInteractivityDelegate.condVarType === "true or false"
                                                    model: ["true", "false"]
                                                    currentIndex: (itemConditionVal === "false") ? 1 : 0
                                                    onActivated: function(idx) {
                                                        areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemConditionVal", idx === 0 ? "true" : "false")
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 4; rightPadding: 14; text: parent.displayText
                                                        font.pixelSize: 10; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 9; color: "white"
                                                    }
                                                    background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 50; height: 20; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width; height: 42; padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: areaBoolValCombo.delegateModel; currentIndex: areaBoolValCombo.currentIndex }
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: areaInteractivityDelegate.condVarType === ""
                                                    color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                                }
                                            }

                                            ComboBox {
                                                id: areaCommandCombo
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 0
                                                Layout.minimumWidth: 0
                                                Layout.preferredHeight: 26
                                                model: ["jump", "sound", "video", "update", "transport"]
                                                currentIndex: {
                                                    var idx = model.indexOf(itemCommand)
                                                    return idx < 0 ? 0 : idx
                                                }
                                                onActivated: function(idx) {
                                                    var cmd = areaCommandCombo.model[idx]
                                                    areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemCommand", cmd)
                                                    if (cmd === "update" && itemUpdateVar === "") {
                                                        for (var i = 0; i < variablesModel.count; i++) {
                                                            var n = variablesModel.get(i).varName
                                                            if (n !== "") {
                                                                areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateVar", n)
                                                                break
                                                            }
                                                        }
                                                    }
                                                }
                                                contentItem: Text {
                                                    leftPadding: 6; rightPadding: 18
                                                    text: parent.displayText
                                                    font.pixelSize: 11; color: "white"
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                indicator: Text {
                                                    x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                    text: "▾"; font.pixelSize: 10; color: "white"
                                                }
                                                background: Rectangle {
                                                    radius: 4; color: "transparent"; border.color: "white"; border.width: 1
                                                }
                                                delegate: ItemDelegate {
                                                    width: parent ? parent.width : 80; height: 22; padding: 0
                                                    contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                    background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                }
                                                popup: Popup {
                                                    y: parent.height + 2; width: parent.width; height: 112; padding: 1
                                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                    contentItem: ListView { clip: true; model: areaCommandCombo.delegateModel; currentIndex: areaCommandCombo.currentIndex }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: itemAction === "if" ? 26 : 0
                                                Layout.minimumWidth: itemAction === "if" ? 26 : 0
                                                Layout.maximumWidth: itemAction === "if" ? 26 : 10000
                                                Layout.preferredHeight: 26
                                                visible: itemCommand === "jump"
                                                radius: 4
                                                property bool hovered: false
                                                property bool toggled: sceneEditorButtons.interactivityPickerOpen
                                                color: toggled || hovered ? "white" : "transparent"
                                                border.color: "white"
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: itemTargetSceneName !== "" ? itemTargetSceneName : "+"
                                                    font.pixelSize: itemTargetSceneName !== "" ? 11 : 18
                                                    font.bold: itemTargetSceneName === ""
                                                    color: (parent.toggled || parent.hovered) ? "darkslategrey" : "white"
                                                    elide: Text.ElideRight
                                                    width: parent.width - 8
                                                    horizontalAlignment: Text.AlignHCenter
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onEntered: parent.hovered = true
                                                    onExited: parent.hovered = false
                                                    onClicked: {
                                                        sceneEditorButtons.interactivityPickerTargetIdx = areaInteractivityDelegate.listIdx
                                                        sceneEditorButtons.interactivityPickerTargetModel = "area"
                                                        sceneEditorButtons.interactivityPickerOpen = !sceneEditorButtons.interactivityPickerOpen
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            width: parent.width
                                            height: itemCommand === "jump" ? Math.round((parent.width - 16) / 5) : 0
                                            visible: itemCommand === "jump"

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 4

                                                Repeater {
                                                    model: [
                                                        { icon: "cut",      key: "cut"      },
                                                        { icon: "dissolve", key: "dissolve" },
                                                        { icon: "wipe",     key: "wipe"     },
                                                        { icon: "push",     key: "push"     },
                                                        { icon: "look",     key: "look"     }
                                                    ]
                                                    delegate: Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        radius: 4
                                                        property bool isActive: itemTransition === modelData.key
                                                        color: isActive ? "#477B78" : "transparent"
                                                        border.color: "white"
                                                        border.width: 1
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        Image {
                                                            anchors.centerIn: parent
                                                            width: Math.round(parent.height * 0.72)
                                                            height: width
                                                            source: "icons/" + modelData.icon + ".svg"
                                                            fillMode: Image.PreserveAspectFit
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: {
                                                                areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemTransition", modelData.key)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            width: parent.width
                                            height: (itemCommand === "jump" && itemTransition !== "cut") ? 22 : 0
                                            visible: itemCommand === "jump" && itemTransition !== "cut"

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 6

                                                Slider {
                                                    id: areaTransSpeedSlider
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 22
                                                    from: 0; to: 1; stepSize: 0
                                                    Component.onCompleted: {
                                                        var s = itemTransitionSpeed || 1.0
                                                        value = s <= 2.0 ? s / 4.0 : 0.5 + (s - 2.0) / 16.0
                                                    }
                                                    onMoved: {
                                                        var speed = value <= 0.5 ? value * 4.0 : 2.0 + (value - 0.5) * 16.0
                                                        var rounded = Math.round(speed * 100) / 100
                                                        areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemTransitionSpeed", rounded)
                                                        areaTransSpeedField.text = rounded.toFixed(1)
                                                    }
                                                    background: Rectangle {
                                                        x: areaTransSpeedSlider.leftPadding
                                                        y: areaTransSpeedSlider.topPadding + areaTransSpeedSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 200; implicitHeight: 4
                                                        width: areaTransSpeedSlider.availableWidth; height: 4
                                                        radius: 2; color: "#333"
                                                        Rectangle {
                                                            width: areaTransSpeedSlider.visualPosition * parent.width
                                                            height: parent.height; color: "#5DA9A4"; radius: 2
                                                        }
                                                    }
                                                    handle: Rectangle {
                                                        x: areaTransSpeedSlider.leftPadding + areaTransSpeedSlider.visualPosition * (areaTransSpeedSlider.availableWidth - width)
                                                        y: areaTransSpeedSlider.topPadding + areaTransSpeedSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 12; implicitHeight: 12; radius: 6
                                                        color: areaTransSpeedSlider.pressed ? "#80cfff" : "#5DA9A4"
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.preferredWidth: 52
                                                    Layout.preferredHeight: 22
                                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                    TextInput {
                                                        id: areaTransSpeedField
                                                        anchors.left: parent.left; anchors.right: areaSuffix.left
                                                        anchors.leftMargin: 4; anchors.rightMargin: 2
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                        validator: DoubleValidator { bottom: 0.0; top: 10.0 }
                                                        Component.onCompleted: text = (itemTransitionSpeed || 1.0).toFixed(1)
                                                        Keys.onReturnPressed: focus = false
                                                        Keys.onEscapePressed: focus = false
                                                        onEditingFinished: {
                                                            var speed = Math.min(10.0, Math.max(0.0, parseFloat(text) || 0.0))
                                                            text = speed.toFixed(1)
                                                            areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemTransitionSpeed", speed)
                                                            areaTransSpeedSlider.value = speed <= 2.0 ? speed / 4.0 : 0.5 + (speed - 2.0) / 16.0
                                                        }
                                                    }
                                                    Text {
                                                        id: areaSuffix
                                                        anchors.right: parent.right; anchors.rightMargin: 4
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "sec"; font.pixelSize: 10; color: "#aaa"
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            width: parent.width
                                            height: itemCommand === "sound" ? 26 : 0
                                            visible: itemCommand === "sound"

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
                                                color: "black"

                                                Image {
                                                    id: areaDropSoundIcon
                                                    anchors.centerIn: parent
                                                    width: 20; height: 20
                                                    source: "icons/dropsound.svg"
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: false
                                                }
                                                ColorOverlay {
                                                    anchors.fill: areaDropSoundIcon
                                                    source: areaDropSoundIcon
                                                    color: "#666"
                                                    opacity: itemSoundPath !== "" ? 0.3 : 1.0
                                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                                }
                                                Text {
                                                    anchors.fill: parent; anchors.margins: 4
                                                    visible: itemSoundPath !== ""
                                                    text: itemSoundPath.replace(/.*[\/\\]/, "")
                                                    font.pixelSize: 10; color: "white"
                                                    elide: Text.ElideMiddle
                                                    verticalAlignment: Text.AlignVCenter
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        areaSoundFileDialog.targetIdx = areaInteractivityDelegate.listIdx
                                                        areaSoundFileDialog.open()
                                                    }
                                                }
                                                DropArea {
                                                    anchors.fill: parent
                                                    onDropped: drop => {
                                                        if (drop.hasUrls)
                                                            areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemSoundPath", drop.urls[0].toString())
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            width: parent.width
                                            height: itemCommand === "update" ? 26 : 0
                                            visible: itemCommand === "update"

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 4

                                                ComboBox {
                                                    id: areaUpdateVarCombo
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 0
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 26
                                                    model: {
                                                        var names = []
                                                        for (var i = 0; i < variablesModel.count; i++) {
                                                            var n = variablesModel.get(i).varName
                                                            if (n !== "") names.push(n)
                                                        }
                                                        return names
                                                    }
                                                    currentIndex: {
                                                        var mdl = areaUpdateVarCombo.model
                                                        for (var i = 0; i < mdl.length; i++) {
                                                            if (mdl[i] === itemUpdateVar) return i
                                                        }
                                                        return 0
                                                    }
                                                    onActivated: function(idx) {
                                                        areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateVar", areaUpdateVarCombo.model[idx])
                                                        areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateOp", "=")
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 6; rightPadding: 14; text: parent.displayText
                                                        font.pixelSize: 11; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 10; color: "white"
                                                    }
                                                    background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 80; height: 22; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width
                                                        height: Math.min(areaUpdateVarCombo.model.length, 6) * 22 + 2
                                                        padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: areaUpdateVarCombo.delegateModel; currentIndex: areaUpdateVarCombo.currentIndex }
                                                    }
                                                }

                                                ComboBox {
                                                    id: areaUpdateOpCombo
                                                    Layout.preferredWidth: 36
                                                    Layout.preferredHeight: 26
                                                    model: areaInteractivityDelegate.updateVarType === "number" ? ["=", "+", "-"] : ["="]
                                                    currentIndex: Math.max(0, model.indexOf(itemUpdateOp))
                                                    onActivated: function(idx) {
                                                        areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateOp", areaUpdateOpCombo.model[idx])
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 4; rightPadding: 12; text: parent.displayText
                                                        font.pixelSize: 11; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 3; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 9; color: "white"
                                                    }
                                                    background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 36; height: 22; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width
                                                        height: areaUpdateOpCombo.model.length * 22 + 2; padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: areaUpdateOpCombo.delegateModel; currentIndex: areaUpdateOpCombo.currentIndex }
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 0
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 26

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: areaInteractivityDelegate.updateVarType === "text"
                                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                        TextInput {
                                                            anchors.left: parent.left; anchors.right: parent.right
                                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                            text: areaInteractivityDelegate.updateVarType === "text" ? (itemUpdateVal || "") : ""
                                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                            onEditingFinished: areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateVal", text)
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: areaInteractivityDelegate.updateVarType === "number"
                                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                        TextInput {
                                                            anchors.left: parent.left; anchors.right: parent.right
                                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                            validator: DoubleValidator {}
                                                            text: areaInteractivityDelegate.updateVarType === "number" ? (itemUpdateVal || "") : ""
                                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                            onEditingFinished: areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateVal", text)
                                                        }
                                                    }
                                                    ComboBox {
                                                        id: areaUpdateBoolCombo
                                                        anchors.fill: parent
                                                        visible: areaInteractivityDelegate.updateVarType === "true or false"
                                                        model: ["true", "false"]
                                                        currentIndex: (itemUpdateVal === "false") ? 1 : 0
                                                        onActivated: function(idx) {
                                                            areaInteractivityModel.setProperty(areaInteractivityDelegate.listIdx, "itemUpdateVal", idx === 0 ? "true" : "false")
                                                        }
                                                        contentItem: Text {
                                                            leftPadding: 4; rightPadding: 14; text: parent.displayText
                                                            font.pixelSize: 10; color: "white"
                                                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                        }
                                                        indicator: Text {
                                                            x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                            text: "▾"; font.pixelSize: 9; color: "white"
                                                        }
                                                        background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                        delegate: ItemDelegate {
                                                            width: parent ? parent.width : 50; height: 20; padding: 0
                                                            contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                            background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                        }
                                                        popup: Popup {
                                                            y: parent.height + 2; width: parent.width; height: 42; padding: 1
                                                            background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                            contentItem: ListView { clip: true; model: areaUpdateBoolCombo.delegateModel; currentIndex: areaUpdateBoolCombo.currentIndex }
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: areaInteractivityDelegate.updateVarType === ""
                                                        color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                                    }
                                                }
                                            }
                                        }
                                        } // close innerAreaCol Column
                                    }
                                }
                            }

                            Item { width: 1; height: 8 }
                        }
                    }
                }

                Rectangle {
                    id: imageSettings
                    visible: buttonGrid.selectedTool === "newimage" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string selectedFilePath: ""
                    property real imageAspectRatio: 0

                    Image {
                        id: imageProbe
                        source: imageSettings.selectedFilePath
                        visible: false
                        width: 0
                        height: 0
                        onStatusChanged: {
                            if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0)
                                imageSettings.imageAspectRatio = implicitWidth / implicitHeight;
                            else if (status === Image.Null || status === Image.Error)
                                imageSettings.imageAspectRatio = 0;
                        }
                    }

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

                    // Image drop zone — fixed, not scrollable
                    Rectangle {
                        id: imageDropZone
                        anchors.top: imageSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        height: 80
                        color: "black"
                        radius: 4

                        Image {
                            id: dropImageIcon
                            anchors.fill: parent
                            anchors.margins: 9
                            sourceSize.width: 256
                            sourceSize.height: 256
                            source: "icons/dropimage.svg"
                            fillMode: Image.PreserveAspectFit
                            opacity: imageSettings.selectedFilePath !== "" ? 0.3 : 1.0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: imageSettings.selectedFilePath !== "" ? imageSettings.selectedFilePath.replace(/.*\//, "") : ""
                            color: "white"
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
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
                                    imageSettings.selectedFilePath = drop.urls[0].toString();
                            }
                        }
                    }

                    // Scrollable props below drop zone
                    ScrollView {
                        id: imagePropsScroll
                        anchors.top: imageDropZone.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            id: imageSpatialProps
                            width: imagePropsScroll.availableWidth
                            spacing: 4

                            property real propX: 0
                            property real propY: 0
                            property real propW: 200
                            property real propH: 150
                            property bool propLock: false
                            property string propName: ""

                            Row {
                                width: imageSpatialProps.width; height: 26; spacing: 6
                                Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Rectangle {
                                    width: parent.width - 50; height: 26
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 3
                                        color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                        text: imageSpatialProps.propName
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: imageSpatialProps.propName = text
                                    }
                                }
                            }

                            Repeater {
                                model: [{ lbl:"x",key:"propX" },{ lbl:"y",key:"propY" },{ lbl:"width",key:"propW" },{ lbl:"height",key:"propH" }]
                                delegate: Row {
                                    width: imageSpatialProps.width; height: 26; spacing: 6
                                    Text { text: modelData.lbl; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                    Rectangle {
                                        width: parent.width - 50; height: 26
                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: 3
                                            color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                            text: imageSpatialProps[modelData.key].toFixed(0)
                                            Keys.onReturnPressed: focus = false
                                            Keys.onEscapePressed: focus = false
                                            onEditingFinished: imageSpatialProps[modelData.key] = parseFloat(text) || 0
                                        }
                                    }
                                }
                            }

                            Row {
                                width: imageSpatialProps.width; height: 26; spacing: 6
                                Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Row {
                                    spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                        delegate: Row {
                                            spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                border.color: "white"; border.width: 1; color: "transparent"
                                                anchors.verticalCenter: parent.verticalCenter
                                                Rectangle {
                                                    anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                    color: "white"; visible: imageSpatialProps.propLock === modelData.val
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: imageSpatialProps.propLock = modelData.val }
                                            }
                                            Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: videoSettings
                    visible: buttonGrid.selectedTool === "newvideo" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string selectedFilePath: ""
                    property real videoAspectRatio: 0

                    MediaPlayer {
                        id: videoProbe
                        source: videoSettings.selectedFilePath
                        onMediaStatusChanged: (status) => {
                            if (status === MediaPlayer.LoadedMedia || status === MediaPlayer.BufferedMedia) {
                                var res = metaData.value(MediaMetaData.Resolution);
                                if (res && res.width > 0 && res.height > 0)
                                    videoSettings.videoAspectRatio = res.width / res.height;
                            } else if (status === MediaPlayer.NoMedia || status === MediaPlayer.InvalidMedia) {
                                videoSettings.videoAspectRatio = 0;
                            }
                        }
                    }

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

                    // Video drop zone — fixed, not scrollable
                    Rectangle {
                        id: videoDropZone
                        anchors.top: videoSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        height: 80
                        color: "black"
                        radius: 4

                        Image {
                            id: dropVideoIcon
                            anchors.fill: parent
                            anchors.margins: 9
                            sourceSize.width: 256
                            sourceSize.height: 256
                            source: "icons/dropvideo.svg"
                            fillMode: Image.PreserveAspectFit
                            opacity: videoSettings.selectedFilePath !== "" ? 0.3 : 1.0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: videoSettings.selectedFilePath !== "" ? videoSettings.selectedFilePath.replace(/.*\//, "") : ""
                            color: "white"
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
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
                                    videoSettings.selectedFilePath = drop.urls[0].toString();
                            }
                        }
                    }

                    // Scrollable props below drop zone
                    ScrollView {
                        id: videoPropsScroll
                        anchors.top: videoDropZone.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            id: videoSpatialProps
                            width: videoPropsScroll.availableWidth
                            spacing: 4

                            property real propX: 0
                            property real propY: 0
                            property real propW: 200
                            property real propH: 150
                            property bool propLock: false
                            property string propName: ""

                            Row {
                                width: videoSpatialProps.width; height: 26; spacing: 6
                                Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Rectangle {
                                    width: parent.width - 50; height: 26
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 3
                                        color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                        text: videoSpatialProps.propName
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: videoSpatialProps.propName = text
                                    }
                                }
                            }

                            Repeater {
                                model: [{ lbl:"x",key:"propX" },{ lbl:"y",key:"propY" },{ lbl:"width",key:"propW" },{ lbl:"height",key:"propH" }]
                                delegate: Row {
                                    width: videoSpatialProps.width; height: 26; spacing: 6
                                    Text { text: modelData.lbl; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                    Rectangle {
                                        width: parent.width - 50; height: 26
                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: 3
                                            color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                            text: videoSpatialProps[modelData.key].toFixed(0)
                                            Keys.onReturnPressed: focus = false
                                            Keys.onEscapePressed: focus = false
                                            onEditingFinished: videoSpatialProps[modelData.key] = parseFloat(text) || 0
                                        }
                                    }
                                }
                            }

                            Row {
                                width: videoSpatialProps.width; height: 26; spacing: 6
                                Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Row {
                                    spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                    Repeater {
                                        model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                        delegate: Row {
                                            spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                border.color: "white"; border.width: 1; color: "transparent"
                                                anchors.verticalCenter: parent.verticalCenter
                                                Rectangle {
                                                    anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                    color: "white"; visible: videoSpatialProps.propLock === modelData.val
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: videoSpatialProps.propLock = modelData.val }
                                            }
                                            Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: textSettings
                    visible: buttonGrid.selectedTool === "newtext" && !sceneEditorButtons.navigationOpen
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

                    ScrollView {
                        id: textPropsScroll
                        anchors.top: textSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            width: textPropsScroll.availableWidth
                            spacing: 8

                    Column {
                        id: textFormattingCol
                        width: parent.width
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
                                    anchors.margins: 9
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

                    Text {
                        text: "information"
                        font.pixelSize: 11
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                        color: "white"
                        width: parent.width
                        bottomPadding: 6
                    }

                    Column {
                        id: textSpatialProps
                        width: parent.width
                        spacing: 4

                        property real propX: 0
                        property real propY: 0
                        property real propW: 200
                        property real propH: 150
                        property bool propLock: false
                        property string propName: ""

                        Row {
                            width: textSpatialProps.width; height: 26; spacing: 6
                            Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            Rectangle {
                                width: parent.width - 50; height: 26
                                color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                TextInput {
                                    anchors.fill: parent; anchors.margins: 3
                                    color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                    text: textSpatialProps.propName
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: textSpatialProps.propName = text
                                }
                            }
                        }

                        Repeater {
                            model: [{ lbl:"x",key:"propX" },{ lbl:"y",key:"propY" },{ lbl:"width",key:"propW" },{ lbl:"height",key:"propH" }]
                            delegate: Row {
                                width: textSpatialProps.width; height: 26; spacing: 6
                                Text { text: modelData.lbl; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Rectangle {
                                    width: parent.width - 50; height: 26
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 3
                                        color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                        text: textSpatialProps[modelData.key].toFixed(0)
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: textSpatialProps[modelData.key] = parseFloat(text) || 0
                                    }
                                }
                            }
                        }

                        Row {
                            width: textSpatialProps.width; height: 26; spacing: 6
                            Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            Row {
                                spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                    delegate: Row {
                                        spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 12; height: 12; radius: 6
                                            border.color: "white"; border.width: 1; color: "transparent"
                                            anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                color: "white"; visible: textSpatialProps.propLock === modelData.val
                                            }
                                            MouseArea { anchors.fill: parent; onClicked: textSpatialProps.propLock = modelData.val }
                                        }
                                        Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 8 }
                        }  // close outer Column
                    }  // close ScrollView

                    ColorDialog {
                        id: txtColorDialog
                        selectedColor: textSettings.txtColor
                        onAccepted: textSettings.txtColor = selectedColor
                    }
                }

                Rectangle {
                    id: selectSettings
                    visible: buttonGrid.selectedTool === "select" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string interactivityTab: "click"
                    readonly property bool hasActiveArea: (viewport.selectionRevision >= 0) && viewport.selectedAreas.length === 1 && viewport.selectionCount === 1
                    readonly property bool hasActiveTb: (viewport.selectionRevision >= 0) && viewport.selectedTbs.length === 1 && viewport.selectionCount === 1
                    readonly property bool hasActiveImage: (viewport.selectionRevision >= 0) && viewport.selectedImages.length === 1 && viewport.selectionCount === 1
                    readonly property bool hasActiveVideo: (viewport.selectionRevision >= 0) && viewport.selectedVideos.length === 1 && viewport.selectionCount === 1
                    readonly property bool hasActiveShader: (viewport.selectionRevision >= 0) && viewport.selectedShaders.length === 1 && viewport.selectionCount === 1

                    // Uniform list for the currently selected shader (excludes time, which is auto-animated).
                    property var shaderUniforms: []
                    function refreshShaderUniforms() {
                        if (hasActiveShader) {
                            var idx = viewport.selectedShaders[0];
                            var data = shadersModel.get(idx);
                            var all;
                            try { all = JSON.parse(data.uniformsJson || "[]"); } catch(e) { all = []; }
                            shaderUniforms = all.filter(function(u) { return u.name !== "time"; });
                        } else {
                            shaderUniforms = [];
                        }
                    }
                    Connections {
                        target: viewport
                        function onSelectionRevisionChanged() { selectSettings.refreshShaderUniforms(); }
                    }

                    // Spatial state for the currently selected element
                    property real selX: 0
                    property real selY: 0
                    property real selW: 200
                    property real selH: 150
                    property bool selLock: false
                    property string selName: ""

                    function syncSpatialFromModel() {
                        var m = null;
                        if (hasActiveArea)        m = areasModel.get(viewport.selectedAreas[0]);
                        else if (hasActiveTb)     m = textBoxesModel.get(viewport.selectedTbs[0]);
                        else if (hasActiveImage)  m = imagesModel.get(viewport.selectedImages[0]);
                        else if (hasActiveVideo)  m = videosModel.get(viewport.selectedVideos[0]);
                        else if (hasActiveShader) m = shadersModel.get(viewport.selectedShaders[0]);
                        if (m) {
                            selX = Math.min(m.x1, m.x2);
                            selY = Math.min(m.y1, m.y2);
                            selW = Math.abs(m.x2 - m.x1);
                            selH = Math.abs(m.y2 - m.y1);
                            selName = m.name || "";
                        }
                    }

                    function writeSpatialToModel() {
                        var idx = -1;
                        var mod = null;
                        if (hasActiveArea)        { idx = viewport.selectedAreas[0];   mod = areasModel; }
                        else if (hasActiveTb)     { idx = viewport.selectedTbs[0];     mod = textBoxesModel; }
                        else if (hasActiveImage)  { idx = viewport.selectedImages[0];  mod = imagesModel; }
                        else if (hasActiveVideo)  { idx = viewport.selectedVideos[0];  mod = videosModel; }
                        else if (hasActiveShader) { idx = viewport.selectedShaders[0]; mod = shadersModel; }
                        if (mod !== null && idx >= 0) {
                            mod.setProperty(idx, "x1", selX);
                            mod.setProperty(idx, "y1", selY);
                            mod.setProperty(idx, "x2", selX + selW);
                            mod.setProperty(idx, "y2", selY + selH);
                            viewport.layoutRevision++;
                        }
                    }

                    function writeNameToModel(n) {
                        var idx = -1;
                        var mod = null;
                        if (hasActiveArea)        { idx = viewport.selectedAreas[0];   mod = areasModel; }
                        else if (hasActiveTb)     { idx = viewport.selectedTbs[0];     mod = textBoxesModel; }
                        else if (hasActiveImage)  { idx = viewport.selectedImages[0];  mod = imagesModel; }
                        else if (hasActiveVideo)  { idx = viewport.selectedVideos[0];  mod = videosModel; }
                        else if (hasActiveShader) { idx = viewport.selectedShaders[0]; mod = shadersModel; }
                        if (mod !== null && idx >= 0)
                            mod.setProperty(idx, "name", n);
                    }

                    Connections {
                        target: viewport
                        function onSelectionRevisionChanged() { selectSettings.syncSpatialFromModel(); }
                        function onPosRevisionChanged()       { selectSettings.syncSpatialFromModel(); }
                        function onElementDraggingChanged()   { if (!viewport.elementDragging) selectSettings.syncSpatialFromModel(); }
                    }

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
                        text: selectSettings.hasActiveArea ? "area" : (selectSettings.hasActiveTb ? "text" : (selectSettings.hasActiveImage ? "image" : (selectSettings.hasActiveVideo ? "video" : (selectSettings.hasActiveShader ? "shader" : "select"))))
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }

                    ListModel { id: selectInteractivityModel }

                    ScrollView {
                        id: selectPropsScroll
                        anchors.top: selectSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            width: selectPropsScroll.availableWidth
                            spacing: 8

                            // Text formatting controls — visible when a text box is active
                            Column {
                                visible: selectSettings.hasActiveTb
                                width: parent.width
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
                                    anchors.margins: 9
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

                            // Image swap — visible when a single image is selected
                            Rectangle {
                                visible: selectSettings.hasActiveImage
                                width: parent.width
                                height: 80
                                color: "black"
                                radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropimage.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.3
                            }

                            Text {
                                anchors.centerIn: parent
                                text: selectSettings.hasActiveImage ? imagesModel.get(viewport.selectedImages[0]).filePath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: selectImageSwapDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (drop.hasUrls && selectSettings.hasActiveImage)
                                        imagesModel.setProperty(viewport.selectedImages[0], "filePath", drop.urls[0].toString());
                                }
                            }
                            }

                            // Video swap — visible when a single video is selected
                            Rectangle {
                                visible: selectSettings.hasActiveVideo
                                width: parent.width
                                height: 80
                                color: "black"
                            radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropvideo.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.3
                            }

                            Text {
                                anchors.centerIn: parent
                                text: selectSettings.hasActiveVideo ? videosModel.get(viewport.selectedVideos[0]).filePath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: selectVideoSwapDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (drop.hasUrls && selectSettings.hasActiveVideo)
                                        videosModel.setProperty(viewport.selectedVideos[0], "filePath", drop.urls[0].toString());
                                }
                            }
                            }

                            // Shader swap + uniforms — visible when a single shader is selected
                            Column {
                                visible: selectSettings.hasActiveShader
                                width: parent.width
                                spacing: 8

                                Item {
                                    id: shaderSwapItem
                                    width: parent.width
                                    height: 80

                        Rectangle {
                            width: (parent.width - 8) / 2
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropfrag.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.3
                            }

                            Text {
                                anchors.centerIn: parent
                                text: selectSettings.hasActiveShader ? shadersModel.get(viewport.selectedShaders[0]).fragPath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: selectFragSwapDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (!drop.hasUrls || !selectSettings.hasActiveShader) return;
                                    var path = drop.urls[0].toString();
                                    if (path.endsWith(".frag.qsb")) {
                                        var idx = viewport.selectedShaders[0];
                                        shadersModel.setProperty(idx, "fragPath", path);
                                        shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(viewport.buildUniformsList(shaderInspector.inspectShader(path))));
                                        selectSettings.refreshShaderUniforms();
                                    } else if (path.endsWith(".frag"))
                                        newshaderSettings.warnUncompiled();
                                }
                            }
                        }

                        Rectangle {
                            x: (parent.width - 8) / 2 + 8
                            width: (parent.width - 8) / 2
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropvert.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: 0.3
                            }

                            Text {
                                anchors.centerIn: parent
                                text: selectSettings.hasActiveShader ? shadersModel.get(viewport.selectedShaders[0]).vertPath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: selectVertSwapDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (!drop.hasUrls || !selectSettings.hasActiveShader) return;
                                    var path = drop.urls[0].toString();
                                    if (path.endsWith(".vert.qsb"))
                                        shadersModel.setProperty(viewport.selectedShaders[0], "vertPath", path);
                                    else if (path.endsWith(".vert"))
                                        newshaderSettings.warnUncompiled();
                                }
                            }
                        }
                    }

                                // Editable uniform fields
                                Repeater {
                                    model: selectSettings.shaderUniforms
                                    delegate: Row {
                                        width: parent.width
                                height: 26
                                spacing: 6

                                // Capture model data into local properties for reliable access in nested items.
                                property string uName: modelData.name
                                property string uType: modelData.type
                                property var uValue: modelData.value

                                readonly property bool isScalar: uType === "float" || uType === "int"

                                Text {
                                    text: uName
                                    width: 108
                                    color: "white"
                                    font.pixelSize: 11
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                Slider {
                                    id: selectUniformSlider
                                    visible: isScalar
                                    width: parent.width - 175
                                    height: parent.height
                                    from: 0; to: 1
                                    stepSize: 0
                                    Component.onCompleted: {
                                        var v = parseFloat(uValue);
                                        if (isNaN(v) || v <= 0) value = 0;
                                        else if (v >= 100) value = 1;
                                        else value = Math.pow(v / 100.0, 0.2);
                                    }
                                    onMoved: {
                                        var expanded = parseFloat((Math.pow(value, 5) * 100.0).toFixed(4));
                                        var name = uName;
                                        var idx = viewport.selectedShaders[0];
                                        var uniforms;
                                        try { uniforms = JSON.parse(shadersModel.get(idx).uniformsJson || "[]"); } catch(e) { uniforms = []; }
                                        for (var i = 0; i < uniforms.length; i++) {
                                            if (uniforms[i].name === name) { uniforms[i].value = expanded; break; }
                                        }
                                        shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(uniforms));
                                        var del = shadersRepeater.itemAt(idx);
                                        if (del && del.dynamicShaderEffect)
                                            del.dynamicShaderEffect[name] = expanded;
                                        selectNumericField.text = expanded.toString();
                                    }
                                    background: Rectangle {
                                        x: selectUniformSlider.leftPadding
                                        y: selectUniformSlider.topPadding + selectUniformSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 200; implicitHeight: 4
                                        width: selectUniformSlider.availableWidth; height: 4
                                        radius: 2; color: "#333"
                                        Rectangle {
                                            width: selectUniformSlider.visualPosition * parent.width
                                            height: parent.height; color: "#5DA9A4"; radius: 2
                                        }
                                    }
                                    handle: Rectangle {
                                        x: selectUniformSlider.leftPadding + selectUniformSlider.visualPosition * (selectUniformSlider.availableWidth - width)
                                        y: selectUniformSlider.topPadding + selectUniformSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 12; implicitHeight: 12; radius: 6
                                        color: selectUniformSlider.pressed ? "#80cfff" : "#5DA9A4"
                                    }
                                }

                                Rectangle {
                                    width: isScalar ? 55 : (parent.width - 114)
                                    height: 26
                                    color: uType === "sampler2D" ? "black" : "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4

                                    // Texture label (sampler2D)
                                    Text {
                                        visible: uType === "sampler2D"
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        text: (uValue && uValue !== "") ? uValue.toString().replace(/.*\//, "") : "drop image or video"
                                        color: (uValue && uValue !== "") ? "white" : "#555"
                                        font.pixelSize: 11
                                        elide: Text.ElideLeft
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: uType === "sampler2D"
                                        onClicked: {
                                            selectTextureDialog.pendingUniformName = uName;
                                            selectTextureDialog.open();
                                        }
                                    }

                                    DropArea {
                                        anchors.fill: parent
                                        enabled: uType === "sampler2D"
                                        onDropped: drop => {
                                            if (!drop.hasUrls || !selectSettings.hasActiveShader) return;
                                            var path = drop.urls[0].toString();
                                            var name = uName;
                                            var idx = viewport.selectedShaders[0];
                                            var uniforms;
                                            try { uniforms = JSON.parse(shadersModel.get(idx).uniformsJson || "[]"); } catch(e) { uniforms = []; }
                                            for (var i = 0; i < uniforms.length; i++) {
                                                if (uniforms[i].name === name) { uniforms[i].value = path; break; }
                                            }
                                            shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(uniforms));
                                            var del = shadersRepeater.itemAt(idx);
                                            if (del) del.applyTextureSource(name, path);
                                            selectSettings.refreshShaderUniforms();
                                        }
                                    }

                                    // Numeric input (float/vec)
                                    TextInput {
                                        id: selectNumericField
                                        visible: uType !== "sampler2D"
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        color: "white"
                                        font.pixelSize: 11
                                        clip: true
                                        selectByMouse: true
                                        text: {
                                            if (uValue === null || uValue === undefined) return "1";
                                            if (Array.isArray(uValue)) return uValue.map(function(n) { return parseFloat(Number(n).toFixed(4)); }).join(", ");
                                            var v = Number(uValue);
                                            return isNaN(v) ? uValue.toString() : parseFloat(v.toFixed(4)).toString();
                                        }
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: {
                                            var name = uName;
                                            var type = uType;
                                            var idx = viewport.selectedShaders[0];
                                            // Sync slider position for scalar types
                                            if (isScalar) {
                                                var v = parseFloat(text);
                                                if (!isNaN(v)) {
                                                    var pos = v >= 100 ? 1.0 : (v <= 0 ? 0.0 : Math.pow(v / 100.0, 0.2));
                                                    selectUniformSlider.value = pos;
                                                }
                                            }
                                            var qmlVal = viewport.parseUniformToQml(type, text);
                                            var arrVal = viewport.parseUniformToArray(type, text);
                                            var uniforms;
                                            try { uniforms = JSON.parse(shadersModel.get(idx).uniformsJson || "[]"); } catch(e) { uniforms = []; }
                                            for (var i = 0; i < uniforms.length; i++) {
                                                if (uniforms[i].name === name) { uniforms[i].value = arrVal; break; }
                                            }
                                            shadersModel.setProperty(idx, "uniformsJson", JSON.stringify(uniforms));
                                            var del = shadersRepeater.itemAt(idx);
                                            if (del && del.dynamicShaderEffect)
                                                del.dynamicShaderEffect[name] = qmlVal;
                                        }
                                    }
                                }
                            }
                            }  // close Repeater
                            }  // close shader Column

                            // Spatial props — always visible when something is selected
                            Column {
                                visible: selectSettings.hasActiveArea || selectSettings.hasActiveTb || selectSettings.hasActiveImage || selectSettings.hasActiveVideo || selectSettings.hasActiveShader
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: "information"
                                    font.pixelSize: 11
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1
                                    color: "white"
                                    width: parent.width
                                    bottomPadding: 6
                                }

                                Row {
                                    width: parent.width; height: 26; spacing: 6
                                    Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                    Rectangle {
                                        width: parent.width - 50; height: 26
                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                        TextInput {
                                            anchors.fill: parent; anchors.margins: 3
                                            color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                            text: selectSettings.selName
                                            Keys.onReturnPressed: focus = false
                                            Keys.onEscapePressed: focus = false
                                            onEditingFinished: {
                                                selectSettings.selName = text;
                                                selectSettings.writeNameToModel(text);
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: [{ lbl:"x", prop:"selX" }, { lbl:"y", prop:"selY" }, { lbl:"width", prop:"selW" }, { lbl:"height", prop:"selH" }]
                                    delegate: Row {
                                        width: parent.width; height: 26; spacing: 6
                                        Text { text: modelData.lbl; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                        Rectangle {
                                            width: parent.width - 50; height: 26
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                anchors.fill: parent; anchors.margins: 3
                                                color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                                text: selectSettings[modelData.prop].toFixed(0)
                                                Keys.onReturnPressed: focus = false
                                                Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    selectSettings[modelData.prop] = parseFloat(text) || 0;
                                                    selectSettings.writeSpatialToModel();
                                                }
                                            }
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width; height: 26; spacing: 6
                                    Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                    Row {
                                        spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                        Repeater {
                                            model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                            delegate: Row {
                                                spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    border.color: "white"; border.width: 1; color: "transparent"
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Rectangle {
                                                        anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                        color: "white"; visible: selectSettings.selLock === modelData.val
                                                    }
                                                    MouseArea { anchors.fill: parent; onClicked: selectSettings.selLock = modelData.val }
                                                }
                                                Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                    }
                                }
                            }

                            // Interactivity — only for areas
                            Column {
                                visible: selectSettings.hasActiveArea
                                width: parent.width
                                spacing: 4

                                RowLayout {
                                    width: parent.width
                                    height: 26
                                    spacing: 4

                                    Text {
                                        text: "interactivity"
                                        font.pixelSize: 11
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 1
                                        color: "white"
                                        verticalAlignment: Text.AlignVCenter
                                        Layout.rightMargin: 4
                                    }

                                    Repeater {
                                        model: ["click", "hover"]
                                        delegate: Rectangle {
                                            Layout.preferredWidth: 36
                                            Layout.preferredHeight: 18
                                            radius: 3
                                            property bool active: selectSettings.interactivityTab === modelData
                                            color: active ? "white" : "transparent"
                                            border.color: "white"
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.pixelSize: 10
                                                color: parent.active ? "#1a1a1d" : "white"
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: selectSettings.interactivityTab = modelData
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        radius: 4
                                        property bool hovered: false
                                        color: hovered ? "white" : "transparent"
                                        border.color: "white"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Text {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: 0
                                            anchors.horizontalCenterOffset: -0.5
                                            text: "+"
                                            font.pixelSize: 18
                                            font.bold: true
                                            color: parent.hovered ? "darkslategrey" : "white"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: parent.hovered = true
                                            onExited: parent.hovered = false
                                            onClicked: {
                                                var tab = selectSettings.interactivityTab
                                                var defaultAction = "cue"
                                                for (var i = 0; i < selectInteractivityModel.count; i++) {
                                                    var e = selectInteractivityModel.get(i)
                                                    if (e.itemTrigger !== tab) continue
                                                    if ((e.itemAction === "cue" && e.itemCommand === "jump") ||
                                                        (e.itemAction === "else" && e.itemCommand === "jump")) {
                                                        defaultAction = "if"; break
                                                    }
                                                }
                                                var firstVar = ""
                                                if (defaultAction === "if") {
                                                    for (var i = 0; i < variablesModel.count; i++) {
                                                        if (variablesModel.get(i).varName !== "") { firstVar = variablesModel.get(i).varName; break }
                                                    }
                                                    if (firstVar === "") return
                                                }
                                                selectInteractivityModel.append({ itemTrigger: tab, itemAction: defaultAction, itemCommand: "jump", itemTransition: "cut", itemTransitionSpeed: 1.0, itemTargetSceneId: -1, itemTargetSceneName: "", itemConditionVar: firstVar, itemConditionOp: "is", itemConditionVal: "", itemSoundPath: "", itemUpdateVar: "", itemUpdateOp: "=", itemUpdateVal: "" })
                                            }
                                        }
                                    }
                                }

                                Repeater {
                                    model: selectInteractivityModel
                                    delegate: Component {
                                        Item {
                                            id: selInteractivityDelegate
                                            width: parent ? parent.width : 0
                                            height: itemTrigger === selectSettings.interactivityTab ? innerSelCol.height : 0
                                            visible: itemTrigger === selectSettings.interactivityTab
                                            property int listIdx: index
                                            property real deleteProgress: 0.0
                                            property string condVarType: {
                                                var v = itemConditionVar
                                                if (!v || v === "") return ""
                                                for (var i = 0; i < variablesModel.count; i++) {
                                                    if (variablesModel.get(i).varName === v) return variablesModel.get(i).varType
                                                }
                                                return ""
                                            }
                                            property string updateVarType: {
                                                var v = itemUpdateVar
                                                if (!v || v === "") return ""
                                                for (var i = 0; i < variablesModel.count; i++) {
                                                    if (variablesModel.get(i).varName === v) return variablesModel.get(i).varType
                                                }
                                                return ""
                                            }

                                            NumberAnimation {
                                                id: selDeleteAnim
                                                target: selInteractivityDelegate
                                                property: "deleteProgress"
                                                to: 1.0
                                                duration: 1200
                                                easing.type: Easing.Linear
                                                onFinished: {
                                                    if (selInteractivityDelegate.deleteProgress >= 1.0) {
                                                        var item = selectInteractivityModel.get(selInteractivityDelegate.listIdx)
                                                        var wasIf = item.itemAction === "if"
                                                        var trigger = item.itemTrigger
                                                        selectInteractivityModel.remove(selInteractivityDelegate.listIdx)
                                                        if (wasIf) {
                                                            var hasIf = false
                                                            for (var i = 0; i < selectInteractivityModel.count; i++) {
                                                                var e = selectInteractivityModel.get(i)
                                                                if (e.itemTrigger === trigger && e.itemAction === "if") { hasIf = true; break }
                                                            }
                                                            if (!hasIf) {
                                                                for (var i = selectInteractivityModel.count - 1; i >= 0; i--) {
                                                                    var e = selectInteractivityModel.get(i)
                                                                    if (e.itemTrigger === trigger && e.itemAction === "else")
                                                                        selectInteractivityModel.remove(i)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.RightButton
                                                z: 10
                                                onPressed: mouse => { selInteractivityDelegate.deleteProgress = 0; selDeleteAnim.start() }
                                                onReleased: mouse => { selDeleteAnim.stop(); selInteractivityDelegate.deleteProgress = 0 }
                                                onExited: { selDeleteAnim.stop(); selInteractivityDelegate.deleteProgress = 0 }
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 4
                                                color: "#ff4444"
                                                opacity: selInteractivityDelegate.deleteProgress * 0.75
                                                visible: selInteractivityDelegate.deleteProgress > 0
                                                z: 9
                                            }

                                            Column {
                                                id: innerSelCol
                                                width: parent.width
                                                spacing: 4

                                            Item { width: 1; height: 2 }

                                            RowLayout {
                                                width: parent.width
                                                height: 26
                                                spacing: 4

                                                ComboBox {
                                                    id: selActionCombo
                                                    Layout.preferredWidth: 62
                                                    Layout.preferredHeight: 26
                                                    model: {
                                                        var hasVars = false
                                                        for (var i = 0; i < variablesModel.count; i++) {
                                                            if (variablesModel.get(i).varName !== "") { hasVars = true; break }
                                                        }
                                                        if (!hasVars) return ["cue"]
                                                        var opts = ["cue", "if"]
                                                        var thisIdx = selInteractivityDelegate.listIdx
                                                        var thisTrigger = itemTrigger
                                                        for (var i = 0; i < selectInteractivityModel.count; i++) {
                                                            var e = selectInteractivityModel.get(i)
                                                            if (i !== thisIdx && e.itemTrigger === thisTrigger && e.itemAction === "if") {
                                                                opts.push("else"); break
                                                            }
                                                        }
                                                        return opts
                                                    }
                                                    currentIndex: Math.max(0, model.indexOf(itemAction))
                                                    onActivated: function(activatedIndex) {
                                                        var newAction = selActionCombo.model[activatedIndex]
                                                        var itemIdx = selInteractivityDelegate.listIdx
                                                        var revertIdx = Math.max(0, selActionCombo.model.indexOf(itemAction))
                                                        var trigger = itemTrigger
                                                        if (newAction === "cue") {
                                                            for (var i = 0; i < selectInteractivityModel.count; i++) {
                                                                if (i === itemIdx) continue
                                                                var e = selectInteractivityModel.get(i)
                                                                if (e.itemTrigger !== trigger) continue
                                                                if ((e.itemAction === "cue" && e.itemCommand === "jump") ||
                                                                    (e.itemAction === "else" && e.itemCommand === "jump")) {
                                                                    currentIndex = revertIdx; return
                                                                }
                                                            }
                                                        } else if (newAction === "else") {
                                                            var hasIf = false
                                                            for (var i = 0; i < selectInteractivityModel.count; i++) {
                                                                if (i === itemIdx) continue
                                                                var e = selectInteractivityModel.get(i)
                                                                if (e.itemTrigger !== trigger) continue
                                                                if (e.itemAction === "else" || (e.itemAction === "cue" && e.itemCommand === "jump")) {
                                                                    currentIndex = revertIdx; return
                                                                }
                                                                if (e.itemAction === "if") hasIf = true
                                                            }
                                                            if (!hasIf) { currentIndex = revertIdx; return }
                                                        }
                                                        selectInteractivityModel.setProperty(itemIdx, "itemAction", newAction)
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 6; rightPadding: 18
                                                        text: parent.displayText
                                                        font.pixelSize: 11; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 10; color: "white"
                                                    }
                                                    background: Rectangle {
                                                        radius: 4; color: "transparent"; border.color: "white"; border.width: 1
                                                    }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 62; height: 22; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width
                                                        height: selActionCombo.model.length * 22 + 2; padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: selActionCombo.delegateModel; currentIndex: selActionCombo.currentIndex }
                                                    }
                                                }

                                                // "if" condition — variable name
                                                ComboBox {
                                                    id: selCondVarCombo
                                                    visible: itemAction === "if"
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 0
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 26
                                                    model: {
                                                        var names = []
                                                        for (var i = 0; i < variablesModel.count; i++) {
                                                            var n = variablesModel.get(i).varName
                                                            if (n !== "") names.push(n)
                                                        }
                                                        return names
                                                    }
                                                    currentIndex: {
                                                        var v = itemConditionVar
                                                        if (!v || v === "") return 0
                                                        for (var i = 0; i < variablesModel.count; i++) {
                                                            if (variablesModel.get(i).varName === v) return i
                                                        }
                                                        return 0
                                                    }
                                                    onActivated: function(idx) {
                                                        var itemIdx = selInteractivityDelegate.listIdx
                                                        var varName = variablesModel.get(idx).varName
                                                        var varType = variablesModel.get(idx).varType
                                                        selectInteractivityModel.setProperty(itemIdx, "itemConditionVar", varName)
                                                        var op = selectInteractivityModel.get(itemIdx).itemConditionOp
                                                        if (varType !== "number" && (op === ">" || op === "<"))
                                                            selectInteractivityModel.setProperty(itemIdx, "itemConditionOp", "is")
                                                        selectInteractivityModel.setProperty(itemIdx, "itemConditionVal", "")
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 4; rightPadding: 14
                                                        text: parent.displayText
                                                        font.pixelSize: 10; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 9; color: "white"
                                                    }
                                                    background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 60; height: 20; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2
                                                        width: Math.max(parent.width, 80)
                                                        height: Math.min(selCondVarCombo.model.length * 20 + 2, 102); padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: selCondVarCombo.delegateModel; currentIndex: selCondVarCombo.currentIndex }
                                                    }
                                                }

                                                // "if" condition — operator
                                                ComboBox {
                                                    id: selCondOpCombo
                                                    visible: itemAction === "if"
                                                    Layout.preferredWidth: 44
                                                    Layout.preferredHeight: 26
                                                    model: selInteractivityDelegate.condVarType === "number" ? ["is","not",">","<"] : ["is","not"]
                                                    currentIndex: Math.max(0, model.indexOf(itemConditionOp || "is"))
                                                    onActivated: function(idx) {
                                                        selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemConditionOp", model[idx])
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 4; rightPadding: 14
                                                        text: parent.displayText
                                                        font.pixelSize: 10; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 9; color: "white"
                                                    }
                                                    background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 44; height: 20; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width
                                                        height: (selInteractivityDelegate.condVarType === "number" ? 4 : 2) * 20 + 2; padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: selCondOpCombo.delegateModel; currentIndex: selCondOpCombo.currentIndex }
                                                    }
                                                }

                                                // "if" condition — value
                                                Item {
                                                    visible: itemAction === "if"
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 0
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 26

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: selInteractivityDelegate.condVarType === "text"
                                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                        TextInput {
                                                            anchors.left: parent.left; anchors.right: parent.right
                                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                            text: selInteractivityDelegate.condVarType === "text" ? (itemConditionVal || "") : ""
                                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                            onEditingFinished: selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemConditionVal", text)
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: selInteractivityDelegate.condVarType === "number"
                                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                        TextInput {
                                                            anchors.left: parent.left; anchors.right: parent.right
                                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                            validator: DoubleValidator {}
                                                            text: selInteractivityDelegate.condVarType === "number" ? (itemConditionVal || "") : ""
                                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                            onEditingFinished: selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemConditionVal", text)
                                                        }
                                                    }
                                                    ComboBox {
                                                        id: selBoolValCombo
                                                        anchors.fill: parent
                                                        visible: selInteractivityDelegate.condVarType === "true or false"
                                                        model: ["true", "false"]
                                                        currentIndex: (itemConditionVal === "false") ? 1 : 0
                                                        onActivated: function(idx) {
                                                            selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemConditionVal", idx === 0 ? "true" : "false")
                                                        }
                                                        contentItem: Text {
                                                            leftPadding: 4; rightPadding: 14; text: parent.displayText
                                                            font.pixelSize: 10; color: "white"
                                                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                        }
                                                        indicator: Text {
                                                            x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                            text: "▾"; font.pixelSize: 9; color: "white"
                                                        }
                                                        background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                        delegate: ItemDelegate {
                                                            width: parent ? parent.width : 50; height: 20; padding: 0
                                                            contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                            background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                        }
                                                        popup: Popup {
                                                            y: parent.height + 2; width: parent.width; height: 42; padding: 1
                                                            background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                            contentItem: ListView { clip: true; model: selBoolValCombo.delegateModel; currentIndex: selBoolValCombo.currentIndex }
                                                        }
                                                    }
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: selInteractivityDelegate.condVarType === ""
                                                        color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                                    }
                                                }

                                                ComboBox {
                                                    id: selCommandCombo
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 0
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 26
                                                    model: ["jump", "sound", "video", "update", "transport"]
                                                    currentIndex: {
                                                        var idx = model.indexOf(itemCommand)
                                                        return idx < 0 ? 0 : idx
                                                    }
                                                    onActivated: function(idx) {
                                                        var cmd = selCommandCombo.model[idx]
                                                        selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemCommand", cmd)
                                                        if (cmd === "update" && itemUpdateVar === "") {
                                                            for (var i = 0; i < variablesModel.count; i++) {
                                                                var n = variablesModel.get(i).varName
                                                                if (n !== "") {
                                                                    selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateVar", n)
                                                                    break
                                                                }
                                                            }
                                                        }
                                                    }
                                                    contentItem: Text {
                                                        leftPadding: 6; rightPadding: 18
                                                        text: parent.displayText
                                                        font.pixelSize: 11; color: "white"
                                                        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                    }
                                                    indicator: Text {
                                                        x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                        text: "▾"; font.pixelSize: 10; color: "white"
                                                    }
                                                    background: Rectangle {
                                                        radius: 4; color: "transparent"; border.color: "white"; border.width: 1
                                                    }
                                                    delegate: ItemDelegate {
                                                        width: parent ? parent.width : 80; height: 22; padding: 0
                                                        contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                        background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                    }
                                                    popup: Popup {
                                                        y: parent.height + 2; width: parent.width; height: 112; padding: 1
                                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                        contentItem: ListView { clip: true; model: selCommandCombo.delegateModel; currentIndex: selCommandCombo.currentIndex }
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: itemAction === "if" ? 26 : 0
                                                    Layout.minimumWidth: itemAction === "if" ? 26 : 0
                                                    Layout.maximumWidth: itemAction === "if" ? 26 : 10000
                                                    Layout.preferredHeight: 26
                                                    visible: itemCommand === "jump"
                                                    radius: 4
                                                    property bool hovered: false
                                                    property bool toggled: sceneEditorButtons.interactivityPickerOpen
                                                    color: toggled || hovered ? "white" : "transparent"
                                                    border.color: "white"
                                                    border.width: 1
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: itemTargetSceneName !== "" ? itemTargetSceneName : "+"
                                                        font.pixelSize: itemTargetSceneName !== "" ? 11 : 18
                                                        font.bold: itemTargetSceneName === ""
                                                        color: (parent.toggled || parent.hovered) ? "darkslategrey" : "white"
                                                        elide: Text.ElideRight
                                                        width: parent.width - 8
                                                        horizontalAlignment: Text.AlignHCenter
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onEntered: parent.hovered = true
                                                        onExited: parent.hovered = false
                                                        onClicked: {
                                                            sceneEditorButtons.interactivityPickerTargetIdx = selInteractivityDelegate.listIdx
                                                            sceneEditorButtons.interactivityPickerTargetModel = "select"
                                                            sceneEditorButtons.interactivityPickerOpen = !sceneEditorButtons.interactivityPickerOpen
                                                        }
                                                    }
                                                }
                                            }

                                            Item {
                                                width: parent.width
                                                height: itemCommand === "jump" ? Math.round((parent.width - 16) / 5) : 0
                                                visible: itemCommand === "jump"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 4

                                                    Repeater {
                                                        model: [
                                                            { icon: "cut",      key: "cut"      },
                                                            { icon: "dissolve", key: "dissolve" },
                                                            { icon: "wipe",     key: "wipe"     },
                                                            { icon: "push",     key: "push"     },
                                                            { icon: "look",     key: "look"     }
                                                        ]
                                                        delegate: Rectangle {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            radius: 4
                                                            property bool isActive: itemTransition === modelData.key
                                                            color: isActive ? "#477B78" : "transparent"
                                                            border.color: "white"
                                                            border.width: 1
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                            Image {
                                                                anchors.centerIn: parent
                                                                width: Math.round(parent.height * 0.72)
                                                                height: width
                                                                source: "icons/" + modelData.icon + ".svg"
                                                                fillMode: Image.PreserveAspectFit
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                onClicked: {
                                                                    selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemTransition", modelData.key)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Item {
                                                width: parent.width
                                                height: (itemCommand === "jump" && itemTransition !== "cut") ? 22 : 0
                                                visible: itemCommand === "jump" && itemTransition !== "cut"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 6

                                                    Slider {
                                                        id: selTransSpeedSlider
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 22
                                                        from: 0; to: 1; stepSize: 0
                                                        Component.onCompleted: {
                                                            var s = itemTransitionSpeed || 1.0
                                                            value = s <= 2.0 ? s / 4.0 : 0.5 + (s - 2.0) / 16.0
                                                        }
                                                        onMoved: {
                                                            var speed = value <= 0.5 ? value * 4.0 : 2.0 + (value - 0.5) * 16.0
                                                            var rounded = Math.round(speed * 100) / 100
                                                            selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemTransitionSpeed", rounded)
                                                            selTransSpeedField.text = rounded.toFixed(1)
                                                        }
                                                        background: Rectangle {
                                                            x: selTransSpeedSlider.leftPadding
                                                            y: selTransSpeedSlider.topPadding + selTransSpeedSlider.availableHeight / 2 - height / 2
                                                            implicitWidth: 200; implicitHeight: 4
                                                            width: selTransSpeedSlider.availableWidth; height: 4
                                                            radius: 2; color: "#333"
                                                            Rectangle {
                                                                width: selTransSpeedSlider.visualPosition * parent.width
                                                                height: parent.height; color: "#5DA9A4"; radius: 2
                                                            }
                                                        }
                                                        handle: Rectangle {
                                                            x: selTransSpeedSlider.leftPadding + selTransSpeedSlider.visualPosition * (selTransSpeedSlider.availableWidth - width)
                                                            y: selTransSpeedSlider.topPadding + selTransSpeedSlider.availableHeight / 2 - height / 2
                                                            implicitWidth: 12; implicitHeight: 12; radius: 6
                                                            color: selTransSpeedSlider.pressed ? "#80cfff" : "#5DA9A4"
                                                        }
                                                    }

                                                    Rectangle {
                                                        Layout.preferredWidth: 52
                                                        Layout.preferredHeight: 22
                                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                        TextInput {
                                                            id: selTransSpeedField
                                                            anchors.left: parent.left; anchors.right: selSuffix.left
                                                            anchors.leftMargin: 4; anchors.rightMargin: 2
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                            validator: DoubleValidator { bottom: 0.0; top: 10.0 }
                                                            Component.onCompleted: text = (itemTransitionSpeed || 1.0).toFixed(1)
                                                            Keys.onReturnPressed: focus = false
                                                            Keys.onEscapePressed: focus = false
                                                            onEditingFinished: {
                                                                var speed = Math.min(10.0, Math.max(0.0, parseFloat(text) || 0.0))
                                                                text = speed.toFixed(1)
                                                                selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemTransitionSpeed", speed)
                                                                selTransSpeedSlider.value = speed <= 2.0 ? speed / 4.0 : 0.5 + (speed - 2.0) / 16.0
                                                            }
                                                        }
                                                        Text {
                                                            id: selSuffix
                                                            anchors.right: parent.right; anchors.rightMargin: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: "sec"; font.pixelSize: 10; color: "#aaa"
                                                        }
                                                    }
                                                }
                                            }

                                            Item {
                                                width: parent.width
                                                height: itemCommand === "sound" ? 26 : 0
                                                visible: itemCommand === "sound"

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 4
                                                    color: "black"

                                                    Image {
                                                        id: selDropSoundIcon
                                                        anchors.centerIn: parent
                                                        width: 20; height: 20
                                                        source: "icons/dropsound.svg"
                                                        fillMode: Image.PreserveAspectFit
                                                        visible: false
                                                    }
                                                    ColorOverlay {
                                                        anchors.fill: selDropSoundIcon
                                                        source: selDropSoundIcon
                                                        color: "#666"
                                                        opacity: itemSoundPath !== "" ? 0.3 : 1.0
                                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                                    }
                                                    Text {
                                                        anchors.fill: parent; anchors.margins: 4
                                                        visible: itemSoundPath !== ""
                                                        text: itemSoundPath.replace(/.*[\/\\]/, "")
                                                        font.pixelSize: 10; color: "white"
                                                        elide: Text.ElideMiddle
                                                        verticalAlignment: Text.AlignVCenter
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onClicked: {
                                                            selSoundFileDialog.targetIdx = selInteractivityDelegate.listIdx
                                                            selSoundFileDialog.open()
                                                        }
                                                    }
                                                    DropArea {
                                                        anchors.fill: parent
                                                        onDropped: drop => {
                                                            if (drop.hasUrls)
                                                                selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemSoundPath", drop.urls[0].toString())
                                                        }
                                                    }
                                                }
                                            }

                                            Item {
                                                width: parent.width
                                                height: itemCommand === "update" ? 26 : 0
                                                visible: itemCommand === "update"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 4

                                                    ComboBox {
                                                        id: selUpdateVarCombo
                                                        Layout.fillWidth: true
                                                        Layout.preferredWidth: 0
                                                        Layout.minimumWidth: 0
                                                        Layout.preferredHeight: 26
                                                        model: {
                                                            var names = []
                                                            for (var i = 0; i < variablesModel.count; i++) {
                                                                var n = variablesModel.get(i).varName
                                                                if (n !== "") names.push(n)
                                                            }
                                                            return names
                                                        }
                                                        currentIndex: {
                                                            var mdl = selUpdateVarCombo.model
                                                            for (var i = 0; i < mdl.length; i++) {
                                                                if (mdl[i] === itemUpdateVar) return i
                                                            }
                                                            return 0
                                                        }
                                                        onActivated: function(idx) {
                                                            selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateVar", selUpdateVarCombo.model[idx])
                                                            selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateOp", "=")
                                                        }
                                                        contentItem: Text {
                                                            leftPadding: 6; rightPadding: 14; text: parent.displayText
                                                            font.pixelSize: 11; color: "white"
                                                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                        }
                                                        indicator: Text {
                                                            x: parent.width - width - 5; anchors.verticalCenter: parent.verticalCenter
                                                            text: "▾"; font.pixelSize: 10; color: "white"
                                                        }
                                                        background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                        delegate: ItemDelegate {
                                                            width: parent ? parent.width : 80; height: 22; padding: 0
                                                            contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 6; verticalAlignment: Text.AlignVCenter }
                                                            background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                        }
                                                        popup: Popup {
                                                            y: parent.height + 2; width: parent.width
                                                            height: Math.min(selUpdateVarCombo.model.length, 6) * 22 + 2
                                                            padding: 1
                                                            background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                            contentItem: ListView { clip: true; model: selUpdateVarCombo.delegateModel; currentIndex: selUpdateVarCombo.currentIndex }
                                                        }
                                                    }

                                                    ComboBox {
                                                        id: selUpdateOpCombo
                                                        Layout.preferredWidth: 36
                                                        Layout.preferredHeight: 26
                                                        model: selInteractivityDelegate.updateVarType === "number" ? ["=", "+", "-"] : ["="]
                                                        currentIndex: Math.max(0, model.indexOf(itemUpdateOp))
                                                        onActivated: function(idx) {
                                                            selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateOp", selUpdateOpCombo.model[idx])
                                                        }
                                                        contentItem: Text {
                                                            leftPadding: 4; rightPadding: 12; text: parent.displayText
                                                            font.pixelSize: 11; color: "white"
                                                            verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                                        }
                                                        indicator: Text {
                                                            x: parent.width - width - 3; anchors.verticalCenter: parent.verticalCenter
                                                            text: "▾"; font.pixelSize: 9; color: "white"
                                                        }
                                                        background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                        delegate: ItemDelegate {
                                                            width: parent ? parent.width : 36; height: 22; padding: 0
                                                            contentItem: Text { text: modelData; font.pixelSize: 11; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                                                            background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                        }
                                                        popup: Popup {
                                                            y: parent.height + 2; width: parent.width
                                                            height: selUpdateOpCombo.model.length * 22 + 2; padding: 1
                                                            background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                            contentItem: ListView { clip: true; model: selUpdateOpCombo.delegateModel; currentIndex: selUpdateOpCombo.currentIndex }
                                                        }
                                                    }

                                                    Item {
                                                        Layout.fillWidth: true
                                                        Layout.preferredWidth: 0
                                                        Layout.minimumWidth: 0
                                                        Layout.preferredHeight: 26

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            visible: selInteractivityDelegate.updateVarType === "text"
                                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                            TextInput {
                                                                anchors.left: parent.left; anchors.right: parent.right
                                                                anchors.leftMargin: 4; anchors.rightMargin: 4
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                                text: selInteractivityDelegate.updateVarType === "text" ? (itemUpdateVal || "") : ""
                                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                                onEditingFinished: selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateVal", text)
                                                            }
                                                        }
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            visible: selInteractivityDelegate.updateVarType === "number"
                                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                                            TextInput {
                                                                anchors.left: parent.left; anchors.right: parent.right
                                                                anchors.leftMargin: 4; anchors.rightMargin: 4
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                                validator: DoubleValidator {}
                                                                text: selInteractivityDelegate.updateVarType === "number" ? (itemUpdateVal || "") : ""
                                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                                onEditingFinished: selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateVal", text)
                                                            }
                                                        }
                                                        ComboBox {
                                                            id: selUpdateBoolCombo
                                                            anchors.fill: parent
                                                            visible: selInteractivityDelegate.updateVarType === "true or false"
                                                            model: ["true", "false"]
                                                            currentIndex: (itemUpdateVal === "false") ? 1 : 0
                                                            onActivated: function(idx) {
                                                                selectInteractivityModel.setProperty(selInteractivityDelegate.listIdx, "itemUpdateVal", idx === 0 ? "true" : "false")
                                                            }
                                                            contentItem: Text {
                                                                leftPadding: 4; rightPadding: 14; text: parent.displayText
                                                                font.pixelSize: 10; color: "white"
                                                                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                            }
                                                            indicator: Text {
                                                                x: parent.width - width - 4; anchors.verticalCenter: parent.verticalCenter
                                                                text: "▾"; font.pixelSize: 9; color: "white"
                                                            }
                                                            background: Rectangle { radius: 4; color: "transparent"; border.color: "white"; border.width: 1 }
                                                            delegate: ItemDelegate {
                                                                width: parent ? parent.width : 50; height: 20; padding: 0
                                                                contentItem: Text { text: modelData; font.pixelSize: 10; color: "white"; leftPadding: 4; verticalAlignment: Text.AlignVCenter }
                                                                background: Rectangle { color: highlighted ? "#477B78" : "transparent" }
                                                            }
                                                            popup: Popup {
                                                                y: parent.height + 2; width: parent.width; height: 42; padding: 1
                                                                background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                                                contentItem: ListView { clip: true; model: selUpdateBoolCombo.delegateModel; currentIndex: selUpdateBoolCombo.currentIndex }
                                                            }
                                                        }
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            visible: selInteractivityDelegate.updateVarType === ""
                                                            color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                                        }
                                                    }
                                                }
                                            }
                                            } // close innerSelCol Column
                                        }
                                    }
                                }
                            }

                            Item { width: 1; height: 16 }
                        }  // close outer Column
                    }  // close outer ScrollView

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
                    id: newshaderSettings
                    visible: buttonGrid.selectedTool === "newshader" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string fragFilePath: ""
                    property string vertFilePath: ""
                    property bool showUncompiledWarning: false
                    property var rawUniforms: []  // full list from inspectShader, including time
                    property real propX: 0
                    property real propY: 0
                    property real propW: 200
                    property real propH: 150
                    property bool propLock: false
                    property string propName: ""

                    ListModel { id: uniformFieldsModel }  // one entry per non-time uniform shown in UI

                    // Call inspectShader when frag path is set and populate the uniform fields model.
                    onFragFilePathChanged: {
                        uniformFieldsModel.clear();
                        if (fragFilePath !== "") {
                            rawUniforms = shaderInspector.inspectShader(fragFilePath);
                            for (var i = 0; i < rawUniforms.length; i++) {
                                var u = rawUniforms[i];
                                if (u.name === "time") continue;
                                var def = u.type === "sampler2D" ? "" : viewport.uniformDefault(u.type);
                                var defText = (def === null || def === "") ? "" : (Array.isArray(def) ? def.join(", ") : def.toString());
                                uniformFieldsModel.append({uName: u.name, uType: u.type, uText: defText});
                            }
                        } else {
                            rawUniforms = [];
                        }
                    }

                    // Build the uniformsJson to store in the model when a shader is created.
                    function buildCurrentUniformsList() {
                        var list = [];
                        for (var k = 0; k < rawUniforms.length; k++) {
                            var u = rawUniforms[k];
                            if (u.name === "time") {
                                list.push({name: "time", type: "float", value: 0.0});
                            } else {
                                var fieldIdx = 0;
                                for (var fi = 0; fi < uniformFieldsModel.count; fi++) {
                                    if (uniformFieldsModel.get(fi).uName === u.name) { fieldIdx = fi; break; }
                                }
                                var field = uniformFieldsModel.count > 0 ? uniformFieldsModel.get(fieldIdx) : null;
                                var txt = field ? field.uText : "";
                                if (u.type === "sampler2D") {
                                    list.push({name: u.name, type: u.type, value: txt});
                                } else {
                                    list.push({name: u.name, type: u.type, value: viewport.parseUniformToArray(u.type, txt || "1")});
                                }
                            }
                        }
                        return JSON.stringify(list);
                    }

                    Timer {
                        id: shaderWarningTimer
                        interval: 10000
                        onTriggered: newshaderSettings.showUncompiledWarning = false
                    }

                    function warnUncompiled() {
                        newshaderSettings.showUncompiledWarning = true;
                        shaderWarningTimer.restart();
                    }

                    Text {
                        id: newshaderSettingsHeading
                        text: "new shader"
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }

                    Text {
                        visible: newshaderSettings.showUncompiledWarning
                        text: "Please compile shader\nwith QSB."
                        font.pixelSize: 11
                        color: "white"
                        horizontalAlignment: Text.AlignRight
                        anchors.top: parent.top
                        anchors.topMargin: 18
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                    }

                    Row {
                        id: shaderDropZonesRow
                        anchors.top: newshaderSettingsHeading.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 8

                        // Fragment shader drop zone
                        Rectangle {
                            width: (parent.width - parent.spacing) / 2
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropfrag.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: newshaderSettings.fragFilePath !== "" ? 0.3 : 1.0
                            }

                            Text {
                                anchors.centerIn: parent
                                text: newshaderSettings.fragFilePath !== "" ? newshaderSettings.fragFilePath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                visible: newshaderSettings.fragFilePath !== ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: fragFileDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (!drop.hasUrls) return;
                                    var path = drop.urls[0].toString();
                                    if (path.endsWith(".frag.qsb")) {
                                        newshaderSettings.fragFilePath = path;
                                    } else if (path.endsWith(".frag")) {
                                        newshaderSettings.warnUncompiled();
                                    }
                                }
                            }
                        }

                        // Vertex shader drop zone
                        Rectangle {
                            width: (parent.width - parent.spacing) / 2
                            height: 80
                            color: "black"
                            radius: 4

                            Image {
                                anchors.fill: parent
                                anchors.margins: 9
                                sourceSize.width: 256
                                sourceSize.height: 256
                                source: "icons/dropvert.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: newshaderSettings.vertFilePath !== "" ? 0.3 : 1.0
                            }

                            Text {
                                anchors.centerIn: parent
                                text: newshaderSettings.vertFilePath !== "" ? newshaderSettings.vertFilePath.replace(/.*\//, "") : ""
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                visible: newshaderSettings.vertFilePath !== ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: vertFileDialog.open()
                            }

                            DropArea {
                                anchors.fill: parent
                                onDropped: drop => {
                                    if (!drop.hasUrls) return;
                                    var path = drop.urls[0].toString();
                                    if (path.endsWith(".vert.qsb")) {
                                        newshaderSettings.vertFilePath = path;
                                    } else if (path.endsWith(".vert")) {
                                        newshaderSettings.warnUncompiled();
                                    }
                                }
                            }
                        }
                    }

                    // Scrollable list: uniforms first, then name + spatial props.
                    ScrollView {
                        id: newShaderUniformsScroll
                        anchors.top: shaderDropZonesRow.bottom
                        anchors.topMargin: 10
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.bottomMargin: 8
                        clip: true

                        Column {
                            width: newShaderUniformsScroll.availableWidth
                            spacing: 5

                        Repeater {
                            model: uniformFieldsModel
                            delegate: Row {
                                width: parent.width
                                height: 26
                                spacing: 6

                                // Capture model roles into local properties for reliable access in nested items.
                                property string uName: model.uName
                                property string uType: model.uType
                                property string uText: model.uText
                                property int uIndex: index

                                readonly property bool isScalar: uType === "float" || uType === "int"

                                Text {
                                    text: uName
                                    width: 108
                                    color: "white"
                                    font.pixelSize: 11
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                Slider {
                                    id: newShaderUniformSlider
                                    visible: isScalar
                                    width: parent.width - 175
                                    height: parent.height
                                    from: 0; to: 1
                                    stepSize: 0
                                    Component.onCompleted: {
                                        var v = parseFloat(uText);
                                        if (isNaN(v) || v <= 0) value = 0;
                                        else if (v >= 100) value = 1;
                                        else value = Math.pow(v / 100.0, 0.2);
                                    }
                                    onMoved: {
                                        var expanded = parseFloat((Math.pow(value, 5) * 100.0).toFixed(4));
                                        uniformFieldsModel.setProperty(uIndex, "uText", expanded.toString());
                                        newShaderNumericField.text = expanded.toString();
                                    }
                                    background: Rectangle {
                                        x: newShaderUniformSlider.leftPadding
                                        y: newShaderUniformSlider.topPadding + newShaderUniformSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 200; implicitHeight: 4
                                        width: newShaderUniformSlider.availableWidth; height: 4
                                        radius: 2; color: "#333"
                                        Rectangle {
                                            width: newShaderUniformSlider.visualPosition * parent.width
                                            height: parent.height; color: "#5DA9A4"; radius: 2
                                        }
                                    }
                                    handle: Rectangle {
                                        x: newShaderUniformSlider.leftPadding + newShaderUniformSlider.visualPosition * (newShaderUniformSlider.availableWidth - width)
                                        y: newShaderUniformSlider.topPadding + newShaderUniformSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 12; implicitHeight: 12; radius: 6
                                        color: newShaderUniformSlider.pressed ? "#80cfff" : "#5DA9A4"
                                    }
                                }

                                Rectangle {
                                    width: isScalar ? 55 : (parent.width - 114)
                                    height: 26
                                    color: uType === "sampler2D" ? "black" : "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4

                                    // Texture label (sampler2D)
                                    Text {
                                        visible: uType === "sampler2D"
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        text: uText !== "" ? uText.replace(/.*\//, "") : "drop image or video"
                                        color: uText !== "" ? "white" : "#555"
                                        font.pixelSize: 11
                                        elide: Text.ElideLeft
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: uType === "sampler2D"
                                        onClicked: {
                                            newShaderTextureDialog.pendingUniformName = uName;
                                            newShaderTextureDialog.pendingUniformIndex = uIndex;
                                            newShaderTextureDialog.open();
                                        }
                                    }

                                    DropArea {
                                        anchors.fill: parent
                                        enabled: uType === "sampler2D"
                                        onDropped: drop => {
                                            if (!drop.hasUrls) return;
                                            uniformFieldsModel.setProperty(uIndex, "uText", drop.urls[0].toString());
                                        }
                                    }

                                    // Numeric input (float/vec)
                                    TextInput {
                                        id: newShaderNumericField
                                        visible: uType !== "sampler2D"
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        color: "white"
                                        font.pixelSize: 11
                                        clip: true
                                        selectByMouse: true
                                        text: uText
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: {
                                            if (isScalar) {
                                                var v = parseFloat(text);
                                                if (!isNaN(v)) {
                                                    var pos = v >= 100 ? 1.0 : (v <= 0 ? 0.0 : Math.pow(v / 100.0, 0.2));
                                                    newShaderUniformSlider.value = pos;
                                                }
                                            }
                                            uniformFieldsModel.setProperty(uIndex, "uText", text);
                                        }
                                    }
                                }
                            }
                        }
                        Item { width: 1; height: 8 }

                        // Name + spatial props (always shown, below uniforms)
                        Row {
                            width: parent.width; height: 26; spacing: 6
                            Text { text: "name"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            Rectangle {
                                width: parent.width - 50; height: 26
                                color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                TextInput {
                                    anchors.fill: parent; anchors.margins: 3
                                    color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                    text: newshaderSettings.propName
                                    Keys.onReturnPressed: focus = false
                                    Keys.onEscapePressed: focus = false
                                    onEditingFinished: newshaderSettings.propName = text
                                }
                            }
                        }

                        Repeater {
                            model: [{ lbl:"x",key:"propX" },{ lbl:"y",key:"propY" },{ lbl:"width",key:"propW" },{ lbl:"height",key:"propH" }]
                            delegate: Row {
                                width: parent.width; height: 26; spacing: 6
                                Text { text: modelData.lbl; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                Rectangle {
                                    width: parent.width - 50; height: 26
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 3
                                        color: "white"; font.pixelSize: 11; clip: true; selectByMouse: true
                                        text: newshaderSettings[modelData.key].toFixed(0)
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: newshaderSettings[modelData.key] = parseFloat(text) || 0
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width; height: 26; spacing: 6
                            Text { text: "lock"; width: 44; color: "white"; font.pixelSize: 11; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            Row {
                                spacing: 12; anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: [{ lbl: "on", val: true }, { lbl: "off", val: false }]
                                    delegate: Row {
                                        spacing: 4; anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 12; height: 12; radius: 6
                                            border.color: "white"; border.width: 1; color: "transparent"
                                            anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                anchors.centerIn: parent; width: 6; height: 6; radius: 3
                                                color: "white"; visible: newshaderSettings.propLock === modelData.val
                                            }
                                            MouseArea { anchors.fill: parent; onClicked: newshaderSettings.propLock = modelData.val }
                                        }
                                        Text { text: modelData.lbl; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }
                        }

                        Item { width: 1; height: 16 }
                        }  // Column
                    }  // ScrollView
                }

                Rectangle {
                    id: simulateSettings
                    visible: buttonGrid.selectedTool === "simulate" && !sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Text {
                        id: simulateSettingsHeading
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
                    visible: buttonGrid.selectedTool === "relayer" && !sceneEditorButtons.navigationOpen
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
                    visible: buttonGrid.selectedTool === "destroy" && !sceneEditorButtons.navigationOpen
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
                    visible: sceneEditorButtons.navigationOpen
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    property string deleteTarget: ""
                    property real deleteProgress: 0.0

                    function cancelNavDelete() {
                        deleteTarget = ""
                        deleteProgress = 0.0
                    }

                    Timer {
                        interval: 16
                        repeat: true
                        running: navigationSettings.deleteTarget !== ""
                        onTriggered: {
                            navigationSettings.deleteProgress += 16.0 / 600.0
                            if (navigationSettings.deleteProgress >= 1.0) {
                                var t = navigationSettings.deleteTarget
                                navigationSettings.cancelNavDelete()
                                if (t === "n") { nSettingsArea.linkedSceneId = -1; nSettingsArea.linkedSceneName = ""; nSettingsArea.linkedThumbnailRev = 0 }
                                else if (t === "s") { sSettingsArea.linkedSceneId = -1; sSettingsArea.linkedSceneName = ""; sSettingsArea.linkedThumbnailRev = 0 }
                                else if (t === "e") { eSettingsArea.linkedSceneId = -1; eSettingsArea.linkedSceneName = ""; eSettingsArea.linkedThumbnailRev = 0 }
                                else if (t === "w") { wSettingsArea.linkedSceneId = -1; wSettingsArea.linkedSceneName = ""; wSettingsArea.linkedThumbnailRev = 0 }
                            }
                        }
                    }

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

                        Timer {
                            id: layoutAreasDismissTimer
                            interval: 120
                            repeat: false
                            onTriggered: sceneEditorButtons.navigationOpen = false
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: navigationLayoutButton.hovered = true
                            onExited: navigationLayoutButton.hovered = false
                            onPressed: navigationLayoutButton.pressed = true
                            onReleased: navigationLayoutButton.pressed = false

                            onClicked: {
                                layoutAreasDismissTimer.start();
                            }
                        }
                    }

                    Rectangle {
                        id: nSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: linkedSceneId !== -1 ? "#5DA9A4" : "white"
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        clip: true

                        property int linkedSceneId: -1
                        property string linkedSceneName: ""
                        property int linkedThumbnailRev: 0

                        Item {
                            id: nThumbClip
                            anchors.fill: parent
                            visible: parent.linkedSceneId !== -1
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: nThumbClip.width
                                    height: nThumbClip.height
                                    radius: 12
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: nSettingsArea.linkedSceneId !== -1 && nSettingsArea.linkedThumbnailRev > 0
                                    ? ("image://thumbnails/" + nSettingsArea.linkedSceneId + "?rev=" + nSettingsArea.linkedThumbnailRev) : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"
                            visible: parent.linkedSceneId === -1

                            Image {
                                id: nHeading
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/n_heading.svg"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: parent.linkedSceneName
                            font.pixelSize: 9
                            color: "white"
                            style: Text.Outline
                            styleColor: "black"
                            visible: parent.linkedSceneId !== -1
                            elide: Text.ElideMiddle
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(1, 0, 0, navigationSettings.deleteProgress * 0.6)
                            border.color: Qt.rgba(1, 0, 0, 0.4 + navigationSettings.deleteProgress * 0.6)
                            border.width: navigationSettings.deleteTarget === "n" ? 2 : 0
                            visible: navigationSettings.deleteTarget === "n"
                            Behavior on color { ColorAnimation { duration: 40 } }
                        }

                        DropArea {
                            anchors.fill: parent
                            keys: ["navScene"]
                            onDropped: function(drop) {
                                nSettingsArea.linkedSceneId = navDragGhost.draggedSceneId
                                nSettingsArea.linkedSceneName = navDragGhost.draggedSceneName
                                nSettingsArea.linkedThumbnailRev = navDragGhost.draggedThumbnailRev
                                drop.accept()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            enabled: nSettingsArea.linkedSceneId !== -1
                            onPressed: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    navigationSettings.deleteTarget = "n"
                            }
                            onReleased: function(mouse) {
                                if (mouse.button === Qt.RightButton && navigationSettings.deleteTarget === "n")
                                    navigationSettings.cancelNavDelete()
                            }
                        }
                    }

                    Rectangle {
                        id: sSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: linkedSceneId !== -1 ? "#5DA9A4" : "white"
                        border.width: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        clip: true

                        property int linkedSceneId: -1
                        property string linkedSceneName: ""
                        property int linkedThumbnailRev: 0

                        Item {
                            id: sThumbClip
                            anchors.fill: parent
                            visible: parent.linkedSceneId !== -1
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: sThumbClip.width
                                    height: sThumbClip.height
                                    radius: 12
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: sSettingsArea.linkedSceneId !== -1 && sSettingsArea.linkedThumbnailRev > 0
                                    ? ("image://thumbnails/" + sSettingsArea.linkedSceneId + "?rev=" + sSettingsArea.linkedThumbnailRev) : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"
                            visible: parent.linkedSceneId === -1

                            Image {
                                id: sHeading
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/s_heading.svg"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: parent.linkedSceneName
                            font.pixelSize: 9
                            color: "white"
                            style: Text.Outline
                            styleColor: "black"
                            visible: parent.linkedSceneId !== -1
                            elide: Text.ElideMiddle
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(1, 0, 0, navigationSettings.deleteProgress * 0.6)
                            border.color: Qt.rgba(1, 0, 0, 0.4 + navigationSettings.deleteProgress * 0.6)
                            border.width: navigationSettings.deleteTarget === "s" ? 2 : 0
                            visible: navigationSettings.deleteTarget === "s"
                            Behavior on color { ColorAnimation { duration: 40 } }
                        }

                        DropArea {
                            anchors.fill: parent
                            keys: ["navScene"]
                            onDropped: function(drop) {
                                sSettingsArea.linkedSceneId = navDragGhost.draggedSceneId
                                sSettingsArea.linkedSceneName = navDragGhost.draggedSceneName
                                sSettingsArea.linkedThumbnailRev = navDragGhost.draggedThumbnailRev
                                drop.accept()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            enabled: sSettingsArea.linkedSceneId !== -1
                            onPressed: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    navigationSettings.deleteTarget = "s"
                            }
                            onReleased: function(mouse) {
                                if (mouse.button === Qt.RightButton && navigationSettings.deleteTarget === "s")
                                    navigationSettings.cancelNavDelete()
                            }
                        }
                    }

                    Rectangle {
                        id: eSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: linkedSceneId !== -1 ? "#5DA9A4" : "white"
                        border.width: 2
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        clip: true

                        property int linkedSceneId: -1
                        property string linkedSceneName: ""
                        property int linkedThumbnailRev: 0

                        Item {
                            id: eThumbClip
                            anchors.fill: parent
                            visible: parent.linkedSceneId !== -1
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: eThumbClip.width
                                    height: eThumbClip.height
                                    radius: 12
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: eSettingsArea.linkedSceneId !== -1 && eSettingsArea.linkedThumbnailRev > 0
                                    ? ("image://thumbnails/" + eSettingsArea.linkedSceneId + "?rev=" + eSettingsArea.linkedThumbnailRev) : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"
                            visible: parent.linkedSceneId === -1

                            Image {
                                id: eHeading
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/e_heading.svg"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: parent.linkedSceneName
                            font.pixelSize: 9
                            color: "white"
                            style: Text.Outline
                            styleColor: "black"
                            visible: parent.linkedSceneId !== -1
                            elide: Text.ElideMiddle
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(1, 0, 0, navigationSettings.deleteProgress * 0.6)
                            border.color: Qt.rgba(1, 0, 0, 0.4 + navigationSettings.deleteProgress * 0.6)
                            border.width: navigationSettings.deleteTarget === "e" ? 2 : 0
                            visible: navigationSettings.deleteTarget === "e"
                            Behavior on color { ColorAnimation { duration: 40 } }
                        }

                        DropArea {
                            anchors.fill: parent
                            keys: ["navScene"]
                            onDropped: function(drop) {
                                eSettingsArea.linkedSceneId = navDragGhost.draggedSceneId
                                eSettingsArea.linkedSceneName = navDragGhost.draggedSceneName
                                eSettingsArea.linkedThumbnailRev = navDragGhost.draggedThumbnailRev
                                drop.accept()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            enabled: eSettingsArea.linkedSceneId !== -1
                            onPressed: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    navigationSettings.deleteTarget = "e"
                            }
                            onReleased: function(mouse) {
                                if (mouse.button === Qt.RightButton && navigationSettings.deleteTarget === "e")
                                    navigationSettings.cancelNavDelete()
                            }
                        }
                    }

                    Rectangle {
                        id: wSettingsArea
                        width: 110
                        height: 70
                        radius: 12
                        color: "transparent"
                        border.color: linkedSceneId !== -1 ? "#5DA9A4" : "white"
                        border.width: 2
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        clip: true

                        property int linkedSceneId: -1
                        property string linkedSceneName: ""
                        property int linkedThumbnailRev: 0

                        Item {
                            id: wThumbClip
                            anchors.fill: parent
                            visible: parent.linkedSceneId !== -1
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: wThumbClip.width
                                    height: wThumbClip.height
                                    radius: 12
                                    color: "white"
                                }
                            }
                            Image {
                                anchors.fill: parent
                                source: wSettingsArea.linkedSceneId !== -1 && wSettingsArea.linkedThumbnailRev > 0
                                    ? ("image://thumbnails/" + wSettingsArea.linkedSceneId + "?rev=" + wSettingsArea.linkedThumbnailRev) : ""
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                            }
                        }

                        Rectangle {
                            width: parent.width - 50
                            height: parent.height - 50
                            anchors.centerIn: parent
                            color: "transparent"
                            visible: parent.linkedSceneId === -1

                            Image {
                                id: wHeading
                                height: parent.height
                                anchors.centerIn: parent
                                fillMode: Image.PreserveAspectFit
                                source: "headings/w_heading.svg"
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: parent.linkedSceneName
                            font.pixelSize: 9
                            color: "white"
                            style: Text.Outline
                            styleColor: "black"
                            visible: parent.linkedSceneId !== -1
                            elide: Text.ElideMiddle
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(1, 0, 0, navigationSettings.deleteProgress * 0.6)
                            border.color: Qt.rgba(1, 0, 0, 0.4 + navigationSettings.deleteProgress * 0.6)
                            border.width: navigationSettings.deleteTarget === "w" ? 2 : 0
                            visible: navigationSettings.deleteTarget === "w"
                            Behavior on color { ColorAnimation { duration: 40 } }
                        }

                        DropArea {
                            anchors.fill: parent
                            keys: ["navScene"]
                            onDropped: function(drop) {
                                wSettingsArea.linkedSceneId = navDragGhost.draggedSceneId
                                wSettingsArea.linkedSceneName = navDragGhost.draggedSceneName
                                wSettingsArea.linkedThumbnailRev = navDragGhost.draggedThumbnailRev
                                drop.accept()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            enabled: wSettingsArea.linkedSceneId !== -1
                            onPressed: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    navigationSettings.deleteTarget = "w"
                            }
                            onReleased: function(mouse) {
                                if (mouse.button === Qt.RightButton && navigationSettings.deleteTarget === "w")
                                    navigationSettings.cancelNavDelete()
                            }
                        }
                    }
                }

                Rectangle {
                    id: sceneSettings
                    visible: sceneEditorButtons.conditionsOpen
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
                    visible: sceneEditorButtons.variablesOpen
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

                    function loadVariablesFromDb() {
                        variablesModel.clear();
                        var vars = storyManager.getVariables();
                        for (var i = 0; i < vars.length; i++)
                            variablesModel.append(vars[i]);
                    }

                    function saveVariablesToDb() {
                        var out = [];
                        for (var i = 0; i < variablesModel.count; i++)
                            out.push(variablesModel.get(i));
                        storyManager.saveVariables(JSON.stringify(out));
                    }

                    Connections {
                        target: storyManager
                        function onStoryOpened() { sceneScript.loadVariablesFromDb(); }
                    }

                    // Remove unnamed variables and persist when the user navigates away
                    onVisibleChanged: {
                        if (!visible) {
                            for (var i = variablesModel.count - 1; i >= 0; i--) {
                                if (variablesModel.get(i).varName === "")
                                    variablesModel.remove(i);
                            }
                            saveVariablesToDb();
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
                                    id: varDelegate
                                    width: parent.width
                                    height: 26

                                    // Capture the Repeater index so it isn't shadowed by
                                    // signal parameters also named index
                                    property int delegateIndex: index
                                    property real deleteProgress: 0.0

                                    NumberAnimation {
                                        id: varDeleteAnim
                                        target: varDelegate
                                        property: "deleteProgress"
                                        to: 1.0
                                        duration: 1200
                                        easing.type: Easing.Linear
                                        onFinished: {
                                            if (varDelegate.deleteProgress >= 1.0) {
                                                var deletedName = variablesModel.get(varDelegate.delegateIndex).varName
                                                var models = [areaInteractivityModel, selectInteractivityModel]
                                                for (var m = 0; m < models.length; m++) {
                                                    var mdl = models[m]
                                                    for (var i = mdl.count - 1; i >= 0; i--) {
                                                        if (mdl.get(i).itemConditionVar === deletedName)
                                                            mdl.remove(i)
                                                    }
                                                    // Per-trigger: if no "if" items remain for a trigger, remove orphaned "else" items
                                                    var triggers = ["click", "hover"]
                                                    for (var t = 0; t < triggers.length; t++) {
                                                        var trig = triggers[t]
                                                        var hasIf = false
                                                        for (var i = 0; i < mdl.count; i++) {
                                                            var e = mdl.get(i)
                                                            if (e.itemTrigger === trig && e.itemAction === "if") { hasIf = true; break }
                                                        }
                                                        if (!hasIf) {
                                                            for (var i = mdl.count - 1; i >= 0; i--) {
                                                                var e = mdl.get(i)
                                                                if (e.itemTrigger === trig && e.itemAction === "else")
                                                                    mdl.remove(i)
                                                            }
                                                        }
                                                    }
                                                }
                                                variablesModel.remove(varDelegate.delegateIndex)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.RightButton
                                        z: 10
                                        onPressed: mouse => {
                                            varDelegate.deleteProgress = 0
                                            varDeleteAnim.start()
                                        }
                                        onReleased: mouse => {
                                            varDeleteAnim.stop()
                                            varDelegate.deleteProgress = 0
                                        }
                                        onExited: {
                                            varDeleteAnim.stop()
                                            varDelegate.deleteProgress = 0
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4
                                        color: "#ff4444"
                                        opacity: varDelegate.deleteProgress * 0.75
                                        visible: varDelegate.deleteProgress > 0
                                        z: 9
                                    }

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
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.leftMargin: 4
                                                anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
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
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
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
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 4
                                                    anchors.verticalCenter: parent.verticalCenter
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
                    visible: ["select", "simulate", "relayer", "destroy"].indexOf(buttonGrid.selectedTool) !== -1 && !sceneEditorButtons.conditionsOpen && !sceneEditorButtons.variablesOpen && !sceneEditorButtons.navigationOpen && !(buttonGrid.selectedTool === "select" && viewport.selectionCount > 0)
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    readonly property var toolDisplayNames: ({ "select": "select", "simulate": "simulate", "relayer": "stack", "destroy": "delete" })

                    Text {
                        text: sceneNameSettings.toolDisplayNames[buttonGrid.selectedTool] || ""
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                    }

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
                        onEditingFinished: {
                            if (mainWindow.currentSceneId !== -1) {
                                storyManager.updateSceneName(mainWindow.currentSceneId, text);
                                // Keep scene menu cards in sync
                                for (var i = 0; i < scenesRectModel.count; i++) {
                                    if (scenesRectModel.get(i).sceneId === mainWindow.currentSceneId) {
                                        scenesRectModel.setProperty(i, "sceneName", text);
                                        break;
                                    }
                                }
                            }
                        }
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
                property bool toggled: sceneEditorButtons.navigationOpen

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
                        sceneEditorButtons.navigationOpen = !sceneEditorButtons.navigationOpen;
                        if (sceneEditorButtons.navigationOpen)
                            sceneEditorButtons.navOverlayOpen = true;
                    }
                }
            }
        }

        // Drag ghost for navigation scene drag-and-drop
        Rectangle {
            id: navDragGhost
            width: 120
            height: 75
            radius: 12
            z: 1000
            visible: false
            color: "black"
            layer.enabled: true

            property int draggedSceneId: -1
            property string draggedSceneName: ""
            property int draggedThumbnailRev: 0

            Drag.active: visible
            Drag.keys: ["navScene"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: navDragGhost.width
                        height: navDragGhost.height
                        radius: navDragGhost.radius
                        color: "white"
                    }
                }
                Image {
                    anchors.fill: parent
                    source: navDragGhost.draggedSceneId !== -1 && navDragGhost.draggedThumbnailRev > 0
                        ? ("image://thumbnails/" + navDragGhost.draggedSceneId + "?rev=" + navDragGhost.draggedThumbnailRev) : ""
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: navDragGhost.draggedSceneName
                font.pixelSize: 9
                color: "white"
                style: Text.Outline
                styleColor: "black"
                elide: Text.ElideMiddle
                width: parent.width - 8
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: "white"
                border.width: 2
                radius: 12
            }
        }
    }

    Timer {
        id: closeSceneTimer
        interval: 1000
        repeat: false
        onTriggered: {
            viewportFadeInAnim.start();
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
                    viewportFadeOutAnim.start();
                    sceneMenu2sceneEditor.visible = false;
                    sceneMenu.visible = false;
                    viewport.capturingThumbnail = false;
                    buttonGrid.selectedTool = "select";
                    sceneEditorButtons.conditionsOpen = false;
                    sceneEditorButtons.variablesOpen = false;
                    sceneEditorButtons.navigationOpen = false;
                    sceneEditorButtons.interactivityPickerOpen = false;
                    // Populate the scene name field from the DB
                    if (mainWindow.currentSceneId !== -1)
                        sceneNameInput.text = storyManager.getSceneName(mainWindow.currentSceneId);
                }
            }
        }

        VideoOutput {
            id: sceneMenu2sceneEditorVideoOutput
            anchors.fill: parent
        }
    }

    // ------------------------------------------------------------------ story file dialogs

    FileDialog {
        id: openStoryDialog
        title: "Open story"
        nameFilters: ["Story files (*.story)"]
        property string pendingStoryPath: ""
        onAccepted: {
            var path = selectedFile.toString();
            if (sceneEditor.visible) {
                // Scene editor is open — capture thumbnail, save state, close scene,
                // then load story once the close-scene transition finishes
                // (see sceneEditor2sceneMenu handler for the final load step)
                pendingStoryPath = path;
                var savedSceneId = mainWindow.currentSceneId;
                viewport.captureAndSaveThumbnail(savedSceneId, function() {
                    if (savedSceneId !== -1) {
                        storyManager.updateSceneName(savedSceneId, sceneNameInput.text);
                        storyManager.saveSceneElements(savedSceneId, viewport.collectSceneElements());
                    }
                    sceneScript.saveVariablesToDb();
                    nodeWorkspace.saveToDb();
                    if (savedSceneId !== -1)
                        storyManager.setEditorState("scene_" + savedSceneId + "_timeline_open", sceneEditorButtons.timelineOpen ? "1" : "0");
                    if (sceneEditorButtons.timelineOpen) {
                        sceneEditorButtons.timelineOpen = false;
                        yanimationduration = 1000;
                        mainWindow.height = 540;
                        mainWindow.y = mainWindow.y + 150;
                        closeSceneTimer.start();
                    } else {
                        viewportFadeInAnim.start();
                        xanimationduration = 1000;
                        mainWindow.width = 960;
                        mainWindow.x = sceneEditorEntryX;
                        sceneEditor2sceneMenu.windowSizeCompleteTrigger = true;
                    }
                });
            } else if (storyMenu.visible) {
                // On story menu — load and animate to scene menu
                if (storyManager.openStory(path)) {
                    story2sceneMenu.visible = true;
                    story2sceneMenuPlayer.play();
                }
            } else {
                // On scene menu — just load; scene menu updates reactively
                storyManager.openStory(path);
            }
        }
    }

    FileDialog {
        id: saveStoryDialog
        title: "Save story"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "story"
        nameFilters: ["Story files (*.story)"]
        property string pendingAction: "new"
        property bool triggerTransition: false
        onAccepted: {
            var ok = false;
            if (pendingAction === "new")
                ok = storyManager.newStory(selectedFile.toString());
            else
                ok = storyManager.saveStoryAs(selectedFile.toString());
            if (ok && triggerTransition && pendingAction === "new") {
                story2sceneMenu.visible = true;
                story2sceneMenuPlayer.play();
            }
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
                    viewportBlackOverlay.opacity = 1;
                    sceneEditor2sceneMenu.visible = false;
                    sceneMenu.visible = true;
                    sceneEditor2sceneMenu.windowSizeCompleteTrigger = false;
                    if (openStoryDialog.pendingStoryPath !== "") {
                        storyManager.openStory(openStoryDialog.pendingStoryPath);
                        openStoryDialog.pendingStoryPath = "";
                    }
                }
            }
        }

        VideoOutput {
            id: sceneEditor2sceneMenuVideoOutput
            anchors.fill: parent
        }
    }
}
