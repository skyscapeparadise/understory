import QtQuick 2.15
import Qt5Compat.GraphicalEffects

Item {
    id: cvRoot

    property var pressedButtons:    ({})
    property var selectedButtonData: null

    onVisibleChanged: if (!visible) selectedButtonData = null

    // Scale: fit 48×32 ps5 viewBox at 90% of the component
    readonly property real u:     Math.min(width * 0.90 / 48, height * 0.90 / 32)
    readonly property real bodyW: 48 * u
    readonly property real bodyH: 32 * u

    // cx/cy — center in 48×32 SVG space. bw/bh — hit zone size (scale already applied).
    readonly property var buttonDefs: [
        // ── Face buttons ────────────────────────────────────────────────────
        { t:"△", kc:"triangle", icon:"icons/ps5triangle.svg", cx:38.5, cy:7.5,  bw:3,    bh:3   },
        { t:"○", kc:"circle",   icon:"icons/ps5circle.svg",   cx:41.5, cy:10.5, bw:3,    bh:3   },
        { t:"✕", kc:"cross",    icon:"icons/ps5cross.svg",    cx:38.5, cy:13.5, bw:3,    bh:3   },
        { t:"□", kc:"square",   icon:"icons/ps5square.svg",   cx:35.5, cy:10.5, bw:3,    bh:3   },
        // ── D-pad (scale 1.5 baked in: bw/bh × 1.5) ────────────────────────
        { t:"↑", kc:"dpadup",    icon:"icons/ps5dpadup.svg",    cx:10.0, cy:6.9,  bw:3.0, bh:6.0 },
        { t:"↓", kc:"dpaddown",  icon:"icons/ps5dpaddown.svg",  cx:10.0, cy:13.4, bw:3.0, bh:6.0 },
        { t:"←", kc:"dpadleft",  icon:"icons/ps5dpadleft.svg",  cx:6.9,  cy:10.0, bw:6.0, bh:3.0 },
        { t:"→", kc:"dpadright", icon:"icons/ps5dpadright.svg", cx:13.4, cy:10.0, bw:6.0, bh:3.0 },
        // ── Shoulder bumpers ─────────────────────────────────────────────────
        { t:"L1", kc:"l1", icon:"icons/ps5l1.svg", cx:-1.0, cy:7.0, bw:7,    bh:3.5 },
        { t:"R1", kc:"r1", icon:"icons/ps5r1.svg", cx:49.0, cy:7.0, bw:7,    bh:3.5 },
        // ── Triggers ────────────────────────────────────────────────────────
        { t:"L2", kc:"l2", icon:"icons/ps5l2.svg", cx:-1.0, cy:3.0, bw:7,    bh:3.5 },
        { t:"R2", kc:"r2", icon:"icons/ps5r2.svg", cx:49.0, cy:3.0, bw:7,    bh:3.5 },
        // ── Center (touchpad scale 1.1 baked in: bw 14→15.4, bh 8→8.8) ─────
        { t:"touchpad", kc:"touchpad", icon:"icons/ps5touchpad.svg", cx:24.2, cy:6.5,  bw:15.4, bh:8.8 },
        { t:"options",  kc:"options",  icon:"icons/ps5options.svg",  cx:34.0, cy:5.0,  bw:2.5,  bh:4.5 },
    ]

    // ── Controller body ──────────────────────────────────────────────────────
    Item {
        id: controllerBody
        anchors.centerIn: parent
        width:  cvRoot.bodyW
        height: cvRoot.bodyH

        // sourceSize forces rasterization at display size — prevents pixelation when
        // stretching an SVG whose intrinsic size is only its 48×32 viewBox.
        Image {
            id: bgImg
            anchors.fill: parent
            source:       "icons/ps5.svg"
            fillMode:     Image.Stretch
            opacity:      0.18
            sourceSize.width:  Math.ceil(cvRoot.bodyW)
            sourceSize.height: Math.ceil(cvRoot.bodyH)
        }

        // ── Button overlays ──────────────────────────────────────────────────
        Repeater {
            model: cvRoot.buttonDefs

            delegate: Item {
                id: btnDelegate
                readonly property var  d:        modelData
                readonly property bool pressed:  cvRoot.pressedButtons[d.kc] === true
                readonly property bool selected: cvRoot.selectedButtonData !== null &&
                                                 cvRoot.selectedButtonData.kc === d.kc

                x:      (d.cx - d.bw * 0.5) * cvRoot.u
                y:      (d.cy - d.bh * 0.5) * cvRoot.u
                width:  d.bw * cvRoot.u
                height: d.bh * cvRoot.u

                Rectangle {
                    anchors.fill: parent
                    color:        "transparent"
                    border.width: parent.selected ? 2 : 0
                    border.color: "#5DA9A4"
                    radius: 3
                    Behavior on border.width { NumberAnimation { duration: 60 } }
                }

                Image {
                    id: btnIcon
                    anchors.fill:    parent
                    anchors.margins: 2
                    source:          d.icon
                    fillMode:        Image.PreserveAspectFit
                    visible:         false
                    sourceSize.width:  128
                    sourceSize.height: 128
                }

                ColorOverlay {
                    anchors.fill: btnIcon
                    source:       btnIcon
                    color:        parent.pressed ? "#5DA9A4" : "white"
                    opacity:      parent.pressed ? 1.0 : 0.35
                    Behavior on color   { ColorAnimation  { duration: 80 } }
                    Behavior on opacity { NumberAnimation { duration: 80 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: cvRoot.selectedButtonData =
                        (cvRoot.selectedButtonData !== null &&
                         cvRoot.selectedButtonData.kc === d.kc) ? null : d
                }
            }
        }
    }
}
