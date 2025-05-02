import QtQuick
import QtQuick.Window
import QtMultimedia
import QtQuick.Controls

Window {
	visible: true
	width: 400
	height: 400

	Item {
		id: item
		property color globalColor: "red"

		Button {
			text: "Change global color"
			onPressed: {
				item.globalColor = item.globalColor === Qt.color("red") ? "green" : "red"
			}
		}

		Button {
			x: 150
			text: "Clear rectangles"
			onPressed: repeater.model = 0
		}

		Repeater {
			id: repeater
			model: 5
			Rectangle {
				id: rect
				color: "red"
				width: 50
				height: 50
				x: (width + 2) * index + 2
				y: 100
				Component.onCompleted: {
					if (index % 2 === 0) {
						item.globalColorChanged.connect(() => {
							color = item.globalColor
						})
					}
				}
			}
		}
	}
}