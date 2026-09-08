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

// Именованный запрос системы: декларируется в reads дескриптора системы,
// строится один раз в setup (после init, когда пулы уже существуют)
// и кэшируется на весь run.
Query_Def :: struct {
	name:  string,
	types: []typeid,
}

// Хранилище закешированных запросов. Живёт столько же, сколько run.
Query_Table :: struct {
	defs:   [dynamic]ecs.Query,
	lookup: map[string]int,
}

query_table_build :: proc(defs: []Query_Def, world: ^ecs.World, allocator := context.allocator) -> (t: Query_Table) {
	if len(defs) == 0 do return // пустая таблица: без аллокаций, ctx_query вернёт false

	t.defs = make([dynamic]ecs.Query, allocator)
	t.lookup = make(map[string]int, allocator)

	for def, i in defs {
		append(&t.defs, ecs.query_new(world, def.types))
		t.lookup[def.name] = i
	}

	return
}

// Возвращает копию закешированного запроса. Копия по значению: система может
// спокойно ресетить/итерировать её, не трогая эталон в таблице.
query_table_get :: proc(t: ^Query_Table, name: string) -> (q: ecs.Query, ok: bool) {
	if t == nil do return {}, false

	i, found := t.lookup[name]
	if !found do return {}, false

	return t.defs[i], true
}

Ctx :: struct {
	world:   ^ecs.World,
	cmds:    ^ecs.Commands,
	queries: ^Query_Table, // запросы ТЕКУЩЕЙ системы; валиден только внутри вызова update/render
}

// Доступ системы к именованному закешированному запросу: без построения
// query на каждый тик, без глобалов. Запрос привязан к миру этого run.
ctx_query :: proc(ctx: ^Ctx, name: string) -> (q: ecs.Query, ok: bool) {
	return query_table_get(ctx.queries, name)
}

UpdateSystem :: struct {
	name:   string,
	types:  []typeid, // главный query: что система итерирует
	reads:  []Query_Def, // доп. запросы: контекст системы (доступ через ctx_query)
	query:  ecs.Query, // строится фреймворком в setup
	read_q: Query_Table, // строится фреймворком в setup
	update: proc(_: ^Ctx, _: ^ecs.Query, _: f32),
}

RenderSystem :: struct {
	name:   string,
	types:  []typeid, // главный query: что система рисует
	reads:  []Query_Def, // доп. запросы: контекст системы (доступ через ctx_query)
	query:  ecs.Query, // строится фреймворком в setup
	read_q: Query_Table, // строится фреймворком в setup
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
		s.read_q = query_table_build(s.reads, world)
	}
	for &s in g.render {
		s.query = ecs.query_new(world, s.types)
		s.read_q = query_table_build(s.reads, world)
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
