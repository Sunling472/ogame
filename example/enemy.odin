package main

import "core:math/rand"
import "../ecs"
import g "../"
import rl "vendor:raylib"
import comp "components"

move_enemy_acc:  f32
move_enemy_time: f32 = 2

enemy_spawn :: proc(ctx: ^g.Ctx, pos: [2]f32) {
	enemy := ecs.entity_new(ctx.world)
	ecs.add_component(ctx.world, enemy, comp.TEnemy{})
	ecs.add_component(ctx.world, enemy, comp.Pos{pos.x, pos.y})
	ecs.add_component(ctx.world, enemy, comp.Size{ 20, 40 })
	ecs.add_component(ctx.world, enemy, comp.Speed{})
	ecs.add_component(ctx.world, enemy, comp.Color(rl.GREEN))
}

enemy_update :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	enemy_x: f32 = rand.float32_range(10, f32(rl.GetScreenWidth())  - 30)
	enemy_y: f32 = rand.float32_range(10, f32(rl.GetScreenHeight()) - 30)

	move_enemy_acc += delta
	if _, ok := ecs.query_first(q).?; !ok {
		enemy_spawn(ctx, [2]f32{enemy_x, enemy_y})
	} 
}

enemy_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if enemy, ok := ecs.query_first(q).?; ok {
		pos   := ecs.query_get(q, enemy, comp.Pos).?
		size  := ecs.query_get(q, enemy, comp.Size).?
		color := ecs.query_get(q, enemy, comp.Color).?

		rl.DrawRectangle(
			i32(pos.x),
			i32(pos.y),
			i32(size.x),
			i32(size.y),
			rl.Color(color^)
		)
	}
}
