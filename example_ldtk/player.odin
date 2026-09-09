package main

import "core:math"
import g "../"
import ecs "../ecs"
import ldtk "../ldtk"
import rl "vendor:raylib"

// Игрок: ввод + движение с коллизиями по IntGrid активного уровня.
is_solid_cell :: proc(ctx: ^g.Ctx(Data), cx, cy: int) -> bool {
	if ctx.data.cur_coll == nil do return false
	v, ok := ldtk.int_grid_cell(ctx.data.cur_coll, cx, cy)
	return ok && v != 0
}

// rect_touches_grid проверяет прямоугольник в МИРОВЫХ координатах на
// пересечение с любыми твёрдыми клетками intGrid активного уровня.
rect_touches_grid :: proc(ctx: ^g.Ctx(Data), x0, y0, x1, y1: f32) -> bool {
	if ctx.data.cur_level == nil || ctx.data.cur_coll == nil do return false

	ox, oy := f32(ctx.data.cur_level.world_x), f32(ctx.data.cur_level.world_y)
	gs := f32(ctx.data.cur_coll.grid_size)

	lx0, ly0 := x0 - ox, y0 - oy
	lx1, ly1 := x1 - ox, y1 - oy

	min_cx := int(math.floor(lx0 / gs))
	max_cx := int(math.floor((lx1 - 0.001) / gs))
	min_cy := int(math.floor(ly0 / gs))
	max_cy := int(math.floor((ly1 - 0.001) / gs))
	for cy in min_cy ..= max_cy {
		for cx in min_cx ..= max_cx {
			if is_solid_cell(ctx, cx, cy) do return true
		}
	}
	return false
}

// move_resolved двигает позицию-центр с разрешением коллизий по осям.
// doors — read-запрос дверей (nil = только intGrid): закрытые двери блокируют.
move_resolved :: proc(ctx: ^g.Ctx(Data), pos: ^[2]f32, v: [2]f32, half: [2]f32, doors: ^ecs.Query) {
	// ось X
	pos.x += v.x
	if solid_at_rect(ctx, pos.x - half.x, pos.y - half.y, pos.x + half.x, pos.y + half.y, doors) {
		pos.x -= v.x
	}
	// ось Y
	pos.y += v.y
	if solid_at_rect(ctx, pos.x - half.x, pos.y - half.y, pos.x + half.x, pos.y + half.y, doors) {
		pos.y -= v.y
	}
}

player_update :: proc(ctx: ^g.Ctx(Data), q: ^ecs.Query, delta: f32) {
	if !scene_ready(ctx) do return

	// read-запрос закрытых/открытых дверей (кешируется фреймворком)
	door_q: ecs.Query
	has_doors := false
	if dq := g.ctx_query(ctx, "doors"); dq != nil {
		door_q = dq.?
		has_doors = true
	}

	if player, ok := ecs.query_first(q).?; ok {
		pos := ecs.query_get(q, player, Pos).?
		vel := ecs.query_get(q, player, Vel).?
		speed := ecs.query_get(q, player, Speed).?
		f32_speed := f32(speed^)

		// активный уровень = тот, где сейчас игрок (для сетки коллизий)
		_refresh_active_level(ctx, pos.x, pos.y)

		vel^ = {}
		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    do vel.y -= f32_speed
		if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  do vel.y += f32_speed
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  do vel.x -= f32_speed
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do vel.x += f32_speed

		if vel.x != 0 && vel.y != 0 { // нормализуем диагональ
			v := [2]f32{vel.x, vel.y}
			len := math.sqrt(v.x * v.x + v.y * v.y)
			vel.x = v.x / len * f32_speed
			vel.y = v.y / len * f32_speed
		}

		// игрок 16x16; коллайдер чуть меньше, чтобы не лип к углам
		doors_arg := has_doors ? &door_q : nil
		move_resolved(ctx, (^[2]f32)(pos), [2]f32{vel.x * delta, vel.y * delta}, {6, 6}, doors_arg)

		// камера плавно едет за игроком (кадр-независимый lerp)
		k := clamp(10 * delta, 0, 1)
		ctx.data.cam_follow.x += (pos.x - ctx.data.cam_follow.x) * k
		ctx.data.cam_follow.y += (pos.y - ctx.data.cam_follow.y) * k
	}
}
