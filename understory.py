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

import base64
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse, unquote

from PySide6.QtCore import QObject, QSize, QUrl, Slot, Signal, Property
from PySide6.QtGui import QGuiApplication, QFont, QFontDatabase, QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider


class ThumbnailProvider(QQuickImageProvider):
    """Serves scene thumbnail PNGs from the open story's SQLite DB.

    QML source: "image://thumbnails/<sceneId>?rev=<N>"
    The ?rev=N suffix busts Qt's image cache when a new thumbnail is saved.
    """

    def __init__(self, story_manager):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._mgr = story_manager

    def requestImage(self, id_str, size, requested_size):
        try:
            scene_id = int(id_str.split("?")[0])
            conn = self._mgr._conn
            if conn:
                row = conn.execute(
                    "SELECT thumbnail FROM scenes WHERE id = ?", (scene_id,)
                ).fetchone()
                if row and row[0]:
                    img = QImage()
                    img.loadFromData(bytes(row[0]))
                    size.setWidth(img.width())
                    size.setHeight(img.height())
                    return img
        except Exception as e:
            print(f"ThumbnailProvider.requestImage error: {e}")
        # Return a 1×1 transparent image so QML doesn't log a load error
        empty = QImage(1, 1, QImage.Format.Format_ARGB32)
        empty.fill(0)
        return empty


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

class StoryManager(QObject):
    """Owns the SQLite connection for the currently-open .story file."""

    storyChanged = Signal()

    def __init__(self):
        super().__init__()
        self._path = ""
        self._title = "new story"
        self._conn = None
        tmpl = Path(__file__).parent / "template.sql"
        self._template_sql = tmpl.read_text() if tmpl.exists() else ""
        self._recent_path = Path.home() / ".config" / "understory" / "recent.json"
        self._thumbs_dir = Path.home() / ".config" / "understory" / "thumbs"
        self._recent = []
        self._load_recent()

    # ------------------------------------------------------------------ helpers

    def _url_to_path(self, s):
        """Strip file:// prefix returned by QML FileDialog."""
        if s.startswith("file://"):
            return unquote(urlparse(s).path)
        return s

    def _close(self):
        if self._conn:
            self._conn.close()
            self._conn = None

    def _load_recent(self):
        try:
            with open(self._recent_path) as f:
                self._recent = json.load(f)
        except Exception:
            self._recent = []

    def _save_recent(self):
        try:
            self._recent_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self._recent_path, "w") as f:
                json.dump(self._recent, f)
        except Exception as e:
            print(f"StoryManager._save_recent: {e}")

    def _add_recent(self, path, title):
        self._recent = [r for r in self._recent if r["path"] != path]
        self._recent.insert(0, {
            "path": path,
            "title": title,
            "filename": Path(path).stem,
        })
        self._recent = self._recent[:8]
        self._save_recent()

    # ------------------------------------------------------------------ properties

    @Property(str, notify=storyChanged)
    def currentPath(self):
        return self._path

    @Property(str, notify=storyChanged)
    def storyTitle(self):
        return self._title

    @Property(bool, notify=storyChanged)
    def isOpen(self):
        return self._conn is not None

    @Property("QVariantList", notify=storyChanged)
    def recentStories(self):
        return self._recent

    # ------------------------------------------------------------------ story slots

    @Slot(str, result=bool)
    def newStory(self, path):
        path = self._url_to_path(path)
        try:
            self._close()
            conn = sqlite3.connect(path)
            conn.executescript(self._template_sql)
            conn.execute("INSERT INTO story (id, title) VALUES (1, 'new story')")
            conn.commit()
            self._conn = conn
            self._path = path
            self._title = "new story"
            self._add_recent(path, "new story")
            self.storyChanged.emit()
            return True
        except Exception as e:
            print(f"StoryManager.newStory: {e}")
            return False

    @Slot(str, result=bool)
    def openStory(self, path):
        path = self._url_to_path(path)
        try:
            self._close()
            conn = sqlite3.connect(path)
            # migrate: add thumbnail column if missing (older .story files)
            cols = {r[1] for r in conn.execute("PRAGMA table_info(scenes)")}
            if "thumbnail" not in cols:
                conn.execute("ALTER TABLE scenes ADD COLUMN thumbnail BLOB")
                conn.commit()
            row = conn.execute("SELECT title FROM story WHERE id = 1").fetchone()
            self._conn = conn
            self._path = path
            self._title = row[0] if row else "untitled"
            self._add_recent(path, self._title)
            self.storyChanged.emit()
            return True
        except Exception as e:
            print(f"StoryManager.openStory: {e}")
            return False

    @Slot(result=bool)
    def saveStory(self):
        if not self._conn:
            return False
        try:
            self._conn.commit()
            return True
        except Exception as e:
            print(f"StoryManager.saveStory: {e}")
            return False

    @Slot(str, result=bool)
    def saveStoryAs(self, path):
        path = self._url_to_path(path)
        if not self._conn:
            return False
        try:
            self._conn.commit()
            shutil.copy2(self._path, path)
            self._close()
            self._conn = sqlite3.connect(path)
            self._path = path
            self._add_recent(path, self._title)
            self.storyChanged.emit()
            return True
        except Exception as e:
            print(f"StoryManager.saveStoryAs: {e}")
            return False

    # ------------------------------------------------------------------ scene slots

    @Slot(result="QVariantList")
    def getScenes(self):
        if not self._conn:
            return []
        try:
            rows = self._conn.execute(
                "SELECT id, name, sort_order FROM scenes ORDER BY sort_order"
            ).fetchall()
            return [{"id": r[0], "name": r[1], "sortOrder": r[2]} for r in rows]
        except Exception as e:
            print(f"StoryManager.getScenes: {e}")
            return []

    @Slot(str, result=int)
    def createScene(self, name):
        if not self._conn:
            return -1
        try:
            row = self._conn.execute(
                "SELECT COALESCE(MAX(sort_order) + 1, 0) FROM scenes"
            ).fetchone()
            sort_order = row[0] if row else 0
            cur = self._conn.execute(
                "INSERT INTO scenes (name, sort_order) VALUES (?, ?)", (name, sort_order)
            )
            self._conn.commit()
            return cur.lastrowid
        except Exception as e:
            print(f"StoryManager.createScene: {e}")
            return -1

    @Slot(int, str)
    def updateSceneName(self, scene_id, name):
        if not self._conn:
            return
        try:
            self._conn.execute("UPDATE scenes SET name = ? WHERE id = ?", (name, scene_id))
            self._conn.commit()
        except Exception as e:
            print(f"StoryManager.updateSceneName: {e}")

    @Slot(int, result=str)
    def getSceneName(self, scene_id):
        if not self._conn:
            return ""
        try:
            row = self._conn.execute(
                "SELECT name FROM scenes WHERE id = ?", (scene_id,)
            ).fetchone()
            return row[0] if row else ""
        except Exception as e:
            print(f"StoryManager.getSceneName: {e}")
            return ""

    @Slot(int, str)
    def saveSceneElements(self, scene_id, elements_json):
        """Replaces all elements for a scene, storing full element state in meta."""
        if not self._conn:
            return
        try:
            data = json.loads(elements_json)
            self._conn.execute("DELETE FROM elements WHERE scene_id = ?", (scene_id,))
            for el in data:
                self._conn.execute(
                    "INSERT INTO elements (scene_id, type, name, x, y, w, h, z_order, meta)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        scene_id,
                        el["type"],
                        el.get("name", ""),
                        el["x"], el["y"], el["w"], el["h"],
                        el.get("z_order", 0),
                        json.dumps(el),
                    ),
                )
            self._conn.commit()
        except Exception as e:
            print(f"StoryManager.saveSceneElements: {e}")

    @Slot(int, result=str)
    def loadSceneElements(self, scene_id):
        """Returns a JSON array of element objects for the given scene."""
        if not self._conn:
            return "[]"
        try:
            rows = self._conn.execute(
                "SELECT meta FROM elements WHERE scene_id = ? ORDER BY z_order",
                (scene_id,),
            ).fetchall()
            return json.dumps([json.loads(r[0]) for r in rows])
        except Exception as e:
            print(f"StoryManager.loadSceneElements: {e}")
            return "[]"

    @Slot(int, str)
    def saveThumbnail(self, scene_id, file_url):
        """Store a PNG file as a BLOB thumbnail for the given scene."""
        if not self._conn:
            return
        try:
            path = unquote(urlparse(file_url).path) if file_url.startswith("file://") else file_url
            with open(path, "rb") as f:
                data = f.read()
            self._conn.execute(
                "UPDATE scenes SET thumbnail = ? WHERE id = ?", (data, scene_id)
            )
            self._conn.commit()
        except Exception as e:
            print(f"StoryManager.saveThumbnail: {e}")

    @Slot(str)
    def saveStoryThumbnail(self, file_url):
        """Copy a PNG to the per-story thumbnail cache and update recent.json.

        The cache file is keyed by MD5 of the current story path so it can be
        located without opening the .story file on next launch.
        """
        if not self._path:
            return
        try:
            src = unquote(urlparse(file_url).path) if file_url.startswith("file://") else file_url
            key = hashlib.md5(self._path.encode()).hexdigest()
            self._thumbs_dir.mkdir(parents=True, exist_ok=True)
            dest = self._thumbs_dir / f"{key}.png"
            shutil.copy2(src, dest)
            # Update the matching recent entry with the cache path
            for r in self._recent:
                if r["path"] == self._path:
                    r["thumbPath"] = str(dest)
                    break
            self._save_recent()
            self.storyChanged.emit()
        except Exception as e:
            print(f"StoryManager.saveStoryThumbnail: {e}")

    @Slot(int, result=str)
    def getThumbnailDataUrl(self, scene_id):
        """Return a data: URL (base64 PNG) for the scene thumbnail, or empty string."""
        if not self._conn:
            return ""
        try:
            row = self._conn.execute(
                "SELECT thumbnail FROM scenes WHERE id = ?", (scene_id,)
            ).fetchone()
            if row and row[0]:
                encoded = base64.b64encode(bytes(row[0])).decode()
                return f"data:image/png;base64,{encoded}"
            return ""
        except Exception as e:
            print(f"StoryManager.getThumbnailDataUrl: {e}")
            return ""

    @Slot(int, result=bool)
    def hasThumbnail(self, scene_id):
        """Returns True if the scene has a stored thumbnail BLOB."""
        if not self._conn:
            return False
        try:
            row = self._conn.execute(
                "SELECT thumbnail IS NOT NULL FROM scenes WHERE id = ?", (scene_id,)
            ).fetchone()
            return bool(row and row[0])
        except Exception as e:
            print(f"StoryManager.hasThumbnail: {e}")
            return False


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

# Expose story manager so QML can open/save/create .story files
storyManager = StoryManager()
engine.rootContext().setContextProperty("storyManager", storyManager)

# Register image provider so QML can load thumbnails via image://thumbnails/<sceneId>
thumbnailProvider = ThumbnailProvider(storyManager)
engine.addImageProvider("thumbnails", thumbnailProvider)


# Load QML file
qml_file = QUrl("understoryui.qml")
engine.load(qml_file)

# Quit if loading fails
if not engine.rootObjects():
    sys.exit(-1)

sys.exit(app.exec())
