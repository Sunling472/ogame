package main

import "core:fmt"
import "core:log"
import g "../"
import ecs "../ecs"
import ldtk "../ldtk"
import rl "vendor:raylib"

// Сцена: загрузка LDtk-проекта, тайлсетов и спавн акторов уровня.
// Пути относительно корня репозитория (запуск: odin run example_ldtk).

PROJECT_PATH :: "ldtk/example/example.ldtk"
LEVEL_DIR    :: "ldtk/example/"

// Камера: мир рисуется в мировых координатах, масштаб задаёт zoom (2x).
g_camera:     rl.Camera2D
g_cam_follow: [2]f32 // куда камера плавно едет (позиция игрока)

g_project: ldtk.Project
g_levels:  []ldtk.Level  // все уровни проекта (слайс в g_project)
g_world:   struct { min_x, min_y, max_x, max_y: f32 } // границы всего мира

// активный уровень (тот, где сейчас игрок) — его IntGrid для коллизий
g_cur_level: ^ldtk.Level
g_cur_coll:  ^ldtk.Layer_Instance // слой "Collisions" активного уровня

g_ready: bool

g_textures:      map[i32]rl.Texture2D
g_texture_uids:  [dynamic]i32
g_tileset_grid:  i32 // grid_size тайлсета уровня (для рисования тайлов)

hex_nibble :: proc(ch: byte) -> u8 {
	switch {
	case ch >= '0' && ch <= '9': return ch - '0'
	case ch >= 'a' && ch <= 'f': return ch - 'a' + 10
	case ch >= 'A' && ch <= 'F': return ch - 'A' + 10
	}
	return 0
}

// hex_color парсит "#RRGGBB" в rl.Color.
hex_color :: proc(s: string) -> rl.Color {
	c: rl.Color = {255, 255, 255, 255}
	if len(s) < 7 do return c
	r := 16 * hex_nibble(s[1]) + hex_nibble(s[2])
	gg := 16 * hex_nibble(s[3]) + hex_nibble(s[4])
	b := 16 * hex_nibble(s[5]) + hex_nibble(s[6])
	return rl.Color{r, gg, b, 255}
}

// top_left возвращает левый верхний угол прямоугольника по якорю (px), pivot и размеру.
top_left :: proc(anchor: [2]f32, pivot: Pivot, size: Size) -> [2]f32 {
	return {anchor.x - pivot.x * size.w, anchor.y - pivot.y * size.h}
}

scene_ready :: proc() -> bool {
	return g_ready && len(g_levels) > 0
}

// _level_collisions: IntGrid-слой "Collisions" уровня.
_level_collisions :: proc(lv: ^ldtk.Level) -> ^ldtk.Layer_Instance {
	for &li in lv.layer_instances {
		if li.identifier == "Collisions" {
			return &li
		}
	}
	return nil
}

// level_at_point: уровень, содержащий мировую точку (и его слой Collisions).
level_at_point :: proc(x, y: f32) -> (lv: ^ldtk.Level, coll: ^ldtk.Layer_Instance) {
	for &l in g_levels {
		x0, y0 := f32(l.world_x), f32(l.world_y)
		if x >= x0 && x < x0 + f32(l.px_wid) &&
		   y >= y0 && y < y0 + f32(l.px_hei) {
			return &l, _level_collisions(&l)
		}
	}
	return nil, nil
}

_compute_world_bounds :: proc() {
	g_world = {1e9, 1e9, -1e9, -1e9}
	for &l in g_levels {
		x0, y0 := f32(l.world_x), f32(l.world_y)
		x1, y1 := x0 + f32(l.px_wid), y0 + f32(l.px_hei)
		g_world.min_x = min(g_world.min_x, x0)
		g_world.min_y = min(g_world.min_y, y0)
		g_world.max_x = max(g_world.max_x, x1)
		g_world.max_y = max(g_world.max_y, y1)
	}
}

scene_init :: proc(ctx: ^g.Ctx) {
	project, err, rerr := ldtk.load_file(PROJECT_PATH)
	if rerr != nil {
		log.errorf("ldtk: не удалось прочитать %s: %v", PROJECT_PATH, rerr)
		return
	}
	if err != nil {
		log.errorf("ldtk: ошибка парсинга %s: %v", PROJECT_PATH, err)
		return
	}
	g_project = project
	g_levels = g_project.levels
	if len(g_levels) == 0 {
		log.errorf("ldtk: в проекте нет уровней")
		return
	}
	_compute_world_bounds()

	g_textures     = make(map[i32]rl.Texture2D)
	g_texture_uids = make([dynamic]i32, context.allocator)

	_load_tile_textures()
	_spawn_level_entities(ctx)

	// стартовый активный уровень — по позиции игрока (камера уже на нём)
	if lv, cl := level_at_point(g_cam_follow.x, g_cam_follow.y); lv != nil {
		g_cur_level = lv
		g_cur_coll = cl
	}

	g_ready = true
	log.infof(
		"ldtk: мир загружен, уровней %d, границы (%.0f..%.0f, %.0f..%.0f)",
		len(g_levels), g_world.min_x, g_world.max_x, g_world.min_y, g_world.max_y,
	)
}

_load_tile_textures :: proc() {
	for &lv in g_levels {
		for &li in lv.layer_instances {
			has_tiles := len(li.auto_layer_tiles) > 0 || len(li.grid_tiles) > 0
			if !has_tiles || li.tileset_def_uid <= 0 do continue

			uid := i32(li.tileset_def_uid)
			if uid in g_textures do continue

			ts_maybe := ldtk.tileset_by_uid(&g_project, li.tileset_def_uid)
			if ts_maybe == nil do continue
			ts := ts_maybe.?
			if ts.rel_path == "" do continue // встроенные иконки (embed) — без файла

			// путь атласа в стек-буфер (без аллокаций): LoadTexture читает файл
			// синхронно, буфер можно не хранить
			path_buf: [256]byte
			path := fmt.bprintf(path_buf[:], "%s%s", LEVEL_DIR, ts.rel_path)
			tex := rl.LoadTexture(cstring(raw_data(path)))
			if tex.id == 0 {
				log.errorf("не удалось загрузить тайлсет %s", path)
				continue
			}
			g_textures[uid] = tex
			append(&g_texture_uids, uid)
			g_tileset_grid = i32(ts.tile_grid_size)
			log.infof("загружен атлас %s (%dx%d)", path, tex.width, tex.height)
		}
	}
}

// pass 1: спавним акторов ВСЕХ уровней (координаты — мировые), помечаем
// двери/кнопки, запоминаем iid → Entity.
_spawn_level_entities :: proc(ctx: ^g.Ctx) {
	iid_map := make(map[string]ecs.Entity)
	defer delete(iid_map)

	for &lv in g_levels {
		ox, oy := f32(lv.world_x), f32(lv.world_y)

		for &li in lv.layer_instances {
			if li.type != "Entities" do continue

			for &ei in li.entity_instances {
				ent := ecs.entity_new(ctx.world)

				anchor := [2]f32{ox + f32(ei.px[0]), oy + f32(ei.px[1])}
				size := Size{f32(ei.width), f32(ei.height)}
				px := [2]f64{0, 0}
				if len(ei.pivot) >= 2 do px = [2]f64{ei.pivot[0], ei.pivot[1]}

				color: rl.Color = {255, 255, 255, 255}
				if def := ldtk.entity_def_by_uid(&g_project, ei.def_uid); def != nil {
					color = hex_color(def.?.color)
				}

				ecs.add_component(ctx.world, ent, TActor{})
				ecs.add_component(ctx.world, ent, Pos(anchor))
				ecs.add_component(ctx.world, ent, size)
				ecs.add_component(ctx.world, ent, Pivot{f32(px.x), f32(px.y)})
				ecs.add_component(ctx.world, ent, Col{color})

				iid_map[ei.iid] = ent

				// категория для отрисовки (в этом сэмпле спрайты сущностей —
				// встроенные иконки LDtk, файла нет, поэтому рисуем процедурно)
				kind: Actor_Kind = .None
				switch ei.identifier {
				case "Player":     kind = .Player
				case "Door":       kind = .Door
				case "Button":     kind = .Button
				case "Item":       kind = .Item
				case "SecretWall": kind = .Secret_Wall
				}
				if kind != .None do ecs.add_component(ctx.world, ent, kind)

				switch ei.identifier {
				case "Player":
					life := 100
					ammo := 0
					if l := ldtk.field_int(&ei, "life"); l != nil do life = int(l.?)
					if a := ldtk.field_int(&ei, "ammo"); a != nil do ammo = int(a.?)

					ecs.add_component(ctx.world, ent, TPlayer{})
					ecs.add_component(ctx.world, ent, Vel{})
					ecs.add_component(ctx.world, ent, Player_State{life, ammo})
					ecs.add_component(ctx.world, ent, Speed(130))
					g_cam_follow = anchor // камера стартует на игроке
					log.infof("игрок: life=%d ammo=%d", life, ammo)

				case "Door":
					ecs.add_component(ctx.world, ent, TDoor{})
					ecs.add_component(ctx.world, ent, Door_State{open = false})

				case "Button":
					ecs.add_component(ctx.world, ent, TButton{})
					ecs.add_component(ctx.world, ent, Interactable{range = 20})
				}
			}
		}
	}

	// pass 2: кнопки -> связанные двери (поле LDtk "targets", EntityRef-ы по iid)
	for &lv in g_levels {
		for &li in lv.layer_instances {
			if li.type != "Entities" do continue

			for &ei in li.entity_instances {
				if ei.identifier != "Button" do continue

				button := iid_map[ei.iid]
				targets: [dynamic]ecs.Entity
				refs, ok := ldtk.field_entity_refs(&ei, "targets")
				if !ok {
					continue
				}
				defer delete(refs)

				for r in refs {
					if door, found := iid_map[r.entity_iid]; found {
						append(&targets, door)
					} else {
						log.warnf("кнопка ссылается на неизвестную сущность %s", r.entity_iid)
					}
				}
				ecs.add_component(ctx.world, button, Button_Link{targets})
				log.infof("кнопка связана с %d дверьми", len(targets))
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Рендер уровня и акторов
// ---------------------------------------------------------------------------

// cam_axis_target: целевая координата камеры по одной оси, ограниченная
// границами мира (не показываем пустоту). Если мир влезает в экран по этой
// оси целиком — держим его центр.
cam_axis_target :: proc(follow, min_x, max_x, view_half: f32) -> f32 {
	if max_x - min_x <= 2 * view_half do return (min_x + max_x) / 2
	return clamp(follow, min_x + view_half, max_x - view_half)
}

// level_render рисует тайловые слои ВСЕХ уровней мира (атлас uid 1) под камерой.
level_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	rl.ClearBackground({14, 17, 26, 255})
	if !scene_ready() do return

	// камера: zoom фиксирован, offset — центр экрана, target плавно следует за игроком
	g_camera.zoom = 2
	g_camera.offset = {
		f32(rl.GetScreenWidth()) * 0.5,
		f32(rl.GetScreenHeight()) * 0.5,
	}

	// полвида камеры в мировых единицах: (экран/2) / zoom
	view_half := [2]f32{
		f32(rl.GetScreenWidth()) * 0.5 / g_camera.zoom,
		f32(rl.GetScreenHeight()) * 0.5 / g_camera.zoom,
	}
	// ограничиваем цель границами мира
	g_camera.target.x = cam_axis_target(g_cam_follow.x, g_world.min_x, g_world.max_x, view_half.x)
	g_camera.target.y = cam_axis_target(g_cam_follow.y, g_world.min_y, g_world.max_y, view_half.y)

	rl.BeginMode2D(g_camera)
	defer rl.EndMode2D()

	gs := g_tileset_grid
	if gs <= 0 do gs = 16

	for &lv in g_levels {
		ox, oy := f32(lv.world_x), f32(lv.world_y)

		// фон уровня
		rl.DrawRectangle(i32(ox), i32(oy), i32(lv.px_wid), i32(lv.px_hei), hex_color(lv.bg_color))

		// слои рисуем снизу вверх (в файле верхние идут первыми)
		for i := len(lv.layer_instances) - 1; i >= 0; i -= 1 {
			li := &lv.layer_instances[i]
			if li.type == "Entities" do continue
			tex, have_tex := g_textures[i32(li.tileset_def_uid)]
			if !have_tex do continue

			for &t in li.auto_layer_tiles do _draw_tile(tex, t, gs, ox, oy)
			for &t in li.grid_tiles       do _draw_tile(tex, t, gs, ox, oy)
		}
	}
}

_draw_tile :: proc(tex: rl.Texture2D, t: ldtk.Tile, gs: i32, ox, oy: f32) {
	src := rl.Rectangle{f32(t.src[0]), f32(t.src[1]), f32(gs), f32(gs)}
	if t.f & 1 != 0 do src.width = -src.width // flip X
	if t.f & 2 != 0 do src.height = -src.height // flip Y

	dest := rl.Rectangle {
		ox + f32(t.px[0]),
		oy + f32(t.px[1]),
		f32(gs),
		f32(gs),
	}
	rl.DrawTexturePro(tex, src, dest, {0, 0}, 0, rl.WHITE)
}

// shade возвращает цвет, затемнённый/осветлённый в f раз (0..1).
shade :: proc(c: rl.Color, f: f32) -> rl.Color {
	r := u8(clamp(i32(f32(c.r) * f), 0, 255))
	g := u8(clamp(i32(f32(c.g) * f), 0, 255))
	b := u8(clamp(i32(f32(c.b) * f), 0, 255))
	return rl.Color{r, g, b, c.a}
}

// draw_actor_icon рисует «иконку» актора по категории.
draw_actor_icon :: proc(tl: [2]f32, size: Size, kind: Actor_Kind, col: rl.Color, open: bool) {
	x0, y0 := tl.x, tl.y
	x1, y1 := tl.x + size.w, tl.y + size.h
	cx, cy := (x0 + x1) / 2, (y0 + y1) / 2
	rect := rl.Rectangle{x0, y0, size.w, size.h}

	switch kind {
	case .Door:
		if open {
			// открытая дверь — проём: полупрозрачная рама
			rl.DrawRectangleRec(rect, {col.r, col.g, col.b, 60})
			rl.DrawRectangleLinesEx(rect, 1.5, shade(col, 0.6))
			return
		}
		// закрытая дверь: панели
		rl.DrawRectangleRec(rect, col)
		panel := shade(col, 0.55)
		rl.DrawRectangleLinesEx(rect, 2, panel)
		rl.DrawRectangle(i32(x0 + size.w * 0.28), i32(y0 + 1), i32(size.w * 0.12), i32(size.h - 2), panel)
		rl.DrawRectangle(i32(x0 + size.w * 0.60), i32(y0 + 1), i32(size.w * 0.12), i32(size.h - 2), panel)
		rl.DrawCircle(i32(cx), i32(cy + size.h * 0.28), 2.5, {10, 10, 10, 255}) // ручка

	case .Button:
		// плашка-кнопка: тёмная подложка + яркая крышка
		r := min(size.w, size.h) * 0.5
		rl.DrawCircle(i32(cx), i32(cy), r, shade(col, 0.45))
		rl.DrawCircle(i32(cx), i32(cy), r * 0.62, col)
		rl.DrawCircle(i32(cx), i32(cy), r * 0.3, shade(col, 0.7))

	case .Item:
		// предмет: ромб
		rl.DrawTriangle({cx, y0}, {x1 - 1, cy}, {cx, y1 - 1}, shade(col, 0.8))
		rl.DrawTriangle({cx, y0}, {x0 + 1, cy}, {cx, y1 - 1}, col)
		rl.DrawTriangleLines({cx, y0}, {x1 - 1, cy}, {cx, y1 - 1}, shade(col, 0.5))
		rl.DrawTriangleLines({cx, y0}, {x0 + 1, cy}, {cx, y1 - 1}, shade(col, 0.5))

	case .Secret_Wall:
		// кирпичная кладка
		rl.DrawRectangleRec(rect, col)
		line := shade(col, 0.6)
		y := y0 + 5
		for y < y1 {
			rl.DrawLine(i32(x0), i32(y), i32(x1), i32(y), line)
			y += 5
		}
		rl.DrawRectangleLinesEx(rect, 2, shade(col, 0.45))

	case .Player:
		rl.DrawRectangleRec(rect, col)
		rl.DrawRectangleLinesEx(rect, 2, rl.RAYWHITE)

	case .None:
		rl.DrawRectangleRec(rect, col)
	}
}

// actors_render рисует сущности уровня по категориям (акторные «иконки»).
actors_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if !scene_ready() do return

	rl.BeginMode2D(g_camera)
	defer rl.EndMode2D()

	for ecs.query_next(q) {
		e      := q.entity
		anchor := ecs.query_get(q, e, Pos).?^
		size   := ecs.query_get(q, e, Size).?^
		pivot  := ecs.query_get(q, e, Pivot).?^
		col    := ecs.query_get(q, e, Col).?^

		kind := Actor_Kind.None
		if k := ecs.query_get(q, e, Actor_Kind); k != nil {
			pk := k.?
			kind = pk^
		}
		open := false
		if ds := ecs.get_component(ctx.world, e, Door_State); ds != nil {
			open = ds.open
		}

		tl := top_left(cast([2]f32)anchor, pivot, size)
		draw_actor_icon(tl, size, kind, col.c, open)
	}
}
