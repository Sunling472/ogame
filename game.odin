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
	world: ^ecs.World,
	cmds:  ^ecs.Commands,
}

UpdateSystem :: struct {
	name:   string,
	types:  []typeid,
	query:  ecs.Query,
	update: proc(_: ^Ctx, _: ^ecs.Query, _: f32),
}

RenderSystem :: struct {
	name:   string,
	types:  []typeid,
	query:  ecs.Query,
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

	for &s in g.update {s.query = ecs.query_new(world, s.types)}
	for &s in g.render {s.query = ecs.query_new(world, s.types)}

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		for &s in g.update {
			ecs.query_reset(&s.query)
			s.update(&g.ctx, &s.query, delta)
		}

		ecs.cmds_flush(&cmds)

		rl.BeginDrawing()
		for &s in g.render {
			ecs.query_reset(&s.query)
			s.render(&g.ctx, &s.query)
		}
		rl.EndDrawing()

		free_all(context.temp_allocator)
	}

}
