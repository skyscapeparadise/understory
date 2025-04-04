import QtQuick 2.15
import QtQuick.Window 2.15
import QtMultimedia 5.15

Window {
	visible: true
	width: 1280
	height: 720
	title: qsTr("Intro Video")

	MediaPlayer {
		id: mediaPlayer
		source: "intro.mp4"
		autoPlay: true
	}

	VideoOutput {
		anchors.fill: parent
		source: mediaPlayer
		fillMode: VideoOutput.PreserveAspectFit
	}
}