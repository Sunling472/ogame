package ldtk

import "core:encoding/json"
import "core:os"

/*
Loader for LDtk project files (JSON export, see schema.odin for the typed
model). Unknown keys in the file are skipped, so the model may stay a
"working subset" of the full LDtk schema.

Memory: the returned Project (its strings, dynamic arrays, maps and json.Value
contents) is allocated with the provided allocator and must outlive all uses
of the values it references.
*/

// load parses an LDtk project from raw JSON bytes.
load :: proc(data: []byte, allocator := context.allocator) -> (project: Project, err: json.Unmarshal_Error) {
	err = json.unmarshal(data, &project, allocator = allocator)
	return
}

// load_file reads an .ldtk file and parses it. ok == false means the file
// could not be read; err != nil means it failed to parse.
load_file :: proc(path: string, allocator := context.allocator) -> (project: Project, ok: bool, err: json.Unmarshal_Error) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		return {}, false, nil
	}
	defer delete(data, allocator)

	project, err = load(data, allocator)
	return project, err == nil, err
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
