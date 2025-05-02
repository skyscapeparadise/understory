import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia

ApplicationWindow {
	visible: true
	width: 1280
	height: 720
	title: "Looping Video in Rectangle"

	Rectangle {
		anchors.fill: parent
		color: "#222" // Background color

		Rectangle {
			width: 960
			height: 540
			anchors.centerIn: parent
			color: "black" // Optional background behind the video

			Item {
			MediaPlayer {
				id: mediaplayer
				source: "intro.mp4"
				audioOutput: AudioOutput {}
				videoOutput: videoOutput
			}
			
			VideoOutput {
				id: videoOutput
				anchors.fill: parent
			}
			
			MouseArea {
				anchors.fill: parent
				onPressed: mediaplayer.play();
			}
		}
		}
	}
}