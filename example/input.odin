package main

import g "../"
import "../ecs"
import rl "vendor:raylib"


input_system :: proc(ctx: ^g.Ctx(Data), delta: f32) {
	if rl.IsKeyPressed(.I) {
		ctx.data.debug_ui = !ctx.data.debug_ui
	}
}
