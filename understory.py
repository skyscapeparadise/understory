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

import json
import re
import subprocess
import sys

from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtGui import QGuiApplication, QFont, QFontDatabase
from PySide6.QtQml import QQmlApplicationEngine


class ShaderInspector(QObject):
    """Parses QSB shader reflection data to expose custom uniforms to QML."""

    @Slot(str, result="QVariant")
    def inspectShader(self, path):
        if path.startswith("file://"):
            path = path[7:]
        try:
            result = subprocess.run(
                ["/Users/kady/Qt/6.9.0/macos/bin/qsb", "-d", path],
                capture_output=True, text=True, timeout=5,
            )
            output = result.stdout
        except Exception:
            return []

        idx = output.find("Reflection info: ")
        if idx == -1:
            return []

        json_start = output.index("{", idx)
        depth = 0
        json_end = json_start
        for i, c in enumerate(output[json_start:]):
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    json_end = json_start + i + 1
                    break

        try:
            info = json.loads(output[json_start:json_end])
        except Exception:
            return []

        # qt_Matrix and qt_Opacity are handled internally by Qt; skip them.
        # time and other user uniforms are returned so QML can handle them.
        BUILTINS = {"qt_Matrix", "qt_Opacity"}
        uniforms = []
        for block in info.get("uniformBlocks", []):
            for member in block.get("members", []):
                if member["name"] not in BUILTINS:
                    uniforms.append({"name": member["name"], "type": member["type"]})
        for sampler in info.get("combinedImageSamplers", []):
            uniforms.append({"name": sampler["name"], "type": "sampler2D"})
        return uniforms

versionnumber = "0.1"


app = QGuiApplication(sys.argv)

QFontDatabase.addApplicationFont("headings/MonaSans-VariableFont_wdth,wght.ttf")
QFontDatabase.addApplicationFont("headings/MonaSans-Italic-VariableFont_wdth,wght.ttf")
app.setFont(QFont("Mona Sans"))

engine = QQmlApplicationEngine()

# Set the version number as a context property
engine.rootContext().setContextProperty("versionnumber", versionnumber)

# Expose shader inspector so QML can detect uniforms from .frag.qsb files
shaderInspector = ShaderInspector()
engine.rootContext().setContextProperty("shaderInspector", shaderInspector)


# Load QML file
qml_file = QUrl("understoryui.qml")
engine.load(qml_file)

# Quit if loading fails
if not engine.rootObjects():
    sys.exit(-1)

sys.exit(app.exec())
