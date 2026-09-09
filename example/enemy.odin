package main

import "core:math"
import "core:math/rand"
import "../ecs"
import g "../"
import rl "vendor:raylib"
import comp "components"

move_enemy_acc:  f32
move_enemy_time: f32 = 2

enemy_spawn :: proc(ctx: ^g.Ctx(Data), pos: [2]f32) {
	// Игровая фаза: структуру — отложенно через cmds.
	e := ecs.cmds_spawn(ctx.cmds)
	ecs.cmds_add(ctx.cmds, e, comp.TEnemy{})
	ecs.cmds_add(ctx.cmds, e, comp.Pos{pos.x, pos.y})
	ecs.cmds_add(ctx.cmds, e, comp.Size{ 20, 40 })
	ecs.cmds_add(ctx.cmds, e, comp.Speed(100))
	ecs.cmds_add(ctx.cmds, e, comp.Color(rl.GREEN))
}

enemy_update :: proc(ctx: ^g.Ctx(Data), delta: f32) {
	enemy_x: f32 = rand.float32_range(10, f32(rl.GetScreenWidth())  - 30)
	enemy_y: f32 = rand.float32_range(10, f32(rl.GetScreenHeight()) - 30)

	move_enemy_acc += delta
	if _, ok := ecs.query_first(ctx.query).?; !ok {
		enemy_spawn(ctx, [2]f32{enemy_x, enemy_y})
	} 
}

enemy_move :: proc(ctx: ^g.Ctx(Data), delta: f32) {
	pq := g.ctx_query(ctx, "player").?
	if player, ok := ecs.query_first(&pq).?; ok {
		player_pos := ecs.query_get(&pq, player, comp.Pos).?
		for ecs.query_next(ctx.query) {
			enemy := ctx.query.entity
			pos   := ecs.query_get(ctx.query, enemy, comp.Pos).?
			speed := ecs.query_get(ctx.query, enemy, comp.Speed).?
			
			enemy_direct: [2]f32
			enemy_direct.x = player_pos.x - pos.x
			enemy_direct.y = player_pos.y - pos.y

			dist := math.sqrt_f32(enemy_direct.x * enemy_direct.x + enemy_direct.y * enemy_direct.y)
			
			step := f32(speed^) * delta
			pos.x += (enemy_direct.x / dist) * step
			pos.y += (enemy_direct.y / dist) * step
		}
	}
}

enemy_render :: proc(ctx: ^g.Ctx(Data)) {
	if enemy, ok := ecs.query_first(ctx.query).?; ok {
		pos   := ecs.query_get(ctx.query, enemy, comp.Pos).?
		size  := ecs.query_get(ctx.query, enemy, comp.Size).?
		color := ecs.query_get(ctx.query, enemy, comp.Color).?

		rl.DrawRectangle(
			i32(pos.x),
			i32(pos.y),
			i32(size.x),
			i32(size.y),
			rl.Color(color^)
		)
	}
}
