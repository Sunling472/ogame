package main

import "core:log"
import g "../"
import rl "vendor:raylib"

/*
Кто чем владеет — и зачем вообще CleanupSystem.

1. Мир (ECS)              → ecs.world_destroy(&world) в main, после run
2. Внутренности run()     → query-таблицы и cmds: run освобождает сам
3. context.allocator      → heap: живёт до выхода из main
   temp_allocator (арена) → сбрасывается run() каждый кадр

Всё это освободится БЕЗ CleanupSystem. CleanupSystem чистит то, чем владеет
САМА ИГРА, — ресурсы, которых не видят ни мир, ни аллокаторы:

  a) ресурсы raylib/ОС: текстуры, шрифты, звуки, музыка — память GPU/аудио
     вне Odin-аллокаторов. Выгружать их можно только ПОКА живы окно и аудио,
     а они живы как раз во время cleanup (CloseWindow/CloseAudioDevice — defer
     в конце run);
  b) собственные heap-аллокации игры в глобалах/стейте (если не на арене);
  c) данные, спрятанные ВНУТРИ компонентов (строки/слайсы, владелец — игра):
     мир копирует в пул только заголовок и о содержимом не знает, поэтому
     world_destroy его не освободит — а мир в cleanup ещё жив, и можно
     обойти компоненты запросом.

В этом демо реально присутствует только категория (a), она и показана.
*/

// raylib-ресурс, которым владеет игра (GPU-память, вне любых Odin-аллокаторов).
player_tex: rl.Texture2D

// resources_init — зеркало cleanup: игра грузит свои ресурсы в init.
resources_init :: proc(ctx: ^g.Ctx(Data)) {
	img := rl.GenImageColor(8, 8, rl.WHITE) // белый квадрат 8x8, без файла
	defer rl.UnloadImage(img)               // CPU-копия больше не нужна
	player_tex = rl.LoadTextureFromImage(img)
	log.info("resources: player texture loaded")
}

// cleanup_system выполняется после главного цикла (в конце run), но ДО
// defers run (CloseWindow/CloseAudioDevice) и ДО world_destroy в main.
cleanup_system :: proc(ctx: ^g.Ctx(Data)) {
	// (a) raylib: выгружаем GPU-ресурс, пока окно живо. Этого не сделают
	//     ни arena_destroy, ни world_destroy, ни teardown run.
	if rl.IsTextureReady(player_tex) {
		rl.UnloadTexture(player_tex)
		player_tex = {}
	}

	// (b) Если бы игра держала свои heap-данные в глобалах (вне арены):
	//     for s in owned_strings do delete(s, context.allocator)
	//     delete(owned_strings, context.allocator)

	// (c) Если бы компоненты содержали строки/слайсы, которыми владеет игра:
	//     мир здесь ещё жив, поэтому их можно обойти запросом и освободить:
	//     ctx.query := ecs.query_new(ctx.world, {comp.TEnemy, comp.Name})
	//     for ecs.query_next(&ctx.query) {
	//         name := ecs.query_get(&ctx.query, ctx.query.entity, comp.Name).?
	//         delete(name^, context.allocator)
	//     }
	//     (world_destroy освободит слот пула, но не содержимое name — о нём
	//     мир не знает: в пуле лежит только заголовок строки.)

	// мир ещё жив — можно читать компоненты, если нужно что-то сохранить
	log.infof("cleanup: окно живо, пулов компонентов в мире: %d", len(ctx.world.pools))
}
