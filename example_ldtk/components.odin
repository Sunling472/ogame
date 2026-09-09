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

// Тип предмета (enum LDtk "Item" из поля entity "type").
Item_Kind :: enum {
	None,
	Wood,
	Metal,
	Food,
	Health,
	Rifle,
	KeyA,
	KeyB,
	Gold,
}

// --- интерактив уровня: двери, кнопки, предметы ---

// TSolid — открываемая преграда (дверь, секретная стена): пока закрыта,
// блокирует движение; состояние открытости — в Door_State.
TSolid :: struct{}

TButton :: struct{}

Door_State :: struct {
	open: bool,
	// чем заперта дверь (поле LDtk "lockedWith": KeyA/KeyB/None)
	lock: Item_Kind,
}

// Инвентарь игрока: ключи и счёт (наполняется подбором предметов).
Inventory :: struct {
	key_a:  bool,
	key_b:  bool,
	score:  int,
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
