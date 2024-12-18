
package game

import rl "vendor:raylib"

s_v2 :: rl.Vector2;
s_v4 :: rl.Vector4;
s_color :: rl.Color;
s_render_texture :: rl.RenderTexture
s_rect :: rl.Rectangle
s_sound :: rl.Sound

e_enemy :: enum
{
	red,
	blue,
	green,
	yellow,
}

s_enemy_child :: struct
{
	type: e_enemy,
	count: i32,
}

s_enemy_data :: struct
{
	speed: f32,
	color: s_color,
	child_count: i32,
	children: [4]s_enemy_child,
}

c_enemy_data := []s_enemy_data{
	e_enemy.red = {speed = 128.0, color = rl.RED},
	e_enemy.blue = {speed = 140.0, color = rl.BLUE, child_count = 1, children = {0 = {.red, 1}}},
	e_enemy.green = {speed = 160.0, color = rl.GREEN, child_count = 1, children = {0 = {.blue, 1}}},
	e_enemy.yellow = {speed = 200.0, color = rl.YELLOW, child_count = 1, children = {0 = {.green, 1}}},
}

e_sound :: enum
{
	pop,
}

s_entity_id :: struct {
	index: i32,
	id: i32,
}

s_v2i :: struct {
	x: i32,
	y: i32,
}

s_path :: struct
{
	length: i32,
	pos_arr: [c_total_tiles]s_v2i,
}

s_tower :: struct {
	id: i32,
	pos: s_v2i,
	shot_timestamp: f32,
	last_shot_angle: f32,
}

s_wave_spawn_data :: struct
{
	type: e_enemy,
	to_spawn: i32,
	delay: f32,
}

s_wave :: struct
{
	data: s_list(s_wave_spawn_data, 16),
}

s_live_wave_info :: struct
{
	index: i32,
	how_many_spawned: i32,
	finished: bool,
	last_spawn_timestamp: f32,
}


s_enemy :: struct {
	type: e_enemy,
	id: i32,
	prev_pos: s_v2,
	pos: s_v2,
	damage_taken: i32,
	max_health: i32,
	last_hit_time : f32,
}

s_projectile :: struct {
	id: i32,
	prev_pos: s_v2,
	pos: s_v2,
	dir: s_v2,
	spawn_timestamp: f32,
	damage: i32,
}

s_tile_info :: struct {
	id: s_entity_id,
}

s_entity_info :: struct(type: typeid, max_elements: i32)
{
	count: i32,
	active: [max_elements]bool,
	free: [max_elements]i32,
	data: #soa[max_elements]type,
}

s_replay :: struct
{
	replaying: bool,
	dragging: bool,
	in_slider: bool,
}

s_circular :: struct
{
	curr: i32,
	start: i32,
	end: i32,
	count: i32,
}

s_play :: struct
{
	gold: i32,

	tower_arr: s_entity_info(s_tower, c_max_towers),
	enemy_arr: s_entity_info(s_enemy, c_max_enemies),
	proj_arr: s_entity_info(s_projectile, c_max_projectiles),

	tile_info: [c_num_tiles][c_num_tiles]s_tile_info,
	path_mask : [c_num_tiles][c_num_tiles]bool,
	next_path_tile : [c_num_tiles][c_num_tiles]s_v2i,

	live_wave_info_arr: [c_max_waves]s_live_wave_info,

	tower_to_place : Maybe(i32),
	selected_tower: Maybe(i32),
	curr_wave : i32,

}

s_game :: struct
{
	update_count: i32,
	next_entity_id: i32,
	accumulator: f32,
	update_time: f32,
	spawn_timer: f32,

	speed_index : i32,

	render_texture: s_render_texture,

	play: s_play,

	node_arr: [c_num_tiles][c_num_tiles]s_astar_node,

	particle_arr: s_list(s_particle, c_max_particles),

	max_compress_size : i32,
	max_states: i32,

	sound_arr: [len(e_sound)][c_sound_duplicates]s_sound,
	sound_play_index_arr: [len(e_sound)]i32,

	disable_sounds: bool,
}


e_astar_node_status :: enum
{
	none,
	open,
	closed,
};

s_astar_node :: struct
{
	a: i32,
	pos: s_v2i,
	occupied: bool,
}

s_list :: struct(type: typeid, max_elements: i32)
{
	count: i32,
	data: [max_elements]type,
}

s_light :: struct
{
	pos: s_v2,
	radius: f32,
	color: s_color,
}

s_particle :: struct
{
	pos: s_v2,
	size: s_v2,
	spawn_timestamp: f32,
	duration: f32,
	speed: f32,
	shrink: f32,
	dir: s_v2,
	start_color: s_color,
	end_color: s_color,
	slowdown: f32,
}

s_particle_data :: struct
{
	duration: f32,
	min_speed: f32,
	max_speed: f32,
	min_angle: f32,
	max_angle: f32,
	start_color: s_color,
	end_color: s_color,
	min_duration: f32,
	max_duration: f32,
	min_size: s_v2,
	max_size: s_v2,
	shrink: f32,
	slowdown: f32,
}