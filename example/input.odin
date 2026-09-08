package main

import g "../"
import "../ecs"
import rl "vendor:raylib"


input_system :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	if rl.IsKeyPressed(.I) {
		show_ui = !show_ui
	}
}
