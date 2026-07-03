import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// One channel in the audio mixer stage. Source-agnostic — NodeWorkspace.qml (or
// understoryui.qml) owns where trackKey/filePath/volume/pan/level actually come
// from and writes edits back via the *Dragged/*Dropped signals.
Item {
    id: strip

    property string trackKey: ""
    property string displayName: ""
    property string filePath: ""
    property real volume: 1.0
    property real pan: 0.0
    // Placeholder meter level (0..1) — no real audio analysis exists yet; a future
    // audio-buffer tap sets this. Deliberately NOT derived from the fader position.
    property real level: 0.0
    property bool selected: false
    // True for standalone tracks dropped/added straight into the mixer (not tied
    // to a sound node, video element, or interactivity "sound" cue) — tinted
    // differently so authors can tell them apart, and only these are deletable.
    property bool isExtra: false
    property bool deletable: false
    property real deleteProgress: 0.0

    signal selectedRequested()
    signal volumeDragged(real value)
    signal panDragged(real value)
    signal fileDropped(string path)
    signal deleteRequested()

    width: 72
    height: parent ? parent.height : 220

    readonly property string fileBaseName: filePath ? filePath.toString().replace(/.*[\/\\]/, "") : ""
    readonly property string headerText: displayName !== "" ? displayName : fileBaseName

    NumberAnimation {
        id: stripDeleteAnim
        target: strip
        property: "deleteProgress"
        to: 1.0
        duration: 1200
        easing.type: Easing.Linear
        onFinished: {
            if (strip.deleteProgress >= 1.0) strip.deleteRequested()
        }
    }

    Rectangle {
        id: stripBg
        anchors.fill: parent
        anchors.margins: 2
        radius: 4
        color: strip.selected ? (strip.isExtra ? "#3a2a23" : "#233a3a") : (strip.isExtra ? "#241c1c" : "#1c1c20")
        border.color: strip.selected ? "#5DA9A4" : (strip.isExtra ? "#3a2a2a" : "#2a2a30")
        border.width: strip.selected ? 2 : 1
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }

        MouseArea {
            anchors.fill: parent
            onClicked: strip.selectedRequested()
        }

        // Right-click and hold to delete — only wired up for deletable (extra)
        // tracks; tracks tied to a real media object/source can't be removed here.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            enabled: strip.deletable
            z: 10
            onPressed: mouse => { strip.deleteProgress = 0; stripDeleteAnim.start() }
            onReleased: mouse => { stripDeleteAnim.stop(); strip.deleteProgress = 0 }
            onExited: { stripDeleteAnim.stop(); strip.deleteProgress = 0 }
        }

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: "#ff4444"
            opacity: strip.deleteProgress * 0.75
            visible: strip.deleteProgress > 0
            z: 9
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4

            // Drop zone / source label
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 4
                color: "black"
                border.color: dropArea.containsDrag ? "#5DA9A4" : "transparent"
                border.width: 1

                Text {
                    anchors.fill: parent
                    anchors.margins: 3
                    visible: strip.headerText !== ""
                    text: strip.headerText
                    color: "white"
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    anchors.centerIn: parent
                    visible: strip.headerText === ""
                    text: "drop\nsound"
                    color: "#555"
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: strip.selectedRequested()
                }

                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    onDropped: drop => {
                        if (drop.hasUrls) strip.fileDropped(drop.urls[0].toString())
                    }
                }
            }

            // Meter + fader
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                // VU meter — green/yellow/red gradient, masked by `level` (placeholder).
                Item {
                    Layout.preferredWidth: 10
                    Layout.fillHeight: true

                    Rectangle {
                        id: meterTrack
                        anchors.fill: parent
                        radius: 2
                        color: "#0a0a0c"
                        border.color: "#2a2a30"
                        border.width: 1
                    }

                    Rectangle {
                        id: meterFill
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * Math.max(0, Math.min(1, strip.level))
                        radius: 2
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#e04040" }
                            GradientStop { position: 0.25; color: "#e0c040" }
                            GradientStop { position: 0.65; color: "#4caf50" }
                            GradientStop { position: 1.0; color: "#4caf50" }
                        }
                    }
                }

                Slider {
                    id: volSlider
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: Qt.Vertical
                    from: 0.0; to: 1.0; stepSize: 0
                    value: strip.volume
                    onMoved: strip.volumeDragged(value)

                    // Fill/handle are driven directly off strip.volume rather than
                    // visualPosition — dragging the mouse up already raises the raw
                    // position (and so the value) on this Slider build, so no from/to
                    // trickery is needed; only the drawing needed fixing.
                    background: Rectangle {
                        x: volSlider.leftPadding + volSlider.availableWidth / 2 - width / 2
                        y: volSlider.topPadding
                        implicitWidth: 4; implicitHeight: 200
                        width: 4; height: volSlider.availableHeight
                        radius: 2; color: "#333"
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: strip.volume * parent.height
                            radius: 2; color: "#5DA9A4"
                        }
                    }
                    handle: Rectangle {
                        x: volSlider.leftPadding + volSlider.availableWidth / 2 - width / 2
                        y: volSlider.topPadding + (1 - strip.volume) * (volSlider.availableHeight - height)
                        implicitWidth: 20; implicitHeight: 10; radius: 3
                        color: volSlider.pressed ? "#80cfff" : "#5DA9A4"
                    }
                }
            }

            // Pan slider
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                spacing: 2

                Text { text: "L"; font.pixelSize: 8; color: "#888" }

                Slider {
                    id: panSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    from: -1.0; to: 1.0; stepSize: 0
                    value: strip.pan
                    onMoved: strip.panDragged(value)

                    background: Rectangle {
                        x: panSlider.leftPadding
                        y: panSlider.topPadding + panSlider.availableHeight / 2 - height / 2
                        implicitWidth: 60; implicitHeight: 3
                        width: panSlider.availableWidth; height: 3
                        radius: 1; color: "#333"
                    }
                    handle: Rectangle {
                        x: panSlider.leftPadding + panSlider.visualPosition * (panSlider.availableWidth - width)
                        y: panSlider.topPadding + panSlider.availableHeight / 2 - height / 2
                        implicitWidth: 8; implicitHeight: 8; radius: 4
                        color: panSlider.pressed ? "#80cfff" : "#5DA9A4"
                    }
                }

                Text { text: "R"; font.pixelSize: 8; color: "#888" }
            }
        }
    }
}
