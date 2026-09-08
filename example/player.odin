package main

import comp "components"
import g "../"
import ecs "../ecs"
import rl "vendor:raylib"

is_sprint: bool
player_init :: proc(ctx: ^g.Ctx) {
	player := ecs.entity_new(ctx.world)
	ecs.add_component(ctx.world, player, comp.TPlayer{})
	ecs.add_component(ctx.world, player, comp.Pos{10, 10})
	ecs.add_component(ctx.world, player, comp.Vel{})
	ecs.add_component(ctx.world, player, comp.Size{20, 40})
	ecs.add_component(ctx.world, player, comp.Speed(200))
	ecs.add_component(ctx.world, player, comp.Side.Right)
	ecs.add_component(ctx.world, player, comp.Color(rl.RED))
	ecs.add_component(ctx.world, player, comp.Sprint{})
	ecs.add_component(
		ctx.world,
		player,
		comp.Weapon {
			mag         = 10,
			mag_size    = 10,
			cd          = 5,
			fire_rate   = 0.2,
			fire_acc    = 0,
			reload_time = 3,
		},
	)
}

player_update :: proc(ctx: ^g.Ctx, q: ^ecs.Query, delta: f32) {
	if player, ok := ecs.query_first(q).?; ok {
		pos    := ecs.query_get(q, player, comp.Pos).?
		speed  := ecs.query_get(q, player, comp.Speed).?
		side   := ecs.query_get(q, player, comp.Side).?
		weapon := ecs.query_get(q, player, comp.Weapon).?
		sprint := ecs.query_get(q, player, comp.Sprint).?
		vel    := ecs.query_get(q, player, comp.Vel).?
		vel^ = comp.Vel{}

		if rl.IsKeyDown(.LEFT_SHIFT)    do sprint^ = true
		else if rl.IsKeyUp(.LEFT_SHIFT) do sprint^ = false
		
		if sprint^ do speed^ = 400
		else do speed^ = 200

		if rl.IsKeyDown(.W) { 
			vel.y -= f32(speed^) 
			side^ = .Up
		}
		if rl.IsKeyDown(.S) { 
			vel.y += f32(speed^) 
			side^ = .Down
		}
		if rl.IsKeyDown(.A) { 
			vel.x -= f32(speed^) 
			side^ = .Left
		}
		if rl.IsKeyDown(.D) { 
			vel.x += f32(speed^) 
			side^ = .Right
		}

		if rl.IsKeyDown(.ENTER) {
			if !weapon.reloading && weapon.fire_acc > weapon.fire_rate {
				weapon.fire_acc = 0

				// дуло на грани игрока в сторону взгляда, а не внутри него:
				// иначе при спринте (скорость == скорость пули) пуля «прилипает»
				// к игроку, копится внутри и бьёт врага пачкой в одном кадре
				muzzle := [2]f32{pos.x, pos.y}
				switch side^ {
				case .Right: muzzle.x += 20 // правый край (Size 20x40)
				case .Left:  muzzle.x -= 10 // слева от игрока (ширина пули 10)
				case .Down:  muzzle.y += 40
				case .Up:    muzzle.y -= 10 // над игроком (высота пули 10)
				}
				bullet_spawn(ctx, muzzle, side^)
			}
		}
		pos.x += vel.x * delta
		pos.y += vel.y * delta
		weapon.fire_acc += delta
	}

}

player_render :: proc(ctx: ^g.Ctx, q: ^ecs.Query) {
	player := ecs.query_first(q).?
	pos := ecs.query_get(q, player, comp.Pos).?
	size := ecs.query_get(q, player, comp.Size).?
	color := ecs.query_get(q, player, comp.Color).?

	rl.DrawRectangle(i32(pos.x), i32(pos.y), size.x, size.y, rl.Color(color^))
}
