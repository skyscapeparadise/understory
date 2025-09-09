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
                model: ["new story", "update", "settings", "credits"]
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
            opacity: 0.0
            visible: sceneMenuButtons.selectedButton === "settings"
            clip: true
            topPadding: 20
            leftPadding: 20
            rightPadding: 20

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }

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
                model: ["new scene", "delete", "settings", "exit story"]
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

            Image {
                anchors.fill: parent
                source: "file:stairwell.jpg"
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

                Repeater {
                    model: ["scene script", "scene settings", "save scene", "close scene"]

                    delegate: Item {
                        id: editorBtn
                        width: 138
                        height: 28

                        property bool hovered: false
                        property bool togglable: modelData === "scene script" || modelData === "scene settings"
                        property bool toggled: togglable && buttonGrid.selectedTool === modelData
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
                                } else if (modelData === "save scene") {
                                    console.log("Saving scene…");
                                } else if (modelData === "close scene") {
                                    console.log("Closing scene…");
                                    xanimationduration = 1000;
                                    mainWindow.width = 960;
                                    mainWindow.x = x + 275;
                                    sceneEditor2sceneMenu.windowSizeCompleteTrigger = true;
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

                    Item {
                        id: areaSettingsHeading

                        property string iconSource: "headings/area_heading.svg"
                        anchors.top: parent.top
                        anchors.topMargin: 25
                        anchors.left: parent.left
                        anchors.leftMargin: 20

                        Rectangle {
                            height: 20
                            color: "transparent"

                            Image {
                                id: areaHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                source: areaSettingsHeading.iconSource
                            }
                        }
                    }
                }

                Rectangle {
                    id: imageSettings
                    visible: buttonGrid.selectedTool === "newimage"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "transparent"

                    Item {
                        id: imageSettingsHeading

                        property string iconSource: "headings/image_heading.svg"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20

                        Rectangle {
                            height: 35
                            color: "transparent"

                            Image {
                                id: imageHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                source: imageSettingsHeading.iconSource
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

                    Item {
                        id: videoSettingsHeading

                        property string iconSource: "headings/video_heading.svg"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20

                        Rectangle {
                            height: 25
                            color: "transparent"

                            Image {
                                id: videoHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                source: videoSettingsHeading.iconSource
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

                    Item {
                        id: textSettingsHeading

                        property string iconSource: "headings/text_heading.svg"
                        anchors.top: parent.top
                        anchors.topMargin: 20
                        anchors.left: parent.left
                        anchors.leftMargin: 20

                        Rectangle {
                            height: 25
                            color: "transparent"

                            Image {
                                id: textHeading
                                x: parent.x
                                y: parent.y
                                height: parent.height
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                source: textSettingsHeading.iconSource
                            }
                        }
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
                    visible: buttonGrid.selectedTool === "scene settings"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "darkcyan"
                    border.color: "white"
                    border.width: 2
                }

                Rectangle {
                    id: sceneScript
                    visible: buttonGrid.selectedTool === "scene script"
                    height: parent.height
                    width: parent.width
                    radius: parent.radius
                    color: "darkslategrey"
                    border.color: "white"
                    border.width: 2
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
                    xanimationduration = 1000;
                    mainWindow.width = 1365;
                    mainWindow.x = x - 202;
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
