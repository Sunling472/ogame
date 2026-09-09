package main

import ecs "../ecs"
import rl "vendor:raylib"

// Компоненты демо (типизация как в example/components).

Pos   :: distinct [2]f32 // якорь — точка pivot сущности LDtk (px)
Vel   :: distinct [2]f32
Speed :: distinct f32

Size :: struct { w, h: f32 }
Pivot :: struct { x, y: f32 }
Col   :: struct { c: rl.Color }

TActor       :: struct{} // любой актор уровня (спавнится из LDtk)
TPlayer      :: struct{}

Player_State :: struct {
	life: int,
	ammo: int,
}

// Категория актора (identifier сущности из LDtk) — для отрисовки/логики.
Actor_Kind :: enum {
	None,
	Player,
	Door,
	Button,
	Item,
	Secret_Wall,
}

// --- интерактив уровня: двери и кнопки ---

TDoor :: struct{}
TButton :: struct{}

Door_State :: struct {
	open: bool,
}

// Button_Link — сущности-двери, которые открывает эта кнопка (из поля
// LDtk "targets"). Массив владеет демо: память освобождается в cleanup.
Button_Link :: struct {
	targets: [dynamic]ecs.Entity,
}

// Interactable — объект, с которым можно взаимодействовать клавишей E,
// подойдя вплотную (в пределах range от центра игрока).
Interactable :: struct {
	range: f32,
}
