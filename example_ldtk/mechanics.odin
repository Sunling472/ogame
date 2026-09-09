package main

import "core:fmt"
import "core:math"
import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

// Механика уровня: твёрдость закрытых дверей + интерактивные объекты (E).

rects_overlap :: proc(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1: f32) -> bool {
	return ax0 < bx1 && bx0 < ax1 && ay0 < by1 && by0 < ay1
}

// actor_rect: прямоугольник актора (anchor/pivot/size) в координатах уровня.
actor_rect :: proc(q: ^ecs.Query, e: ecs.Entity) -> (x0, y0, x1, y1: f32) {
	anchor := ecs.query_get(q, e, Pos).?^
	size   := ecs.query_get(q, e, Size).?^
	pivot  := ecs.query_get(q, e, Pivot).?^
	tl := top_left(cast([2]f32)anchor, pivot, size)
	return tl.x, tl.y, tl.x + size.w, tl.y + size.h
}

// solid_at_rect: пересекает ли прямоугольник что-то твёрдое — клетки IntGrid
// или ЗАКРЫТУЮ дверь. doors может быть nil (тогда только сетка).
solid_at_rect :: proc(x0, y0, x1, y1: f32, doors: ^ecs.Query) -> bool {
	if rect_touches_grid(x0, y0, x1, y1) do return true
	if doors == nil do return false

	ecs.query_reset(doors)
	for ecs.query_next(doors) {
		d := doors.entity
		st := ecs.query_get(doors, d, Door_State).?
		if st.open do continue // в открытую дверь проходим

		dx0, dy0, dx1, dy1 := actor_rect(doors, d)
		if rects_overlap(x0, y0, x1, y1, dx0, dy0, dx1, dy1) do return true
	}
	return false
}

// ---------------------------------------------------------------------------
// Интерактивные объекты: подошёл вплотную (в пределах range) -> E
// ---------------------------------------------------------------------------

// состояние подсказки на текущий кадр (обновляет interact_system,
// рисует hint_render)
g_hint_active: bool
g_hint_pos:    [2]f32

// dist_to_rect: расстояние от точки до прямоугольника (0 — внутри).
dist_to_rect :: proc(x, y: f32, x0, y0, x1, y1: f32) -> f32 {
	nx := clamp(x, x0, x1)
	ny := clamp(y, y0, y1)
	dx := x - nx
	dy := y - ny
	return math.sqrt(dx * dx + dy * dy)
}

// do_interact выполняет взаимодействие с выбранным объектом.
do_interact :: proc(ctx: ^g.Ctx, e: ecs.Entity) {
	// пока поддерживаем кнопки: переключить связанные двери
	link := ecs.get_component(ctx.world, e, Button_Link)
	if link == nil do return

	for t in link.targets {
		if st := ecs.get_component(ctx.world, t, Door_State); st != nil {
			st.open = !st.open
		}
	}
}

// interact_system ищет ближайший интерактивный объект рядом с игроком,
// показывает подсказку и обрабатывает клавишу E.
interact_system :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	g_hint_active = false
	if !scene_ready() do return

	pq := g.ctx_query(ctx, "player")
	if pq == nil do return
	qv := pq.?

	player, ok := ecs.query_first(&qv).?
	if !ok do return

	ppos  := ecs.query_get(&qv, player, Pos).?^
	psize := ecs.query_get(&qv, player, Size).?^

	best_entity: ecs.Entity
	best_dist := max(f32)
	best_pos: [2]f32

	for ecs.query_next(q) {
		it := ecs.query_get(q, q.entity, Interactable).?
		x0, y0, x1, y1 := actor_rect(q, q.entity)

		// центр игрока относительно расширенного прямоугольника объекта:
		// расстояние до «вплотную» зоны
		d := dist_to_rect(ppos.x, ppos.y, x0 - it.range, y0 - it.range, x1 + it.range, y1 + it.range)
		if d < best_dist {
			best_dist = d
			best_entity = q.entity
			best_pos = {(x0 + x1) / 2, y0} // подсказка над объектом
		}
	}

	// используем небольшой зазор, чтобы «вплотную» не было ровно 0
	if best_dist <= 0.001 {
		g_hint_active = true
		g_hint_pos = best_pos

		if rl.IsKeyPressed(.E) {
			do_interact(ctx, best_entity)
		}
	}
}

// hint_render рисует подсказку «E» над активным интерактивным объектом.
hint_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if !g_hint_active do return

	rl.BeginMode2D(g_camera)
	defer rl.EndMode2D()

	buf: [32]byte
	text := fmt.bprintf(buf[:], "E")
	rl.DrawText(cstring(raw_data(text)), i32(g_hint_pos.x) - 5, i32(g_hint_pos.y) - 18, 16, rl.RAYWHITE)
}
