package ogame

import ecs "ecs"
import rl "vendor:raylib"

Settings :: struct {
	window: struct {
		title: cstring,
		size:  [2]i32,
		flags: rl.ConfigFlags,
	},
}

Ctx :: struct ($Data: typeid) {
	data:    Data,
	world:   ^ecs.World,
	cmds:    ^ecs.Commands,
	queries: ^ecs.Query_Table,
}

ctx_query :: proc(ctx: ^Ctx($Data), name: string) -> Maybe(ecs.Query) {
	return ecs.query_table_get(ctx.queries, name)
}

UpdateSystem :: struct ($Data: typeid) {
	name:   string,
	types:  []typeid,
	reads:  []ecs.Query_Def,
	query:  ecs.Query,
	read_q: ecs.Query_Table,
	update: proc(_: ^Ctx(Data), _: ^ecs.Query, _: f32),
}

RenderSystem :: struct ($Data: typeid) {
	name:   string,
	types:  []typeid,
	reads:  []ecs.Query_Def,
	query:  ecs.Query,
	read_q: ecs.Query_Table,
	render: proc(_: ^Ctx(Data), _: ^ecs.Query),
}

// CleanupSystem is the mirror of init: it runs once after the main loop
// ends, while the window, audio and the ECS world are still alive, so the
// game can release USER-owned data (unload textures/sounds, free strings or
// slices stored inside components, save state...). Everything the framework
// itself allocated (system query tables, deferred-destroy buffer) is freed
// by run() after the cleanup systems; the World itself is owned by the
// caller of run and must be freed with ecs.world_destroy afterwards.
CleanupSystem :: struct ($Data: typeid) {
	name:    string,
	cleanup: proc(_: ^Ctx(Data)),
}

Game :: struct ($Data: typeid) {
	ctx:      Ctx(Data),
	settings: Settings,
	init:     proc(_: ^Ctx(Data)),
	cleanup:  []CleanupSystem(Data),
	update:   []UpdateSystem(Data),
	render:   []RenderSystem(Data),
}

run :: proc(g: ^Game($Data), world: ^ecs.World) {
	assert(g.init != nil)

	cmds: ecs.Commands
	ecs.cmds_init(&cmds, world)

	g.ctx.world = world
	g.ctx.cmds = &cmds


	rl.SetConfigFlags(g.settings.window.flags)

	rl.InitWindow(
		g.settings.window.size.x,
		g.settings.window.size.y,
		g.settings.window.title,
	); defer rl.CloseWindow()
	rl.InitAudioDevice(); defer rl.CloseAudioDevice()

	g.init(&g.ctx)

	for &s in g.update {
		s.query = ecs.query_new(world, s.types)
		s.read_q = ecs.query_table_build(s.reads, world)
	}
	for &s in g.render {
		s.query = ecs.query_new(world, s.types)
		s.read_q = ecs.query_table_build(s.reads, world)
	}

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		// Игровая фаза: структуру мира меняем только через cmds_* —
		// прямые add/remove/destroy упадут с понятной ошибкой. Пулы не
		// двигаются, пока системы держат указатели на компоненты.
		world.locked = true

		for &s in g.update {
			g.ctx.queries = &s.read_q // контекст = запросы текущей системы
			ecs.query_reset(&s.query)
			s.update(&g.ctx, &s.query, delta)
		}
		g.ctx.queries = nil

		// Граница фаз: применяем отложенную структуру (adds→removes→destroys).
		ecs.cmds_flush(&cmds)

		rl.BeginDrawing()
		for &s in g.render {
			g.ctx.queries = &s.read_q
			ecs.query_reset(&s.query)
			s.render(&g.ctx, &s.query)
		}
		g.ctx.queries = nil
		rl.EndDrawing()

		world.locked = false
		free_all(context.temp_allocator)
	}

	// --- teardown ---
	// 1. user cleanup: ECS world and raylib are still alive here, so systems
	//    can read components and unload resources.
	g.ctx.queries = nil
	for &c in g.cleanup {
		c.cleanup(&g.ctx)
	}

	// 2. framework cleanup: free what run() itself allocated (query tables
	//    built before the loop, deferred-destroy buffer). Arena-safe, see
	//    ecs.query_table_destroy / ecs.world_destroy.
	for &s in g.update {
		ecs.query_table_destroy(&s.read_q)
		s.read_q = {}
	}
	for &s in g.render {
		ecs.query_table_destroy(&s.read_q)
		s.read_q = {}
	}
	ecs.cmds_free(&cmds)

	// 3. the World belongs to the caller: free it with ecs.world_destroy()
	//    after run() returns.
}
