package ecs

import "core:mem"

Entity :: distinct uint

World :: struct {
	next_id:  uint,
	free:     [dynamic]Entity,
	pools:    [dynamic]^Pool,
	pool_for: map[typeid]int,

	// locked: run() ставит true на время игровой фазы (update/render).
	// В это время прямые структурные мутации (add_component/remove_component/
	// destroy_entity) запрещены — структуру меняют только через cmds_*,
	// а применяет её cmds_flush на границе фаз. Так пулы не двигаются,
	// пока системы держат указатели на компоненты.
	locked: bool,
}

world_new :: proc(allocator := context.allocator) -> (w: World) {
	w.free = make([dynamic]Entity, allocator)
	w.pools = make([dynamic]^Pool, allocator)
	w.pool_for = make(map[typeid]int, allocator)

	return
}

/*
world_destroy frees everything the ECS itself allocated: every pool's
containers and pool object, plus the world's own lists/map. It needs no
allocator argument and guesses nothing:

- [dynamic] and map containers remember the allocator they were made with
  (stored in their header), so plain delete() is always correct;
- each Pool object keeps the allocator of the exact _pool_for call that
  allocated it, so free(p, p.allocator) is always correct too.

User-owned data (e.g. strings/slices inside component values) is NOT freed:
components are copied by value into the pool and the world cannot know about
their internals. Free such data yourself before calling world_destroy (e.g.
in a game CleanupSystem).

Allocator-agnostic by design: on a heap-like allocator this releases memory;
on an arena every delete/free is a no-op and the arena itself is freed with
arena_free_all. The world is zeroed afterwards, so a second world_destroy is
a harmless no-op.
*/
world_destroy :: proc(w: ^World) {
	if w == nil do return

	for p in w.pools {
		delete(p.entities) // containers remember their allocator
		delete(p.data)
		delete(p.sparse)
		free(p, p.allocator) // the pool object itself
	}

	delete(w.pools)
	delete(w.free)
	delete(w.pool_for)

	w^ = {}
}

@(private)
_pool_for :: proc(w: ^World, $T: typeid, allocator := context.allocator) -> ^Pool {
	return _pool_for_id(w, typeid_of(T), size_of(T), align_of(T), allocator)
}

// runtime (type-erased) variant: used by cmds_flush, where component types
// are known only as typeid/size/align values.
@(private)
_pool_for_id :: proc(w: ^World, tid: typeid, size, align: int, allocator: mem.Allocator) -> ^Pool {
	if idx, ok := w.pool_for[tid]; ok do return w.pools[idx]

	p, alloc_err := new(Pool, allocator)
	if alloc_err != nil do panic("Pool allocation error")

	p.tid, p.align = tid, align
	p.stride = _stride_of(size, p.align)
	p.allocator = allocator // this pool remembers the allocator of ITS creation

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

STRUCTURAL_LOCKED_MSG :: "structural mutation during the game phase: pools must not move while systems hold component pointers. Use cmds_spawn/cmds_add/cmds_remove/cmds_destroy inside update/render; direct add_component/remove_component/destroy_entity is only allowed outside the locked phase (init/cleanup)."

destroy_entity :: proc(w: ^World, e: Entity) {
	assert(!w.locked, STRUCTURAL_LOCKED_MSG)
	_destroy_entity_impl(w, e)
}

// unlocked impl used by cmds_flush at the phase boundary.
@(private)
_destroy_entity_impl :: proc(w: ^World, e: Entity) {
	for p in w.pools {
		if int(e) < len(p.sparse) {
			_pool_remove(p, e)
		}
	}
	append(&w.free, e)
}

/*
add_component stores (or overwrites) a component of type T on entity e.

Phase rule: adding a component grows the pool's dense storage and can
invalidate previously obtained ^T pointers, therefore during the game phase
(world.locked, see run) only cmds_add may be used; the actual add is applied
by cmds_flush at the phase boundary. Outside the locked phase (init/cleanup)
direct use is fine.
*/
add_component :: proc(w: ^World, e: Entity, c: $T) {
	assert(!w.locked, STRUCTURAL_LOCKED_MSG)
	c := c
	_add_component_bytes(w, e, typeid_of(T), size_of(T), align_of(T), &c, context.allocator)
}

// runtime (type-erased) add: copy `size` bytes from `ptr` into the pool slot.
@(private)
_add_component_bytes :: proc(w: ^World, e: Entity, tid: typeid, size, align: int, ptr: rawptr, allocator: mem.Allocator) {
	p := _pool_for_id(w, tid, size, align, allocator)
	if !_pool_has(p, e) do _pool_add(p, e)

	if p.stride > 0 {
		di := p.sparse[int(e)]
		mem.copy(&p.data[di * p.stride], ptr, size)
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

/*
remove_component removes the component of type T from entity e, if present.

Phase rule (see add_component): removal uses swap-remove, which MOVES the
dense slot of the last entity — during the game phase it must go through
cmds_remove and is applied by cmds_flush at the phase boundary.
*/
remove_component :: proc(w: ^World, e: Entity, $T: typeid) {
	assert(!w.locked, STRUCTURAL_LOCKED_MSG)
	_remove_component_tid(w, e, typeid_of(T))
}

// runtime (type-erased) variant used by cmds_flush.
@(private)
_remove_component_tid :: proc(w: ^World, e: Entity, tid: typeid) {
	if idx, ok := w.pool_for[tid]; ok {
		_pool_remove(w.pools[idx], e)
	}
}
