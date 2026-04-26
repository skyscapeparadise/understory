import QtQuick 2.15

Item {
    id: kbRoot

    property var    pressedKeys:     ({})
    property string layout:          "mac"   // "mac" | "pc"
    property var    selectedKeyData: null

    // Full keyboard grid dimensions in "key units"
    readonly property real uW: 23.5
    readonly property real uH: 6.5

    readonly property real u: Math.min(
        width  * 0.95 / (uW + 1),
        height * 0.95 / (uH + 1)
    )
    readonly property real bodyW: u * (uW + 1)
    readonly property real bodyH: u * (uH + 1)
    readonly property real pad:   u * 0.5
    readonly property real g:     Math.max(2, u * 0.08)

    property var keyDefs: buildKeys(layout)

    onVisibleChanged: if (!visible) selectedKeyData = null

    function buildKeys(lyt) {
        var k = []
        var NP = 0x01000000

        // ── Function row  (y = 0) ───────────────────────────────────────────
        k.push({t:"Esc",   x:0,     y:0,   w:1,    h:1, kc:Qt.Key_Escape})
        k.push({t:"F1",    x:2,     y:0,   w:1,    h:1, kc:Qt.Key_F1})
        k.push({t:"F2",    x:3,     y:0,   w:1,    h:1, kc:Qt.Key_F2})
        k.push({t:"F3",    x:4,     y:0,   w:1,    h:1, kc:Qt.Key_F3})
        k.push({t:"F4",    x:5,     y:0,   w:1,    h:1, kc:Qt.Key_F4})
        k.push({t:"F5",    x:6.5,   y:0,   w:1,    h:1, kc:Qt.Key_F5})
        k.push({t:"F6",    x:7.5,   y:0,   w:1,    h:1, kc:Qt.Key_F6})
        k.push({t:"F7",    x:8.5,   y:0,   w:1,    h:1, kc:Qt.Key_F7})
        k.push({t:"F8",    x:9.5,   y:0,   w:1,    h:1, kc:Qt.Key_F8})
        k.push({t:"F9",    x:11,    y:0,   w:1,    h:1, kc:Qt.Key_F9})
        k.push({t:"F10",   x:12,    y:0,   w:1,    h:1, kc:Qt.Key_F10})
        k.push({t:"F11",   x:13,    y:0,   w:1,    h:1, kc:Qt.Key_F11})
        k.push({t:"F12",   x:14,    y:0,   w:1,    h:1, kc:Qt.Key_F12})
        k.push({t:"PrtSc", x:16,    y:0,   w:1,    h:1, kc:Qt.Key_Print})
        k.push({t:"ScrLk", x:17,    y:0,   w:1,    h:1, kc:Qt.Key_ScrollLock})
        k.push({t:"Pause", x:18,    y:0,   w:1,    h:1, kc:Qt.Key_Pause})

        // ── Number row  (y = 1.5) ───────────────────────────────────────────
        k.push({t:"`",     x:0,     y:1.5, w:1,    h:1, kc:Qt.Key_QuoteLeft})
        k.push({t:"1",     x:1,     y:1.5, w:1,    h:1, kc:Qt.Key_1})
        k.push({t:"2",     x:2,     y:1.5, w:1,    h:1, kc:Qt.Key_2})
        k.push({t:"3",     x:3,     y:1.5, w:1,    h:1, kc:Qt.Key_3})
        k.push({t:"4",     x:4,     y:1.5, w:1,    h:1, kc:Qt.Key_4})
        k.push({t:"5",     x:5,     y:1.5, w:1,    h:1, kc:Qt.Key_5})
        k.push({t:"6",     x:6,     y:1.5, w:1,    h:1, kc:Qt.Key_6})
        k.push({t:"7",     x:7,     y:1.5, w:1,    h:1, kc:Qt.Key_7})
        k.push({t:"8",     x:8,     y:1.5, w:1,    h:1, kc:Qt.Key_8})
        k.push({t:"9",     x:9,     y:1.5, w:1,    h:1, kc:Qt.Key_9})
        k.push({t:"0",     x:10,    y:1.5, w:1,    h:1, kc:Qt.Key_0})
        k.push({t:"-",     x:11,    y:1.5, w:1,    h:1, kc:Qt.Key_Minus})
        k.push({t:"=",     x:12,    y:1.5, w:1,    h:1, kc:Qt.Key_Equal})
        k.push({t:"⌫",    x:13,    y:1.5, w:2,    h:1, kc:Qt.Key_Backspace})
        k.push({t:"Ins",   x:16,    y:1.5, w:1,    h:1, kc:Qt.Key_Insert})
        k.push({t:"Home",  x:17,    y:1.5, w:1,    h:1, kc:Qt.Key_Home})
        k.push({t:"PgUp",  x:18,    y:1.5, w:1,    h:1, kc:Qt.Key_PageUp})
        k.push({t:"NmLk",  x:19.5,  y:1.5, w:1,    h:1, kc:Qt.Key_NumLock})
        k.push({t:"/",     x:20.5,  y:1.5, w:1,    h:1, kc:Qt.Key_Slash   |NP})
        k.push({t:"*",     x:21.5,  y:1.5, w:1,    h:1, kc:Qt.Key_Asterisk|NP})
        k.push({t:"−",     x:22.5,  y:1.5, w:1,    h:1, kc:Qt.Key_Minus   |NP})

        // ── QWERTY row  (y = 2.5) ───────────────────────────────────────────
        k.push({t:"Tab",   x:0,     y:2.5, w:1.5,  h:1, kc:Qt.Key_Tab})
        k.push({t:"Q",     x:1.5,   y:2.5, w:1,    h:1, kc:Qt.Key_Q})
        k.push({t:"W",     x:2.5,   y:2.5, w:1,    h:1, kc:Qt.Key_W})
        k.push({t:"E",     x:3.5,   y:2.5, w:1,    h:1, kc:Qt.Key_E})
        k.push({t:"R",     x:4.5,   y:2.5, w:1,    h:1, kc:Qt.Key_R})
        k.push({t:"T",     x:5.5,   y:2.5, w:1,    h:1, kc:Qt.Key_T})
        k.push({t:"Y",     x:6.5,   y:2.5, w:1,    h:1, kc:Qt.Key_Y})
        k.push({t:"U",     x:7.5,   y:2.5, w:1,    h:1, kc:Qt.Key_U})
        k.push({t:"I",     x:8.5,   y:2.5, w:1,    h:1, kc:Qt.Key_I})
        k.push({t:"O",     x:9.5,   y:2.5, w:1,    h:1, kc:Qt.Key_O})
        k.push({t:"P",     x:10.5,  y:2.5, w:1,    h:1, kc:Qt.Key_P})
        k.push({t:"[",     x:11.5,  y:2.5, w:1,    h:1, kc:Qt.Key_BracketLeft})
        k.push({t:"]",     x:12.5,  y:2.5, w:1,    h:1, kc:Qt.Key_BracketRight})
        k.push({t:"\\",    x:13.5,  y:2.5, w:1.5,  h:1, kc:Qt.Key_Backslash})
        k.push({t:"Del",   x:16,    y:2.5, w:1,    h:1, kc:Qt.Key_Delete})
        k.push({t:"End",   x:17,    y:2.5, w:1,    h:1, kc:Qt.Key_End})
        k.push({t:"PgDn",  x:18,    y:2.5, w:1,    h:1, kc:Qt.Key_PageDown})
        k.push({t:"7",     x:19.5,  y:2.5, w:1,    h:1, kc:Qt.Key_7|NP})
        k.push({t:"8",     x:20.5,  y:2.5, w:1,    h:1, kc:Qt.Key_8|NP})
        k.push({t:"9",     x:21.5,  y:2.5, w:1,    h:1, kc:Qt.Key_9|NP})
        k.push({t:"+",     x:22.5,  y:2.5, w:1,    h:2, kc:Qt.Key_Plus    |NP})

        // ── ASDF row  (y = 3.5) ─────────────────────────────────────────────
        k.push({t:"Caps",  x:0,     y:3.5, w:1.75, h:1, kc:Qt.Key_CapsLock})
        k.push({t:"A",     x:1.75,  y:3.5, w:1,    h:1, kc:Qt.Key_A})
        k.push({t:"S",     x:2.75,  y:3.5, w:1,    h:1, kc:Qt.Key_S})
        k.push({t:"D",     x:3.75,  y:3.5, w:1,    h:1, kc:Qt.Key_D})
        k.push({t:"F",     x:4.75,  y:3.5, w:1,    h:1, kc:Qt.Key_F})
        k.push({t:"G",     x:5.75,  y:3.5, w:1,    h:1, kc:Qt.Key_G})
        k.push({t:"H",     x:6.75,  y:3.5, w:1,    h:1, kc:Qt.Key_H})
        k.push({t:"J",     x:7.75,  y:3.5, w:1,    h:1, kc:Qt.Key_J})
        k.push({t:"K",     x:8.75,  y:3.5, w:1,    h:1, kc:Qt.Key_K})
        k.push({t:"L",     x:9.75,  y:3.5, w:1,    h:1, kc:Qt.Key_L})
        k.push({t:";",     x:10.75, y:3.5, w:1,    h:1, kc:Qt.Key_Semicolon})
        k.push({t:"'",     x:11.75, y:3.5, w:1,    h:1, kc:Qt.Key_Apostrophe})
        k.push({t:"↵",     x:12.75, y:3.5, w:2.25, h:1, kc:Qt.Key_Return})
        k.push({t:"4",     x:19.5,  y:3.5, w:1,    h:1, kc:Qt.Key_4|NP})
        k.push({t:"5",     x:20.5,  y:3.5, w:1,    h:1, kc:Qt.Key_5|NP})
        k.push({t:"6",     x:21.5,  y:3.5, w:1,    h:1, kc:Qt.Key_6|NP})

        // ── ZXCV row  (y = 4.5) ─────────────────────────────────────────────
        k.push({t:"Shift", x:0,     y:4.5, w:2.25, h:1, kc:Qt.Key_Shift})
        k.push({t:"Z",     x:2.25,  y:4.5, w:1,    h:1, kc:Qt.Key_Z})
        k.push({t:"X",     x:3.25,  y:4.5, w:1,    h:1, kc:Qt.Key_X})
        k.push({t:"C",     x:4.25,  y:4.5, w:1,    h:1, kc:Qt.Key_C})
        k.push({t:"V",     x:5.25,  y:4.5, w:1,    h:1, kc:Qt.Key_V})
        k.push({t:"B",     x:6.25,  y:4.5, w:1,    h:1, kc:Qt.Key_B})
        k.push({t:"N",     x:7.25,  y:4.5, w:1,    h:1, kc:Qt.Key_N})
        k.push({t:"M",     x:8.25,  y:4.5, w:1,    h:1, kc:Qt.Key_M})
        k.push({t:",",     x:9.25,  y:4.5, w:1,    h:1, kc:Qt.Key_Comma})
        k.push({t:".",     x:10.25, y:4.5, w:1,    h:1, kc:Qt.Key_Period})
        k.push({t:"/",     x:11.25, y:4.5, w:1,    h:1, kc:Qt.Key_Slash})
        k.push({t:"Shift", x:12.25, y:4.5, w:2.75, h:1, kc:Qt.Key_Shift})
        k.push({t:"↑",     x:17,    y:4.5, w:1,    h:1, kc:Qt.Key_Up})
        k.push({t:"1",     x:19.5,  y:4.5, w:1,    h:1, kc:Qt.Key_1|NP})
        k.push({t:"2",     x:20.5,  y:4.5, w:1,    h:1, kc:Qt.Key_2|NP})
        k.push({t:"3",     x:21.5,  y:4.5, w:1,    h:1, kc:Qt.Key_3|NP})
        k.push({t:"↵",     x:22.5,  y:4.5, w:1,    h:2, kc:Qt.Key_Return  |NP})

        // ── Modifier row  (y = 5.5) — layout-specific ───────────────────────
        if (lyt === "mac") {
            k.push({t:"ctrl", x:0,     y:5.5, w:1.25, h:1, kc:Qt.Key_Meta})
            k.push({t:"⌥",    x:1.25,  y:5.5, w:1.25, h:1, kc:Qt.Key_Alt})
            k.push({t:"⌘",    x:2.5,   y:5.5, w:1.5,  h:1, kc:Qt.Key_Control})
            k.push({t:"",     x:4.0,   y:5.5, w:7.0,  h:1, kc:Qt.Key_Space})
            k.push({t:"⌘",    x:11,    y:5.5, w:1.5,  h:1, kc:Qt.Key_Control})
            k.push({t:"⌥",    x:12.5,  y:5.5, w:1.25, h:1, kc:Qt.Key_Alt})
            k.push({t:"ctrl", x:13.75, y:5.5, w:1.25, h:1, kc:Qt.Key_Meta})
        } else {
            k.push({t:"Ctrl", x:0,     y:5.5, w:1.75, h:1, kc:Qt.Key_Control})
            k.push({t:"⊞",    x:1.75,  y:5.5, w:1.25, h:1, kc:Qt.Key_Meta})
            k.push({t:"Alt",  x:3,     y:5.5, w:1.25, h:1, kc:Qt.Key_Alt})
            k.push({t:"",     x:4.25,  y:5.5, w:6.25, h:1, kc:Qt.Key_Space})
            k.push({t:"Alt",  x:10.5,  y:5.5, w:1.25, h:1, kc:Qt.Key_Alt})
            k.push({t:"Fn",   x:11.75, y:5.5, w:1.25, h:1, kc:Qt.Key_unknown})
            k.push({t:"Ctrl", x:13,    y:5.5, w:2,    h:1, kc:Qt.Key_Control})
        }

        // Arrow cluster and numpad bottom row (same for both layouts)
        k.push({t:"←",     x:16,    y:5.5, w:1,    h:1, kc:Qt.Key_Left})
        k.push({t:"↓",     x:17,    y:5.5, w:1,    h:1, kc:Qt.Key_Down})
        k.push({t:"→",     x:18,    y:5.5, w:1,    h:1, kc:Qt.Key_Right})
        k.push({t:"0",     x:19.5,  y:5.5, w:2,    h:1, kc:Qt.Key_0      |NP})
        k.push({t:"·",     x:21.5,  y:5.5, w:1,    h:1, kc:Qt.Key_Period |NP})

        return k
    }

    // ── Layout toggle (top-left, mirrors networkBar position) ───────────────
    Row {
        anchors.top:         parent.top
        anchors.right:       parent.right
        anchors.topMargin:   8
        anchors.rightMargin: 8
        spacing: 4
        z: 10

        Repeater {
            model: ["mac", "pc"]

            delegate: Item {
                id: toggleBtn
                property bool active:  kbRoot.layout === modelData
                property bool hovered: false

                width:  Math.max(36, labelSizer.contentWidth + 24)
                height: 36

                Text { id: labelSizer; visible: false; text: modelData; font.pixelSize: 12 }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: toggleBtn.active ? "white" : "transparent"
                    border.width: 1
                    border.color: "white"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 12
                    color: toggleBtn.active ? "#1a1a1d" : "white"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: toggleBtn.hovered = true
                    onExited:  toggleBtn.hovered = false
                    onClicked: kbRoot.layout = modelData
                }
            }
        }
    }

    // ── Keyboard body ────────────────────────────────────────────────────────
    Rectangle {
        id: kbBody
        anchors.centerIn: parent
        width:  kbRoot.bodyW
        height: kbRoot.bodyH
        color:  "#101013"
        radius: kbRoot.u * 0.4

        Repeater {
            model: kbRoot.keyDefs

            delegate: Item {
                readonly property var  d:        modelData
                readonly property bool pressed:  kbRoot.pressedKeys[d.kc] === true
                readonly property bool selected: kbRoot.selectedKeyData !== null && kbRoot.selectedKeyData.kc === d.kc

                x:      kbRoot.pad + d.x * kbRoot.u + kbRoot.g * 0.5
                y:      kbRoot.pad + d.y * kbRoot.u + kbRoot.g * 0.5
                width:  d.w * kbRoot.u - kbRoot.g
                height: d.h * kbRoot.u - kbRoot.g

                Rectangle {
                    anchors.fill: parent
                    radius: kbRoot.u * 0.15
                    color:        parent.pressed ? "white" : "transparent"
                    border.width: parent.selected ? 2 : 1
                    border.color: parent.selected ? "#5DA9A4" : (parent.pressed ? "white" : "#666666")
                    Behavior on color        { ColorAnimation { duration: 60 } }
                    Behavior on border.color { ColorAnimation { duration: 60 } }
                }

                Text {
                    anchors.centerIn: parent
                    text:           d.t
                    font.pixelSize: Math.max(7, kbRoot.u * 0.28)
                    color:          parent.pressed ? "#5DA9A4" : "#999999"
                    Behavior on color { ColorAnimation { duration: 60 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: kbRoot.selectedKeyData = (kbRoot.selectedKeyData !== null && kbRoot.selectedKeyData.kc === d.kc) ? null : d
                }
            }
        }
    }
}
