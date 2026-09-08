package main

import "core:log"
import g "../"
import ecs "../ecs"

cleanup_system :: proc(ctx: ^g.Ctx) {
	log.infof("cleanup: мир жив, пулов компонентов: %d", len(ctx.world.pools))
}
