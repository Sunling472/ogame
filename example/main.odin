package main

import comp "components"
import "core:log"
import vmem "core:mem/virtual"
import g "../"
import ecs "../ecs"

Data :: struct {
	debug_ui: bool
}

init :: proc(ctx: ^g.Ctx(Data)) {
	player_init(ctx)
	resources_init(ctx) // грузим ресурсы игры — их же освободит cleanup
}


main :: proc() {
	context.logger = log.create_console_logger()

	arena: vmem.Arena
	defer vmem.arena_destroy(&arena)

	err_arena_init := vmem.arena_init_growing(&arena)
	if err_arena_init != nil do log.panic(err_arena_init)

	// Две зоны памяти:
	//   context.allocator      — обычный heap (по умолчанию): мир и долгоживущее;
	//   context.temp_allocator — vmem-арена: кадровое, run() сбрасывает её каждый кадр.
	// Кадровые аллокации — только явно на context.temp_allocator или в стек-буфер.
	context.temp_allocator = vmem.arena_allocator(&arena)
	defer free_all(context.temp_allocator)

	world := ecs.world_new(context.allocator)
	defer ecs.world_destroy(&world) // мир на heap — освобождаем после run

	game: g.Game(Data)
	game.settings = {
		window = {
			size = {1280, 720},
			title = "ECS2",
			flags = {.VSYNC_HINT, .MSAA_4X_HINT,},
		},
	}

	game.init = init
	game.cleanup = {
		{
			name    = "game_cleanup",
			cleanup = cleanup_system,
		},
	}
	game.update = {
		{
			name = "input",
			types = {},
			update = input_system
		},
		{
			name = "collision",
			types = {
				comp.TPlayer,
				comp.Pos,
				comp.Size,
				comp.Speed,
				comp.Vel
			},
			update = player_border_collision
		},
		{
			name = "player",
			types = {
				comp.TPlayer,
				comp.Pos,
				comp.Vel,
				comp.Size,
				comp.Speed,
				comp.Color,
				comp.Side,
				comp.Weapon,
				comp.Sprint,
			},
			update = player_update,
		},
		{
			name = "bullet",
			types = {
				comp.TBullet,
				comp.Pos,
				comp.Size,
				comp.Speed,
				comp.Color,
				comp.Side
			},
			update = bullet_move
		},
		{
			name = "bullet_collision",
			types = {
				comp.TBullet,
				comp.Pos,
				comp.Size,
			},
			reads = {
				{name = "enemies", types = {comp.TEnemy, comp.Pos, comp.Size}},
			},
			update = bullet_collision
		},
		{
			name = "enemy",
			types = {
				comp.TEnemy,
				comp.Pos,
				comp.Size,
				comp.Speed,
				comp.Color
			},
			update = enemy_update
		},
		{
			name = "enemy_move",
			types = {
				comp.TEnemy,
				comp.Pos,
				comp.Speed,
			},
			reads = {
				{ name = "player", types = {comp.TPlayer, comp.Pos, comp.Vel} }
			},
			update = enemy_move
		}
	}

	game.render = {
		{
			name = "background", 
			types = {}, 
			render = background_render
		},
		{
			name = "player",
			types = {comp.TPlayer, comp.Pos, comp.Size, comp.Color},
			render = player_render,
		},
		{
			name = "bullet",
			types = {
				comp.TBullet,
				comp.Pos,
				comp.Size,
				comp.Color
			},
			render = bullet_render
		},
		{
			name = "enemy",
			types = {
				comp.TEnemy,
				comp.Pos,
				comp.Size,
				comp.Color
			},
			render = enemy_render
		},
		{
			name = "ui-debug",
			types = {},
			reads = {
				{
					name = "player",
					types = {
						comp.TPlayer,
						comp.Pos,
						comp.Side,
						comp.Weapon,
						comp.Vel,
						comp.Sprint,
					},
				},
			},
			render = ui_debug_render
		}
	}

	g.run(&game, &world)

}
