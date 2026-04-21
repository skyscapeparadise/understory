import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Qt.labs.platform as Platform

Item {
    id: root

    property var interactivityModel
    property var variablesModel
    property var scenePickerButtons

    implicitHeight: listCol.height

    Platform.FileDialog {
        id: soundFileDialog
        title: "Select audio file"
        nameFilters: ["Audio files (*.mp3 *.wav *.aac *.ogg *.flac *.m4a)"]
        property int targetIdx: -1
        onAccepted: {
            if (targetIdx >= 0)
                root.interactivityModel.setProperty(targetIdx, "itemSoundPath", soundFileDialog.file.toString())
        }
    }

    Platform.FileDialog {
        id: videoFileDialog
        title: "Select video file"
        nameFilters: ["Video files (*.mp4 *.mov *.avi *.mkv *.webm *.m4v)"]
        property int targetIdx: -1
        onAccepted: {
            if (targetIdx >= 0)
                root.interactivityModel.setProperty(targetIdx, "itemVideoPath", videoFileDialog.file.toString())
        }
    }

    Column {
        id: listCol
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
                    property bool active: root.currentTab === modelData
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
                        onClicked: root.currentTab = modelData
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
                        var tab = root.currentTab
                        var defaultCommand = "jump"
                        var insertIdx = -1
                        for (var i = 0; i < root.interactivityModel.count; i++) {
                            var e = root.interactivityModel.get(i)
                            if (e.itemTrigger !== tab) continue
                            if ((e.itemAction === "cue" || e.itemAction === "else") && e.itemCommand === "jump") {
                                defaultCommand = "sound"; insertIdx = i; break
                            }
                        }
                        var newItem = { itemTrigger: tab, itemAction: "cue", itemCommand: defaultCommand, itemTransition: "cut", itemTransitionSpeed: 0.4, itemWipeFeather: 0.15, itemWipeDirection: "right", itemPushDirection: "right", itemLookYaw: 90.0, itemLookPitch: 0.0, itemLookFovMM: 24.0, itemLookOvershoot: 1.0, itemLookShutter: 0.10, itemTargetSceneId: -1, itemTargetSceneName: "", itemConditionVar: "", itemConditionOp: "is", itemConditionVal: "", itemSoundPath: "", itemVideoPath: "", itemVideoTarget: "fill", itemUpdateVar: "", itemUpdateOp: "=", itemUpdateVal: "" }
                        if (insertIdx >= 0) root.interactivityModel.insert(insertIdx, newItem)
                        else root.interactivityModel.append(newItem)
                    }
                }
            }
        }

        Repeater {
            model: root.interactivityModel
            delegate: Component {
                Item {
                    id: interactivityDelegate
                    width: parent ? parent.width : 0
                    height: itemTrigger === root.currentTab ? innerCol.height : 0
                    visible: itemTrigger === root.currentTab
                    property int listIdx: index
                    property real deleteProgress: 0.0
                    property string condVarType: {
                        var v = itemConditionVar
                        if (!v || v === "") return ""
                        for (var i = 0; i < root.variablesModel.count; i++) {
                            if (root.variablesModel.get(i).varName === v) return root.variablesModel.get(i).varType
                        }
                        return ""
                    }
                    property string updateVarType: {
                        var v = itemUpdateVar
                        if (!v || v === "") return ""
                        for (var i = 0; i < root.variablesModel.count; i++) {
                            if (root.variablesModel.get(i).varName === v) return root.variablesModel.get(i).varType
                        }
                        return ""
                    }

                    NumberAnimation {
                        id: deleteAnim
                        target: interactivityDelegate
                        property: "deleteProgress"
                        to: 1.0
                        duration: 1200
                        easing.type: Easing.Linear
                        onFinished: {
                            if (interactivityDelegate.deleteProgress >= 1.0) {
                                var item = root.interactivityModel.get(interactivityDelegate.listIdx)
                                var wasIf = item.itemAction === "if"
                                var trigger = item.itemTrigger
                                root.interactivityModel.remove(interactivityDelegate.listIdx)
                                if (wasIf) {
                                    var hasIf = false
                                    for (var i = 0; i < root.interactivityModel.count; i++) {
                                        var e = root.interactivityModel.get(i)
                                        if (e.itemTrigger === trigger && e.itemAction === "if") { hasIf = true; break }
                                    }
                                    if (!hasIf) {
                                        for (var i = root.interactivityModel.count - 1; i >= 0; i--) {
                                            var e = root.interactivityModel.get(i)
                                            if (e.itemTrigger === trigger && e.itemAction === "else")
                                                root.interactivityModel.remove(i)
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
                        onPressed: mouse => { interactivityDelegate.deleteProgress = 0; deleteAnim.start() }
                        onReleased: mouse => { deleteAnim.stop(); interactivityDelegate.deleteProgress = 0 }
                        onExited: { deleteAnim.stop(); interactivityDelegate.deleteProgress = 0 }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: "#ff4444"
                        opacity: interactivityDelegate.deleteProgress * 0.75
                        visible: interactivityDelegate.deleteProgress > 0
                        z: 9
                    }

                    Column {
                        id: innerCol
                        width: parent.width
                        spacing: 4

                        Item { width: 1; height: 2 }

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 4

                            ComboBox {
                                id: actionCombo
                                Layout.preferredWidth: 62
                                Layout.preferredHeight: 26
                                model: {
                                    var hasVars = false
                                    for (var i = 0; i < root.variablesModel.count; i++) {
                                        if (root.variablesModel.get(i).varName !== "") { hasVars = true; break }
                                    }
                                    if (!hasVars) return ["cue"]
                                    var opts = ["cue", "if"]
                                    var thisIdx = interactivityDelegate.listIdx
                                    var thisTrigger = itemTrigger
                                    for (var i = 0; i < root.interactivityModel.count; i++) {
                                        var e = root.interactivityModel.get(i)
                                        if (i !== thisIdx && e.itemTrigger === thisTrigger && e.itemAction === "if") {
                                            opts.push("else"); break
                                        }
                                    }
                                    return opts
                                }
                                currentIndex: Math.max(0, model.indexOf(itemAction))
                                onActivated: function(activatedIndex) {
                                    var newAction = actionCombo.model[activatedIndex]
                                    var itemIdx = interactivityDelegate.listIdx
                                    var revertIdx = Math.max(0, actionCombo.model.indexOf(itemAction))
                                    var trigger = itemTrigger
                                    if (newAction === "cue") {
                                        for (var i = 0; i < root.interactivityModel.count; i++) {
                                            if (i === itemIdx) continue
                                            var e = root.interactivityModel.get(i)
                                            if (e.itemTrigger !== trigger) continue
                                            if ((e.itemAction === "cue" && e.itemCommand === "jump") ||
                                                (e.itemAction === "else" && e.itemCommand === "jump")) {
                                                currentIndex = revertIdx; return
                                            }
                                        }
                                    } else if (newAction === "else") {
                                        var hasIf = false
                                        for (var i = 0; i < root.interactivityModel.count; i++) {
                                            if (i === itemIdx) continue
                                            var e = root.interactivityModel.get(i)
                                            if (e.itemTrigger !== trigger) continue
                                            if (e.itemAction === "else" || (e.itemAction === "cue" && e.itemCommand === "jump")) {
                                                currentIndex = revertIdx; return
                                            }
                                            if (e.itemAction === "if") hasIf = true
                                        }
                                        if (!hasIf) { currentIndex = revertIdx; return }
                                    }
                                    root.interactivityModel.setProperty(itemIdx, "itemAction", newAction)
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
                                    height: actionCombo.model.length * 22 + 2; padding: 1
                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                    contentItem: ListView { clip: true; model: actionCombo.delegateModel; currentIndex: actionCombo.currentIndex }
                                }
                            }

                            ComboBox {
                                id: condVarCombo
                                visible: itemAction === "if"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 26
                                model: {
                                    var names = []
                                    for (var i = 0; i < root.variablesModel.count; i++) {
                                        var n = root.variablesModel.get(i).varName
                                        if (n !== "") names.push(n)
                                    }
                                    return names
                                }
                                currentIndex: {
                                    var v = itemConditionVar
                                    if (!v || v === "") return 0
                                    for (var i = 0; i < root.variablesModel.count; i++) {
                                        if (root.variablesModel.get(i).varName === v) return i
                                    }
                                    return 0
                                }
                                onActivated: function(idx) {
                                    var itemIdx = interactivityDelegate.listIdx
                                    var varName = root.variablesModel.get(idx).varName
                                    var varType = root.variablesModel.get(idx).varType
                                    root.interactivityModel.setProperty(itemIdx, "itemConditionVar", varName)
                                    var op = root.interactivityModel.get(itemIdx).itemConditionOp
                                    if (varType !== "number" && (op === ">" || op === "<"))
                                        root.interactivityModel.setProperty(itemIdx, "itemConditionOp", "is")
                                    root.interactivityModel.setProperty(itemIdx, "itemConditionVal", "")
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
                                    height: Math.min(condVarCombo.model.length * 20 + 2, 102); padding: 1
                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                    contentItem: ListView { clip: true; model: condVarCombo.delegateModel; currentIndex: condVarCombo.currentIndex }
                                }
                            }

                            ComboBox {
                                id: condOpCombo
                                visible: itemAction === "if"
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 26
                                model: interactivityDelegate.condVarType === "number" ? ["is","not",">","<"] : ["is","not"]
                                currentIndex: Math.max(0, model.indexOf(itemConditionOp || "is"))
                                onActivated: function(idx) {
                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemConditionOp", model[idx])
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
                                    height: (interactivityDelegate.condVarType === "number" ? 4 : 2) * 20 + 2; padding: 1
                                    background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                    contentItem: ListView { clip: true; model: condOpCombo.delegateModel; currentIndex: condOpCombo.currentIndex }
                                }
                            }

                            Item {
                                visible: itemAction === "if"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 26

                                Rectangle {
                                    anchors.fill: parent
                                    visible: interactivityDelegate.condVarType === "text"
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                        text: interactivityDelegate.condVarType === "text" ? (itemConditionVal || "") : ""
                                        Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                        onEditingFinished: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemConditionVal", text)
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: interactivityDelegate.condVarType === "number"
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                        validator: DoubleValidator {}
                                        text: interactivityDelegate.condVarType === "number" ? (itemConditionVal || "") : ""
                                        Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                        onEditingFinished: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemConditionVal", text)
                                    }
                                }
                                ComboBox {
                                    id: boolValCombo
                                    anchors.fill: parent
                                    visible: interactivityDelegate.condVarType === "true or false"
                                    model: ["true", "false"]
                                    currentIndex: (itemConditionVal === "false") ? 1 : 0
                                    onActivated: function(idx) {
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemConditionVal", idx === 0 ? "true" : "false")
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
                                        contentItem: ListView { clip: true; model: boolValCombo.delegateModel; currentIndex: boolValCombo.currentIndex }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: interactivityDelegate.condVarType === ""
                                    color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                }
                            }

                            ComboBox {
                                id: commandCombo
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 26
                                model: {
                                    var _cnt = root.interactivityModel.count
                                    var tab = root.currentTab
                                    for (var i = 0; i < _cnt; i++) {
                                        if (i === interactivityDelegate.listIdx) continue
                                        var e = root.interactivityModel.get(i)
                                        if (e.itemTrigger !== tab) continue
                                        if ((e.itemAction === "cue" || e.itemAction === "else") && e.itemCommand === "jump")
                                            return ["sound", "video", "update", "transport"]
                                    }
                                    return ["jump", "sound", "video", "update", "transport"]
                                }
                                currentIndex: {
                                    var idx = model.indexOf(itemCommand)
                                    return idx < 0 ? 0 : idx
                                }
                                onActivated: function(idx) {
                                    var cmd = commandCombo.model[idx]
                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemCommand", cmd)
                                    if (cmd === "update" && itemUpdateVar === "") {
                                        for (var i = 0; i < root.variablesModel.count; i++) {
                                            var n = root.variablesModel.get(i).varName
                                            if (n !== "") {
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateVar", n)
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
                                    contentItem: ListView { clip: true; model: commandCombo.delegateModel; currentIndex: commandCombo.currentIndex }
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
                                property bool toggled: root.scenePickerButtons.interactivityPickerOpen
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
                                        root.scenePickerButtons.interactivityPickerTargetIdx = interactivityDelegate.listIdx
                                        root.scenePickerButtons.interactivityPickerModel = root.interactivityModel
                                        root.scenePickerButtons.interactivityPickerOpen = !root.scenePickerButtons.interactivityPickerOpen
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
                                        color: isActive ? "white" : "transparent"
                                        border.color: "white"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Image {
                                            id: transIcon
                                            anchors.centerIn: parent
                                            width: Math.round(parent.height * 0.72)
                                            height: width
                                            source: "icons/" + modelData.icon + ".svg"
                                            fillMode: Image.PreserveAspectFit
                                            visible: false
                                        }
                                        ColorOverlay {
                                            anchors.fill: transIcon
                                            source: transIcon
                                            color: isActive ? "#477B78" : "white"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemTransition", modelData.key)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: (itemCommand === "jump" && itemTransition !== "cut" && itemTransition !== "look") ? 22 : 0
                            visible: itemCommand === "jump" && itemTransition !== "cut" && itemTransition !== "look"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 6

                                Text {
                                    text: "speed"; font.pixelSize: 10; color: "#aaa"
                                    Layout.preferredHeight: 22
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Slider {
                                    id: transSpeedSlider
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
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemTransitionSpeed", rounded)
                                        transSpeedField.text = rounded.toFixed(1)
                                    }
                                    background: Rectangle {
                                        x: transSpeedSlider.leftPadding
                                        y: transSpeedSlider.topPadding + transSpeedSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 200; implicitHeight: 4
                                        width: transSpeedSlider.availableWidth; height: 4
                                        radius: 2; color: "#333"
                                        Rectangle {
                                            width: transSpeedSlider.visualPosition * parent.width
                                            height: parent.height; color: "#5DA9A4"; radius: 2
                                        }
                                    }
                                    handle: Rectangle {
                                        x: transSpeedSlider.leftPadding + transSpeedSlider.visualPosition * (transSpeedSlider.availableWidth - width)
                                        y: transSpeedSlider.topPadding + transSpeedSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 12; implicitHeight: 12; radius: 6
                                        color: transSpeedSlider.pressed ? "#80cfff" : "#5DA9A4"
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 22
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        id: transSpeedField
                                        anchors.left: parent.left; anchors.right: speedSuffix.left
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
                                            root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemTransitionSpeed", speed)
                                            transSpeedSlider.value = speed <= 2.0 ? speed / 4.0 : 0.5 + (speed - 2.0) / 16.0
                                        }
                                    }
                                    Text {
                                        id: speedSuffix
                                        anchors.right: parent.right; anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "sec"; font.pixelSize: 10; color: "#aaa"
                                    }
                                }

                                Repeater {
                                    model: ["left", "up", "down", "right"]
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        visible: itemTransition === "push"
                                        radius: 4
                                        property bool isActive: itemPushDirection === modelData
                                        color: isActive ? "white" : "transparent"
                                        border.color: "white"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Image {
                                            id: pushDirIcon
                                            anchors.centerIn: parent
                                            width: 14; height: 14
                                            source: "icons/" + modelData + ".svg"
                                            fillMode: Image.PreserveAspectFit
                                            visible: false
                                        }
                                        ColorOverlay {
                                            anchors.fill: pushDirIcon
                                            source: pushDirIcon
                                            color: isActive ? "#477B78" : "white"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemPushDirection", modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: (itemCommand === "jump" && itemTransition === "wipe") ? 22 : 0
                            visible: itemCommand === "jump" && itemTransition === "wipe"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4

                                Text {
                                    text: "feather"; font.pixelSize: 10; color: "#aaa"
                                    Layout.preferredHeight: 22
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Slider {
                                    id: wipeFeatherSlider
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    from: 0.0; to: 0.5; stepSize: 0
                                    Component.onCompleted: value = itemWipeFeather || 0.0
                                    onMoved: {
                                        var f = Math.round(value * 1000) / 1000
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemWipeFeather", f)
                                        wipeFeatherField.text = Math.round(f * 200).toString()
                                    }
                                    background: Rectangle {
                                        x: wipeFeatherSlider.leftPadding
                                        y: wipeFeatherSlider.topPadding + wipeFeatherSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 200; implicitHeight: 4
                                        width: wipeFeatherSlider.availableWidth; height: 4
                                        radius: 2; color: "#333"
                                        Rectangle {
                                            width: wipeFeatherSlider.visualPosition * parent.width
                                            height: parent.height; color: "#5DA9A4"; radius: 2
                                        }
                                    }
                                    handle: Rectangle {
                                        x: wipeFeatherSlider.leftPadding + wipeFeatherSlider.visualPosition * (wipeFeatherSlider.availableWidth - width)
                                        y: wipeFeatherSlider.topPadding + wipeFeatherSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 12; implicitHeight: 12; radius: 6
                                        color: wipeFeatherSlider.pressed ? "#80cfff" : "#5DA9A4"
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 22
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                    TextInput {
                                        id: wipeFeatherField
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                        validator: IntValidator { bottom: 0; top: 100 }
                                        Component.onCompleted: text = Math.round((itemWipeFeather || 0.0) * 200).toString()
                                        Keys.onReturnPressed: focus = false
                                        Keys.onEscapePressed: focus = false
                                        onEditingFinished: {
                                            var pct = Math.min(100, Math.max(0, parseInt(text) || 0))
                                            text = pct.toString()
                                            var f = Math.round(pct / 200 * 1000) / 1000
                                            root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemWipeFeather", f)
                                            wipeFeatherSlider.value = f
                                        }
                                    }
                                }

                                Repeater {
                                    model: ["left", "up", "down", "right"]
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: 4
                                        property bool isActive: itemWipeDirection === modelData
                                        color: isActive ? "white" : "transparent"
                                        border.color: "white"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Image {
                                            id: dirIcon
                                            anchors.centerIn: parent
                                            width: 14; height: 14
                                            source: "icons/" + modelData + ".svg"
                                            fillMode: Image.PreserveAspectFit
                                            visible: false
                                        }
                                        ColorOverlay {
                                            anchors.fill: dirIcon
                                            source: dirIcon
                                            color: isActive ? "#477B78" : "white"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemWipeDirection", modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: (itemCommand === "jump" && itemTransition === "look") ? 126 : 0
                            visible: itemCommand === "jump" && itemTransition === "look"
                            clip: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true; height: 22; spacing: 6
                                        Text { text: "speed"; font.pixelSize: 10; color: "#aaa"; Layout.preferredHeight: 22; verticalAlignment: Text.AlignVCenter }
                                        Slider {
                                            id: lookSpeedSlider
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            from: 0; to: 1; stepSize: 0
                                            Component.onCompleted: {
                                                var s = itemTransitionSpeed || 0.4
                                                value = s <= 2.0 ? s / 4.0 : 0.5 + (s - 2.0) / 16.0
                                            }
                                            onMoved: {
                                                var speed = value <= 0.5 ? value * 4.0 : 2.0 + (value - 0.5) * 16.0
                                                var rounded = Math.round(speed * 100) / 100
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemTransitionSpeed", rounded)
                                                lookSpeedField.text = rounded.toFixed(1)
                                            }
                                            background: Rectangle {
                                                x: lookSpeedSlider.leftPadding; y: lookSpeedSlider.topPadding + lookSpeedSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 4; width: lookSpeedSlider.availableWidth; height: 4; radius: 2; color: "#333"
                                                Rectangle { width: lookSpeedSlider.visualPosition * parent.width; height: parent.height; color: "#5DA9A4"; radius: 2 }
                                            }
                                            handle: Rectangle {
                                                x: lookSpeedSlider.leftPadding + lookSpeedSlider.visualPosition * (lookSpeedSlider.availableWidth - width)
                                                y: lookSpeedSlider.topPadding + lookSpeedSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12; implicitHeight: 12; radius: 6; color: lookSpeedSlider.pressed ? "#80cfff" : "#5DA9A4"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 52; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookSpeedField
                                                anchors.left: parent.left; anchors.right: lookSpeedSec.left
                                                anchors.leftMargin: 4; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: DoubleValidator { bottom: 0.0; top: 10.0 }
                                                Component.onCompleted: text = (itemTransitionSpeed || 0.4).toFixed(1)
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var speed = Math.min(10.0, Math.max(0.0, parseFloat(text) || 0.0))
                                                    text = speed.toFixed(1)
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemTransitionSpeed", speed)
                                                    lookSpeedSlider.value = speed <= 2.0 ? speed / 4.0 : 0.5 + (speed - 2.0) / 16.0
                                                }
                                            }
                                            Text { id: lookSpeedSec; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "sec"; font.pixelSize: 10; color: "#aaa" }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; height: 22; spacing: 6
                                        Text { text: "fov"; font.pixelSize: 10; color: "#aaa"; Layout.preferredHeight: 22; verticalAlignment: Text.AlignVCenter }
                                        Slider {
                                            id: lookFovSlider
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            from: 10; to: 75; stepSize: 0
                                            Component.onCompleted: value = itemLookFovMM || 24.0
                                            onMoved: {
                                                var v = Math.round(value * 10) / 10
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookFovMM", v)
                                                lookFovField.text = Math.round(v).toString()
                                            }
                                            background: Rectangle {
                                                x: lookFovSlider.leftPadding; y: lookFovSlider.topPadding + lookFovSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 4; width: lookFovSlider.availableWidth; height: 4; radius: 2; color: "#333"
                                                Rectangle { width: lookFovSlider.visualPosition * parent.width; height: parent.height; color: "#5DA9A4"; radius: 2 }
                                            }
                                            handle: Rectangle {
                                                x: lookFovSlider.leftPadding + lookFovSlider.visualPosition * (lookFovSlider.availableWidth - width)
                                                y: lookFovSlider.topPadding + lookFovSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12; implicitHeight: 12; radius: 6; color: lookFovSlider.pressed ? "#80cfff" : "#5DA9A4"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 46; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookFovField
                                                anchors.left: parent.left; anchors.right: lookFovMmLabel.left
                                                anchors.leftMargin: 4; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: IntValidator { bottom: 10; top: 75 }
                                                Component.onCompleted: text = Math.round(itemLookFovMM || 24).toString()
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var v = Math.min(75, Math.max(10, parseInt(text) || 24))
                                                    text = v.toString()
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookFovMM", v)
                                                    lookFovSlider.value = v
                                                }
                                            }
                                            Text { id: lookFovMmLabel; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "mm"; font.pixelSize: 10; color: "#aaa" }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; height: 22; spacing: 6
                                        Text { text: "overshoot"; font.pixelSize: 10; color: "#aaa"; Layout.preferredHeight: 22; verticalAlignment: Text.AlignVCenter }
                                        Slider {
                                            id: lookOvershootSlider
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            from: 0.0; to: 3.0; stepSize: 0
                                            Component.onCompleted: value = (itemLookOvershoot !== undefined ? itemLookOvershoot : 1.0)
                                            onMoved: {
                                                var v = Math.round(value * 100) / 100
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookOvershoot", v)
                                                lookOvershootField.text = v.toFixed(2)
                                            }
                                            background: Rectangle {
                                                x: lookOvershootSlider.leftPadding; y: lookOvershootSlider.topPadding + lookOvershootSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 4; width: lookOvershootSlider.availableWidth; height: 4; radius: 2; color: "#333"
                                                Rectangle { width: lookOvershootSlider.visualPosition * parent.width; height: parent.height; color: "#5DA9A4"; radius: 2 }
                                            }
                                            handle: Rectangle {
                                                x: lookOvershootSlider.leftPadding + lookOvershootSlider.visualPosition * (lookOvershootSlider.availableWidth - width)
                                                y: lookOvershootSlider.topPadding + lookOvershootSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12; implicitHeight: 12; radius: 6; color: lookOvershootSlider.pressed ? "#80cfff" : "#5DA9A4"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 46; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookOvershootField
                                                anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 4; anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: DoubleValidator { bottom: 0.0; top: 3.0 }
                                                Component.onCompleted: text = (itemLookOvershoot !== undefined ? itemLookOvershoot : 1.0).toFixed(2)
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var v = Math.min(3.0, Math.max(0.0, parseFloat(text) || 0.0))
                                                    text = v.toFixed(2)
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookOvershoot", v)
                                                    lookOvershootSlider.value = v
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; height: 22; spacing: 6
                                        Text { text: "shutter"; font.pixelSize: 10; color: "#aaa"; Layout.preferredHeight: 22; verticalAlignment: Text.AlignVCenter }
                                        Slider {
                                            id: lookShutterSlider
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            from: 0.0; to: 0.5; stepSize: 0
                                            Component.onCompleted: value = (itemLookShutter !== undefined ? itemLookShutter : 0.10)
                                            onMoved: {
                                                var v = Math.round(value * 1000) / 1000
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookShutter", v)
                                                lookShutterField.text = v.toFixed(2)
                                            }
                                            background: Rectangle {
                                                x: lookShutterSlider.leftPadding; y: lookShutterSlider.topPadding + lookShutterSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 200; implicitHeight: 4; width: lookShutterSlider.availableWidth; height: 4; radius: 2; color: "#333"
                                                Rectangle { width: lookShutterSlider.visualPosition * parent.width; height: parent.height; color: "#5DA9A4"; radius: 2 }
                                            }
                                            handle: Rectangle {
                                                x: lookShutterSlider.leftPadding + lookShutterSlider.visualPosition * (lookShutterSlider.availableWidth - width)
                                                y: lookShutterSlider.topPadding + lookShutterSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12; implicitHeight: 12; radius: 6; color: lookShutterSlider.pressed ? "#80cfff" : "#5DA9A4"
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 46; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookShutterField
                                                anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 4; anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: DoubleValidator { bottom: 0.0; top: 0.5 }
                                                Component.onCompleted: text = (itemLookShutter !== undefined ? itemLookShutter : 0.10).toFixed(2)
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var v = Math.min(0.5, Math.max(0.0, parseFloat(text) || 0.0))
                                                    text = v.toFixed(2)
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookShutter", v)
                                                    lookShutterSlider.value = v
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; height: 22; spacing: 4
                                        Text { text: "yaw"; font.pixelSize: 10; color: "#aaa"; verticalAlignment: Text.AlignVCenter }
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookYawField
                                                anchors.left: parent.left; anchors.right: lookYawDeg.left
                                                anchors.leftMargin: 4; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: DoubleValidator { bottom: -9999; top: 9999 }
                                                Component.onCompleted: text = (itemLookYaw !== undefined ? itemLookYaw : 90.0).toFixed(1)
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var v = parseFloat(text) || 0.0
                                                    text = v.toFixed(1)
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookYaw", v)
                                                }
                                            }
                                            Text { id: lookYawDeg; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "°"; font.pixelSize: 10; color: "#aaa" }
                                        }
                                        Text { text: "pitch"; font.pixelSize: 10; color: "#aaa"; verticalAlignment: Text.AlignVCenter }
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 22
                                            color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                            TextInput {
                                                id: lookPitchField
                                                anchors.left: parent.left; anchors.right: lookPitchDeg.left
                                                anchors.leftMargin: 4; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
                                                color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                                validator: DoubleValidator { bottom: -9999; top: 9999 }
                                                Component.onCompleted: text = (itemLookPitch !== undefined ? itemLookPitch : 0.0).toFixed(1)
                                                Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                                onEditingFinished: {
                                                    var v = parseFloat(text) || 0.0
                                                    text = v.toFixed(1)
                                                    root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookPitch", v)
                                                }
                                            }
                                            Text { id: lookPitchDeg; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "°"; font.pixelSize: 10; color: "#aaa" }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 76
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 4
                                    property bool lookPickerBack: false

                                    RowLayout {
                                        Layout.preferredWidth: 76; height: 16; spacing: 4
                                        Repeater {
                                            model: [{ label: "front", back: false }, { label: "back", back: true }]
                                            delegate: Rectangle {
                                                Layout.fillWidth: true; Layout.preferredHeight: 16; radius: 4
                                                property bool isActive: parent.parent.lookPickerBack === modelData.back
                                                color: isActive ? "white" : "transparent"
                                                border.color: "white"; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.label; font.pixelSize: 9
                                                    color: parent.isActive ? "#477B78" : "white"
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: parent.parent.parent.lookPickerBack = modelData.back
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 68; Layout.preferredHeight: 68
                                        Layout.alignment: Qt.AlignHCenter
                                        ShaderEffect {
                                            anchors.fill: parent
                                            fragmentShader: "lookpicker.frag.qsb"
                                            property real yaw:   itemLookYaw   !== undefined ? itemLookYaw   : 90.0
                                            property real pitch: itemLookPitch || 0.0
                                            property real fovMM: itemLookFovMM || 24.0
                                            property real back:  parent.parent.lookPickerBack ? 1.0 : 0.0
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onPressed:         lookPickerMouse(mouseX, mouseY)
                                            onPositionChanged: if (pressed) lookPickerMouse(mouseX, mouseY)
                                            function lookPickerMouse(mx, my) {
                                                var cx = 34.0, cy = 34.0
                                                var nx = (mx - cx) / cx
                                                var ny = (my - cy) / cy
                                                var r = Math.sqrt(nx * nx + ny * ny)
                                                if (r > 1.0) { nx /= r; ny /= r; r = 1.0 }
                                                var z  = Math.sqrt(Math.max(0.0, 1.0 - r * r))
                                                var lx = nx, ly = -ny
                                                var lz = parent.parent.lookPickerBack ? -z : z
                                                var newYaw   = Math.round(Math.atan2(lx, lz) * 1800.0 / Math.PI) / 10
                                                var absCosy  = Math.sqrt(ly * ly + lz * lz)
                                                var sinPitch = absCosy > 0.0001 ? ly / (lz >= 0 ? absCosy : -absCosy) : 0.0
                                                var newPitch = Math.round(Math.asin(Math.max(-1.0, Math.min(1.0, sinPitch))) * 1800.0 / Math.PI) / 10
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookYaw",   newYaw)
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookPitch", newPitch)
                                                lookYawField.text   = newYaw.toFixed(1)
                                                lookPitchField.text = newPitch.toFixed(1)
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.preferredWidth: 76; height: 16; spacing: 4
                                        Repeater {
                                            model: [
                                                { icon: "left",  yaw: -90.0, pitch:   0.0 },
                                                { icon: "up",    yaw:   0.0, pitch:  90.0 },
                                                { icon: "down",  yaw:   0.0, pitch: -90.0 },
                                                { icon: "right", yaw:  90.0, pitch:   0.0 }
                                            ]
                                            delegate: Rectangle {
                                                Layout.preferredWidth: 16; Layout.preferredHeight: 16; radius: 4
                                                property bool isActive: Math.abs((itemLookYaw !== undefined ? itemLookYaw : 90.0) - modelData.yaw) < 0.6 &&
                                                                        Math.abs((itemLookPitch !== undefined ? itemLookPitch : 0.0) - modelData.pitch) < 0.6
                                                color: isActive ? "white" : "transparent"
                                                border.color: "white"; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Image {
                                                    id: lookDirIcon; anchors.centerIn: parent; width: 12; height: 12
                                                    source: "icons/" + modelData.icon + ".svg"; fillMode: Image.PreserveAspectFit; visible: false
                                                }
                                                ColorOverlay {
                                                    anchors.fill: lookDirIcon; source: lookDirIcon
                                                    color: isActive ? "#477B78" : "white"
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookYaw",   modelData.yaw)
                                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemLookPitch", modelData.pitch)
                                                        lookYawField.text   = modelData.yaw.toFixed(1)
                                                        lookPitchField.text = modelData.pitch.toFixed(1)
                                                    }
                                                }
                                            }
                                        }
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
                                    id: dropSoundIcon
                                    anchors.centerIn: parent
                                    width: 20; height: 20
                                    source: "icons/dropsound.svg"
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: dropSoundIcon
                                    source: dropSoundIcon
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
                                        soundFileDialog.targetIdx = interactivityDelegate.listIdx
                                        soundFileDialog.open()
                                    }
                                }
                                DropArea {
                                    anchors.fill: parent
                                    onDropped: drop => {
                                        if (drop.hasUrls)
                                            root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemSoundPath", drop.urls[0].toString())
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: itemCommand === "video" ? 26 : 0
                            visible: itemCommand === "video"

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4

                                Repeater {
                                    model: ["fill", "object"]
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 26
                                        radius: 4
                                        property bool isActive: itemVideoTarget === modelData
                                        color: isActive ? "white" : "transparent"
                                        border.color: "white"; border.width: 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.pixelSize: 9
                                            color: parent.isActive ? "black" : "white"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemVideoTarget", modelData)
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 4
                                    color: "black"

                                    Image {
                                        id: dropVideoIcon
                                        anchors.centerIn: parent
                                        width: 20; height: 20
                                        source: "icons/dropvideo.svg"
                                        fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: dropVideoIcon
                                        source: dropVideoIcon
                                        color: "#666"
                                        opacity: itemVideoPath !== "" ? 0.3 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    Text {
                                        anchors.fill: parent; anchors.margins: 4
                                        visible: itemVideoPath !== ""
                                        text: itemVideoPath.replace(/.*[\/\\]/, "")
                                        font.pixelSize: 10; color: "white"
                                        elide: Text.ElideMiddle
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            videoFileDialog.targetIdx = interactivityDelegate.listIdx
                                            videoFileDialog.open()
                                        }
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        onDropped: drop => {
                                            if (drop.hasUrls)
                                                root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemVideoPath", drop.urls[0].toString())
                                        }
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
                                    id: updateVarCombo
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 26
                                    model: {
                                        var names = []
                                        for (var i = 0; i < root.variablesModel.count; i++) {
                                            var n = root.variablesModel.get(i).varName
                                            if (n !== "") names.push(n)
                                        }
                                        return names
                                    }
                                    currentIndex: {
                                        var mdl = updateVarCombo.model
                                        for (var i = 0; i < mdl.length; i++) {
                                            if (mdl[i] === itemUpdateVar) return i
                                        }
                                        return 0
                                    }
                                    onActivated: function(idx) {
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateVar", updateVarCombo.model[idx])
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateOp", "=")
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
                                        height: Math.min(updateVarCombo.model.length, 6) * 22 + 2
                                        padding: 1
                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                        contentItem: ListView { clip: true; model: updateVarCombo.delegateModel; currentIndex: updateVarCombo.currentIndex }
                                    }
                                }

                                ComboBox {
                                    id: updateOpCombo
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 26
                                    model: interactivityDelegate.updateVarType === "number" ? ["=", "+", "-"] : ["="]
                                    currentIndex: Math.max(0, model.indexOf(itemUpdateOp))
                                    onActivated: function(idx) {
                                        root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateOp", updateOpCombo.model[idx])
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
                                        height: updateOpCombo.model.length * 22 + 2; padding: 1
                                        background: Rectangle { color: "#162020"; border.color: "white"; border.width: 1; radius: 4 }
                                        contentItem: ListView { clip: true; model: updateOpCombo.delegateModel; currentIndex: updateOpCombo.currentIndex }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 26

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: interactivityDelegate.updateVarType === "text"
                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                        TextInput {
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                            text: interactivityDelegate.updateVarType === "text" ? (itemUpdateVal || "") : ""
                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                            onEditingFinished: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateVal", text)
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: interactivityDelegate.updateVarType === "number"
                                        color: "transparent"; border.color: "white"; border.width: 1; radius: 4
                                        TextInput {
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 4; anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: "white"; font.pixelSize: 10; clip: true; selectByMouse: true
                                            validator: DoubleValidator {}
                                            text: interactivityDelegate.updateVarType === "number" ? (itemUpdateVal || "") : ""
                                            Keys.onReturnPressed: focus = false; Keys.onEscapePressed: focus = false
                                            onEditingFinished: root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateVal", text)
                                        }
                                    }
                                    ComboBox {
                                        id: updateBoolCombo
                                        anchors.fill: parent
                                        visible: interactivityDelegate.updateVarType === "true or false"
                                        model: ["true", "false"]
                                        currentIndex: (itemUpdateVal === "false") ? 1 : 0
                                        onActivated: function(idx) {
                                            root.interactivityModel.setProperty(interactivityDelegate.listIdx, "itemUpdateVal", idx === 0 ? "true" : "false")
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
                                            contentItem: ListView { clip: true; model: updateBoolCombo.delegateModel; currentIndex: updateBoolCombo.currentIndex }
                                        }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: interactivityDelegate.updateVarType === ""
                                        color: "transparent"; border.color: "#555"; border.width: 1; radius: 4
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 8 }
    }

    property string currentTab: "click"
}
