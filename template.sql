-- the story itself (single row)
CREATE TABLE story (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    title TEXT NOT NULL DEFAULT 'new story',
    resolution_w INTEGER NOT NULL DEFAULT 1920,
    resolution_h INTEGER NOT NULL DEFAULT 1080,
    framerate REAL NOT NULL DEFAULT 30.0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    modified_at TEXT NOT NULL DEFAULT (datetime('now')),
    meta TEXT  -- CBOR or JSON blob for extensible metadata
);

-- typed story variables
CREATE TABLE variables (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL CHECK (type IN ('bool','int','float','string','color')),
    default_value TEXT NOT NULL,
    description TEXT
);

-- characters (abstract entities)
CREATE TABLE characters (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('perform','wild')),
    portrait_path TEXT,  -- optional external image ref
    meta TEXT
);

-- sounds (can be scene-scoped or global)
CREATE TABLE sounds (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    loop INTEGER NOT NULL DEFAULT 0,
    volume REAL NOT NULL DEFAULT 1.0,
    spatial INTEGER NOT NULL DEFAULT 0,
    meta TEXT
);

-- scenes
CREATE TABLE scenes (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    -- canvas defaults (inherit from story if null)
    bg_color TEXT,
    duration_ms INTEGER,  -- null = indefinite/interactive
    meta TEXT
);

-- which sounds play in which scenes (junction)
CREATE TABLE scene_sounds (
    scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
    sound_id INTEGER NOT NULL REFERENCES sounds(id) ON DELETE CASCADE,
    start_ms INTEGER NOT NULL DEFAULT 0,
    fade_in_ms INTEGER NOT NULL DEFAULT 0,
    fade_out_ms INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (scene_id, sound_id)
);

-- composition elements (unified table, type-discriminated)
CREATE TABLE elements (
    id INTEGER PRIMARY KEY,
    scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('area','text','image','video','shader')),
    name TEXT,
    -- spatial (all elements occupy a rectangle)
    x REAL NOT NULL DEFAULT 0,
    y REAL NOT NULL DEFAULT 0,
    w REAL NOT NULL,
    h REAL NOT NULL,
    rotation REAL NOT NULL DEFAULT 0,
    z_order INTEGER NOT NULL DEFAULT 0,
    visible INTEGER NOT NULL DEFAULT 1,
    opacity REAL NOT NULL DEFAULT 1.0,
    -- conditional visibility
    condition TEXT,  -- expression referencing variables
    meta TEXT
);

-- type-specific properties (one row per element, only in matching table)

CREATE TABLE element_text (
    element_id INTEGER PRIMARY KEY REFERENCES elements(id) ON DELETE CASCADE,
    content TEXT NOT NULL DEFAULT '',
    font_family TEXT NOT NULL DEFAULT 'sans-serif',
    font_size REAL NOT NULL DEFAULT 16,
    color TEXT NOT NULL DEFAULT '#FFFFFF',
    alignment TEXT NOT NULL DEFAULT 'left'
        CHECK (alignment IN ('left','center','right','justify')),
    line_height REAL NOT NULL DEFAULT 1.4,
    overflow TEXT NOT NULL DEFAULT 'clip'
        CHECK (overflow IN ('clip','scroll','expand'))
);

CREATE TABLE element_image (
    element_id INTEGER PRIMARY KEY REFERENCES elements(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    fit TEXT NOT NULL DEFAULT 'cover'
        CHECK (fit IN ('cover','contain','stretch','tile')),
    anchor_x REAL NOT NULL DEFAULT 0.5,
    anchor_y REAL NOT NULL DEFAULT 0.5
);

CREATE TABLE element_video (
    element_id INTEGER PRIMARY KEY REFERENCES elements(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    fit TEXT NOT NULL DEFAULT 'cover'
        CHECK (fit IN ('cover','contain','stretch')),
    autoplay INTEGER NOT NULL DEFAULT 1,
    loop INTEGER NOT NULL DEFAULT 0,
    start_ms INTEGER NOT NULL DEFAULT 0,
    end_ms INTEGER,  -- null = play to end
    playback_rate REAL NOT NULL DEFAULT 1.0
);

CREATE TABLE element_shader (
    element_id INTEGER PRIMARY KEY REFERENCES elements(id) ON DELETE CASCADE,
    fragment_path TEXT,  -- path to .qsb
    vertex_path TEXT,    -- path to .qsb (optional)
    -- uniform bindings
    uniforms TEXT  -- JSON object: {"time": "elapsed", "mouse": "cursor", "tint": "#FF0000"}
);

-- hotspot links (area elements that trigger scene transitions)
CREATE TABLE links (
    id INTEGER PRIMARY KEY,
    element_id INTEGER NOT NULL REFERENCES elements(id) ON DELETE CASCADE,
    target_scene_id INTEGER NOT NULL REFERENCES scenes(id) ON DELETE CASCADE,
    transition TEXT NOT NULL DEFAULT 'cut'
        CHECK (transition IN ('cut','fade','dissolve','wipe_left','wipe_right',
                              'wipe_up','wipe_down','push_left','push_right',
                              'iris_in','iris_out','custom')),
    transition_duration_ms INTEGER NOT NULL DEFAULT 500,
    custom_shader_path TEXT,  -- for transition = 'custom'
    condition TEXT,  -- expression: only follow if true
    -- cursor/hover behavior
    cursor TEXT NOT NULL DEFAULT 'pointer',
    hover_opacity REAL
);

-- networks (optional, for NPC simulation / cross-scene effects)
CREATE TABLE networks (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    meta TEXT
);

CREATE TABLE network_nodes (
    id INTEGER PRIMARY KEY,
    network_id INTEGER NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    node_type TEXT NOT NULL,  -- user-defined types
    -- position in network editor canvas
    canvas_x REAL NOT NULL DEFAULT 0,
    canvas_y REAL NOT NULL DEFAULT 0,
    properties TEXT  -- JSON/CBOR blob, schema depends on node_type
);

CREATE TABLE network_edges (
    id INTEGER PRIMARY KEY,
    network_id INTEGER NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    source_node_id INTEGER NOT NULL REFERENCES network_nodes(id) ON DELETE CASCADE,
    target_node_id INTEGER NOT NULL REFERENCES network_nodes(id) ON DELETE CASCADE,
    source_port TEXT,
    target_port TEXT,
    weight REAL NOT NULL DEFAULT 1.0,
    condition TEXT,
    meta TEXT
);

-- which characters participate in which networks
CREATE TABLE network_characters (
    network_id INTEGER NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    role TEXT,
    PRIMARY KEY (network_id, character_id)
);

-- editor state (not part of the story, but saved for UX continuity)
CREATE TABLE editor_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- indexes for common queries
CREATE INDEX idx_elements_scene ON elements(scene_id);
CREATE INDEX idx_elements_type ON elements(scene_id, type);
CREATE INDEX idx_links_target ON links(target_scene_id);
CREATE INDEX idx_network_nodes ON network_nodes(network_id);
CREATE INDEX idx_network_edges_source ON network_edges(source_node_id);
CREATE INDEX idx_network_edges_target ON network_edges(target_node_id);