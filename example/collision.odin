package main

import "../ecs"
import g "../"
import rl "vendor:raylib"
import comp "components"


bullet_collision :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	eq, ok := g.ctx_query(ctx, "enemies").?
	if !ok do return

	for ecs.query_next(q) {
		bullet := q.entity
		b_pos  := ecs.query_get(q, bullet, comp.Pos).?
		b_size := ecs.query_get(q, bullet, comp.Size).?

		r1 := rl.Rectangle {
			f32(b_pos.x),
			f32(b_pos.y),
			f32(b_size.x),
			f32(b_size.y)
		}

		ecs.query_reset(&eq)
		for ecs.query_next(&eq) {
			enemy  := eq.entity
			e_pos  := ecs.query_get(&eq, enemy, comp.Pos).?
			e_size := ecs.query_get(&eq, enemy, comp.Size).?
			
			r2 := rl.Rectangle {
				f32(e_pos.x),
				f32(e_pos.y),
				f32(e_size.x),
				f32(e_size.y)
			}

			if rl.CheckCollisionRecs(r1, r2) {
				ecs.cmds_destroy(ctx.cmds, bullet)
				ecs.cmds_destroy(ctx.cmds, enemy)
				break // пуля убита — остальных врагов в этом кадре не проверяем
			}
		}
	}
}

player_border_collision :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	min_x: f32 = 0
	min_y: f32 = 0
	max_x: f32 = f32(rl.GetScreenWidth())
	max_y: f32 = f32(rl.GetScreenHeight())

	if player, ok := ecs.query_first(q).?; ok {
		pos   := ecs.query_get(q, player, comp.Pos).?
		size  := ecs.query_get(q, player, comp.Size).?
		speed := ecs.query_get(q, player, comp.Speed).?
		vel   := ecs.query_get(q, player, comp.Vel).?

		left   := pos.x
		right  := pos.x + f32(size.x)
		top    := pos.y
		bottom := pos.y + f32(size.y)

		if left   < 0      do pos.x = 0
		if top    < 0      do pos.y = 0
		if right  > max_x  do pos.x = max_x - f32(size.x)
		if bottom > max_y  do pos.y = max_y - f32(size.y)
	}
}
