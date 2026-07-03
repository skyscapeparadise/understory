import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Dropdown + "+" + inline group card (name / start timecode / end behavior /
// right-click-hold delete) for assigning a sync group to a track. Shared by the
// mixer's "track" subpanel and the sound list's inline "sync" toggle so both
// present the exact same interface for managing sync groups.
Item {
    id: syncEditor

    // The NodeWorkspace root — owns syncGroupsModel and the add/rename/set/delete
    // functions, and mixerRevision for reactivity.
    property var nodeWorkspace: null
    // Currently-assigned group id for whatever track this instance represents, -1 = none.
    property int syncGroupId: -1
    signal syncGroupIdEdited(int groupId)

    width: parent ? parent.width : 0
    height: mainCol.height

    readonly property var group: {
        if (!nodeWorkspace) return null
        nodeWorkspace.mixerRevision
        if (syncEditor.syncGroupId < 0) return null
        return nodeWorkspace.syncGroupById(syncEditor.syncGroupId)
    }

    Column {
        id: mainCol
        width: parent.width
        spacing: 6

        RowLayout {
            width: parent.width
            spacing: 4

            ComboBox {
                id: combo
                Layout.fillWidth: true
                model: {
                    if (!syncEditor.nodeWorkspace) return ["none"]
                    syncEditor.nodeWorkspace.mixerRevision
                    var arr = ["none"]
                    var gm = syncEditor.nodeWorkspace.syncGroupsModel
                    for (var i = 0; i < gm.count; i++) arr.push(gm.get(i).groupName)
                    return arr
                }
                currentIndex: {
                    if (!syncEditor.nodeWorkspace) return 0
                    syncEditor.nodeWorkspace.mixerRevision
                    if (syncEditor.syncGroupId < 0) return 0
                    var gm = syncEditor.nodeWorkspace.syncGroupsModel
                    for (var i = 0; i < gm.count; i++)
                        if (gm.get(i).groupId === syncEditor.syncGroupId) return i + 1
                    return 0
                }
                onActivated: idx => {
                    if (idx === 0) syncEditor.syncGroupIdEdited(-1)
                    else syncEditor.syncGroupIdEdited(syncEditor.nodeWorkspace.syncGroupsModel.get(idx - 1).groupId)
                }
            }

            Rectangle {
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                radius: 4
                color: newGroupMouse.containsMouse ? "white" : "transparent"
                border.color: "white"; border.width: 1
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -0.5
                    text: "+"; font.pixelSize: 16; font.bold: true
                    color: newGroupMouse.containsMouse ? "darkslategrey" : "white"
                }
                MouseArea {
                    id: newGroupMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var newId = syncEditor.nodeWorkspace.addSyncGroup()
                        syncEditor.syncGroupIdEdited(newId)
                    }
                }
            }
        }

        Item {
            id: card
            width: parent.width
            height: cardCol.height
            visible: syncEditor.group !== null
            property real deleteProgress: 0.0

            // Right-click and hold anywhere on this card to delete the sync group —
            // same convention as interactivity items, sound rows, etc.
            NumberAnimation {
                id: cardDeleteAnim
                target: card
                property: "deleteProgress"
                to: 1.0; duration: 1200; easing.type: Easing.Linear
                onFinished: {
                    if (card.deleteProgress >= 1.0 && syncEditor.group) {
                        var gid = syncEditor.group.groupId
                        syncEditor.syncGroupIdEdited(-1)
                        syncEditor.nodeWorkspace.deleteSyncGroup(gid)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                z: 10
                onPressed: mouse => { card.deleteProgress = 0; cardDeleteAnim.start() }
                onReleased: mouse => { cardDeleteAnim.stop(); card.deleteProgress = 0 }
                onExited: { cardDeleteAnim.stop(); card.deleteProgress = 0 }
            }

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: "#ff4444"
                opacity: card.deleteProgress * 0.75
                visible: card.deleteProgress > 0
                z: 9
            }

            Column {
                id: cardCol
                width: parent.width
                spacing: 6

                Rectangle {
                    width: parent.width; height: 24
                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                    TextInput {
                        anchors.fill: parent
                        anchors.margins: 6
                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                        text: syncEditor.group ? syncEditor.group.groupName : ""
                        Keys.onReturnPressed: focus = false
                        Keys.onEscapePressed: focus = false
                        onEditingFinished: if (syncEditor.group) syncEditor.nodeWorkspace.renameSyncGroup(syncEditor.group.groupId, text)
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: 6
                    Text { text: "start"; font.pixelSize: 10; color: "#aaa"; Layout.alignment: Qt.AlignVCenter }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                        TextInput {
                            id: timecodeField
                            anchors.fill: parent
                            anchors.margins: 6
                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                            inputMask: "99:99:99:99"
                            text: syncEditor.group ? (syncEditor.group.startTimecode || "00:00:00:00") : "00:00:00:00"
                            Keys.onReturnPressed: focus = false
                            Keys.onEscapePressed: {
                                text = syncEditor.group ? (syncEditor.group.startTimecode || "00:00:00:00") : "00:00:00:00"
                                focus = false
                            }
                            onEditingFinished: {
                                if (syncEditor.group) {
                                    var tc = /^\d{2}:\d{2}:\d{2}:\d{2}$/.test(text) ? text : "00:00:00:00"
                                    syncEditor.nodeWorkspace.setSyncGroupProp(syncEditor.group.groupId, "startTimecode", tc)
                                    text = tc
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 40; Layout.preferredHeight: 24
                        radius: 4
                        color: markMouse.containsMouse ? "white" : "transparent"
                        border.color: "white"; border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "mark"; font.pixelSize: 9
                            color: markMouse.containsMouse ? "darkslategrey" : "white"
                        }
                        MouseArea {
                            id: markMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (!syncEditor.group || !syncEditor.nodeWorkspace) return
                                var tc = syncEditor.nodeWorkspace.secondsToTimecode(syncEditor.nodeWorkspace.playheadTime).replace(";", ":")
                                syncEditor.nodeWorkspace.setSyncGroupProp(syncEditor.group.groupId, "startTimecode", tc)
                                timecodeField.text = tc
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: ["loop", "freeze", "hide"]
                        delegate: Rectangle {
                            width: (cardCol.width - 8) / 3; height: 22
                            radius: 4
                            property bool isActive: syncEditor.group && syncEditor.group.endBehavior === modelData
                            color: isActive ? "white" : "transparent"
                            border.color: "white"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData; font.pixelSize: 9
                                color: parent.isActive ? "darkslategrey" : "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (syncEditor.group) syncEditor.nodeWorkspace.setSyncGroupProp(syncEditor.group.groupId, "endBehavior", modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
