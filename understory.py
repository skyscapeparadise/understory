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
import ctypes
import hashlib
import json
import math
import queue as _queue
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import threading
from pathlib import Path
from urllib.parse import unquote, urlparse

from PySide6.QtCore import Property, QObject, QSize, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication, QImage
from PySide6.QtMultimedia import QAudioBufferOutput, QAudioFormat, QAudioSink

try:
    import numpy as _np

    _HAS_NUMPY = True
except Exception:
    _np = None
    _HAS_NUMPY = False
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider

try:
    from sdl3 import *
    _SDL3_AVAILABLE = True
except Exception:
    _SDL3_AVAILABLE = False

try:
    from hdr_viewport import HDRVideoBridge
except Exception:
    HDRVideoBridge = None

try:
    from hdr_viewport import compile_and_reflect_glsl
except Exception:
    compile_and_reflect_glsl = None

versionnumber = "0.4"


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
    """Parses shader reflection data to expose custom uniforms to QML.

    Two entirely separate reflection sources depending on shader format --
    matching Phase 7 Part 2's decision to run two fully parallel shader
    systems rather than unify them: legacy .qsb (Qt Shader Tools' own
    `qsb -d` dump, still used when native rendering is off, so old stories
    keep working unchanged) or native .frag/.vert GLSL (glslc + spirv-cross
    via hdr_viewport.compile_and_reflect_glsl, used when native rendering
    is on, in either color-space mode -- this is what actually drops the
    qsb requirement/licensing concern for shader elements going forward,
    not just moving where qsb gets invoked from)."""

    @Slot(str, result="QVariant")
    def inspectShader(self, path):
        if path.startswith("file://"):
            path = path[7:]
        lower = path.lower()
        if lower.endswith(".frag") or lower.endswith(".vert"):
            return self._inspectGlslShader(path)
        return self._inspectQsbShader(path)

    def _inspectGlslShader(self, path):
        if compile_and_reflect_glsl is None:
            return []
        stage_name = "vert" if path.lower().endswith(".vert") else "frag"
        entry = "vs_main" if stage_name == "vert" else "fs_main"
        try:
            _msl, reflection = compile_and_reflect_glsl(path, stage_name, entry)
        except Exception:
            return []
        uniforms = []
        for ubo in reflection.get("ubos", []):
            members = reflection.get("types", {}).get(ubo["type"], {}).get("members", [])
            for member in members:
                uniforms.append({"name": member["name"], "type": member["type"]})
        for texture in reflection.get("textures", []):
            uniforms.append({"name": texture["name"], "type": "sampler2D"})
        return uniforms

    def _inspectQsbShader(self, path):
        try:
            result = subprocess.run(
                ["/Users/kady/Qt/6.9.0/macos/bin/qsb", "-d", path],
                capture_output=True,
                text=True,
                timeout=5,
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


def _computeRmsLevel(buffer):
    """RMS level (0..1) from a QAudioBuffer's raw PCM. QML can't read sample
    data out of a QAudioBuffer itself, which is why this has to happen here."""
    if not buffer.isValid() or buffer.sampleCount() == 0:
        return 0.0
    try:
        raw = bytes(buffer.constData())
    except Exception:
        return 0.0
    if not raw:
        return 0.0

    sample_format = buffer.format().sampleFormat()
    try:
        if sample_format == QAudioFormat.SampleFormat.Int16:
            count = len(raw) // 2
            if count == 0:
                return 0.0
            samples = struct.unpack(f"<{count}h", raw[: count * 2])
            rms = math.sqrt(sum(s * s for s in samples) / count) / 32768.0
        elif sample_format == QAudioFormat.SampleFormat.UInt8:
            count = len(raw)
            samples = [b - 128 for b in raw]
            rms = math.sqrt(sum(s * s for s in samples) / count) / 128.0
        elif sample_format == QAudioFormat.SampleFormat.Int32:
            count = len(raw) // 4
            if count == 0:
                return 0.0
            samples = struct.unpack(f"<{count}i", raw[: count * 4])
            rms = math.sqrt(sum(s * s for s in samples) / count) / 2147483648.0
        elif sample_format == QAudioFormat.SampleFormat.Float:
            count = len(raw) // 4
            if count == 0:
                return 0.0
            samples = struct.unpack(f"<{count}f", raw[: count * 4])
            rms = math.sqrt(sum(s * s for s in samples) / count)
        else:
            return 0.0
    except Exception:
        return 0.0

    return min(1.0, rms)


_SAMPLE_DTYPES = {
    QAudioFormat.SampleFormat.Int16: ("int16", "h", -32768, 32767),
    QAudioFormat.SampleFormat.Int32: ("int32", "i", -2147483648, 2147483647),
    QAudioFormat.SampleFormat.Float: ("float32", "f", -1.0, 1.0),
    QAudioFormat.SampleFormat.UInt8: ("uint8", "B", 0, 255),
}


def _panGains(pan, volume):
    pan = max(-1.0, min(1.0, pan))
    left = (1.0 if pan <= 0.0 else (1.0 - pan)) * volume
    right = (1.0 if pan >= 0.0 else (1.0 + pan)) * volume
    return left, right


def _applyPanBytes(raw, sample_format, channel_count, pan, volume):
    """Re-pans raw PCM to stereo (upmixing mono if needed) and returns new raw
    bytes ready to hand to a stereo QAudioSink, or None if the format/channel
    layout isn't one this can process (caller should just skip writing)."""
    info = _SAMPLE_DTYPES.get(sample_format)
    if info is None or channel_count not in (1, 2):
        return None
    dtype, fmt_char, lo, hi = info
    left_gain, right_gain = _panGains(pan, volume)
    is_uint8 = dtype == "uint8"

    if _HAS_NUMPY:
        arr = _np.frombuffer(raw, dtype=dtype).astype(_np.float64)
        if is_uint8:
            arr = arr - 128.0
        if channel_count == 1:
            left = arr * left_gain
            right = arr * right_gain
        else:
            stereo = arr.reshape(-1, 2)
            left = stereo[:, 0] * left_gain
            right = stereo[:, 1] * right_gain
        out = _np.empty(left.size * 2, dtype=_np.float64)
        out[0::2] = left
        out[1::2] = right
        if is_uint8:
            out = out + 128.0
        out = _np.clip(out, lo, hi)
        return out.astype(dtype).tobytes()

    # Pure-Python fallback (no numpy installed) — noticeably slower per buffer;
    # fine for a track or two, but multiple simultaneous panned tracks without
    # numpy installed risk audible crackle/underrun under real-time playback.
    stride = struct.calcsize(fmt_char)
    count = len(raw) // stride
    if count == 0:
        return None
    samples = struct.unpack(f"<{count}{fmt_char}", raw[: count * stride])

    def clamp(v):
        v = lo if v < lo else (hi if v > hi else v)
        return v if dtype == "float32" else int(v)

    out = []
    if channel_count == 1:
        for s in samples:
            v = (s - 128) if is_uint8 else s
            l = v * left_gain
            r = v * right_gain
            out.append(clamp(l + 128 if is_uint8 else l))
            out.append(clamp(r + 128 if is_uint8 else r))
    else:
        for i in range(0, count - 1, 2):
            lv = (samples[i] - 128) if is_uint8 else samples[i]
            rv = (samples[i + 1] - 128) if is_uint8 else samples[i + 1]
            l = lv * left_gain
            r = rv * right_gain
            out.append(clamp(l + 128 if is_uint8 else l))
            out.append(clamp(r + 128 if is_uint8 else r))
    return struct.pack(f"<{len(out)}{fmt_char}", *out)


class AudioLevelMeter(QObject):
    """Wraps a QAudioBufferOutput attached to one MediaPlayer. Emits
    levelChanged(float) with a raw RMS level (0..1) for every decoded buffer,
    for the mixer's VU meters — and, since QMediaPlayer's built-in AudioOutput
    has no pan control at all, also re-pans the decoded audio in software and
    plays it through a private QAudioSink. QML mutes the built-in AudioOutput
    and calls setPan()/setVolume() here instead; this is the actual audible
    output path once a meter is attached.
    """

    levelChanged = Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._bufferOutput = QAudioBufferOutput(self)
        self._bufferOutput.audioBufferReceived.connect(self._onBuffer)
        self._sink = None
        self._sinkFormat = None
        self._sinkDevice = None
        self._pan = 0.0
        self._volume = 1.0

    def attach(self, player):
        player.setAudioBufferOutput(self._bufferOutput)

    @Slot(float)
    def setPan(self, pan):
        self._pan = pan

    @Slot(float)
    def setVolume(self, volume):
        self._volume = volume

    def _ensureSink(self, buffer_format):
        out_format = QAudioFormat(buffer_format)
        out_format.setChannelConfig(QAudioFormat.ChannelConfig.ChannelConfigStereo)
        out_format.setChannelCount(2)
        if self._sink is not None and self._sinkFormat == out_format:
            return
        if self._sink is not None:
            self._sink.stop()
        self._sinkFormat = out_format
        self._sink = QAudioSink(out_format, self)
        self._sinkDevice = self._sink.start()

    def _onBuffer(self, buffer):
        self.levelChanged.emit(_computeRmsLevel(buffer))
        if not buffer.isValid() or buffer.sampleCount() == 0:
            return
        try:
            raw = bytes(buffer.constData())
        except Exception:
            return
        if not raw:
            return
        fmt = buffer.format()
        panned = _applyPanBytes(raw, fmt.sampleFormat(), fmt.channelCount(), self._pan, self._volume)
        if panned is None:
            return
        self._ensureSink(fmt)
        if self._sinkDevice:
            self._sinkDevice.write(panned)


class AudioMeterFactory(QObject):
    """Exposed to QML so each MediaPlayer can get its own AudioLevelMeter."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._meters = []

    @Slot(QObject, result=QObject)
    def createLevelMeter(self, player):
        meter = AudioLevelMeter(self)
        meter.attach(player)
        self._meters.append(meter)
        return meter


class _Command:
    """Single undoable/redoable action stored in session history."""
    __slots__ = ("_undo_fn", "_redo_fn")

    def __init__(self, undo_fn, redo_fn):
        self._undo_fn = undo_fn
        self._redo_fn = redo_fn

    def undo(self):
        self._undo_fn()

    def redo(self):
        self._redo_fn()


class _CommandHistory:
    """Unbounded undo/redo stack that lives for the duration of a story session."""

    def __init__(self):
        self._stack = []
        self._index = -1

    def push(self, command):
        del self._stack[self._index + 1:]
        self._stack.append(command)
        self._index = len(self._stack) - 1

    def undo(self):
        if self._index < 0:
            return False
        self._stack[self._index].undo()
        self._index -= 1
        return True

    def redo(self):
        if self._index >= len(self._stack) - 1:
            return False
        self._index += 1
        self._stack[self._index].redo()
        return True

    @property
    def can_undo(self):
        return self._index >= 0

    @property
    def can_redo(self):
        return self._index < len(self._stack) - 1

    def clear(self):
        self._stack.clear()
        self._index = -1


def _rescale_elements_meta(conn, scale_x, scale_y):
    """Scale all element spatial data (stored in the meta JSON blob) by (scale_x, scale_y).

    The elements table keeps a parallel set of x/y/w/h columns used for SQLite
    querying, and a JSON blob in `meta` that holds the full element state read by
    QML.  Both must be updated together for the resolution change to take effect.
    """
    coord_fields_x = {"x", "x1", "x2"}
    coord_fields_y = {"y", "y1", "y2"}
    size_fields_x  = {"w"}
    size_fields_y  = {"h"}

    rows = conn.execute("SELECT id, meta FROM elements").fetchall()
    for elem_id, meta_json in rows:
        try:
            el = json.loads(meta_json)
        except Exception:
            continue
        for f in coord_fields_x:
            if f in el:
                el[f] = el[f] * scale_x
        for f in coord_fields_y:
            if f in el:
                el[f] = el[f] * scale_y
        for f in size_fields_x:
            if f in el:
                el[f] = el[f] * scale_x
        for f in size_fields_y:
            if f in el:
                el[f] = el[f] * scale_y
        # Font size for text elements (stored as "size" in QML model → meta)
        if "size" in el:
            el["size"] = el["size"] * scale_x
        conn.execute(
            "UPDATE elements SET x = ?, y = ?, w = ?, h = ?, meta = ? WHERE id = ?",
            (el.get("x", 0), el.get("y", 0), el.get("w", 0), el.get("h", 0),
             json.dumps(el), elem_id),
        )


class _SaveThread(threading.Thread):
    """Daemon thread that performs fire-and-forget SQLite element writes."""

    def __init__(self):
        super().__init__(daemon=True)
        self._q = _queue.Queue()
        self._conn = None

    def open(self, path):
        self._q.put(("open", path))

    def close(self):
        self._q.put(("close", None))

    def write(self, scene_id, elements_json):
        self._q.put(("write", (scene_id, elements_json)))

    def stop(self):
        self._q.put(None)

    def run(self):
        while True:
            item = self._q.get()
            if item is None:
                if self._conn:
                    self._conn.close()
                    self._conn = None
                break
            op, data = item
            if op == "open":
                if self._conn:
                    self._conn.close()
                try:
                    self._conn = sqlite3.connect(data)
                    self._conn.execute("PRAGMA journal_mode=WAL")
                    self._conn.execute("PRAGMA synchronous=NORMAL")
                except Exception as e:
                    print(f"SaveThread.open: {e}")
                    self._conn = None
            elif op == "close":
                if self._conn:
                    self._conn.close()
                    self._conn = None
            elif op == "write":
                if not self._conn:
                    continue
                scene_id, elements_json = data
                try:
                    d = json.loads(elements_json)
                    self._conn.execute(
                        "DELETE FROM elements WHERE scene_id = ?", (scene_id,)
                    )
                    for el in d:
                        self._conn.execute(
                            "INSERT INTO elements"
                            " (scene_id, type, name, x, y, w, h, z_order, meta)"
                            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (
                                scene_id,
                                el["type"],
                                el.get("name", ""),
                                el["x"],
                                el["y"],
                                el["w"],
                                el["h"],
                                el.get("z_order", 0),
                                json.dumps(el),
                            ),
                        )
                    self._conn.commit()
                except Exception as e:
                    print(f"SaveThread.write: ERROR scene={scene_id} {e}")


class StoryManager(QObject):
    """Owns the SQLite connection for the currently-open .story file."""

    storyChanged = Signal()
    storyOpened = Signal()  # fires only on open/new, not on metadata updates
    undoAvailabilityChanged = Signal()
    redoAvailabilityChanged = Signal()
    resolutionChanged = Signal(int, int)

    def __init__(self):
        super().__init__()
        self._path = ""
        self._title = "new story"
        self._conn = None
        self._history = _CommandHistory()
        tmpl = Path(__file__).parent / "template.sql"
        self._template_sql = tmpl.read_text() if tmpl.exists() else ""
        self._recent_path = Path.home() / ".config" / "understory" / "recent.json"
        self._thumbs_dir = Path.home() / ".config" / "understory" / "thumbs"
        self._recent = []
        self._load_recent()
        self._save_thread = _SaveThread()
        self._save_thread.start()

    # ------------------------------------------------------------------ helpers

    def _url_to_path(self, s):
        """Strip file:// prefix returned by QML FileDialog."""
        if s.startswith("file://"):
            return unquote(urlparse(s).path)
        return s

    def _close(self):
        self._save_thread.close()
        if self._conn:
            self._conn.close()
            self._conn = None

    def _cleanup_save_thread(self):
        self._save_thread.stop()
        self._save_thread.join(timeout=3.0)

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
        existing = next((r for r in self._recent if r["path"] == path), None)
        self._recent = [r for r in self._recent if r["path"] != path]
        entry = {"path": path, "title": title, "filename": Path(path).stem}
        if existing and existing.get("thumbPath"):
            entry["thumbPath"] = existing["thumbPath"]
        self._recent.insert(0, entry)
        self._recent = self._recent[:8]
        self._save_recent()

    # ------------------------------------------------------------------ undo/redo

    def _push_command(self, undo_fn, redo_fn):
        had_redo = self._history.can_redo
        had_undo = self._history.can_undo
        self._history.push(_Command(undo_fn, redo_fn))
        if not had_undo:
            self.undoAvailabilityChanged.emit()
        if had_redo:
            self.redoAvailabilityChanged.emit()

    @Property(bool, notify=undoAvailabilityChanged)
    def canUndo(self):
        return self._history.can_undo

    @Property(bool, notify=redoAvailabilityChanged)
    def canRedo(self):
        return self._history.can_redo

    @Slot()
    def undo(self):
        if self._history.undo():
            self.undoAvailabilityChanged.emit()
            self.redoAvailabilityChanged.emit()
            self.storyChanged.emit()

    @Slot()
    def redo(self):
        if self._history.redo():
            self.undoAvailabilityChanged.emit()
            self.redoAvailabilityChanged.emit()
            self.storyChanged.emit()

    # ------------------------------------------------------------------ properties

    @Property(str, notify=storyChanged)
    def currentPath(self):
        return self._path

    @Property(str, notify=storyChanged)
    def storyTitle(self):
        # Custom title takes priority; fall back to the filename stem.
        if self._title:
            return self._title
        return Path(self._path).stem if self._path else ""

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
            conn.execute("INSERT INTO story (id, title) VALUES (1, '')")
            conn.commit()
            conn.execute("PRAGMA journal_mode=WAL")
            self._conn = conn
            self._save_thread.open(path)
            self._path = path
            self._title = ""
            self._history.clear()
            self.undoAvailabilityChanged.emit()
            self.redoAvailabilityChanged.emit()
            self._add_recent(path, self.storyTitle)
            self.storyChanged.emit()
            self.storyOpened.emit()
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
            # migrate: create networks table if missing (older .story files)
            tables = {
                r[0]
                for r in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
            if "networks" not in tables:
                conn.executescript(
                    "CREATE TABLE networks ("
                    "    id INTEGER PRIMARY KEY,"
                    "    name TEXT NOT NULL,"
                    "    color TEXT NOT NULL DEFAULT '#2e2e33',"
                    "    description TEXT,"
                    "    meta TEXT"
                    ");"
                )
                conn.commit()
            if "editor_state" not in tables:
                conn.executescript(
                    "CREATE TABLE editor_state ("
                    "    key TEXT PRIMARY KEY,"
                    "    value TEXT NOT NULL"
                    ");"
                )
                conn.commit()
            if "networks" in tables:
                # migrate: add color column if missing (stories created before this feature)
                net_cols = {
                    r[1] for r in conn.execute("PRAGMA table_info(networks)").fetchall()
                }
                if "color" not in net_cols:
                    conn.execute(
                        "ALTER TABLE networks ADD COLUMN color TEXT NOT NULL DEFAULT '#2e2e33'"
                    )
                    conn.commit()
            if "conversations" not in tables:
                conn.executescript(
                    "CREATE TABLE conversations ("
                    "    id INTEGER PRIMARY KEY,"
                    "    name TEXT NOT NULL DEFAULT '',"
                    "    meta TEXT"
                    ");"
                )
                conn.commit()
            if "variables" not in tables:
                conn.executescript(
                    "CREATE TABLE variables ("
                    "    id INTEGER PRIMARY KEY,"
                    "    name TEXT NOT NULL UNIQUE,"
                    "    type TEXT NOT NULL CHECK (type IN ('bool','int','float','string','color')),"
                    "    default_value TEXT NOT NULL,"
                    "    description TEXT"
                    ");"
                )
                conn.commit()
            row = conn.execute("SELECT title FROM story WHERE id = 1").fetchone()
            conn.execute("PRAGMA journal_mode=WAL")
            self._conn = conn
            self._save_thread.open(path)
            self._path = path
            stored = row[0] if row else ""
            # Treat the old default "new story" as no custom title so the
            # filename stem is shown instead.
            self._title = "" if stored in ("", "new story") else stored
            self._history.clear()
            self.undoAvailabilityChanged.emit()
            self.redoAvailabilityChanged.emit()
            self._add_recent(path, self.storyTitle)
            self.storyChanged.emit()
            self.storyOpened.emit()
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
            self._conn.execute("PRAGMA wal_checkpoint(FULL)")
            shutil.copy2(self._path, path)
            self._close()
            conn = sqlite3.connect(path)
            conn.execute("PRAGMA journal_mode=WAL")
            self._conn = conn
            self._save_thread.open(path)
            self._path = path
            self._add_recent(path, self._title)
            self.storyChanged.emit()
            return True
        except Exception as e:
            print(f"StoryManager.saveStoryAs: {e}")
            return False

    @Slot(str)
    def setStoryTitle(self, title):
        """Set a custom display title for the open story, independent of filename."""
        if not self._conn:
            return
        try:
            row = self._conn.execute("SELECT title FROM story WHERE id = 1").fetchone()
            old_title = row[0] if row else ""

            def apply(t):
                self._conn.execute("UPDATE story SET title = ? WHERE id = 1", (t,))
                self._conn.commit()
                self._title = "" if t in ("", "new story") else t
                self._add_recent(self._path, self.storyTitle)
                self.storyChanged.emit()

            apply(title)
            self._push_command(lambda t=old_title: apply(t), lambda t=title: apply(t))
        except Exception as e:
            print(f"StoryManager.setStoryTitle: {e}")

    # ------------------------------------------------------------------ resolution slots

    @Slot(result="QVariantMap")
    def getResolution(self):
        if not self._conn:
            return {"width": 1920, "height": 1080}
        try:
            row = self._conn.execute(
                "SELECT resolution_w, resolution_h FROM story WHERE id = 1"
            ).fetchone()
            if row:
                return {"width": row[0], "height": row[1]}
            return {"width": 1920, "height": 1080}
        except Exception as e:
            print(f"StoryManager.getResolution: {e}")
            return {"width": 1920, "height": 1080}

    @Slot(int, int)
    def setResolution(self, w, h):
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT resolution_w, resolution_h FROM story WHERE id = 1"
            ).fetchone()
            old_w, old_h = (row[0], row[1]) if row else (1920, 1080)
            if old_w == w and old_h == h:
                return
            scale_x = w / old_w
            scale_y = h / old_h
            self._conn.execute(
                "UPDATE story SET resolution_w = ?, resolution_h = ? WHERE id = 1",
                (w, h),
            )
            _rescale_elements_meta(self._conn, scale_x, scale_y)
            self._conn.commit()
            self._history.clear()
            self.undoAvailabilityChanged.emit()
            self.redoAvailabilityChanged.emit()
            self.resolutionChanged.emit(w, h)
        except Exception as e:
            print(f"StoryManager.setResolution: {e}")

    # ------------------------------------------------------------------ timecode format slots

    @Slot(result=str)
    def getTimecodeFormat(self):
        if not self._conn:
            return "24ndf"
        try:
            row = self._conn.execute("SELECT meta FROM story WHERE id = 1").fetchone()
            if row and row[0]:
                meta = json.loads(row[0])
                return meta.get("timecodeFormat", "24ndf")
            return "24ndf"
        except Exception as e:
            print(f"StoryManager.getTimecodeFormat: {e}")
            return "24ndf"

    @Slot(str)
    def setTimecodeFormat(self, fmt):
        if not self._conn:
            return
        try:
            row = self._conn.execute("SELECT meta FROM story WHERE id = 1").fetchone()
            old_meta = json.loads(row[0]) if (row and row[0]) else {}
            old_fmt = old_meta.get("timecodeFormat", "24ndf")

            def apply(f):
                r = self._conn.execute("SELECT meta FROM story WHERE id = 1").fetchone()
                meta = json.loads(r[0]) if (r and r[0]) else {}
                meta["timecodeFormat"] = f
                self._conn.execute("UPDATE story SET meta = ? WHERE id = 1", (json.dumps(meta),))
                self._conn.commit()
                self.storyChanged.emit()

            apply(fmt)
            self._push_command(lambda f=old_fmt: apply(f), lambda f=fmt: apply(f))
        except Exception as e:
            print(f"StoryManager.setTimecodeFormat: {e}")

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
                "INSERT INTO scenes (name, sort_order) VALUES (?, ?)",
                (name, sort_order),
            )
            scene_id = cur.lastrowid
            self._conn.commit()

            def do_undo(sid=scene_id):
                self._conn.execute("DELETE FROM elements WHERE scene_id = ?", (sid,))
                self._conn.execute("DELETE FROM scenes WHERE id = ?", (sid,))
                self._conn.commit()

            def do_redo(sid=scene_id, n=name, so=sort_order):
                self._conn.execute(
                    "INSERT INTO scenes (id, name, sort_order) VALUES (?, ?, ?)",
                    (sid, n, so),
                )
                self._conn.commit()

            self._push_command(do_undo, do_redo)
            return scene_id
        except Exception as e:
            print(f"StoryManager.createScene: {e}")
            return -1

    @Slot(int)
    def deleteScene(self, scene_id):
        """Delete a scene and all its elements (with undo support)."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name, sort_order, thumbnail FROM scenes WHERE id = ?", (scene_id,)
            ).fetchone()
            if not row:
                return
            old_name, old_sort_order, old_thumbnail = row

            elem_rows = self._conn.execute(
                "SELECT type, name, x, y, w, h, z_order, meta"
                " FROM elements WHERE scene_id = ? ORDER BY z_order",
                (scene_id,),
            ).fetchall()

            self._conn.execute("DELETE FROM scenes WHERE id = ?", (scene_id,))
            self._conn.commit()

            def do_undo(sid=scene_id, n=old_name, so=old_sort_order, thumb=old_thumbnail, elems=elem_rows):
                self._conn.execute(
                    "INSERT INTO scenes (id, name, sort_order, thumbnail) VALUES (?, ?, ?, ?)",
                    (sid, n, so, thumb),
                )
                for type_, ename, x, y, w, h, z_order, meta in elems:
                    self._conn.execute(
                        "INSERT INTO elements (scene_id, type, name, x, y, w, h, z_order, meta)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (sid, type_, ename, x, y, w, h, z_order, meta),
                    )
                self._conn.commit()

            def do_redo(sid=scene_id):
                self._conn.execute("DELETE FROM scenes WHERE id = ?", (sid,))
                self._conn.commit()

            self._push_command(do_undo, do_redo)
        except Exception as e:
            print(f"StoryManager.deleteScene: {e}")

    @Slot(int, str)
    def updateSceneName(self, scene_id, name):
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name FROM scenes WHERE id = ?", (scene_id,)
            ).fetchone()
            old_name = row[0] if row else ""

            def apply(sid, n):
                self._conn.execute("UPDATE scenes SET name = ? WHERE id = ?", (n, sid))
                self._conn.commit()

            apply(scene_id, name)
            self._push_command(
                lambda sid=scene_id, n=old_name: apply(sid, n),
                lambda sid=scene_id, n=name: apply(sid, n),
            )
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
            rows = self._conn.execute(
                "SELECT meta FROM elements WHERE scene_id = ? ORDER BY z_order",
                (scene_id,),
            ).fetchall()
            old_json = json.dumps([json.loads(r[0]) for r in rows])

            def apply(sid, ej):
                data = json.loads(ej)
                self._conn.execute("DELETE FROM elements WHERE scene_id = ?", (sid,))
                for el in data:
                    self._conn.execute(
                        "INSERT INTO elements (scene_id, type, name, x, y, w, h, z_order, meta)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            sid,
                            el["type"],
                            el.get("name", ""),
                            el["x"],
                            el["y"],
                            el["w"],
                            el["h"],
                            el.get("z_order", 0),
                            json.dumps(el),
                        ),
                    )
                self._conn.commit()

            apply(scene_id, elements_json)
            self._push_command(
                lambda sid=scene_id, ej=old_json: apply(sid, ej),
                lambda sid=scene_id, ej=elements_json: apply(sid, ej),
            )
        except Exception as e:
            print(f"StoryManager.saveSceneElements: ERROR scene={scene_id} {e}")

    @Slot(int, str)
    def saveSceneElementsDeferred(self, scene_id, elements_json):
        """Like saveSceneElements but dispatches the DB write to the background thread.
        Used by propSaveDebounce to avoid blocking the main thread during transitions."""
        if not self._conn:
            return
        try:
            rows = self._conn.execute(
                "SELECT meta FROM elements WHERE scene_id = ? ORDER BY z_order",
                (scene_id,),
            ).fetchall()
            old_json = json.dumps([json.loads(r[0]) for r in rows])

            self._save_thread.write(scene_id, elements_json)

            def apply_sync(sid, ej):
                if not self._conn:
                    return
                data = json.loads(ej)
                self._conn.execute("DELETE FROM elements WHERE scene_id = ?", (sid,))
                for el in data:
                    self._conn.execute(
                        "INSERT INTO elements (scene_id, type, name, x, y, w, h, z_order, meta)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            sid,
                            el["type"],
                            el.get("name", ""),
                            el["x"],
                            el["y"],
                            el["w"],
                            el["h"],
                            el.get("z_order", 0),
                            json.dumps(el),
                        ),
                    )
                self._conn.commit()

            self._push_command(
                lambda sid=scene_id, ej=old_json: apply_sync(sid, ej),
                lambda sid=scene_id, ej=elements_json: apply_sync(sid, ej),
            )
        except Exception as e:
            print(f"StoryManager.saveSceneElementsDeferred: ERROR scene={scene_id} {e}")

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
            result = json.dumps([json.loads(r[0]) for r in rows])
            return result
        except Exception as e:
            print(f"StoryManager.loadSceneElements: ERROR scene={scene_id} {e}")
            return "[]"

    @Slot(int, str)
    def saveThumbnail(self, scene_id, file_url):
        """Store a PNG file as a BLOB thumbnail for the given scene."""
        if not self._conn:
            return
        try:
            path = (
                unquote(urlparse(file_url).path)
                if file_url.startswith("file://")
                else file_url
            )
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
            src = (
                unquote(urlparse(file_url).path)
                if file_url.startswith("file://")
                else file_url
            )
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

    # ------------------------------------------------------------------ network slots

    @Slot(result=int)
    def ensureDefaultNetwork(self):
        """Returns the id of the first network, creating a default one if none exists."""
        if not self._conn:
            return -1
        try:
            row = self._conn.execute(
                "SELECT id FROM networks ORDER BY id LIMIT 1"
            ).fetchone()
            if row:
                return row[0]
            cur = self._conn.execute("INSERT INTO networks (name) VALUES (?)", ("",))
            self._conn.commit()
            return cur.lastrowid
        except Exception as e:
            print(f"StoryManager.ensureDefaultNetwork: {e}")
            return -1

    @Slot(result="QVariantList")
    def getNetworks(self):
        """Returns list of {id, name, color} for all networks in the story."""
        if not self._conn:
            return []
        try:
            rows = self._conn.execute(
                "SELECT id, name, COALESCE(color, '#2e2e33') FROM networks ORDER BY id"
            ).fetchall()
            return [{"id": r[0], "name": r[1], "color": r[2]} for r in rows]
        except Exception as e:
            print(f"StoryManager.getNetworks: {e}")
            return []

    @Slot(int, result=str)
    def loadNetworkData(self, network_id):
        """Returns JSON blob stored in networks.meta for the given network."""
        if not self._conn:
            return "{}"
        try:
            row = self._conn.execute(
                "SELECT meta FROM networks WHERE id = ?", (network_id,)
            ).fetchone()
            if row and row[0]:
                return row[0]
            return "{}"
        except Exception as e:
            print(f"StoryManager.loadNetworkData: {e}")
            return "{}"

    @Slot(int, result="QVariantList")
    def getNetworkNodeNames(self, network_id):
        """Returns a list of node names for a specific network."""
        raw = self.loadNetworkData(network_id)
        try:
            data = json.loads(raw)
            nodes = data.get("nodes", [])
            return [n.get("name", "") for n in nodes]
        except Exception:
            return []

    @Slot(int, result="QVariantList")
    def getNetworkCharacterNames(self, network_id):
        """Returns a list of character names for a specific network."""
        raw = self.loadNetworkData(network_id)
        try:
            data = json.loads(raw)
            chars = data.get("characters", [])
            return [c.get("charName", "") for c in chars if c.get("charName", "") != ""]
        except Exception:
            return []

    @Slot(int, str)
    def saveNetworkData(self, network_id, json_str):
        """Writes and commits the JSON state blob for a network."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT meta FROM networks WHERE id = ?", (network_id,)
            ).fetchone()
            old_json = row[0] if (row and row[0]) else "{}"

            def apply(nid, js):
                self._conn.execute(
                    "UPDATE networks SET meta = ? WHERE id = ?", (js, nid)
                )
                self._conn.commit()

            apply(network_id, json_str)
            self._push_command(
                lambda nid=network_id, js=old_json: apply(nid, js),
                lambda nid=network_id, js=json_str: apply(nid, js),
            )
        except Exception as e:
            print(f"StoryManager.saveNetworkData: {e}")

    @Slot(str, result=int)
    def createNetwork(self, name):
        """Creates a new named network and returns its id."""
        if not self._conn:
            return -1
        try:
            cur = self._conn.execute("INSERT INTO networks (name) VALUES (?)", (name,))
            network_id = cur.lastrowid
            self._conn.commit()

            def do_undo(nid=network_id):
                self._conn.execute("DELETE FROM networks WHERE id = ?", (nid,))
                self._conn.commit()

            def do_redo(nid=network_id, n=name):
                self._conn.execute(
                    "INSERT INTO networks (id, name) VALUES (?, ?)", (nid, n)
                )
                self._conn.commit()

            self._push_command(do_undo, do_redo)
            return network_id
        except Exception as e:
            print(f"StoryManager.createNetwork: {e}")
            return -1

    @Slot(int, str)
    def renameNetwork(self, network_id, name):
        """Rename a network."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name FROM networks WHERE id = ?", (network_id,)
            ).fetchone()
            old_name = row[0] if row else ""

            def apply(nid, n):
                self._conn.execute(
                    "UPDATE networks SET name = ? WHERE id = ?", (n, nid)
                )
                self._conn.commit()

            apply(network_id, name)
            self._push_command(
                lambda nid=network_id, n=old_name: apply(nid, n),
                lambda nid=network_id, n=name: apply(nid, n),
            )
        except Exception as e:
            print(f"StoryManager.renameNetwork: {e}")

    @Slot(int, str)
    def saveNetworkColor(self, network_id, color):
        """Persist the display color for a network."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT color FROM networks WHERE id = ?", (network_id,)
            ).fetchone()
            old_color = row[0] if (row and row[0]) else "#2e2e33"

            def apply(nid, c):
                self._conn.execute(
                    "UPDATE networks SET color = ? WHERE id = ?", (c, nid)
                )
                self._conn.commit()

            apply(network_id, color)
            self._push_command(
                lambda nid=network_id, c=old_color: apply(nid, c),
                lambda nid=network_id, c=color: apply(nid, c),
            )
        except Exception as e:
            print(f"StoryManager.saveNetworkColor: {e}")

    @Slot(int)
    def deleteNetwork(self, network_id):
        """Delete a network and all its stored data."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name, color, meta FROM networks WHERE id = ?", (network_id,)
            ).fetchone()
            if not row:
                return
            old_name, old_color, old_meta = row

            self._conn.execute("DELETE FROM networks WHERE id = ?", (network_id,))
            self._conn.commit()

            def do_undo(nid=network_id, n=old_name, c=old_color, m=old_meta):
                self._conn.execute(
                    "INSERT INTO networks (id, name, color, meta) VALUES (?, ?, ?, ?)",
                    (nid, n, c or "#2e2e33", m),
                )
                self._conn.commit()

            def do_redo(nid=network_id):
                self._conn.execute("DELETE FROM networks WHERE id = ?", (nid,))
                self._conn.commit()

            self._push_command(do_undo, do_redo)
        except Exception as e:
            print(f"StoryManager.deleteNetwork: {e}")

    # ------------------------------------------------------------------ conversation slots

    @Slot(result=int)
    def ensureDefaultConversation(self):
        """Returns the id of the first conversation tree, creating one if none exist."""
        if not self._conn:
            return -1
        try:
            row = self._conn.execute(
                "SELECT id FROM conversations ORDER BY id LIMIT 1"
            ).fetchone()
            if row:
                return row[0]
            cur = self._conn.execute("INSERT INTO conversations (name) VALUES (?)", ("",))
            self._conn.commit()
            return cur.lastrowid
        except Exception as e:
            print(f"StoryManager.ensureDefaultConversation: {e}")
            return -1

    @Slot(result="QVariantList")
    def getConversations(self):
        """Returns list of {id, name} for all conversation trees in the story."""
        if not self._conn:
            return []
        try:
            rows = self._conn.execute(
                "SELECT id, name FROM conversations ORDER BY id"
            ).fetchall()
            return [{"id": r[0], "name": r[1]} for r in rows]
        except Exception as e:
            print(f"StoryManager.getConversations: {e}")
            return []

    @Slot(int, result=str)
    def loadConversationData(self, conv_id):
        """Returns the JSON blob stored for a conversation tree."""
        if not self._conn:
            return "{}"
        try:
            row = self._conn.execute(
                "SELECT meta FROM conversations WHERE id = ?", (conv_id,)
            ).fetchone()
            if row and row[0]:
                return row[0]
            return "{}"
        except Exception as e:
            print(f"StoryManager.loadConversationData: {e}")
            return "{}"

    @Slot(int, str)
    def saveConversationData(self, conv_id, json_str):
        """Writes and commits the JSON state blob for a conversation tree."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT meta FROM conversations WHERE id = ?", (conv_id,)
            ).fetchone()
            old_json = row[0] if (row and row[0]) else "{}"

            def apply(cid, js):
                self._conn.execute(
                    "UPDATE conversations SET meta = ? WHERE id = ?", (js, cid)
                )
                self._conn.commit()

            apply(conv_id, json_str)
            self._push_command(
                lambda cid=conv_id, js=old_json: apply(cid, js),
                lambda cid=conv_id, js=json_str: apply(cid, js),
            )
        except Exception as e:
            print(f"StoryManager.saveConversationData: {e}")

    @Slot(str, result=int)
    def createConversation(self, name):
        """Creates a new conversation tree and returns its id."""
        if not self._conn:
            return -1
        try:
            cur = self._conn.execute(
                "INSERT INTO conversations (name) VALUES (?)", (name,)
            )
            conv_id = cur.lastrowid
            self._conn.commit()

            def do_undo(cid=conv_id):
                self._conn.execute("DELETE FROM conversations WHERE id = ?", (cid,))
                self._conn.commit()

            def do_redo(cid=conv_id, n=name):
                self._conn.execute(
                    "INSERT INTO conversations (id, name) VALUES (?, ?)", (cid, n)
                )
                self._conn.commit()

            self._push_command(do_undo, do_redo)
            return conv_id
        except Exception as e:
            print(f"StoryManager.createConversation: {e}")
            return -1

    @Slot(int, str)
    def renameConversation(self, conv_id, name):
        """Rename a conversation tree."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name FROM conversations WHERE id = ?", (conv_id,)
            ).fetchone()
            old_name = row[0] if row else ""

            def apply(cid, n):
                self._conn.execute(
                    "UPDATE conversations SET name = ? WHERE id = ?", (n, cid)
                )
                self._conn.commit()

            apply(conv_id, name)
            self._push_command(
                lambda cid=conv_id, n=old_name: apply(cid, n),
                lambda cid=conv_id, n=name: apply(cid, n),
            )
        except Exception as e:
            print(f"StoryManager.renameConversation: {e}")

    @Slot(int)
    def deleteConversation(self, conv_id):
        """Delete a conversation tree and its stored data."""
        if not self._conn:
            return
        try:
            row = self._conn.execute(
                "SELECT name, meta FROM conversations WHERE id = ?", (conv_id,)
            ).fetchone()
            if not row:
                return
            old_name, old_meta = row

            self._conn.execute("DELETE FROM conversations WHERE id = ?", (conv_id,))
            self._conn.commit()

            def do_undo(cid=conv_id, n=old_name, m=old_meta):
                self._conn.execute(
                    "INSERT INTO conversations (id, name, meta) VALUES (?, ?, ?)",
                    (cid, n, m),
                )
                self._conn.commit()

            def do_redo(cid=conv_id):
                self._conn.execute("DELETE FROM conversations WHERE id = ?", (cid,))
                self._conn.commit()

            self._push_command(do_undo, do_redo)
        except Exception as e:
            print(f"StoryManager.deleteConversation: {e}")

    # ------------------------------------------------------------------ variable slots

    # Type mapping between QML display names and DB column values
    _QML_TO_DB_TYPE = {"true or false": "bool", "number": "float", "text": "string"}
    _DB_TO_QML_TYPE = {
        "bool": "true or false",
        "int": "number",
        "float": "number",
        "string": "text",
        "color": "text",
    }

    @Slot(result="QVariantList")
    def getVariables(self):
        """Returns all story variables as [{varName, varType, varValue}] for QML."""
        if not self._conn:
            return []
        try:
            rows = self._conn.execute(
                "SELECT name, type, default_value FROM variables ORDER BY id"
            ).fetchall()
            return [
                {
                    "varName": r[0],
                    "varType": self._DB_TO_QML_TYPE.get(r[1], "text"),
                    "varValue": r[2],
                }
                for r in rows
            ]
        except Exception as e:
            print(f"StoryManager.getVariables: {e}")
            return []

    @Slot(str)
    def saveVariables(self, variables_json):
        """Replace all story variables from a JSON array of {varName, varType, varValue}."""
        if not self._conn:
            return
        try:
            old_rows = self._conn.execute(
                "SELECT name, type, default_value FROM variables ORDER BY id"
            ).fetchall()

            def do_redo(vj=variables_json):
                data = json.loads(vj)
                self._conn.execute("DELETE FROM variables")
                for v in data:
                    name = v.get("varName", "").strip()
                    if not name:
                        continue
                    db_type = self._QML_TO_DB_TYPE.get(v.get("varType", "text"), "string")
                    value = v.get("varValue", "")
                    self._conn.execute(
                        "INSERT INTO variables (name, type, default_value) VALUES (?, ?, ?)",
                        (name, db_type, value),
                    )
                self._conn.commit()

            def do_undo(rows=old_rows):
                self._conn.execute("DELETE FROM variables")
                for name, type_, value in rows:
                    self._conn.execute(
                        "INSERT INTO variables (name, type, default_value) VALUES (?, ?, ?)",
                        (name, type_, value),
                    )
                self._conn.commit()

            do_redo()
            self._push_command(do_undo, do_redo)
        except Exception as e:
            print(f"StoryManager.saveVariables: {e}")

    # ------------------------------------------------------------------ editor state slots

    @Slot(str, result=str)
    def getEditorState(self, key):
        """Return the stored value for key, or empty string if absent."""
        if not self._conn:
            return ""
        try:
            row = self._conn.execute(
                "SELECT value FROM editor_state WHERE key = ?", (key,)
            ).fetchone()
            return row[0] if row else ""
        except Exception as e:
            print(f"StoryManager.getEditorState: {e}")
            return ""

    @Slot(str, str)
    def setEditorState(self, key, value):
        """Upsert a key/value pair into editor_state."""
        if not self._conn:
            return
        try:
            self._conn.execute(
                "INSERT INTO editor_state (key, value) VALUES (?, ?)"
                " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )
            self._conn.commit()
        except Exception as e:
            print(f"StoryManager.setEditorState: {e}")


class ControllerManager(QObject):
    """Polls SDL3 gamepad events and emits Qt signals for button press/release.

    button kc strings match the ControllerVisualizer buttonDefs:
      cross, circle, triangle, square, l1, r1, l2, r2,
      dpadup, dpaddown, dpadleft, dpadright, touchpad, options
    """

    buttonPressed    = Signal(str)
    buttonReleased   = Signal(str)
    connectedChanged = Signal(bool)

    TRIGGER_THRESHOLD = 8000  # out of 32767 (~25 %)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._gamepads         = {}                            # instance_id → LP_SDL_Gamepad
        self._trigger_pressed  = {"l2": False, "r2": False}
        self._connected        = False
        self._button_map       = {}
        self._timer            = None

        if not _SDL3_AVAILABLE:
            return

        self._button_map = {
            int(SDL_GAMEPAD_BUTTON_SOUTH):          "cross",
            int(SDL_GAMEPAD_BUTTON_EAST):           "circle",
            int(SDL_GAMEPAD_BUTTON_NORTH):          "triangle",
            int(SDL_GAMEPAD_BUTTON_WEST):           "square",
            int(SDL_GAMEPAD_BUTTON_LEFT_SHOULDER):  "l1",
            int(SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER): "r1",
            int(SDL_GAMEPAD_BUTTON_DPAD_UP):        "dpadup",
            int(SDL_GAMEPAD_BUTTON_DPAD_DOWN):      "dpaddown",
            int(SDL_GAMEPAD_BUTTON_DPAD_LEFT):      "dpadleft",
            int(SDL_GAMEPAD_BUTTON_DPAD_RIGHT):     "dpadright",
            int(SDL_GAMEPAD_BUTTON_TOUCHPAD):       "touchpad",
            int(SDL_GAMEPAD_BUTTON_START):          "options",
        }

        SDL_Init(SDL_INIT_GAMEPAD)

        # Open any gamepads already connected at startup
        count = ctypes.c_int(0)
        ids = SDL_GetGamepads(ctypes.byref(count))
        if ids and count.value > 0:
            for i in range(count.value):
                gp = SDL_OpenGamepad(ids[i])
                if gp:
                    self._gamepads[int(ids[i])] = gp
        self._connected = len(self._gamepads) > 0

        self._timer = QTimer(self)
        self._timer.setInterval(16)
        self._timer.timeout.connect(self._poll)
        self._timer.start()

    @Property(bool, notify=connectedChanged)
    def connected(self):
        return self._connected

    def _poll(self):
        event = SDL_Event()
        while SDL_PollEvent(ctypes.byref(event)):
            t = int(event.type)

            if t == int(SDL_EVENT_GAMEPAD_ADDED):
                iid = int(event.gdevice.which)
                gp  = SDL_OpenGamepad(event.gdevice.which)
                if gp:
                    self._gamepads[iid] = gp
                    if not self._connected:
                        self._connected = True
                        self.connectedChanged.emit(True)

            elif t == int(SDL_EVENT_GAMEPAD_REMOVED):
                iid = int(event.gdevice.which)
                if iid in self._gamepads:
                    SDL_CloseGamepad(self._gamepads.pop(iid))
                if not self._gamepads and self._connected:
                    self._connected = False
                    self.connectedChanged.emit(False)

            elif t == int(SDL_EVENT_GAMEPAD_BUTTON_DOWN):
                kc = self._button_map.get(int(event.gbutton.button))
                if kc:
                    self.buttonPressed.emit(kc)

            elif t == int(SDL_EVENT_GAMEPAD_BUTTON_UP):
                kc = self._button_map.get(int(event.gbutton.button))
                if kc:
                    self.buttonReleased.emit(kc)

            elif t == int(SDL_EVENT_GAMEPAD_AXIS_MOTION):
                axis = int(event.gaxis.axis)
                val  = int(event.gaxis.value)
                if axis == int(SDL_GAMEPAD_AXIS_LEFT_TRIGGER):
                    now = val >= self.TRIGGER_THRESHOLD
                    if now != self._trigger_pressed["l2"]:
                        self._trigger_pressed["l2"] = now
                        (self.buttonPressed if now else self.buttonReleased).emit("l2")
                elif axis == int(SDL_GAMEPAD_AXIS_RIGHT_TRIGGER):
                    now = val >= self.TRIGGER_THRESHOLD
                    if now != self._trigger_pressed["r2"]:
                        self._trigger_pressed["r2"] = now
                        (self.buttonPressed if now else self.buttonReleased).emit("r2")

    def cleanup(self):
        if self._timer:
            self._timer.stop()
        for gp in self._gamepads.values():
            SDL_CloseGamepad(gp)
        self._gamepads.clear()
        if _SDL3_AVAILABLE:
            SDL_QuitSubSystem(SDL_INIT_GAMEPAD)


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

# Expose audio meter factory so QML can attach a real-level VU meter to any MediaPlayer
audioMeterFactory = AudioMeterFactory()
engine.rootContext().setContextProperty("audioMeterFactory", audioMeterFactory)

# Expose story manager so QML can open/save/create .story files
storyManager = StoryManager()
engine.rootContext().setContextProperty("storyManager", storyManager)

# Register image provider so QML can load thumbnails via image://thumbnails/<sceneId>
thumbnailProvider = ThumbnailProvider(storyManager)
engine.addImageProvider("thumbnails", thumbnailProvider)

# Expose PS5 controller manager so QML can react to gamepad input
controllerManager = ControllerManager()
engine.rootContext().setContextProperty("controllerManager", controllerManager)
app.aboutToQuit.connect(controllerManager.cleanup)
app.aboutToQuit.connect(storyManager._cleanup_save_thread)


# Load QML file
qml_file = QUrl("understoryui.qml")
engine.load(qml_file)

# Quit if loading fails
if not engine.rootObjects():
    sys.exit(-1)

# Native preview pipeline (Phase 4; Phase 8 added the "sdr" mode) -- opt-in
# via appSettings.nativeRenderMode ("off"/"sdr"/"hdr"), no-op unless
# enabled/supported/on macOS. Falls back to the existing Qt video pipeline
# entirely on its own if construction fails for any reason.
hdrBridge = None
if HDRVideoBridge is not None:
    try:
        hdrBridge = HDRVideoBridge(engine.rootObjects()[0])
        if hdrBridge.active:
            app.aboutToQuit.connect(hdrBridge.cleanup)
    except Exception as exc:
        print(f"[hdr_viewport] bridge construction failed, using Qt pipeline: {exc}")

# Exposed so understoryui.qml's captureAndSaveThumbnail() can call
# hdrBridge.capture_thumbnail() directly when the native pipeline is active
# -- None (falsy in QML too) whenever native rendering is off/unsupported,
# so that call site's own qtPresentationSuspended guard is what matters.
engine.rootContext().setContextProperty("hdrBridge", hdrBridge if hdrBridge is not None and hdrBridge.active else None)

sys.exit(app.exec())
