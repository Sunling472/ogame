package main

import "core:math"
import g "../"
import ecs "../ecs"
import ldtk "../ldtk"
import rl "vendor:raylib"

// Игрок: ввод + движение с коллизиями по IntGrid "Collisions".

PLAYER_SPEED :: f32(130)

is_solid_cell :: proc(cx, cy: int) -> bool {
	if g_collisions == nil do return false
	v, ok := ldtk.int_grid_cell(g_collisions, cx, cy)
	return ok && v != 0
}

// rect_touches_solid проверяет прямоугольник игрока (уже в level-координатах)
// на пересечение с любыми твёрдыми клетками intGrid.
rect_touches_solid :: proc(x0, y0, x1, y1: f32) -> bool {
	gs := f32(g_collisions.grid_size)
	min_cx := int(math.floor(x0 / gs))
	max_cx := int(math.floor((x1 - 0.001) / gs))
	min_cy := int(math.floor(y0 / gs))
	max_cy := int(math.floor((y1 - 0.001) / gs))
	for cy in min_cy ..= max_cy {
		for cx in min_cx ..= max_cx {
			if is_solid_cell(cx, cy) do return true
		}
	}
	return false
}

// move_resolved двигает позицию-центр с разрешением коллизий по осям.
move_resolved :: proc(pos: ^[2]f32, v: [2]f32, half: [2]f32) {
	// ось X
	pos.x += v.x
	if rect_touches_solid(pos.x - half.x, pos.y - half.y, pos.x + half.x, pos.y + half.y) {
		pos.x -= v.x
	}
	// ось Y
	pos.y += v.y
	if rect_touches_solid(pos.x - half.x, pos.y - half.y, pos.x + half.x, pos.y + half.y) {
		pos.y -= v.y
	}
}

player_update :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	if !scene_ready() do return

	if player, ok := ecs.query_first(q).?; ok {
		pos := ecs.query_get(q, player, Pos).?
		vel := ecs.query_get(q, player, Vel).?

		vel^ = {}
		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    do vel.y -= PLAYER_SPEED
		if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  do vel.y += PLAYER_SPEED
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  do vel.x -= PLAYER_SPEED
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do vel.x += PLAYER_SPEED

		if vel.x != 0 && vel.y != 0 { // нормализуем диагональ
			v := [2]f32{vel.x, vel.y}
			len := math.sqrt(v.x * v.x + v.y * v.y)
			vel.x = v.x / len * PLAYER_SPEED
			vel.y = v.y / len * PLAYER_SPEED
		}

		// игрок 16x16; коллайдер чуть меньше, чтобы не лип к углам
		move_resolved((^[2]f32)(pos), [2]f32{vel.x * delta, vel.y * delta}, {6, 6})
	}
}
