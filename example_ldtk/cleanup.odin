package main

import "core:fmt"
import "core:log"
import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

// Очистка ресурсов, которыми владеет демо (см. example/cleanup.odin о трёх
// категориях владения). Текстуры raylib нужно выгружать, пока окно живо —
// cleanup выполняется в run до defers CloseWindow.
cleanup_system :: proc(ctx: ^g.Ctx) {
	// (a) raylib-текстуры (GPU-память, вне Odin-аллокаторов)
	for uid in g_texture_uids {
		if tex, ok := g_textures[uid]; ok {
			rl.UnloadTexture(tex)
		}
	}
	delete(g_textures)
	clear(&g_texture_uids)

	// (b) данные, которыми владеет демо внутри компонентов: массивы ссылок
	//     кнопок (Button_Link.targets) — мир хранит только заголовок и не знает
	//     о содержимом, поэтому освобождаем сами, пока мир жив.
	bq := ecs.query_new(ctx.world, {TButton, Button_Link})
	for ecs.query_next(&bq) {
		link := ecs.query_get(&bq, bq.entity, Button_Link).?
		delete(link.targets)
	}

	log.info("cleanup: атласы и ссылки кнопок выгружены, мир жив")
}

// hud_render рисует жизнь/патроны игрока (стек-буфер, без аллокаций в кадр).
hud_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	if !scene_ready() do return

	// читаем read-запрос игрока (кешируется фреймворком)
	if pq := g.ctx_query(ctx, "player"); pq != nil {
		qv := pq.?
		if player, ok := ecs.query_first(&qv).?; ok {
			st := ecs.query_get(&qv, player, Player_State).?
			pos := ecs.query_get(&qv, player, Pos).?

			buf: [128]byte
			text := fmt.bprintf(buf[:], "HP %d  AMMO %d  pos (%.0f, %.0f)", st.life, st.ammo, pos.x, pos.y)
			rl.DrawText(cstring(raw_data(text)), 10, 10, 20, rl.RAYWHITE)
		}
	}
}
