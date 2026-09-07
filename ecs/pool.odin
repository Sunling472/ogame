package ecs2

import "core:mem"

Pool :: struct {
	tid:      typeid,
	stride:   int,
	align:    int,

	// dense
	entities: [dynamic]Entity,
	data:     [dynamic]byte,

	//sparse
	sparse:   [dynamic]int,
}

@(private)
_pool_has :: proc(p: ^Pool, e: Entity) -> bool {
	if int(e) >= len(p.sparse) do return false
	return p.sparse[int(e)] != -1
}

@(private)
_pool_add :: proc(p: ^Pool, e: Entity) {
	for int(e) >= len(p.sparse) {
		append(&p.sparse, -1)
	}

	di := len(p.entities)
	append(&p.entities, e)
	p.sparse[int(e)] = di

	if p.stride > 0 {
		resize(&p.data, len(p.data) + p.stride)
	}
}

@(private)
_pool_remove :: proc(p: ^Pool, e: Entity) {
	if int(e) >= len(p.sparse) do return

	removed_idx := p.sparse[int(e)]
	if removed_idx == -1 do return

	last_idx := len(p.entities) - 1

	if removed_idx != last_idx {
		last_entity := p.entities[last_idx]

		if p.stride > 0 {
			dst := &p.data[removed_idx * p.stride]
			src := &p.data[last_idx * p.stride]
			mem.copy(dst, src, p.stride)
		}

		p.entities[removed_idx] = last_entity
		p.sparse[int(last_entity)] = removed_idx
	}

	pop(&p.entities)

	if p.stride > 0 {
		resize(&p.data, len(p.data) - p.stride)
	}

	p.sparse[int(e)] = -1
}
