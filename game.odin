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


Ctx :: struct {
	world:   ^ecs.World,
	cmds:    ^ecs.Commands,
	queries: ^ecs.Query_Table,
}

ctx_query :: proc(ctx: ^Ctx, name: string) -> Maybe(ecs.Query) {
	return ecs.query_table_get(ctx.queries, name)
}

UpdateSystem :: struct {
	name:   string,
	types:  []typeid,
	reads:  []ecs.Query_Def,
	query:  ecs.Query,
	read_q: ecs.Query_Table,
	update: proc(_: ^Ctx, _: ^ecs.Query, _: f32),
}

RenderSystem :: struct {
	name:   string,
	types:  []typeid,
	reads:  []ecs.Query_Def,
	query:  ecs.Query,
	read_q: ecs.Query_Table,
	render: proc(_: ^Ctx, _: ^ecs.Query),
}

Game :: struct {
	ctx:      Ctx,
	settings: Settings,
	init:     proc(_: ^Ctx),
	update:   []UpdateSystem,
	render:   []RenderSystem,
}

run :: proc(g: ^Game, world: ^ecs.World) {
	assert(g.init != nil)

	cmds: ecs.Commands
	cmds.world = world

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

		for &s in g.update {
			g.ctx.queries = &s.read_q // контекст = запросы текущей системы
			ecs.query_reset(&s.query)
			s.update(&g.ctx, &s.query, delta)
		}
		g.ctx.queries = nil

		ecs.cmds_flush(&cmds)

		rl.BeginDrawing()
		for &s in g.render {
			g.ctx.queries = &s.read_q
			ecs.query_reset(&s.query)
			s.render(&g.ctx, &s.query)
		}
		g.ctx.queries = nil
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

}
