package main

import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

background_render :: proc(ctx: ^g.Ctx(Data)) {
	rl.ClearBackground(rl.BLACK)
}
