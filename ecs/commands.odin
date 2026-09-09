package ecs

import "core:mem"

/*
Deferred structural changes.

During the game phase (world.locked — see world.odin / run in game.odin) the
pools must not move while systems hold component pointers, so every
structural change goes through Commands and is applied by cmds_flush ONCE at
the phase boundary, in a fixed order:

	1. adds    — spawns/component writes (new entities become real here)
	2. removes — swap-remove happens here, outside any live pointers
	3. destroys — entities die and their ids return to the free list

Therefore: VALUES may be written immediately through component pointers;
STRUCTURE (spawn / add / remove / destroy) is always deferred via cmds_*.

Deferred add payload: for now every cmds_add copies the component bytes into
a small allocation freed at flush. Planned improvement (documented, not yet
implemented): a linear scratch buffer owned by Commands (bump appends, rewind
at flush) so mass spawning does not allocate per operation.
*/

Queued_Add :: struct {
	entity: Entity,
	tid:    typeid,
	size:   int,
	align:  int,
	blob:   rawptr, // копия байт значения, аллоцирована c.allocator
}

Queued_Remove :: struct {
	entity: Entity,
	tid:    typeid,
}

Commands :: struct {
	world:     ^World,
	allocator: mem.Allocator, // this Commands remembers the allocator of ITS creation
	destroys:  [dynamic]Entity,
	adds:      [dynamic]Queued_Add,
	removes:   [dynamic]Queued_Remove,
}

// cmds_init prepares a command buffer for one run/game session. The same
// allocator is used for the queue payloads (blobs) of deferred adds.
cmds_init :: proc(c: ^Commands, world: ^World, allocator := context.allocator) {
	c.world = world
	c.allocator = allocator
	c.destroys = make([dynamic]Entity, allocator)
	c.adds = make([dynamic]Queued_Add, allocator)
	c.removes = make([dynamic]Queued_Remove, allocator)
}

// cmds_free releases the command buffer itself (call after the last flush,
// e.g. in run's teardown). Arena-safe like everything else in this package.
cmds_free :: proc(c: ^Commands) {
	if c == nil do return
	for a in c.adds {
		if a.blob != nil do free(a.blob, c.allocator)
	}
	delete(c.adds)
	delete(c.removes)
	delete(c.destroys)
	c^ = {}
}

// cmds_spawn hands out a new entity id immediately (id allocation does not
// move pools, so it is safe during the game phase). The entity becomes real
// (gets its components) at the next cmds_flush.
cmds_spawn :: proc(c: ^Commands) -> Entity {
	return entity_new(c.world)
}

// cmds_add defers writing component T on entity e until cmds_flush. Multiple
// adds of the same type on the same entity in one frame: the last wins.
cmds_add :: proc(c: ^Commands, e: Entity, value: $T) {
	blob, alloc_err := mem.alloc(size_of(T), align_of(T), c.allocator)
	if alloc_err != nil do panic("cmds_add: blob allocation failed")
	value := value
	mem.copy(blob, &value, size_of(T))

	append(&c.adds, Queued_Add {
		entity = e,
		tid    = typeid_of(T),
		size   = size_of(T),
		align  = align_of(T),
		blob   = blob,
	})
}

// cmds_remove defers removing component T from entity e until cmds_flush.
cmds_remove :: proc(c: ^Commands, e: Entity, $T: typeid) {
	append(&c.removes, Queued_Remove{entity = e, tid = typeid_of(T)})
}

// cmds_destroy defers destroying entity e (deduplicated within one frame).
cmds_destroy :: proc(c: ^Commands, e: Entity) {
	for d in c.destroys {
		if d == e do return
	}
	append(&c.destroys, e)
}

// cmds_flush applies all deferred structural changes in the fixed order
// adds → removes → destroys, then rewinds the queues for the next frame.
// Must run at the phase boundary (after update systems, before render in run).
cmds_flush :: proc(c: ^Commands) {
	for &a in c.adds {
		_add_component_bytes(c.world, a.entity, a.tid, a.size, a.align, a.blob, c.allocator)
		free(a.blob, c.allocator)
		a.blob = nil
	}
	clear(&c.adds)

	for r in c.removes {
		_remove_component_tid(c.world, r.entity, r.tid)
	}
	clear(&c.removes)

	for e in c.destroys {
		_destroy_entity_impl(c.world, e)
	}
	clear(&c.destroys)
}
