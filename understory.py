# understory
#
# a multimedia experience engine
#
# license: MIT
# Copyright 2025 Rain Multimedia LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation file(the “Software”), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
# CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
# OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import sys
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtCore import QUrl

versionnumber = "0.1"


app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()

# Set the version number as a context property
engine.rootContext().setContextProperty("versionnumber", versionnumber)


# Load QML file
qml_file = QUrl("understoryui.qml")
engine.load(qml_file)

# Quit if loading fails
if not engine.rootObjects():
	sys.exit(-1)

sys.exit(app.exec())