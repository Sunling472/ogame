package main

import "core:log"
import "core:math"
import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

// Механика уровня: твёрдость закрытых дверей + взаимодействия (E)
// с дверями (замки/кнопки), предметами и кнопками — данные из LDtk.

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
solid_at_rect :: proc(ctx: ^g.Ctx(Data), x0, y0, x1, y1: f32, doors: ^ecs.Query) -> bool {
	if rect_touches_grid(ctx, x0, y0, x1, y1) do return true
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
// Взаимодействия (клавиша E)
// ---------------------------------------------------------------------------

Hint_Kind :: enum {
	E,         // обычное действие
	Need_KeyA, // дверь заперта на KeyA
	Need_KeyB, // дверь заперта на KeyB
}


// dist_to_rect: расстояние от точки до прямоугольника (0 — внутри).
dist_to_rect :: proc(x, y: f32, x0, y0, x1, y1: f32) -> f32 {
	nx := clamp(x, x0, x1)
	ny := clamp(y, y0, y1)
	dx := x - nx
	dy := y - ny
	return math.sqrt(dx * dx + dy * dy)
}

has_key :: proc(inv: Inventory, lock: Item_Kind) -> bool {
	#partial switch lock {
	case .KeyA: return inv.key_a
	case .KeyB: return inv.key_b
	}
	return true // незаперто
}

// pickup применяет эффект предмета к игроку.
pickup :: proc(ctx: ^g.Ctx(Data), player: ecs.Entity, kind: Item_Kind) {
	inv := ecs.get_component(ctx.world, player, Inventory)
	ps := ecs.get_component(ctx.world, player, Player_State)
	if inv == nil || ps == nil do return

	switch kind {
	case .KeyA:   inv.key_a = true
	case .KeyB:   inv.key_b = true
	case .Health: ps.life = min(ps.life + 30, 100)
	case .Rifle:  ps.ammo += 10
	case .Gold:   inv.score += 100
	case .Wood, .Metal, .Food: inv.score += 10
	case .None: return
	}
	log.infof("подобран предмет: %v (life=%d ammo=%d score=%d keyA=%v keyB=%v)",
		kind, ps.life, ps.ammo, inv.score, inv.key_a, inv.key_b)
}

// toggle_linked_doors переключает двери, связанные с кнопкой.
toggle_linked_doors :: proc(ctx: ^g.Ctx(Data), link: ^Button_Link) {
	for t in link.targets {
		if ds := ecs.get_component(ctx.world, t, Door_State); ds != nil {
			ds.open = !ds.open
		}
	}
}

// do_interact выполняет взаимодействие с выбранным объектом.
do_interact :: proc(ctx: ^g.Ctx(Data), e: ecs.Entity, player: ecs.Entity) {
	// дверь: если заперта — нужен ключ; иначе открыть/закрыть
	if ds := ecs.get_component(ctx.world, e, Door_State); ds != nil {
		inv := ecs.get_component(ctx.world, player, Inventory)
		if ds.lock != .None && (inv == nil || !has_key(inv^, ds.lock)) do return
		ds.open = !ds.open
		return
	}

	// предмет: подобрать и убрать из мира
	if it := ecs.get_component(ctx.world, e, Item_Kind); it != nil && it^ != .None {
		pickup(ctx, player, it^)
		ecs.cmds_destroy(ctx.cmds, e)
		return
	}

	// кнопка: переключить связанные двери
	if link := ecs.get_component(ctx.world, e, Button_Link); link != nil {
		toggle_linked_doors(ctx, link)
	}
}

// interact_system ищет ближайший интерактивный объект рядом с игроком,
// показывает подсказку (в т.ч. какой ключ нужен) и обрабатывает клавишу E.
interact_system :: proc(ctx: ^g.Ctx(Data), q: ^ecs.Query, delta: f32) {
	ctx.data.hint_active = false
	if !scene_ready(ctx) do return

	pq := g.ctx_query(ctx, "player")
	if pq == nil do return
	qv := pq.?

	player, ok := ecs.query_first(&qv).?
	if !ok do return

	ppos := ecs.query_get(&qv, player, Pos).?^

	best_entity: ecs.Entity
	best_dist := max(f32)
	best_pos: [2]f32

	for ecs.query_next(q) {
		it := ecs.query_get(q, q.entity, Interactable).?
		x0, y0, x1, y1 := actor_rect(q, q.entity)

		d := dist_to_rect(ppos.x, ppos.y, x0 - it.range, y0 - it.range, x1 + it.range, y1 + it.range)
		if d < best_dist {
			best_dist = d
			best_entity = q.entity
			best_pos = {(x0 + x1) / 2, y0}
		}
	}

	if best_dist > 0.001 {
		return // рядом никого нет
	}

	ctx.data.hint_active = true
	ctx.data.hint_pos = best_pos
	ctx.data.hint_kind = .E

	// замок: подсказываем, какого ключа не хватает
	if ds := ecs.get_component(ctx.world, best_entity, Door_State); ds != nil {
		if ds.lock != .None {
			inv := ecs.get_component(ctx.world, player, Inventory)
			if inv == nil || !has_key(inv^, ds.lock) {
				ctx.data.hint_kind = ds.lock == .KeyA ? .Need_KeyA : .Need_KeyB
			}
		}
	}

	if rl.IsKeyPressed(.E) {
		do_interact(ctx, best_entity, player)
	}
}

// hint_render рисует подсказку над активным интерактивным объектом.
hint_render :: proc(ctx: ^g.Ctx(Data), q: ^ecs.Query) {
	if !ctx.data.hint_active do return

	rl.BeginMode2D(ctx.data.camera)
	defer rl.EndMode2D()

	text: cstring
	col: rl.Color
	switch ctx.data.hint_kind {
	case .E:         text = "E";        col = rl.RAYWHITE
	case .Need_KeyA: text = "KEY A";    col = rl.RED
	case .Need_KeyB: text = "KEY B";    col = rl.RED
	}
	rl.DrawText(text, i32(ctx.data.hint_pos.x) - 12, i32(ctx.data.hint_pos.y) - 20, 16, col)
}
