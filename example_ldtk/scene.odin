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
LEVEL_NAME   :: "World_Level_0"

DRAW_SCALE :: f32(2) // уровень 512x256 -> 1024x512 на экране

g_project:        ldtk.Project
g_level:          ^ldtk.Level
g_collisions:     ^ldtk.Layer_Instance // IntGrid "Collisions"
g_ready:          bool

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
	return g_ready && g_level != nil
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

	lv := ldtk.level_by_identifier(&g_project, LEVEL_NAME)
	if lv == nil {
		log.errorf("ldtk: уровень %q не найден", LEVEL_NAME)
		return
	}
	g_level = lv.?
	if cl := ldtk.layer_instance(g_level, "Collisions"); cl != nil {
		g_collisions = cl.?
	}

	g_textures = make(map[i32]rl.Texture2D)
	g_texture_uids = make([dynamic]i32, context.allocator)

	_load_tile_textures()
	_spawn_level_entities(ctx)

	g_ready = true
	log.infof("ldtk: уровень %s %dx%d загружен", g_level.identifier, g_level.px_wid, g_level.px_hei)
}

_load_tile_textures :: proc() {
	for &li in g_level.layer_instances {
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

_spawn_level_entities :: proc(ctx: ^g.Ctx) {
	for &li in g_level.layer_instances {
		if li.type != "Entities" do continue

		for &ei in li.entity_instances {
			ent := ecs.entity_new(ctx.world)

			anchor := [2]f32{f32(ei.px[0]), f32(ei.px[1])}
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

			if ei.identifier == "Player" {
				life := 100
				ammo := 0
				if l := ldtk.field_int(&ei, "life"); l != nil do life = int(l.?)
				if a := ldtk.field_int(&ei, "ammo"); a != nil do ammo = int(a.?)

				ecs.add_component(ctx.world, ent, TPlayer{})
				ecs.add_component(ctx.world, ent, Vel{})
				ecs.add_component(ctx.world, ent, Player_State{life, ammo})
				log.infof("игрок: life=%d ammo=%d", life, ammo)
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Рендер уровня и акторов
// ---------------------------------------------------------------------------

_level_bg_color :: proc() -> rl.Color {
	if g_level == nil do return rl.BLACK
	return hex_color(g_level.bg_color)
}

// level_render рисует тайловые слои уровня (атлас uid 1).
level_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	rl.ClearBackground({14, 17, 26, 255})
	if !scene_ready() do return

	ox := (f32(rl.GetScreenWidth()) - f32(g_level.px_wid) * DRAW_SCALE) / 2
	oy := (f32(rl.GetScreenHeight()) - f32(g_level.px_hei) * DRAW_SCALE) / 2

	// фон уровня
	rl.DrawRectangle(
		i32(ox), i32(oy),
		i32(f32(g_level.px_wid) * DRAW_SCALE), i32(f32(g_level.px_hei) * DRAW_SCALE),
		_level_bg_color(),
	)

	gs := g_tileset_grid
	if gs <= 0 do gs = 16

	// слои рисуем снизу вверх (в файле верхние идут первыми)
	for i := len(g_level.layer_instances) - 1; i >= 0; i -= 1 {
		li := &g_level.layer_instances[i]
		if li.type == "Entities" do continue
		tex, have_tex := g_textures[i32(li.tileset_def_uid)]
		if !have_tex do continue

		for &t in li.auto_layer_tiles do _draw_tile(tex, t, gs, ox, oy)
		for &t in li.grid_tiles       do _draw_tile(tex, t, gs, ox, oy)
	}
}

_draw_tile :: proc(tex: rl.Texture2D, t: ldtk.Tile, gs: i32, ox, oy: f32) {
	src := rl.Rectangle{f32(t.src[0]), f32(t.src[1]), f32(gs), f32(gs)}
	if t.f & 1 != 0 do src.width = -src.width // flip X
	if t.f & 2 != 0 do src.height = -src.height // flip Y

	dest := rl.Rectangle {
		ox + f32(t.px[0]) * DRAW_SCALE,
		oy + f32(t.px[1]) * DRAW_SCALE,
		f32(gs) * DRAW_SCALE,
		f32(gs) * DRAW_SCALE,
	}
	rl.DrawTexturePro(tex, src, dest, {0, 0}, 0, rl.WHITE)
}

// actors_render рисует сущности уровня цветными прямоугольниками по def-color.
actors_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if !scene_ready() do return
	ox := (f32(rl.GetScreenWidth()) - f32(g_level.px_wid) * DRAW_SCALE) / 2
	oy := (f32(rl.GetScreenHeight()) - f32(g_level.px_hei) * DRAW_SCALE) / 2

	for ecs.query_next(q) {
		e := q.entity
		anchor := ecs.query_get(q, e, Pos).?^
		size := ecs.query_get(q, e, Size).?^
		pivot := ecs.query_get(q, e, Pivot).?^
		col := ecs.query_get(q, e, Col).?^
		is_player := ecs.query_get(q, e, TPlayer) != nil

		tl := top_left(cast([2]f32)anchor, pivot, size)
		rl.DrawRectangleRec(
			{tl.x * DRAW_SCALE + ox, tl.y * DRAW_SCALE + oy, size.w * DRAW_SCALE, size.h * DRAW_SCALE},
			col.c,
		)
		if is_player do rl.DrawRectangleLinesEx(
			{tl.x * DRAW_SCALE + ox, tl.y * DRAW_SCALE + oy, size.w * DRAW_SCALE, size.h * DRAW_SCALE},
			2, rl.RAYWHITE,
		)
	}
}
