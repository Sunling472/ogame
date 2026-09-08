package components

import rl "vendor:raylib"

Pos    :: distinct [2]f32
Size   :: distinct [2]i32
Color  :: distinct rl.Color
Speed  :: distinct f32
Vel    :: distinct [2]f32
Sprint :: distinct bool

Side :: enum {
	Up,
	Down,
	Left,
	Right,
}

Weapon :: struct {
	mag:         int,
	mag_size:    int,
	cd:          f32,
	fire_rate:   f32,
	fire_acc:    f32,
	reloading:   bool,
	reloading_t: f32,
	reload_time: f32,
}
