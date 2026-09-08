package main

import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

background_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	rl.ClearBackground(rl.BLACK)
}
