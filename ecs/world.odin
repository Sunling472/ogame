package ecs2

import "core:mem"

Entity :: distinct uint

World :: struct {
	next_id:  uint,
	free:     [dynamic]Entity,
	pools:    [dynamic]^Pool,
	pool_for: map[typeid]int,
}

world_new :: proc(allocator := context.allocator) -> (w: World) {
	w.free = make([dynamic]Entity, allocator)
	w.pools = make([dynamic]^Pool, allocator)
	w.pool_for = make(map[typeid]int, allocator)

	return
}

@(private)
_pool_for :: proc(w: ^World, $T: typeid, allocator := context.allocator) -> ^Pool {
	tid := typeid_of(T)
	if idx, ok := w.pool_for[tid]; ok do return w.pools[idx]

	p, alloc_err := new(Pool, allocator)
	if alloc_err != nil do panic("Pool allocation error")

	p.tid, p.align = tid, align_of(T)
	p.stride = _stride_of(size_of(T), p.align)

	p.entities = make([dynamic]Entity, allocator)
	if p.stride > 0 do p.data = make([dynamic]byte, allocator)

	p.sparse = make([dynamic]int, allocator)

	append(&w.pools, p)
	w.pool_for[tid] = len(w.pools) - 1

	return p
}

entity_new :: proc(w: ^World) -> Entity {
	if len(w.free) > 0 do return pop(&w.free)

	e := Entity(w.next_id)
	w.next_id += 1

	return e
}

destroy_entity :: proc(w: ^World, e: Entity) {
	for p in w.pools {
		if int(e) < len(p.sparse) {
			_pool_remove(p, e)
		}
	}
	append(&w.free, e)
}

add_component :: proc(w: ^World, e: Entity, c: $T) {
	p := _pool_for(w, T)
	if !_pool_has(p, e) do _pool_add(p, e)

	if p.stride > 0 {
		di := p.sparse[int(e)]
		c := c
		mem.copy(&p.data[di * p.stride], &c, size_of(T))
	}
}

get_component :: proc(w: ^World, e: Entity, $T: typeid) -> ^T {
	idx, ok := w.pool_for[typeid_of(T)]
	if !ok do return nil

	p := w.pools[idx]
	if int(e) >= len(p.sparse) do return nil

	di := p.sparse[int(e)]
	if di < 0 || p.stride == 0 do return nil

	return cast(^T)&p.data[di * p.stride]
}

remove_component :: proc(w: ^World, e: Entity, $T: typeid) {
	if idx, ok := w.pool_for[typeid_of(T)]; ok {
		_pool_remove(w.pools[idx], e)
	}
}
