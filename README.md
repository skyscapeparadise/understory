<img width="1072" alt="may2026screenshot" src="https://github.com/user-attachments/assets/1d5a951c-9155-4c24-b3a1-36562ba8ee43" />

# understory

a constructive tool for creating interactive multimedia stories — no programming required

(currently in development, release planned for 2027)

**understory** is for anyone who has ever wanted to make something you can actually walk around inside — a film where the viewer chooses their own path, a game built entirely out of video, a navigable world made from your own footage. If you can drop a clip into a timeline, you can make something with understory.

You build a story by arranging media on **scenes** — think of each scene like a frame you can fill with video, images, and text — and then connecting those scenes together on a visual map. From there you can add interactivity: make things happen when a viewer clicks somewhere, hovers over an area, or reaches a certain point in time. understory handles all the logic behind the scenes so you can focus on the experience.

When you're ready to share, the plan is to publish your story as a self-contained application that can run on desktop, mobile, and eventually even game consoles.

Built by [Rain Multimedia](https://www.rainmultimedia.net/) and free, open-source software under the LGPL. Stories and applications created with understory may be licensed however you choose. The project is still in active development and is anticipated to be released in 2027. If you want to get involved, please reach out to us at: support@rainmultimedia.net

## Features

- **Scene composer** — layer video, images, text, hotspot areas, and custom GLSL shaders on a compositing canvas with a GPU-accelerated dual-buffer architecture for flash-free transitions
- **Node graph** — map out scene connections and story navigation visually, with support for multiple named networks
- **Timeline & chapters** — choreograph state changes and trigger behaviors at specific playhead positions across discrete chapter timelines
- **Interactivity system** — author click, hover, and time-based (`when`) behaviors driven by typed story variables and conditional logic
- **Scene transitions** — cut, fade, dissolve, directional wipes and pushes, iris in/out, and custom GLSL shader transitions
- **Story variables** — define boolean, numeric, and text variables that drive conditional visibility, navigation, and branching
- **Character & sound management** — manage cast and ambient audio assets across your story
- **Conversation tree editor** — author branching dialogue graphs visually
- **Controller input** — PS5 DualSense and compatible gamepads via SDL3, with keyboard and controller visualizers
- **Undo/redo** — full session-scoped command history
- **Scene thumbnails** — automatic PNG snapshots stored in the `.story` database

## Requirements

- Python (any version supported by the current PySide6 release; Python 3.14+ recommended)
- [PySide6](https://pypi.org/project/PySide6/) — includes Qt Quick, Qt Multimedia, and all required Qt modules
- [pysdl3](https://pypi.org/project/pysdl3/) — required for gamepad and controller input

```
pip install PySide6 pysdl3
```

Packaged releases will bundle all dependencies.

## Running

```
python understory.py
```

## Possible Use Cases

○ Video games and interactive narratives

○ Non-linear films and video albums

○ Transforming home videos into interactive multimedia worlds

○ Museum kiosks and gallery installations

○ Branching documentary and educational experiences

## Roadmap

○ story compiler and SDL3 runtime

○ HDR support

○ beta release

## License

understory is free software released under the [GNU Lesser General Public License v2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html) or later. Stories, films, games, and other works created with understory are not subject to this license and may be distributed under any terms you choose.

Copyright © 2025–2026 Rain Multimedia LLC
