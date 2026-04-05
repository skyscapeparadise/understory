# understory
#
# a multimedia experience engine
#
# Copyright (C) 2025-2026 Rain Multimedia LLC
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
# USA

import sys

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

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
