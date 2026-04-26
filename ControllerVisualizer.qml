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

    // Button definitions — cx/cy are center coords in ps5.svg 48×32 space.
    // bw/bh define the clickable hit zone in the same units.
    // Face button positions derived directly from ps5.svg path "M" coordinates.
    // D-pad positions derived from the cross-path span (x 5–15, y 5–15).
    // Shoulder/trigger positions estimated from controller body outline.
    readonly property var buttonDefs: [
        // ── Face buttons ────────────────────────────────────────────────────
        {t:"△", kc:"triangle", icon:"icons/ps5triangle.svg", cx:40,   cy:7.5,  bw:3,  bh:3},
        {t:"○", kc:"circle",   icon:"icons/ps5circle.svg",   cx:43,   cy:10.5, bw:3,  bh:3},
        {t:"✕", kc:"cross",    icon:"icons/ps5cross.svg",    cx:40,   cy:13.5, bw:3,  bh:3},
        {t:"□", kc:"square",   icon:"icons/ps5square.svg",   cx:37,   cy:10.5, bw:3,  bh:3},
        // ── D-pad ───────────────────────────────────────────────────────────
        {t:"↑", kc:"dpadup",    icon:"icons/ps5dpadup.svg",    cx:10,  cy:7,    bw:2,  bh:4},
        {t:"↓", kc:"dpaddown",  icon:"icons/ps5dpaddown.svg",  cx:10,  cy:13,   bw:2,  bh:4},
        {t:"←", kc:"dpadleft",  icon:"icons/ps5dpadleft.svg",  cx:7,   cy:10,   bw:4,  bh:2},
        {t:"→", kc:"dpadright", icon:"icons/ps5dpadright.svg", cx:13,  cy:10,   bw:4,  bh:2},
        // ── Shoulder bumpers ─────────────────────────────────────────────────
        {t:"L1", kc:"l1", icon:"icons/ps5l1.svg", cx:8,  cy:7,  bw:7, bh:3.5},
        {t:"R1", kc:"r1", icon:"icons/ps5r1.svg", cx:40, cy:7,  bw:7, bh:3.5},
        // ── Triggers ────────────────────────────────────────────────────────
        {t:"L2", kc:"l2", icon:"icons/ps5l2.svg", cx:8,  cy:3,  bw:7, bh:3.5},
        {t:"R2", kc:"r2", icon:"icons/ps5r2.svg", cx:40, cy:3,  bw:7, bh:3.5},
        // ── Center ──────────────────────────────────────────────────────────
        {t:"touchpad", kc:"touchpad", icon:"icons/ps5touchpad.svg", cx:24,   cy:16,   bw:14, bh:8},
        {t:"options",  kc:"options",  icon:"icons/ps5options.svg",  cx:29.5, cy:11.5, bw:2.5,bh:4.5},
    ]

    // ── Controller body ──────────────────────────────────────────────────────
    Item {
        id: controllerBody
        anchors.centerIn: parent
        width:  cvRoot.bodyW
        height: cvRoot.bodyH

        // ps5.svg silhouette — very dim, just for spatial reference
        Image {
            id: bgImg
            anchors.fill: parent
            source: "icons/ps5.svg"
            fillMode: Image.Stretch
            opacity: 0.18
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

                // Teal selection border
                Rectangle {
                    anchors.fill: parent
                    color:        "transparent"
                    border.width: parent.selected ? 2 : 0
                    border.color: "#5DA9A4"
                    radius: 3
                    Behavior on border.width { NumberAnimation { duration: 60 } }
                }

                // Icon (hidden — used as ColorOverlay source)
                Image {
                    id: btnIcon
                    anchors.fill:    parent
                    anchors.margins: 2
                    source:          d.icon
                    fillMode:        Image.PreserveAspectFit
                    visible:         false
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
