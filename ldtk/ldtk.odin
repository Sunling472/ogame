package ldtk

import "core:encoding/json"
import "core:mem"
import "core:os"

/*
LDtk project loader: pure data layer, no engine or game dependencies.

Model coverage (schema anchor: LDtk JSON_SCHEMA 1.5.3, https://ldtk.io/files/JSON_SCHEMA.json):
The typed model in schema.odin covers everything needed to LOAD AND USE levels:
project root, defs (layers/entities/tilesets/enums/field defs), levels
(root + multi-worlds), layer instances (tiles, intGrid, entities), fields.
Intentionally NOT modeled (keys are skipped by json.unmarshal, verified
behavior): editor-only deep data (auto-layer rules, intGrid value groups,
realEditorValues), tileset cachedPixelData/customData, toc/customCommands,
and legacy/rare fields. Unknown keys are always skipped safely, so the model
is a forward-compatible "working subset", not a strict mirror of the schema.

JSON keys are matched EXACTLY against the `json:"..."` struct tags.

Memory model:
- All strings, slices, dynamic arrays and json.Value contents returned by
  load/load_file are allocated with the allocator passed to them.
- The input data buffer is only needed during the call: unmarshal copies
  every string, so load_file may (and does) free the buffer afterwards.
- project_destroy(project, allocator) frees everything recursively. It must
  be called with the same allocator that loaded the project. Alternatively
  load into an arena/temp allocator and free it wholesale without destroy.
- Helper results that allocate (value_entity_refs, field_entity_refs,
  value_ints/..., levels_all) must be freed by the caller with delete.

Semantics:
- absent vs null: both leave the field zeroed (a missing "nullable" string
  and an explicit null are indistinguishable); fine for gameplay data.
- coordinates: entity px is level-local and points at the entity anchor
  (pivot), e.g. top-left for pivot (0,0), center for (0.5,0.5); __worldX/Y
  is the same position in world space. Tile px is level-local too; auto
  layers may add the layer's px_total_offset (e.g. -16 wall tops). intGrid
  cell (x,y) lives at int_grid_csv[y * c_wid + x].
*/

// load parses an LDtk project from raw JSON bytes.
load :: proc(data: []byte, allocator := context.allocator) -> (project: Project, err: json.Unmarshal_Error) {
	err = json.unmarshal(data, &project, allocator = allocator)
	return
}

// load_file reads an .ldtk file and parses it. err == nil means success;
// a non-nil read_err means the file could not be read, a non-nil err means
// it could not be parsed. The returned project must be freed with
// project_destroy (or by freeing the whole allocator).
load_file :: proc(path: string, allocator := context.allocator) -> (project: Project, err: json.Unmarshal_Error, read_err: os.Error) {
	data, rerr := os.read_entire_file(path, allocator)
	if rerr != nil {
		return {}, nil, rerr
	}
	defer delete(data, allocator)

	project, err = load(data, allocator)
	return project, err, nil
}

// ---------------------------------------------------------------------------
// Lookups
// ---------------------------------------------------------------------------

layer_def_by_uid :: proc(p: ^Project, uid: int) -> Maybe(^Layer_Def) {
	for &l in p.defs.layers {
		if l.uid == uid do return &l
	}
	return nil
}

layer_def_by_identifier :: proc(p: ^Project, identifier: string) -> Maybe(^Layer_Def) {
	for &l in p.defs.layers {
		if l.identifier == identifier do return &l
	}
	return nil
}

entity_def_by_uid :: proc(p: ^Project, uid: int) -> Maybe(^Entity_Def) {
	for &e in p.defs.entities {
		if e.uid == uid do return &e
	}
	return nil
}

tileset_by_uid :: proc(p: ^Project, uid: int) -> Maybe(^Tileset_Def) {
	for &t in p.defs.tilesets {
		if t.uid == uid do return &t
	}
	return nil
}

// ---------------------------------------------------------------------------
// Field value accessors (Field_Instance.value is a heterogeneous json.Value)
// ---------------------------------------------------------------------------

value_string :: proc(v: json.Value) -> Maybe(string) {
	if s, ok := v.(json.String); ok {
		return s
	}
	return nil
}

value_int :: proc(v: json.Value) -> Maybe(i64) {
	if i, ok := v.(json.Integer); ok {
		return i
	}
	if f, ok := v.(json.Float); ok {
		if f == f64(int(f)) do return i64(f)
	}
	return nil
}

value_float :: proc(v: json.Value) -> Maybe(f64) {
	if f, ok := v.(json.Float); ok {
		return f
	}
	if i, ok := v.(json.Integer); ok {
		return f64(i)
	}
	return nil
}

value_bool :: proc(v: json.Value) -> Maybe(bool) {
	if b, ok := v.(json.Boolean); ok {
		return b
	}
	return nil
}

value_array :: proc(v: json.Value) -> Maybe(json.Array) {
	if a, ok := v.(json.Array); ok {
		return a
	}
	return nil
}

value_object :: proc(v: json.Value) -> Maybe(json.Object) {
	if o, ok := v.(json.Object); ok {
		return o
	}
	return nil
}

@(private)
_is_null :: proc(v: json.Value) -> bool {
	_, is_nil := v.(json.Null)
	return is_nil
}

// value_ints converts a JSON array of integers into a typed slice.
// Null elements are skipped; ok == false when v is not an array or contains
// a non-integral value. The result is allocated and must be freed by caller.
value_ints :: proc(v: json.Value, allocator := context.allocator) -> (ints: []i64, ok: bool) {
	arr, is_arr := v.(json.Array)
	if !is_arr do return nil, false

	out := make([dynamic]i64, allocator)
	for item in arr {
		if _is_null(item) do continue
		if n := value_int(item); n != nil {
			append(&out, n.?)
		} else {
			delete(out)
			return nil, false
		}
	}
	return out[:], true
}

// value_floats converts a JSON array of numbers into a typed slice.
// Null elements are skipped; ok == false when v is not an array or contains
// a non-numeric value. The result is allocated and must be freed by caller.
value_floats :: proc(v: json.Value, allocator := context.allocator) -> (floats: []f64, ok: bool) {
	arr, is_arr := v.(json.Array)
	if !is_arr do return nil, false

	out := make([dynamic]f64, allocator)
	for item in arr {
		if _is_null(item) do continue
		if n := value_float(item); n != nil {
			append(&out, n.?)
		} else {
			delete(out)
			return nil, false
		}
	}
	return out[:], true
}

// value_strings converts a JSON array of strings (e.g. "MultiLines", arrays
// of enum values) into a typed slice. Null elements are skipped; ok == false
// when v is not an array or contains a non-string value. The element strings
// are borrowed from the project's storage; only the returned slice itself is
// allocated and must be freed by the caller (delete the slice, not elements).
value_strings :: proc(v: json.Value, allocator := context.allocator) -> (strings: []string, ok: bool) {
	arr, is_arr := v.(json.Array)
	if !is_arr do return nil, false

	out := make([dynamic]string, allocator)
	for item in arr {
		if _is_null(item) do continue
		if s, conv := item.(json.String); conv {
			append(&out, s)
		} else {
			delete(out)
			return nil, false
		}
	}
	return out[:], true
}

// ---------------------------------------------------------------------------
// Entity reference helpers
// ---------------------------------------------------------------------------

object_to_ref :: proc(o: json.Object) -> Entity_Ref {
	r: Entity_Ref
	for key, v in o {
		s, is_str := v.(json.String)
		if !is_str do continue
		switch key {
		case "entityIid": r.entity_iid = s
		case "layerIid":  r.layer_iid = s
		case "levelIid":  r.level_iid = s
		case "worldIid":  r.world_iid = s
		}
	}
	return r
}

// value_entity_refs decodes a field value holding LDtk entity references
// (a single EntityRef object or an array of them) into typed Entity_Refs.
// The returned slice is allocated and must be freed by the caller.
// ok == false when the value is neither an object nor an array.
value_entity_refs :: proc(v: json.Value, allocator := context.allocator) -> (refs: []Entity_Ref, ok: bool) {
	out := make([dynamic]Entity_Ref, allocator)

	#partial switch x in v {
	case json.Object:
		append(&out, object_to_ref(x))
	case json.Array:
		for item in x {
			if o, is_obj := item.(json.Object); is_obj {
				append(&out, object_to_ref(o))
			}
		}
	case:
		delete(out)
		return nil, false
	}

	return out[:], true
}

// ---------------------------------------------------------------------------
// Field access on entity instances
// ---------------------------------------------------------------------------

// field_in finds a field by its LDtk identifier ("life", "lockedWith", ...)
// in a slice of field instances (works for entity and level fields alike).
field_in :: proc(fields: []Field_Instance, name: string) -> Maybe(^Field_Instance) {
	for &f in fields {
		if f.identifier == name do return &f
	}
	return nil
}

// field finds a field of an entity instance by its LDtk identifier.
field :: proc(ei: ^Entity_Instance, name: string) -> Maybe(^Field_Instance) {
	if ei == nil do return nil
	return field_in(ei.field_instances, name)
}

field_int :: proc(ei: ^Entity_Instance, name: string) -> Maybe(i64) {
	if fi := field(ei, name); fi != nil {
		return value_int(fi.?.value)
	}
	return nil
}

field_float :: proc(ei: ^Entity_Instance, name: string) -> Maybe(f64) {
	if fi := field(ei, name); fi != nil {
		return value_float(fi.?.value)
	}
	return nil
}

field_string :: proc(ei: ^Entity_Instance, name: string) -> Maybe(string) {
	if fi := field(ei, name); fi != nil {
		return value_string(fi.?.value)
	}
	return nil
}

field_bool :: proc(ei: ^Entity_Instance, name: string) -> Maybe(bool) {
	if fi := field(ei, name); fi != nil {
		return value_bool(fi.?.value)
	}
	return nil
}

// field_ints reads an integer-array field ("Array<Int>" etc). The result is
// allocated and must be freed by the caller.
field_ints :: proc(ei: ^Entity_Instance, name: string, allocator := context.allocator) -> (ints: []i64, ok: bool) {
	if fi := field(ei, name); fi != nil {
		return value_ints(fi.?.value, allocator)
	}
	return nil, false
}

// field_floats reads a numeric-array field ("Array<Float>" etc). The result
// is allocated and must be freed by the caller.
field_floats :: proc(ei: ^Entity_Instance, name: string, allocator := context.allocator) -> (floats: []f64, ok: bool) {
	if fi := field(ei, name); fi != nil {
		return value_floats(fi.?.value, allocator)
	}
	return nil, false
}

// field_strings reads a string-array field ("MultiLines", "Array<String>",
// arrays of enum ids). Only the returned slice is allocated and must be
// freed by the caller; element strings are borrowed from the project.
field_strings :: proc(ei: ^Entity_Instance, name: string, allocator := context.allocator) -> (strings: []string, ok: bool) {
	if fi := field(ei, name); fi != nil {
		return value_strings(fi.?.value, allocator)
	}
	return nil, false
}

// field_entity_refs resolves a ref field ("EntityRef" / "Array<EntityRef>")
// of an entity instance. The returned slice is allocated and must be freed
// by the caller.
field_entity_refs :: proc(ei: ^Entity_Instance, name: string, allocator := context.allocator) -> (refs: []Entity_Ref, ok: bool) {
	if fi := field(ei, name); fi != nil {
		return value_entity_refs(fi.?.value, allocator)
	}
	return nil, false
}

// ---------------------------------------------------------------------------
// Level / layer access
// ---------------------------------------------------------------------------

// level_by_uid finds a level (root or world level) by its project-wide uid.
level_by_uid :: proc(p: ^Project, uid: int) -> Maybe(^Level) {
	for &l in p.levels {
		if l.uid == uid do return &l
	}
	for &w in p.worlds {
		for &l in w.levels {
			if l.uid == uid do return &l
		}
	}
	return nil
}

// level_by_identifier finds a level (root or world level) by identifier.
level_by_identifier :: proc(p: ^Project, identifier: string) -> Maybe(^Level) {
	for &l in p.levels {
		if l.identifier == identifier do return &l
	}
	for &w in p.worlds {
		for &l in w.levels {
			if l.identifier == identifier do return &l
		}
	}
	return nil
}

// layer_instance finds a layer instance of a level by its identifier.
layer_instance :: proc(lv: ^Level, identifier: string) -> Maybe(^Layer_Instance) {
	if lv == nil do return nil
	for &li in lv.layer_instances {
		if li.identifier == identifier do return &li
	}
	return nil
}

// int_grid_cell reads one cell of an IntGrid layer instance at grid
// coordinates (x, y); the value is 0 for empty cells. ok == false when the
// coordinates fall outside the layer.
int_grid_cell :: proc(li: ^Layer_Instance, x, y: int) -> (value: int, ok: bool) {
	if li == nil do return 0, false
	if x < 0 || y < 0 || x >= li.c_wid || y >= li.c_hei do return 0, false
	return li.int_grid_csv[y * li.c_wid + x], true
}

// ---------------------------------------------------------------------------
// World helpers (pure data, no engine dependencies)
// ---------------------------------------------------------------------------

// world_bounds returns the axis-aligned bounds of every level of the project
// (root levels + multi-world levels) in px: useful for camera clamping and
// viewport culling. ok == false when the project has no levels.
world_bounds :: proc(p: ^Project) -> (min_x, min_y, max_x, max_y: int, ok: bool) {
	_grow_world_bounds(p.levels, &min_x, &min_y, &max_x, &max_y, &ok)
	for &w in p.worlds {
		_grow_world_bounds(w.levels, &min_x, &min_y, &max_x, &max_y, &ok)
	}
	return
}

@(private)
_grow_world_bounds :: proc(
	levels: []Level,
	min_x, min_y, max_x, max_y: ^int,
	ok: ^bool,
) {
	for &l in levels {
		x0, y0 := l.world_x, l.world_y
		x1, y1 := x0 + l.px_wid, y0 + l.px_hei
		if !ok^ {
			min_x^, min_y^, max_x^, max_y^ = x0, y0, x1, y1
			ok^ = true
		} else {
			min_x^ = min(min_x^, x0)
			min_y^ = min(min_y^, y0)
			max_x^ = max(max_x^, x1)
			max_y^ = max(max_y^, y1)
		}
	}
}

// level_at_world_point returns the level whose rect contains the given
// world-space point (px), or nil. Searches root and multi-world levels.
level_at_world_point :: proc(p: ^Project, wx, wy: int) -> Maybe(^Level) {
	for &l in p.levels {
		if wx >= l.world_x && wx < l.world_x + l.px_wid &&
		   wy >= l.world_y && wy < l.world_y + l.px_hei {
			return &l
		}
	}
	for &w in p.worlds {
		for &l in w.levels {
			if wx >= l.world_x && wx < l.world_x + l.px_wid &&
			   wy >= l.world_y && wy < l.world_y + l.px_hei {
				return &l
			}
		}
	}
	return nil
}

// entity_by_iid finds an entity instance by its project-wide iid, searching
// every Entities layer of every level (root + worlds).
entity_by_iid :: proc(p: ^Project, iid: string) -> Maybe(^Entity_Instance) {
	if e := _entity_by_iid_in_levels(p.levels, iid); e != nil do return e
	for &w in p.worlds {
		if e := _entity_by_iid_in_levels(w.levels, iid); e != nil do return e
	}
	return nil
}

@(private)
_entity_by_iid_in_levels :: proc(levels: []Level, iid: string) -> Maybe(^Entity_Instance) {
	for &l in levels {
		for &li in l.layer_instances {
			for &e in li.entity_instances {
				if e.iid == iid do return &e
			}
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Destruction
// ---------------------------------------------------------------------------

/*
project_destroy frees every string, slice and json.Value allocated while
loading the project. Must be called with the same allocator that was passed
to load/load_file. After the call the project must not be used anymore.

When the project was loaded into an arena/temp allocator, freeing the arena
is enough and project_destroy can be skipped.
*/
project_destroy :: proc(p: ^Project, allocator := context.allocator) {
	if p == nil do return

	delete(p.header.file_type, allocator)
	delete(p.header.app, allocator)
	delete(p.header.doc, allocator)
	delete(p.header.schema, allocator)
	delete(p.header.app_author, allocator)
	delete(p.header.app_version, allocator)
	delete(p.header.url, allocator)

	delete(p.iid, allocator)
	delete(p.json_version, allocator)
	delete(p.identifier_style, allocator)
	delete(p.bg_color, allocator)
	delete(p.default_level_bg_color, allocator)
	delete(p.level_name_pattern, allocator)
	delete(p.dummy_world_iid, allocator)
	delete(p.world_layout, allocator)
	delete(p.image_export_mode, allocator)
	delete(p.backup_rel_path, allocator)
	_delete_strings(p.flags, allocator)

	_defs_destroy(&p.defs, allocator)

	for &l in p.levels do _level_destroy(&l, allocator)
	delete(p.levels, allocator)

	for &w in p.worlds do _world_destroy(&w, allocator)
	delete(p.worlds, allocator)
}

@(private)
_delete_strings :: proc(list: []string, allocator: mem.Allocator) {
	for s in list {
		delete(s, allocator)
	}
	delete(list, allocator)
}

@(private)
_defs_destroy :: proc(d: ^Defs, allocator: mem.Allocator) {
	for &t in d.tilesets do _tileset_destroy(&t, allocator)
	delete(d.tilesets, allocator)
	for &l in d.layers do _layer_def_destroy(&l, allocator)
	delete(d.layers, allocator)
	for &f in d.level_fields do _field_def_destroy(&f, allocator)
	delete(d.level_fields, allocator)
	for &e in d.enums do _enum_destroy(&e, allocator)
	delete(d.enums, allocator)
	for &e in d.entities do _entity_def_destroy(&e, allocator)
	delete(d.entities, allocator)
	for &e in d.external_enums do _enum_destroy(&e, allocator)
	delete(d.external_enums, allocator)
}

@(private)
_tileset_destroy :: proc(t: ^Tileset_Def, allocator: mem.Allocator) {
	delete(t.identifier, allocator)
	delete(t.rel_path, allocator)
	_delete_strings(t.tags, allocator)
	for &et in t.enum_tags {
		delete(et.enum_value_id, allocator)
		delete(et.tile_ids, allocator)
	}
	delete(t.enum_tags, allocator)
}

@(private)
_enum_destroy :: proc(e: ^Enum_Def, allocator: mem.Allocator) {
	delete(e.identifier, allocator)
	for &v in e.values {
		delete(v.id, allocator)
	}
	delete(e.values, allocator)
	delete(e.external_rel_path, allocator)
	delete(e.external_file_checksum, allocator)
	_delete_strings(e.tags, allocator)
}

@(private)
_layer_def_destroy :: proc(l: ^Layer_Def, allocator: mem.Allocator) {
	delete(l.identifier, allocator)
	delete(l.doc, allocator)
	delete(l.ui_color, allocator)
	_delete_strings(l.required_tags, allocator)
	_delete_strings(l.excluded_tags, allocator)
	_delete_strings(l.ui_filter_tags, allocator)
	for &iv in l.int_grid_values {
		delete(iv.identifier, allocator)
		delete(iv.color, allocator)
	}
	delete(l.int_grid_values, allocator)
}

@(private)
_entity_def_destroy :: proc(e: ^Entity_Def, allocator: mem.Allocator) {
	delete(e.identifier, allocator)
	delete(e.doc, allocator)
	delete(e.color, allocator)
	_delete_strings(e.tags, allocator)
	delete(e.nine_slice_borders, allocator)
	for &f in e.field_defs do _field_def_destroy(&f, allocator)
	delete(e.field_defs, allocator)
}

@(private)
_field_def_destroy :: proc(f: ^Field_Def, allocator: mem.Allocator) {
	delete(f.identifier, allocator)
	delete(f.type, allocator)
	delete(f.kind, allocator)
	delete(f.doc, allocator)
	delete(f.regex, allocator)
}

@(private)
_world_destroy :: proc(w: ^World, allocator: mem.Allocator) {
	delete(w.iid, allocator)
	delete(w.identifier, allocator)
	delete(w.world_layout, allocator)
	for &l in w.levels do _level_destroy(&l, allocator)
	delete(w.levels, allocator)
}

@(private)
_level_destroy :: proc(l: ^Level, allocator: mem.Allocator) {
	delete(l.identifier, allocator)
	delete(l.iid, allocator)
	delete(l.bg_color, allocator)
	delete(l.bg_color_override, allocator)
	delete(l.bg_rel_path, allocator)
	delete(l.smart_color, allocator)
	delete(l.external_rel_path, allocator)

	for &n in l.neighbours {
		delete(n.level_iid, allocator)
		delete(n.dir, allocator)
	}
	delete(l.neighbours, allocator)

	for &f in l.field_instances do _field_instance_destroy(&f, allocator)
	delete(l.field_instances, allocator)

	for &li in l.layer_instances do _layer_instance_destroy(&li, allocator)
	delete(l.layer_instances, allocator)
}

@(private)
_layer_instance_destroy :: proc(li: ^Layer_Instance, allocator: mem.Allocator) {
	delete(li.identifier, allocator)
	delete(li.type, allocator)
	delete(li.tileset_rel_path, allocator)
	delete(li.iid, allocator)
	delete(li.int_grid_csv, allocator)

	for &t in li.auto_layer_tiles do _tile_destroy(&t, allocator)
	delete(li.auto_layer_tiles, allocator)
	for &t in li.grid_tiles do _tile_destroy(&t, allocator)
	delete(li.grid_tiles, allocator)

	for &e in li.entity_instances do _entity_instance_destroy(&e, allocator)
	delete(li.entity_instances, allocator)
}

@(private)
_tile_destroy :: proc(t: ^Tile, allocator: mem.Allocator) {
	delete(t.px, allocator)
	delete(t.src, allocator)
	delete(t.d, allocator)
}

@(private)
_entity_instance_destroy :: proc(e: ^Entity_Instance, allocator: mem.Allocator) {
	delete(e.iid, allocator)
	delete(e.identifier, allocator)
	delete(e.px, allocator)
	delete(e.grid, allocator)
	delete(e.pivot, allocator)
	_delete_strings(e.tags, allocator)
	delete(e.smart_color, allocator)
	for &f in e.field_instances do _field_instance_destroy(&f, allocator)
	delete(e.field_instances, allocator)
}

@(private)
_field_instance_destroy :: proc(f: ^Field_Instance, allocator: mem.Allocator) {
	delete(f.identifier, allocator)
	delete(f.type, allocator)
	json.destroy_value(f.value, allocator)
}
