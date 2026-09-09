package main

import rl "vendor:raylib"

// Компоненты демо (типизация как в example/components).

Pos :: distinct [2]f32 // якорь — точка pivot сущности LDtk (px)
Vel :: distinct [2]f32

Size :: struct { w, h: f32 }
Pivot :: struct { x, y: f32 }
Col   :: struct { c: rl.Color }

TActor       :: struct{} // любой актор уровня (спавнится из LDtk)
TPlayer      :: struct{}
Player_State :: struct {
	life: int,
	ammo: int,
}
