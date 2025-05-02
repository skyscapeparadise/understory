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
	
	property var xanimationduration: 0
	
	// animate any change to `width`
	Behavior on width {
		SequentialAnimation {
			NumberAnimation {
				duration: 1000
				easing.type: Easing.InOutQuad
			}
				
			ScriptAction {
				script:{
					if (sceneEditor2sceneMenu.windowSizeCompleteTrigger) {
						console.log("ScriptAction triggered")
						sceneEditor2sceneMenu.visible = true
						sceneEditor2sceneMenuPlayer.play()
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
					storyMenu.visible = true
					splashScreen.visible = false
					
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
			ListElement { placeholder: "" }  // now we have a 'placeholder' role and start with one cell
		}
		
		ScrollView {
			
			x: 29
			y: 28
			height: 398
			width: 900
			
			Behavior on opacity {
				NumberAnimation {
					duration: 1000  // 1 second
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
						width: 270; height: 150; radius: 30
						color: "transparent"; border.color: "white"; border.width: 4
						
						
		
						property bool hovered: false
						property bool isLast: index === projectsRectModel.count - 1
		
						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							onEntered:  hovered = true
							onExited:   hovered = false
							onClicked: {
								if (isLast) {
									projectsRectModel.append({})
								} else {
									console.log("object number " + index + " clicked!")
									story2sceneMenu.visible = true
									story2sceneMenuPlayer.play()
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
		
		GridLayout {
			id: storyMenuButtons
			x: 23; y: 449
			columns: 2
			rowSpacing: 4; columnSpacing: 4
		
			Repeater {
				model: [ "new story", "update", "settings", "credits" ]
				delegate: Rectangle {
					width: 138; height: 28
					radius: height/2
					color: "transparent"
					border.color: "white"; border.width: 2
		
					Text {
						anchors.centerIn: parent
						text: modelData
						color: "white"
						font.pixelSize: 14
					}
		
					MouseArea {
						anchors.fill: parent
						onClicked: console.log("button", modelData, "clicked!")
						hoverEnabled: true
						// you can also add hover‐state styling here
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
				horizontalAlignment: "AlignRight"
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
			ListElement { placeholder: "" }  // now we have a 'placeholder' role and start with one cell
		}
		
		ScrollView {
			
			x: 29
			y: 28
			height: 398
			width: 900
			
			Behavior on opacity {
				NumberAnimation {
					duration: 1000  // 1 second
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
						width: 270; height: 150; radius: 30
						color: "transparent"; border.color: "white"; border.width: 4
						
						
		
						property bool hovered: false
						property bool isLast: index === scenesRectModel.count - 1
		
						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							onEntered:  hovered = true
							onExited:   hovered = false
							onClicked: {
								if (isLast) {
									scenesRectModel.append({})
								} else {
									console.log("object number " + index + " clicked!")
									sceneMenu2sceneEditor.visible = true
									sceneMenu2sceneEditorPlayer.play()
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
		
		GridLayout {
			id: sceneMenuButtons
			x: 23
			y: 449
			columns: 2
			rowSpacing: 4; columnSpacing: 4
		
			Repeater {
				model: [ "new scene", "delete", "settings", "exit story" ]
				delegate: Rectangle {
					width: 138; height: 28
					radius: height/2
					color: "transparent"
					border.color: "white"; border.width: 2
		
					Text {
						anchors.centerIn: parent
						text: modelData
						color: "white"
						font.pixelSize: 14
					}
		
					MouseArea {
						anchors.fill: parent
						onClicked: {
							console.log("button", modelData, "clicked!")
							if (modelData === "exit story"){
								scene2storyMenu.visible = true
								scene2storyMenuPlayer.play()
							}
						}
						hoverEnabled: true
						// you can also add hover‐state styling here
					}
				}
			}
		}
		
		Rectangle {
			id: storyLogo2
			radius: 14
			//x: 123
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
			
			// scene content goes here
			
			Image {
				anchors.fill: parent
				source: "file:stairwell.jpg"
			}

		}
	
		Rectangle {
			width: 405
			height: 540
			anchors.right: parent.right
			// tool controls go here
			
			// 1) Base linear gradient
			Rectangle {
				anchors.fill: parent
				gradient: Gradient {
					GradientStop { position: 0.00; color: "#477B78" }
					GradientStop { position: 0.40; color: "#5DA9A4" }
					GradientStop { position: 0.70; color: "#2C4948" }
					GradientStop { position: 1.00; color: "#0B1D1D" }
				}
			}
			
			// 2+3) Top glow + vignette in one canvas
			Canvas {
				anchors.fill: parent
			
				onPaint: {
					var ctx = getContext("2d");
					ctx.reset();
					ctx.clearRect(0, 0, width, height);
			
					// A) top-center "glow"
					var cx = width * 0.5, cy = height * 0.15, r1 = width * 0.9;
					var glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, r1);
					glow.addColorStop(0.0, "#6DBFBA");
					glow.addColorStop(1.0, "rgba(0,0,0,0)");
					ctx.fillStyle = glow;
					ctx.fillRect(0, 0, width, height);
			
					// B) edge vignette
					var cx2 = width * 0.5, cy2 = height * 0.5, r2 = width;
					var vign = ctx.createRadialGradient(cx2, cy2, 0, cx2, cy2, r2);
					vign.addColorStop(0.5, "rgba(0,0,0,0)");
					vign.addColorStop(1.0, "rgba(0,0,0,0.7)");
					ctx.fillStyle = vign;
					ctx.fillRect(0, 0, width, height);
				}
			
				// re-draw if window is ever resized
				onWidthChanged: requestPaint()
				onHeightChanged: requestPaint()
			}
			
			// Scene Editor Tools
			
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
					rowSpacing: 8; columnSpacing: 8
				
					// track which tool is on (empty = none)
					property string selectedTool: ""
					// pick your active icon color here
					property color activeIconColor: "#477B78"
				
					Repeater {
						model: ["newarea","newtext","newimage","newvideo","newlink","undo","redo","destroy"]
				
						delegate: Item {
							id: buttonRoot
							width: 88; height: 88
				
							property bool hovered: false
							property bool toggled: buttonGrid.selectedTool === modelData
							property string iconSource: "icons/" + modelData + ".svg"
				
							// background + border
							Rectangle {
								anchors.fill: parent
								radius: 12
								color: toggled ? "white" : "transparent"
								border.width: 2
								border.color: hovered ? "#80cfff" : "white"
								Behavior on border.color { ColorAnimation { duration: 150 } }
							}
				
							// hidden base-SVG
							Image {
								id: svgIcon
								anchors.centerIn: parent
								width: 70; height: 70
								source: iconSource
								visible: false
							}
							// overlay to recolor it
							ColorOverlay {
								anchors.fill: svgIcon
								source: svgIcon
								color: toggled
									? buttonGrid.activeIconColor
									: "white"
								Behavior on color { ColorAnimation { duration: 150 } }
							}
				
							MouseArea {
								anchors.fill: parent
								hoverEnabled: true
				
								onClicked: {
									// click again to turn off
									buttonGrid.selectedTool =
										(buttonGrid.selectedTool === modelData)
										? ""
										: modelData
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
				rowSpacing: 4; columnSpacing: 4
			
				Repeater {
					model: [ "scene script", "settings", "save scene", "close scene" ]
					delegate: Rectangle {
						width: 138; height: 28
						radius: height/2
						color: "transparent"
						border.color: "white"; border.width: 2
			
						Text {
							anchors.centerIn: parent
							text: modelData
							color: "white"
							font.pixelSize: 14
						}
			
						MouseArea {
							anchors.fill: parent
							onClicked: {
								console.log("button", modelData, "clicked!")
								if (modelData === "close scene"){
									xanimationduration = 1000
									mainWindow.width = 960
									mainWindow.x = x + 275
									sceneEditor2sceneMenu.windowSizeCompleteTrigger = true
								}
							}
							hoverEnabled: true
							// you can also add hover‐state styling here
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
				border.width: 2
				anchors.bottom: parent.bottom
				anchors.bottomMargin: 86
				anchors.left: parent.left
				anchors.leftMargin: 14
				
				Rectangle {
					
					id: areaSettings
					visible: false
					height: parent.height
					width: parent.width
					radius: parent.radius
					color: "transparent"
				
					Item {
						
						id: areaSettingsHeading
						
						property string iconSource: "headings/area_heading.svg"
						anchors.top: parent.top
						anchors.topMargin: 20
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
					visible: false
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
							
							height: 20
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
					visible: false
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
							
							height: 20
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
					visible: false
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
							
							height: 20
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
					visible: true
					height: parent.height
					width: parent.width
					radius: parent.radius
					color: "transparent"
				
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
				
				
				
			}
			
			
			Item {
				id: navigationButton
				width: 88; height: 60
				anchors.bottom: parent.bottom; anchors.bottomMargin: 14
				anchors.left:   parent.left;   anchors.leftMargin: 14
			
				// 1) our own state
				property bool hovered: false
				property bool toggled: buttonGrid.selectedTool === "navigation"
			
				// 2) background + border
				Rectangle {
					anchors.fill: parent
					radius: 12
					color: navigationButton.toggled
						? "white"
						: "transparent"
					border.width: 2
					border.color: navigationButton.hovered
						? "#80cfff"
						: "white"
					Behavior on border.color { ColorAnimation { duration: 150 } }
				}
			
				// 3) icon (hidden base SVG + recolor overlay)
				Image {
					id: svgIcon
					anchors.centerIn: parent
					width: 50; height: 50
					fillMode: Image.PreserveAspectFit
					source: "icons/navigation.svg"
					visible: false
				}
				ColorOverlay {
					anchors.fill: svgIcon
					source: svgIcon
					color: navigationButton.toggled
						? buttonGrid.activeIconColor
						: "white"
					Behavior on color { ColorAnimation { duration: 150 } }
				}
			
				// 4) click + hover behavior
				MouseArea {
					anchors.fill: parent
					hoverEnabled: true
			
					onEntered: navigationButton.hovered = true
					onExited:  navigationButton.hovered = false
			
					onClicked: {
						// toggle the same selectedTool string
						buttonGrid.selectedTool =
							navigationButton.toggled
								? ""
								: "navigation"
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
					sceneMenu.visible = true
					story2sceneMenu.visible = false
					storyMenu.visible = false
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
					storyMenu.visible = true
					scene2storyMenu.visible = false
					sceneMenu.visible = false
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
					
					xanimationduration = 1000
					mainWindow.width = 1365
					mainWindow.x = x - 202
					sceneEditor.visible = true
					sceneMenu2sceneEditor.visible = false
					sceneMenu.visible = false
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
		
		property var windowSizeCompleteTrigger: false
		
		MediaPlayer {
			id: sceneEditor2sceneMenuPlayer
			source: "file:sceneeditor2scenemenu.mp4"
			autoPlay: false
			videoOutput: sceneEditor2sceneMenuVideoOutput
		
			onMediaStatusChanged: {
				if (mediaStatus === MediaPlayer.EndOfMedia) {
					
					sceneEditor.visible = false
					sceneEditor2sceneMenu.visible = false
					sceneMenu.visible = true
					sceneEditor2sceneMenu.windowSizeCompleteTrigger = false
				}
			}
		}
		
		VideoOutput {
			id: sceneEditor2sceneMenuVideoOutput
			anchors.fill: parent
		}
		
		
		
	}

}
