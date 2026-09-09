package main

import "core:log"
import g "../"
import ecs "../ecs"
import ldtk "../ldtk"

main :: proc() {
	context.logger = log.create_console_logger()

	world := ecs.world_new()
	defer ecs.world_destroy(&world)

	game: g.Game
	game.settings = {
		window = {
			title = "ogame + ldtk demo",
			size  = {1024, 600},
			flags = {.VSYNC_HINT},
		},
	}

	game.init = scene_init
	game.cleanup = {
		{name = "cleanup", cleanup = cleanup_system},
	}
	game.update = {
		{
			name   = "interact",
			types  = {Interactable, Pos, Size, Pivot},
			reads  = {
				{name = "player", types = {TPlayer, Pos, Size}},
			},
			update = interact_system,
		},
		{
			name   = "player",
			types  = {TPlayer, Pos, Vel, Speed},
			reads  = {
				{name = "doors", types = {TSolid, Door_State, Pos, Size, Pivot}},
			},
			update = player_update,
		},
	}
	game.render = {
		{
			name   = "level",
			types  = {},
			render = level_render,
		},
		{
			name   = "actors",
			types  = {TActor, Pos, Size, Pivot, Col, Actor_Kind},
			render = actors_render,
		},
		{
			name   = "hint",
			types  = {},
			render = hint_render,
		},
		{
			name   = "hud",
			types  = {},
			reads  = {
				{name = "player", types = {TPlayer, Pos, Player_State, Inventory}},
			},
			render = hud_render,
		},
	}

	g.run(&game, &world)

	// данные уровня принадлежат демо (не миру): освобождаем после run,
	// когда текстуры уже выгружены в cleanup.
	if g_ready {
		ldtk.project_destroy(&g_project)
	}
}
