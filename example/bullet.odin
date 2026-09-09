package main

import rl   "vendor:raylib"
import ecs  "../ecs"
import g    "../"
import comp "components"

bullet_spawn :: proc(ctx: ^g.Ctx, pos: [2]f32, side: comp.Side) {
	// Игровая фаза: структуру мира меняем отложенно через cmds —
	// сущность «родится» на cmds_flush (граница update/render).
	b := ecs.cmds_spawn(ctx.cmds)
	ecs.cmds_add(ctx.cmds, b, comp.TBullet{})
	ecs.cmds_add(ctx.cmds, b, comp.Pos(pos))
	ecs.cmds_add(ctx.cmds, b, comp.Size{10, 5})
	ecs.cmds_add(ctx.cmds, b, comp.Speed(400))
	ecs.cmds_add(ctx.cmds, b, comp.Color(rl.WHITE))
	ecs.cmds_add(ctx.cmds, b, comp.Side(side))
}

bullet_move :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	max_x := rl.GetScreenWidth()
	max_y := rl.GetScreenHeight()
	min_x := 0
	min_y := 0
	for ecs.query_next(q) {
		e     := q.entity
		pos   := ecs.query_get(q, e, comp.Pos).?
		speed := ecs.query_get(q, e, comp.Speed).?
		side  := ecs.query_get(q, e, comp.Side).?
		size  := ecs.query_get(q, e, comp.Size).?

		vel2: [2]f32
		switch side^ {
		case .Up:    
			vel2.y -= f32(speed^)
			size^ = {5, 10}
		case .Down:  
			vel2.y += f32(speed^)
			size^ = {5, 10}
		case .Left:  
			vel2.x -= f32(speed^)
		case .Right: 
			vel2.x += f32(speed^)
		}

		pos.x += vel2.x * delta
		pos.y += vel2.y * delta

		if i32(pos.x) > max_x || int(pos.x) < min_x || 
		   i32(pos.y) > max_y || int(pos.y) < min_y {
			ecs.cmds_destroy(ctx.cmds, e)	
		}
	}
}

bullet_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	for ecs.query_next(q) {
		e := q.entity
		p := ecs.query_get(q, e, comp.Pos).?
		s := ecs.query_get(q, e, comp.Size).?
		c := ecs.query_get(q, e, comp.Color).?

		rl.DrawRectangle(
			i32(p.x),
			i32(p.y),
			i32(s.x),
			i32(s.y),
			rl.Color(c^)
		)
	}
}
