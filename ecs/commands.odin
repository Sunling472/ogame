package ecs2

Commands :: struct {
	world:    ^World,
	destroys: [dynamic]Entity,
}

cmds_destroy :: proc(c: ^Commands, e: Entity) {
	for d in c.destroys {
		if d == e do return
	}
	append(&c.destroys, e)
}

cmds_flush :: proc(c: ^Commands) {
	for e in c.destroys do destroy_entity(c.world, e)
	clear(&c.destroys)
}
