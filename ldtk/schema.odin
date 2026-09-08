package ldtk

import "core:encoding/json"

/*
Typed model of an LDtk project file (JSON export), based on the official schema:
https://ldtk.io/files/JSON_SCHEMA.json

Only the fields relevant for loading and using levels are modeled; every other
key present in the file is skipped by json.unmarshal (verified behavior).

JSON keys are matched EXACTLY against the `json:"..."` struct tags.
*/

// ---------------------------------------------------------------------------
// Project root
// ---------------------------------------------------------------------------

Header :: struct {
	file_type:   string `json:"fileType"`,
	app:         string,
	doc:         string,
	schema:      string,
	app_author:  string `json:"appAuthor"`,
	app_version: string `json:"appVersion"`,
	url:         string,
}

Project :: struct {
	header:                 Header `json:"__header__"`,
	iid:                    string,
	json_version:           string `json:"jsonVersion"`,
	app_build_id:           int    `json:"appBuildId"`,
	next_uid:               int    `json:"nextUid"`,
	identifier_style:       string `json:"identifierStyle"`,

	bg_color:               string `json:"bgColor"`,
	default_level_bg_color: string `json:"defaultLevelBgColor"`,
	level_name_pattern:     string `json:"levelNamePattern"`,
	default_grid_size:      int    `json:"defaultGridSize"`,
	default_entity_width:   int    `json:"defaultEntityWidth"`,
	default_entity_height:  int    `json:"defaultEntityHeight"`,
	default_pivot_x:        f64    `json:"defaultPivotX"`,
	default_pivot_y:        f64    `json:"defaultPivotY"`,

	dummy_world_iid:        string `json:"dummyWorldIid"`,

	// World layout (only present when Multi-worlds is OFF).
	world_layout:           string `json:"worldLayout"`,
	world_grid_width:       int    `json:"worldGridWidth"`,
	world_grid_height:      int    `json:"worldGridHeight"`,
	default_level_width:    int    `json:"defaultLevelWidth"`,
	default_level_height:   int    `json:"defaultLevelHeight"`,

	minify_json:            bool   `json:"minifyJson"`,
	external_levels:        bool   `json:"externalLevels"`,
	export_tiled:           bool   `json:"exportTiled"`,
	simplified_export:      bool   `json:"simplifiedExport"`,
	image_export_mode:      string `json:"imageExportMode"`,
	export_level_bg:        bool   `json:"exportLevelBg"`,
	backup_on_save:         bool   `json:"backupOnSave"`,
	backup_limit:           int    `json:"backupLimit"`,
	backup_rel_path:        string `json:"backupRelPath"`,

	flags:                  []string,

	defs:   Defs,
	levels: []Level,
	worlds: []World,
}

// levels_all returns every level of the project: the root `levels` array plus
// the levels of every world (multi-worlds export).
levels_all :: proc(p: ^Project, allocator := context.allocator) -> []Level {
	out := make([dynamic]Level, allocator)
	defer delete(out)
	for l in p.levels do append(&out, l)
	for w in p.worlds {
		for l in w.levels do append(&out, l)
	}
	return out[:]
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

Defs :: struct {
	tilesets:       []Tileset_Def,
	layers:         []Layer_Def,
	level_fields:   []Field_Def `json:"levelFields"`,
	enums:          []Enum_Def,
	entities:       []Entity_Def,
	external_enums: []Enum_Def `json:"externalEnums"`,
}

Tileset_Def :: struct {
	identifier:          string,
	uid:                 int,
	rel_path:            string `json:"relPath"`,
	px_wid:              int    `json:"pxWid"`,
	px_hei:              int    `json:"pxHei"`,
	c_wid:               int    `json:"__cWid"`,
	c_hei:               int    `json:"__cHei"`,
	tile_grid_size:      int    `json:"tileGridSize"`,
	spacing:             int,
	padding:             int,
	tags:                []string,
	enum_tags:           []Enum_Tag_Value `json:"enumTags"`,
	tags_source_enum_uid: int              `json:"tagsSourceEnumUid"`,
}

Enum_Tag_Value :: struct {
	enum_value_id: string `json:"enumValueId"`,
	tile_ids:      []int  `json:"tileIds"`,
}

Enum_Def :: struct {
	identifier:            string,
	uid:                   int,
	values:                []Enum_Value,
	icon_tileset_uid:      int    `json:"iconTilesetUid"`,
	external_rel_path:     string `json:"externalRelPath"`,
	external_file_checksum: string `json:"externalFileChecksum"`,
	tags:                  []string,
}

Enum_Value :: struct {
	id:        string,
	tile_rect: Tileset_Rect `json:"tileRect"`,
	tile_id:   int          `json:"tileId"`,
	color:     int, // packed RGB
}

Layer_Def :: struct {
	identifier:              string,
	uid:                     int,
	type:                    string `json:"__type"`, // "IntGrid" | "AutoLayer" | "Entities" | "Tiles"
	doc:                     string, // nullable
	ui_color:                string `json:"uiColor"`,
	grid_size:               int    `json:"gridSize"`,
	guide_grid_wid:          int    `json:"guideGridWid"`,
	guide_grid_hei:          int    `json:"guideGridHei"`,
	px_offset_x:             int    `json:"pxOffsetX"`,
	px_offset_y:             int    `json:"pxOffsetY"`,
	parallax_factor_x:       f64   `json:"parallaxFactorX"`,
	parallax_factor_y:       f64   `json:"parallaxFactorY"`,
	parallax_scaling:        bool  `json:"parallaxScaling"`,
	display_opacity:         f64   `json:"displayOpacity"`,
	inactive_opacity:        f64   `json:"inactiveOpacity"`,
	hide_in_list:            bool  `json:"hideInList"`,
	hide_fields_when_inactive: bool `json:"hideFieldsWhenInactive"`,
	can_select_when_inactive:  bool `json:"canSelectWhenInactive"`,
	render_in_world_view:      bool `json:"renderInWorldView"`,
	use_async_render:          bool `json:"useAsyncRender"`,

	required_tags:   []string `json:"requiredTags"`,
	excluded_tags:   []string `json:"excludedTags"`,
	ui_filter_tags:  []string `json:"uiFilterTags"`,

	tile_pivot_x: f64 `json:"tilePivotX"`,
	tile_pivot_y: f64 `json:"tilePivotY"`,

	tileset_def_uid:                  int `json:"tilesetDefUid"`,   // nullable
	auto_source_layer_def_uid:        int `json:"autoSourceLayerDefUid"`, // nullable
	auto_tileset_def_uid:             int `json:"autoTilesetDefUid"`,
	auto_tiles_killed_by_other_layer_uid: int `json:"autoTilesKilledByOtherLayerUid"`,
	biome_field_uid:                  int `json:"biomeFieldUid"`,

	int_grid_values: []Int_Grid_Value_Def `json:"intGridValues"`,
}

Int_Grid_Value_Def :: struct {
	value:      int,
	identifier: string, // nullable
	color:      string,
	tile:       Tileset_Rect,
	group_uid:  int `json:"groupUid"`,
}

Entity_Def :: struct {
	identifier:         string,
	uid:                int,
	doc:                string, // nullable
	color:              string,
	tags:               []string,
	width:              int,
	height:             int,
	resizable_x:        bool `json:"resizableX"`,
	resizable_y:        bool `json:"resizableY"`,
	min_width:          int  `json:"minWidth"`,
	min_height:         int  `json:"minHeight"`,
	max_width:          int  `json:"maxWidth"`,
	max_height:         int  `json:"maxHeight"`,
	keep_aspect_ratio:  bool `json:"keepAspectRatio"`,
	pivot_x:            f64  `json:"pivotX"`,
	pivot_y:            f64  `json:"pivotY"`,

	tile_rect:          Tileset_Rect `json:"tileRect"`, // nullable
	tileset_id:         int          `json:"tilesetId"`, // nullable
	tile_id:            int          `json:"tileId"`,    // nullable

	render_mode:        string `json:"renderMode"`,
	tile_render_mode:   string `json:"tileRenderMode"`,
	show_name:          bool   `json:"showName"`,
	export_to_toc:      bool   `json:"exportToToc"`,
	max_count:          int    `json:"maxCount"`,
	limit_scope:        string `json:"limitScope"`,
	limit_behavior:     string `json:"limitBehavior"`,
	allow_out_of_bounds: bool  `json:"allowOutOfBounds"`,

	tile_opacity:       f64 `json:"tileOpacity"`,
	fill_opacity:       f64 `json:"fillOpacity"`,
	line_opacity:       f64 `json:"lineOpacity"`,
	hollow:             bool,

	nine_slice_borders: []int `json:"nineSliceBorders"`,

	field_defs:         []Field_Def `json:"fieldDefs"`,
}

Field_Def :: struct {
	identifier:    string,
	uid:           int,
	type:          string, // e.g. "F_Int", "F_Enum(66)", "F_EntityRef"
	kind:          string `json:"__type"`, // e.g. "Int", "LocalEnum.Item", "Array<EntityRef>"
	doc:           string, // nullable
	is_array:      bool   `json:"isArray"`,
	can_be_null:   bool   `json:"canBeNull"`,
	array_min_length: int `json:"arrayMinLength"`,
	array_max_length: int `json:"arrayMaxLength"`,
	min:           f64, // nullable
	max:           f64, // nullable
	regex:         string, // nullable
	tileset_uid:   int `json:"tilesetUid"`, // nullable
	allowed_refs:  string `json:"allowedRefs"`,
	allowed_refs_entity_uid: int `json:"allowedRefsEntityUid"`,
	allow_out_of_level_ref:  bool  `json:"allowOutOfLevelRef"`,
}

// ---------------------------------------------------------------------------
// Levels / layers / tiles
// ---------------------------------------------------------------------------

World :: struct {
	iid:                    string,
	identifier:             string,
	world_layout:           string `json:"worldLayout"`,
	world_grid_width:       int    `json:"worldGridWidth"`,
	world_grid_height:      int    `json:"worldGridHeight"`,
	default_level_width:    int    `json:"defaultLevelWidth"`,
	default_level_height:   int    `json:"defaultLevelHeight"`,
	levels:                 []Level,
}

Level :: struct {
	identifier:          string,
	iid:                 string,
	uid:                 int,
	world_x:             int `json:"worldX"`,
	world_y:             int `json:"worldY"`,
	world_depth:         int `json:"worldDepth"`,
	px_wid:              int `json:"pxWid"`,
	px_hei:              int `json:"pxHei"`,

	bg_color:            string `json:"__bgColor"`,
	bg_color_override:   string `json:"bgColor"`, // nullable
	bg_rel_path:         string `json:"bgRelPath"`, // nullable
	bg_pivot_x:          f64    `json:"bgPivotX"`,
	bg_pivot_y:          f64    `json:"bgPivotY"`,
	smart_color:         string `json:"__smartColor"`,

	use_auto_identifier: bool `json:"useAutoIdentifier"`,
	external_rel_path:   string `json:"externalRelPath"`, // nullable

	field_instances:     []Field_Instance `json:"fieldInstances"`,
	layer_instances:     []Layer_Instance `json:"layerInstances"`, // nullable (external levels)
	neighbours:          []Neighbour      `json:"__neighbours"`,
}

Neighbour :: struct {
	level_iid: string `json:"levelIid"`,
	dir:       string,
	level_uid: int `json:"levelUid"`, // nullable
}

Layer_Instance :: struct {
	identifier:          string `json:"__identifier"`,
	type:                string `json:"__type"`, // "IntGrid" | "AutoLayer" | "Entities" | "Tiles"
	c_wid:               int    `json:"__cWid"`,
	c_hei:               int    `json:"__cHei"`,
	grid_size:           int    `json:"__gridSize"`,
	opacity:             f64    `json:"__opacity"`,
	px_total_offset_x:   int    `json:"__pxTotalOffsetX"`,
	px_total_offset_y:   int    `json:"__pxTotalOffsetY"`,
	tileset_def_uid:     int    `json:"__tilesetDefUid"`, // nullable
	tileset_rel_path:    string `json:"__tilesetRelPath"`, // nullable

	iid:                 string,
	level_id:            int `json:"levelId"`,
	layer_def_uid:       int `json:"layerDefUid"`,
	px_offset_x:         int `json:"pxOffsetX"`,
	px_offset_y:         int `json:"pxOffsetY"`,
	visible:             bool,
	seed:                int,
	override_tileset_uid: int `json:"overrideTilesetUid"`, // nullable

	int_grid_csv:        []int  `json:"intGridCsv"`,
	auto_layer_tiles:    []Tile `json:"autoLayerTiles"`,
	grid_tiles:          []Tile `json:"gridTiles"`,
	entity_instances:    []Entity_Instance `json:"entityInstances"`,
}

Tile :: struct {
	px:  []int, // [x, y] position in pixels
	src: []int, // [x, y] position in the tileset
	f:   int,   // flip bits
	t:   int,   // tile id inside the tileset
	d:   []int, // additional per-tile data (intGrid based auto layers)
	a:   f64,   // alpha/opacity (0-1)
}

// ---------------------------------------------------------------------------
// Entities / fields
// ---------------------------------------------------------------------------

Entity_Instance :: struct {
	iid:              string,
	identifier:       string `json:"__identifier"`,
	def_uid:          int    `json:"defUid"`,
	width:            int,
	height:           int,
	px:               []int,  // [x, y] in pixels
	world_x:          int `json:"__worldX"`, // nullable
	world_y:          int `json:"__worldY"`, // nullable
	grid:             []int `json:"__grid"`,
	pivot:            []f64 `json:"__pivot"`,
	tags:             []string `json:"__tags"`,
	smart_color:      string `json:"__smartColor"`,
	tile:             Tileset_Rect `json:"__tile"`, // nullable
	field_instances:  []Field_Instance `json:"fieldInstances"`,
}

Field_Instance :: struct {
	identifier: string `json:"__identifier"`,
	type:       string `json:"__type"`, // e.g. "Int", "LocalEnum.Item", "Array<EntityRef>", ...
	value:      json.Value `json:"__value"`, // heterogeneous by field def
	tile:       Tileset_Rect `json:"__tile"`, // nullable
	def_uid:    int `json:"defUid"`,
}

// ---------------------------------------------------------------------------
// Shared small types
// ---------------------------------------------------------------------------

Tileset_Rect :: struct {
	tileset_uid: int `json:"tilesetUid"`,
	x:           int,
	y:           int,
	w:           int,
	h:           int,
}
