package main

import "core:fmt"
import g "../"
import "../ecs"
import rl "vendor:raylib"
import comp "components"

show_ui: bool

ui_debug_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if !show_ui do return

	// закешированный фреймворком запрос — без построения на каждый тик
	pq, ok := g.ctx_query(ctx, "player").?
	if !ok do return

	if player, ok := ecs.query_first(&pq).?; ok {
		pos    := ecs.query_get(&pq, player, comp.Pos).?
		vel    := ecs.query_get(&pq, player, comp.Vel).?
		side   := ecs.query_get(&pq, player, comp.Side).?
		weapon := ecs.query_get(&pq, player, comp.Weapon).?
		sprint := ecs.query_get(&pq, player, comp.Sprint).?

		// ВАЖНО про память: рендер идёт каждый кадр, поэтому никаких аллокаций
		// в context.allocator (в примере это арена — росла бы бесконечно).
		// fmt.caprintf аллоцирует — нельзя. fmt.bprintf пишет в наш стек-буфер:
		// ноль аллокаций в кадр. (Общее правило: «на кадр» — только
		// context.temp_allocator или стек-буфер.)
		buf: [256]byte
		text := fmt.bprintf(
			buf[:],
			"X = {}\nY = {}\nSide = {}\nVel = {}\nSPRINT = {}",
			i32(pos.x), i32(pos.y), side^, vel^, sprint^,
		)

		rl.DrawText(cstring(raw_data(text)), 10, 10, 30, rl.WHITE)
	}
}
