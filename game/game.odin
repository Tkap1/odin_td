// This file is compiled as part of the `odin.dll` file. It contains the
// procs that `game_hot_reload.exe` will call, such as:
//
// game_init: Sets up the game state
// game_update: Run once per frame
// game_shutdown: Shuts down game and frees memory
// game_memory: Run just before a hot reload, so game.exe has a pointer to the
//		game's memory.
// game_hot_reloaded: Run after a hot reload so that the `g_mem` global variable
//		can be set to whatever pointer it was in the old DLL.
//
// Note: When compiled as part of the release executable this whole package is imported as a normal
// odin package instead of a DLL.

package game

// import "core:math/linalg"
import "core:fmt"
import "core:math"
import "core:os"
import "core:os/os2"
import rl "vendor:raylib"
import "vendor:zlib"
import "core:math/rand"

s_v2 :: rl.Vector2;
s_v4 :: rl.Vector4;
s_color :: rl.Color;
s_render_texture :: rl.RenderTexture
s_rect :: rl.Rectangle

pi :: cast(f32)3.1415926;
half_pi :: pi * 0.5;
quarter_pi :: pi * 0.25;
tau :: cast(f32)6.28318530717958647692;
epsilon :: cast(f32)0.000001;

g_game: ^s_game
g_replay_data: rawptr;

g_replay: s_replay;

update :: proc() {
	using g_game;

	delta := cast(f32)c_update_delay;
	update_time += delta;

	spawn_timer += delta
	for spawn_timer >= c_spawn_delay {
		spawn_timer -= c_spawn_delay;
		enemy_index := make_enemy(v2i(0, 15));
	}

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update towers start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_towers {
		if !tower_arr.active[i] { continue; }
		tower := &tower_arr.data[i];
		tower_pos := tile_index_to_pos_center(tower.pos);

		target : i32 = -1;
		passed := update_time - tower.shot_timestamp;
		if passed >= c_tower_shoot_delay {
			for j in 0..<cast(i32)c_max_enemies {
				if !enemy_arr.active[j] { continue; }
				target = j;
				break;
			}
		}
		if target >= 0 {
			enemy := &enemy_arr.data[target];
			tower.shot_timestamp = update_time;
			dir := v2_dir_from_to(tower_pos, enemy.pos);
			tower.last_shot_angle = v2_angle(dir);
			make_proj(tower_pos, dir);

			{
				data := make_particle_data();
				data.start_color = rl.GREEN;
				data.end_color = rl.RED;
				do_particles(tower_pos, 8, data);
			}

		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		update towers end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update projectiles start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_projectiles {
		if !proj_arr.active[i] { continue; }
		proj := &proj_arr.data[i];
		remove_proj := false;
		proj.prev_pos = proj.pos;
		proj.pos += proj.dir * v2_1(c_proj_speed) * delta;

		for j in 0..<cast(i32)c_max_enemies {
			if !enemy_arr.active[j] { continue; }
			enemy := &enemy_arr.data[j];
			if rect_collides_rect_center(proj.pos, c_proj_size, enemy.pos, c_enemy_size) {
				remove_proj = true;

				enemy.damage_taken += proj.damage;
				enemy.last_hit_time = g_game.update_time;
				if enemy.damage_taken >= enemy.max_health {
					remove_entity(&enemy_arr, j);

					{
						data := make_particle_data();
						data.min_speed = 100;
						data.max_speed = 150;
						data.min_duration = 0.5;
						data.max_duration = 0.7;
						data.min_size = v2_1(10);
						data.max_size = v2_1(20);
						data.shrink = 0;
						data.start_color = make_color_rgb(255, 20, 20);
						data.end_color = make_color_rgba(255, 0, 0, 0);
						data.slowdown = 1;
						do_particles(proj.pos, 32, data);
					}

					rl.SetSoundPitch(g_game.pop_sound[g_game.deleteme], 0.7 + rand.float32() * 0.6);
					rl.PlaySound(g_game.pop_sound[g_game.deleteme]);
					g_game.deleteme = (g_game.deleteme + 1) % 16;

				}

				{
					data := make_particle_data();
					angle := v2_angle(proj.dir);
					angle += pi;
					data.min_angle = angle - quarter_pi;
					data.max_angle = angle + quarter_pi;
					data.min_speed = 200;
					data.max_speed = 250;
					data.min_duration = 0.1;
					data.max_duration = 0.2;
					data.shrink = 0;
					do_particles(proj.pos, 4, data);
				}

				break;
			}
		}

		passed := update_time - proj.spawn_timestamp;
		if passed >= c_proj_duration {
			remove_proj = true;
		}

		if remove_proj {
			remove_entity(&proj_arr, i);
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		update projectiles end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update enemies start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_enemies {
		using g_game
		if !enemy_arr.active[i] { continue; }
		enemy := &enemy_arr.data[i];
		enemy.prev_pos = enemy.pos;

		movement := 128 * delta;
		for movement > 0 {
			curr_tile := pos_to_tile_index(enemy.pos);
			target_tile : s_v2i;
			if path_mask[curr_tile.y][curr_tile.x] {
				target_tile = next_path_tile[curr_tile.y][curr_tile.x];
			}
			else {
				target_tile = c_start_tile;
			}
			if compare_v2i(curr_tile, c_end_tile) {
				remove_entity(&g_game.enemy_arr, i);
				break;
			}
			else {
				target_pos := tile_index_to_pos_center(target_tile);
				dir := target_pos - enemy.pos;
				dir_n := rl.Vector2Normalize(dir);
				length := rl.Vector2Length(dir);
				to_move := math.min(length, movement);
				enemy.pos = v2_add_mul(enemy.pos, dir_n, to_move);
				movement -= to_move;
			}
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		update enemies end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	if !g_replay.replaying && c_game_speed <= 1.0 {
		index := g_game.update_count % c_max_states;
		write_game_state(fmt.tprintf("update_state{}.tk", index));
	}
	g_game.update_count += 1;
}

render :: proc(interp_dt: f32) -> bool {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	delta := rl.GetFrameTime();
	mouse := rl.GetMousePosition();

	if rl.IsKeyPressed(.F7) {
		write_game_state("state.tk");
	}

	if rl.IsKeyPressed(.F8) {
		load_game_state("state.tk");
	}
	if rl.IsKeyPressed(.F9) {
		do_replay();
	}

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		replay start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	if g_replay.replaying {
		rl.DrawText(fmt.ctprintf("Frame {} / {}", g_replay.curr, g_replay.count - 1), 4, 64, 32, rl.RAYWHITE);
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) {
			g_replay.curr -= 1;
			if g_replay.curr < 0 {
				g_replay.curr = g_replay.count - 1;
			}
		}

		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) {
			g_replay.curr += 1;
			if g_replay.curr >= g_replay.count {
				g_replay.curr = g_replay.curr % g_replay.count;
			}
		}

		pos := wxy(0.0, 0.95);
		size := wxy(1.0, 0.05);
		if mouse_collides_rect_topleft(mouse, pos, size) && rl.IsMouseButtonDown(.LEFT) {
			mouse_percent := ilerp(pos.x, pos.x + size.x, mouse.x);
			temp_curr := cast(i32)math.floor(math.lerp(cast(f32)g_replay.first, cast(f32)(g_replay.first + g_replay.count - 1), mouse_percent));
			g_replay.curr = temp_curr % c_max_states;
		}

		c := rl.RED;
		c.a = 50;
		draw_rect_topleft(pos, size, c);
		c.a = 255;
		last_frame := g_replay.first + g_replay.count - 1;
		percent := ilerp(cast(f32)g_replay.first, cast(f32)last_frame, cast(f32)g_replay.curr);
		draw_rect_topleft(wxy(0.0, 0.95), wxy(percent, 0.05), c);
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		replay end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render background start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	{
		scale :: 1;
		background_tile_size :: c_tile_size * scale;
		for y in 0..<c_num_tiles / scale {
			for x in 0..<c_num_tiles / scale {
				color: s_color;
				if (x + y) & 1 == 0 {
					color = make_color_r(10);
				}
				else {
					color = make_color_r(20);
				}
				draw_rect_topleft(v2(x * background_tile_size, y * background_tile_size), v2_1(background_tile_size), color);
			}
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render background end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	mouse_index := s_v2i{cast(i32)math.floor(mouse.x / c_tile_size), cast(i32)math.floor(mouse.y / c_tile_size)};
	if rl.IsMouseButtonDown(.LEFT) && is_valid_tile_index_for_tower(mouse_index) {
		if g_game.tile_info[mouse_index.y][mouse_index.x].id.id <= 0 {
			make_tower(mouse_index);
		}
	}

	multiply_light_arr: s_list(s_light, 1024);
	add_light_arr: s_list(s_light, 1024);

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render towers start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<c_max_towers {
		using g_game
		if !tower_arr.active[i] { continue; }
		tower := &tower_arr.data[i];

		pos := tile_index_to_pos_center(tower.pos);
		passed := get_render_time(interp_dt) - tower.shot_timestamp;
		passed_inv := 1.0 - passed;
		if passed < 0.5 {
			recoil_dir := v2_from_angle(tower.last_shot_angle);
			pos += recoil_dir * v2_1(-5.0) * ease_in_expo(passed_inv);
		}

		{
			light: s_light;
			light.pos = pos;
			light.radius = c_tile_size * 2;
			light.color = rl.GREEN;
			light.color.a = 100;
			list_add(&multiply_light_arr, light);
		}

		draw_rect_center(pos, v2_1(c_tile_size - 8), rl.GREEN);
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render towers end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	enemy_flash_arr: s_list(s_v2, c_max_enemies);

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render enemies start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<c_max_enemies {
		using g_game
		if !enemy_arr.active[i] { continue; }
		enemy := enemy_arr.data[i];
		pos := lerp_v2(enemy.prev_pos, enemy.pos, interp_dt);
		passed := get_render_time(interp_dt) - enemy.last_hit_time;

		if passed < 0.2 {
			list_add(&enemy_flash_arr, pos);
		}
		else {
			draw_rect_center(pos, c_enemy_size, rl.RED);
		}

		{
			light: s_light;
			light.pos = pos;
			light.radius = c_tile_size * 2;
			light.color = rl.RED;
			light.color.a = 50;
			list_add(&multiply_light_arr, light);
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render enemies end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render projectiles start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_projectiles {
		if !g_game.proj_arr.active[i] { continue; }
		proj := &g_game.proj_arr.data[i];
		passed := get_render_time(interp_dt) - proj.spawn_timestamp;
		color: s_color;
		size: s_v2;

		animator := make_animator();
		add_position(&animator, c_proj_size, c_proj_size * v2(8.0, 1.0), 0.25, 0.0, &size, .linear);
		add_color(&animator, rl.WHITE, rl.RED, 0.25, 0.0, &color, .in_quad);
		animator_wait_completed(&animator, 0.0);
		add_color(&animator, rl.RED, rl.YELLOW, 0.25, 0.0, &color, .in_quad);
		add_position(&animator, c_proj_size * v2(8.0, 1.0), c_proj_size, 0.25, 0.0, &size, .linear);
		animator_wait_completed(&animator, 0.0);
		update_animator(&animator, &passed, 1.0, false);

		pos := lerp_v2(proj.prev_pos, proj.pos, interp_dt);

		{
			light: s_light;
			light.pos = pos;
			light.radius = size.x * 2;
			light.color = color;
			light.color.a = 200;
			list_add(&multiply_light_arr, light);
		}

		rotation := v2_angle(proj.dir);
		draw_rect_center_rot(pos, size, color, rotation);
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render projectiles end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		multiplicative lights start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	{
		rl.BeginTextureMode(g_game.render_texture);
		color := make_color_ra(100, 255);
		rl.ClearBackground(color);

		if multiply_light_arr.count > 0 {
			rl.BeginBlendMode(.ADDITIVE);
			for light, i in to_slice(&multiply_light_arr) {
				rl.DrawCircleV(light.pos, light.radius, light.color);
			}
			rl.EndBlendMode();
		}

		rl.EndTextureMode();
	}

	{
		rl.BeginBlendMode(.MULTIPLIED);
		draw_render_texture(g_game.render_texture);
		rl.EndBlendMode();
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		multiplicative lights end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		particles start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	if g_game.particle_arr.count > 0 {
		rl.BeginBlendMode(.ADDITIVE);
		i : i32 = 0
		for ; i < g_game.particle_arr.count; i += 1 {
			p := &g_game.particle_arr.data[i];
			passed := get_render_time(interp_dt) - p.spawn_timestamp;
			percent := clamp(passed / p.duration, 0.0, 1.0);
			color := lerp_color(p.start_color, p.end_color, percent);
			size := p.size;
			shrink := clamp(1 - percent * p.shrink, 0.0, 1.0);
			size.x *= shrink;
			size.y *= shrink;
			slowdown := clamp(1 - percent * p.slowdown, 0.0, 1.0);
			p.pos += p.dir * p.speed * slowdown * delta;
			draw_rect_center(p.pos, size, color);

			if passed >= p.duration || shrink <= 0.0 {
				list_remove_and_swap(&g_game.particle_arr, i);
				i -= 1;
			}
		}
		rl.EndBlendMode();
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		particles end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		additive lights start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	{
		// {
		// 	light: s_light;
		// 	light.pos = mouse;
		// 	light.size = v2_1(64);
		// 	light.color = rl.WHITE;
		// 	light.color.a = 255;
		// 	list_add(&add_light_arr, light);
		// }

		if add_light_arr.count > 0 {
			rl.BeginBlendMode(.ADDITIVE);
			for light, i in to_slice(&add_light_arr) {
				rl.DrawCircleV(light.pos, light.radius, light.color);
			}
			rl.EndBlendMode();
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		additive lights end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	for flash, i in to_slice(&enemy_flash_arr) {
		draw_rect_center(flash, c_enemy_size, make_color_r(255));
	}


	// {
	// 	path := get_path(c_start_tile, c_end_tile);
	// 	for i in 0..<path.length {
	// 		c := rl.BLUE;
	// 		c.a = 50;
	// 		pos := tile_index_to_pos(path.pos_arr[i]);
	// 		rl.DrawRectangleV(pos, v2_1(c_tile_size), c);
	// 	}
	// }

	rl.DrawFPS(4, 4);

	rl.EndDrawing()
	keep_running := !rl.WindowShouldClose();
	return keep_running;
}

@(export)
game_update :: proc() -> bool {
	if !is_game_paused() {
		g_game.accumulator += rl.GetFrameTime() * c_game_speed;
	}
	if g_replay.replaying {
		name := fmt.tprintf("update_state{}.tk", g_replay.curr);
		load_game_state(name);
	}
	for g_game.accumulator >= c_update_delay {
		g_game.accumulator -= c_update_delay
		update();
	}
	interp_dt := g_game.accumulator / c_update_delay;
	keep_running := render(interp_dt);
	return keep_running;
}

@(export)
game_init_window :: proc() {
	rl.SetTraceLogLevel(.WARNING);
	rl.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(c_window_width, c_window_height, "UHM")
	rl.InitAudioDevice();
}

@(export)
game_init :: proc() {
	g_game = new(s_game)
	g_replay_data = rl.MemAlloc(1024 * 1024 * 1024);

	g_game^ = s_game {}

	init_entity_arr(&g_game.tower_arr);
	init_entity_arr(&g_game.enemy_arr);
	init_entity_arr(&g_game.proj_arr);

	for y in 0..<cast(i32)c_num_tiles {
		for x in 0..<cast(i32)c_num_tiles {
			node : s_astar_node;
			node.pos = v2i(x, y);
			node.a = math.abs(x - c_end_tile.x) + math.abs(y - c_end_tile.y);
			g_game.node_arr[y][x] = node;
		}
	}

	{
		path := get_path(c_start_tile, c_end_tile);
		for i in 0..<path.length - 1 {
			p := path.pos_arr[i];
			next_p := path.pos_arr[i + 1];
			g_game.next_path_tile[p.y][p.x] = next_p;
			g_game.path_mask[p.y][p.x] = true;
			g_game.path_mask[next_p.y][next_p.x] = true;
		}
	}

	for i in 0..<c_max_states {
		name := fmt.tprintf("update_state{}.tk", i);
		os2.remove(name);
	}

	g_game.render_texture = rl.LoadRenderTexture(c_window_width, c_window_height);
	for i in 0..<16 {
		g_game.pop_sound[i] = rl.LoadSound("assets/pop.wav");
		rl.SetSoundVolume(g_game.pop_sound[i], 0.25);
	}

}

@(export)
game_shutdown :: proc() {
	free(g_game);
	rl.MemFree(g_replay_data);
}

@(export)
game_memory :: proc() -> rawptr {
	return g_game
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(s_game)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_game = (^s_game)(mem)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

is_valid_tower_index :: proc(index: s_entity_id) -> bool
{
	assert(index.index >= 0);
	assert(index.index < c_max_towers);
	assert(index.id >= 0);
	if index.id <= 0 { return false; }
	if !g_game.tower_arr.active[index.index] { return false; }
	if g_game.tower_arr.data.id[index.index] != index.id { return false; }
	return true;
}

make_entity :: proc(info: ^s_entity_info($T, $N)) -> i32
{
	assert(info.count < N);
	index := info.free[info.count];
	assert(!info.active[index]);
	info.active[index] = true;
	info.count += 1;
	g_game.next_entity_id += 1;
	info.data[index] = {};
	info.data[index].id = g_game.next_entity_id;
	return index;
}

make_tower :: proc(tile_index: s_v2i) -> i32
{
	using g_game;
	assert(tower_arr.count < c_max_towers);

	index := make_entity(&tower_arr);

	tower := &tower_arr.data[index];

	tower.pos = tile_index;

	g_game.tile_info[tile_index.y][tile_index.x].id = tower_to_entity_index(index);
	g_game.node_arr[tile_index.y][tile_index.x].occupied = true;

	path := get_path(c_start_tile, c_end_tile);
	path_mask = {};

	for i in 0..<path.length - 1 {
		p := path.pos_arr[i];
		next_p := path.pos_arr[i + 1];
		g_game.next_path_tile[p.y][p.x] = next_p;
		g_game.path_mask[p.y][p.x] = true;
		g_game.path_mask[next_p.y][next_p.x] = true;
	}

	return index;
}

make_enemy :: proc(tile_index: s_v2i) -> i32
{
	using g_game;
	assert(enemy_arr.count < c_max_enemies);

	index := make_entity(&enemy_arr);

	enemy := &enemy_arr.data[index];

	enemy.pos = tile_index_to_pos_center(tile_index);
	enemy.max_health = c_enemy_health;

	return index;
}

make_proj :: proc(pos: s_v2, dir: s_v2) -> i32
{
	using g_game;
	index := make_entity(&proj_arr);
	proj := &proj_arr.data[index];
	proj.prev_pos = pos;
	proj.pos = pos;
	proj.dir = dir;
	proj.spawn_timestamp = g_game.update_time;
	proj.damage = 1;
	return index;
}

tower_to_entity_index :: proc(tower_index : i32) -> s_entity_id
{
	result : s_entity_id;
	result.index = tower_index;
	result.id = g_game.tower_arr.data[tower_index].id;
	return result;
}

is_valid_tile_index :: proc(tile_index: s_v2i) -> bool
{
	using tile_index;
	result := x >= 0 && x < c_num_tiles && y >= 0 && y < c_num_tiles;
	return result;
}

is_valid_tile_index_for_tower :: proc(tile_index: s_v2i) -> bool
{
	using tile_index;
	result := is_valid_tile_index(tile_index);

	// @Hack(tkap, 27/11/2024):
	if result {
		backup := g_game.node_arr[tile_index.y][tile_index.x].occupied;
		g_game.node_arr[tile_index.y][tile_index.x].occupied = true;
		path := get_path(c_start_tile, c_end_tile);

		if path.length <= 0 {
			result = false;
		}

		g_game.node_arr[tile_index.y][tile_index.x].occupied = backup;
	}

	return result;
}

v2i :: proc(x: i32, y: i32) -> s_v2i
{
	return s_v2i{x, y};
}

tile_index_to_pos :: proc(tile_index: s_v2i) -> s_v2
{
	result : s_v2;
	result.x = cast(f32)(tile_index.x * c_tile_size);
	result.y = cast(f32)(tile_index.y * c_tile_size);
	return result;
}

tile_index_to_pos_center :: proc(tile_index: s_v2i) -> s_v2
{
	result : s_v2;
	result.x = cast(f32)(tile_index.x * c_tile_size);
	result.y = cast(f32)(tile_index.y * c_tile_size);
	result.x += c_tile_size * 0.5;
	result.y += c_tile_size * 0.5;
	return result;
}

lerp_v2 :: proc(a: s_v2, b: s_v2, dt: f32) -> s_v2
{
	result : s_v2;
	result.x = math.lerp(a.x, b.x, dt);
	result.y = math.lerp(a.y, b.y, dt);
	return result;
}

v2 :: proc(x : $T0, y: $T1) -> s_v2
{
	result := s_v2{cast(f32)x, cast(f32)y};
	return result;
}

v2_1 :: proc(x: f32) -> s_v2
{
	result := s_v2{x, x};
	return result;
}

get_path :: proc(start_pos, end_pos: s_v2i) -> s_path
{

	s_parent :: struct
	{
		has_parent: bool,
		parent: s_v2i,
	}

	result: s_path;
	start_pos := start_pos;
	end_pos := end_pos;
	swap(&start_pos, &end_pos);
	open_arr : s_list(s_v2i, c_total_tiles);
	status_arr : [c_num_tiles][c_num_tiles]e_astar_node_status = {};
	b_arr : [c_num_tiles][c_num_tiles]i32 = {};
	parent_arr : [c_num_tiles][c_num_tiles]s_parent = {};

	curr := v2i(-1, -1);

	if !get_node(start_pos).occupied {
		status_arr[start_pos.y][start_pos.x] = .open;
		list_add(&open_arr, start_pos);
	}

	for {
		if compare_v2i(curr, end_pos) {
			break;
		}
		if(open_arr.count <= 0) {
			curr = v2i(-1, -1);
			break;
		}

		lowest : i32 = 999999999;
		chosen : i32 = -1;
		for open, i in to_slice(&open_arr) {
			assert(status_arr[open.y][open.x] == .open);
			f := get_node(open).a + b_arr[open.y][open.x];
			if f < lowest {
				lowest = f
				chosen = auto_cast i;
			}
		}

		assert(chosen >= 0);
		curr = open_arr.data[chosen];
		assert(status_arr[curr.y][curr.x] == .open);
		status_arr[curr.y][curr.x] = .closed;
		list_remove_and_swap(&open_arr, chosen);

		offset_arr : [4]s_v2i;
		offset_arr[0] = v2i(-1, 0);
		offset_arr[1] = v2i(1, 0);
		offset_arr[2] = v2i(0, -1);
		offset_arr[3] = v2i(0, 1);
		for offset in offset_arr {
			index := curr;
			index.x += offset.x;
			index.y += offset.y;
			if(is_valid_tile_index(index)) {
				assert(!compare_v2i(index, curr));
				if !get_node(index).occupied && status_arr[index.y][index.x] != .closed {
					possible_new_b := b_arr[curr.y][curr.x] + 1;
					if status_arr[index.y][index.x] == .open {
						if possible_new_b < b_arr[index.y][index.x] {
							b_arr[index.y][index.x] = possible_new_b;
							parent_arr[index.y][index.x].has_parent = true;
							parent_arr[index.y][index.x].parent = curr;
						}
					}
					else {
						b_arr[index.y][index.x] = possible_new_b;
						parent_arr[index.y][index.x].has_parent = true;
						parent_arr[index.y][index.x].parent = curr;
						status_arr[index.y][index.x] = .open;
						list_add(&open_arr, index);
					}
				}
			}
		}
	}

	if curr.x >= 0 {
		for {
			result.pos_arr[result.length] = curr;
			result.length += 1;
			if !parent_arr[curr.y][curr.x].has_parent { break; }
			curr = parent_arr[curr.y][curr.x].parent;
		}
	}

	return result;
}

index_to_2d :: proc(x, y, stride: i32) -> i32
{
	result := x + y * stride;
	return result;
}

v2_add_mul :: proc(a, b: s_v2, c: f32) -> s_v2
{
	result: s_v2;
	result.x = a.x + b.x * c;
	result.y = a.y + b.y * c;
	return result;
}

pos_to_tile_index :: proc(pos: s_v2) -> s_v2i
{
	result: s_v2i;
	result.x = cast(i32)math.floor(pos.x / c_tile_size);
	result.y = cast(i32)math.floor(pos.y / c_tile_size);
	return result;
}

remove_entity :: proc(info: ^s_entity_info($T, $N), index: i32)
{
	info.active[index] = false;
	info.free[info.count - 1] = index;
	info.count -= 1;
}

write_game_state :: proc(name: string)
{
	ptr := cast(rawptr)g_game;
	data := ([^]byte)(ptr)[:size_of(s_game)];
	dst_len := zlib.compressBound(size_of(s_game));
	dst := make([]byte, dst_len);
	zlib.compress(&dst[0], &dst_len, &data[0], size_of(s_game));

	// fmt.printf("{}, ratio: {}\n", dst_len, cast(f32)dst_len / cast(f32)size_of(s_game));

	file, _ := os2.create(name);
	os2.write(file, dst[:dst_len]);
	os2.truncate(file, auto_cast dst_len);
	os2.close(file);

	delete(dst);
}

load_game_state :: proc(name: string)
{
	ptr := cast(rawptr)g_game;
	data := ([^]byte)(ptr)[:size_of(s_game)];
	file, _ := os2.open(name);
	file_size, _ := os2.file_size(file);
	src := make([]byte, file_size);
	os2.read(file, src);
	os2.close(file);
	dst_len := cast(u32)size_of(s_game);
	zlib.uncompress(&data[0], &dst_len, &src[0], cast(u32)file_size);

	delete(src);
}

swap :: proc(a, b: ^$T)
{
	temp := a^;
	a^ = b^;
	b^ = temp;
}

get_node :: proc(index: s_v2i) -> s_astar_node
{
	return g_game.node_arr[index.y][index.x];
}

list_add :: proc(list: ^s_list($T, $N), new_element: T)
{
	list.data[list.count] = new_element;
	list.count += 1;
}

list_remove_and_swap :: proc(list: ^s_list($T, $N), index: i32)
{
	assert(index < list.count);
	list.data[index] = list.data[list.count - 1];
	list.count -= 1;
}

compare_v2i :: proc(a, b: s_v2i) -> bool
{
	result := a.x == b.x && a.y == b.y;
	return result;
}

to_slice :: proc(arr: ^s_list($T, $N)) -> []T
{
	return arr.data[0:arr.count];
}

v2_dir_from_to :: proc(from, to: s_v2) -> s_v2
{
	result := to - from;
	result = rl.Vector2Normalize(result);
	return result;
}

init_entity_arr :: proc(info: ^s_entity_info($T, $N))
{
	for i in 0..<N {
		info.free[i] = i;
	}
}

draw_rect_topleft :: proc(pos, size: s_v2, color: s_color)
{
	rl.DrawRectangleV(pos, size, color);
}

draw_rect_center :: proc(pos, size: s_v2, color: s_color)
{
	pos := pos;
	pos.x -= size.x * 0.5;
	pos.y -= size.y * 0.5;
	rl.DrawRectangleV(pos, size, color);
}

draw_rect_center_rot :: proc(pos, size: s_v2, color: s_color, rotation: f32)
{
	rotation := rotation * rl.RAD2DEG;
	rect : rl.Rectangle;
	rect.x = pos.x;
	rect.y = pos.y;
	rect.width = size.x;
	rect.height = size.y;
	rl.DrawRectanglePro(rect, v2(size.x * 0.5, size.y * 0.5), rotation, color);
}

mouse_collides_rect_topleft :: proc(mouse, pos, size: s_v2) -> bool
{
	result := rect_collides_rect_topleft(mouse, v2_1(1), pos, size);
	return result;
}

rect_collides_rect_topleft :: proc(pos0, size0, pos1, size1: s_v2) -> bool
{
	result := pos0.x + size0.x >= pos1.x && pos0.x < pos1.x + size1.x;
	result &= pos0.y + size0.y >= pos1.y && pos0.y < pos1.y + size1.y;
	return result;
}

rect_collides_rect_center :: proc(pos0, size0, pos1, size1: s_v2) -> bool
{
	pos0 := pos0;
	pos1 := pos1;
	pos0.x -= size0.x * 0.5;
	pos0.y -= size0.y * 0.5;
	pos1.x -= size1.x * 0.5;
	pos1.y -= size1.y * 0.5;
	result := rect_collides_rect_topleft(pos0, size0, pos1, size1);
	return result;
}

do_replay :: proc()
{
	if g_replay.replaying {
		g_replay.replaying = false;
	}
	else {
		g_replay.replaying = true;
		lowest_time : os.File_Time = 0xFFFFFFFFFFFFFFFF;
		lowest : i32 = -1;
		count : i32 = 0;
		for i in 0..<c_max_states {
			name := fmt.tprintf("update_state{}.tk", i);
			mod_time, mod_time_error := os.last_write_time_by_name(name);
			if mod_time_error == nil {
				count += 1;
				if mod_time < lowest_time {
					lowest_time = mod_time;
					lowest = i;
				}
			}
			// file, err := os2.open(name);
			// if err != nil {

				// break;
				// fmt.printf("{}, err {}\n", i, err);
		}
		g_replay.first = lowest;
		g_replay.count = count;
		g_replay.curr = (lowest + count - 1) % c_max_states;

		if count <= 0 {
			g_replay.replaying = false;
			fmt.printf("OI! Nothing to replay, kinda sus...\n");
		}

		fmt.printf("{} {}\n", g_replay.first, count);

	}
	fmt.printf("{}\n", g_replay.replaying);
}

is_game_paused :: proc() -> bool
{
	result := false;
	if g_replay.replaying {
		result = true;
	}
	return result;
}

wxy :: proc(x, y: f32) -> s_v2
{
	result := v2(c_window_width * x, c_window_height * y);
	return result;
}

ilerp :: proc(a, b, dt: f32) -> f32
{
	result := (dt - a) / (b - a);
	return result;
}

v2_angle :: proc(a: s_v2) -> f32
{
	result := math.atan2(a.y, a.x);
	return result;
}

get_render_time :: proc(interp_dt: f32) -> f32
{
	result := g_game.update_time + c_update_delay * interp_dt;
	return result;
}

lerp_color :: proc(a, b: s_color, dt: f32) -> s_color
{
	result : s_color;
	result.r = cast(u8)math.lerp(cast(f32)a.r, cast(f32)b.r, dt);
	result.g = cast(u8)math.lerp(cast(f32)a.g, cast(f32)b.g, dt);
	result.b = cast(u8)math.lerp(cast(f32)a.b, cast(f32)b.b, dt);
	result.a = cast(u8)math.lerp(cast(f32)a.a, cast(f32)b.a, dt);
	return result;
}

make_animator :: proc() -> s_animator
{
	result: s_animator
	result.needs_wait_call = true;
	return result;
}

ilerp_clamp :: proc(start, end, value: $T) -> T
{
	result := ilerp(start, end, clamp(value, start, end));
	return result;
}

clamp :: proc(current, min_val, max_val: $T) -> T
{
	result := at_most(max_val, at_least(min_val, current));
	return result;
}

at_most :: proc(a, b: $T) -> T
{
	result := a < b ? a : b;
	return result;
}

at_least :: proc(a, b: $T) -> T
{
	result := a > b ? a : b;
	return result;
}

lerp_v4 :: proc(a, b: s_v4, dt: f32) -> s_v4
{
	result: s_v4;
	result.x = math.lerp(a.x, b.x, dt);
	result.y = math.lerp(a.y, b.y, dt);
	result.z = math.lerp(a.z, b.z, dt);
	result.w = math.lerp(a.w, b.w, dt);
	return result;
}

bezier :: proc(start, end, pivot: s_v2, t: f32) -> s_v2
{
	a := lerp_v2(start, pivot, t);
	b := lerp_v2(pivot, end, t);
	c := lerp_v2(a, b, t);
	return c;
}

ease_in_expo :: proc(x: f32) -> f32
{
	if floats_equal(x, 0) { return 0; }
	return math.pow(2, 10 * x - 10);
}


ease_linear :: proc(x: f32) -> f32
{
	return x;
}

ease_in_quad :: proc(x: f32) -> f32
{
	return x * x;
}

ease_out_quad :: proc(x: f32) -> f32
{
	x2 := 1.0 - x;
	return 1 - x2 * x2;
}

ease_out_expo :: proc(x: f32) -> f32
{
	if(floats_equal(x, 1)) { return 1; }
	return 1 - math.pow(2, -10 * x);
}

ease_out_elastic :: proc(x: f32) -> f32
{
	c4 :: (2.0 * pi) / 3.0;
	if floats_equal(x, 0) || floats_equal(x, 1) { return x; }
	return math.pow(2, -5 * x) * math.sin((x * 5 - 0.75) * c4) + 1;
}

ease_out_elastic2 :: proc(x: f32) -> f32
{
	c4 :: (2 * pi) / 3;
	if floats_equal(x, 0) || floats_equal(x, 1) { return x; }
	return math.pow(2, -10 * x) * math.sin((x * 10 - 0.75) * c4) + 1;
}

ease_out_back :: proc(x: f32) -> f32
{
	c1 := cast(f32)1.70158;
	c3 := c1 + 1;
	return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2);
}

floats_equal :: proc(a, b: f32) -> bool
{
	return (a >= b - epsilon && a <= b + epsilon);
}

max_by_ptr :: proc(ptr: ^$T, val: T)
{
	ptr^ = max(ptr^, val);
}

v2_from_angle :: proc(angle: f32) -> s_v2
{
	result : s_v2;
	result.x = math.cos(angle);
	result.y = math.sin(angle);
	return result;
}

make_color_r :: proc(r: u8) -> s_color
{
	result: s_color;
	result.r = r;
	result.g = r;
	result.b = r;
	result.a = 255;
	return result;
}

make_color_ra :: proc(r, a: u8) -> s_color
{
	result: s_color;
	result.r = r;
	result.g = r;
	result.b = r;
	result.a = a;
	return result;
}

make_color_rgb :: proc(r, g, b: u8) -> s_color
{
	result: s_color;
	result.r = r;
	result.g = g;
	result.b = b;
	result.a = 255;
	return result;
}

make_color_rgba :: proc(r, g, b, a: u8) -> s_color
{
	result: s_color;
	result.r = r;
	result.g = g;
	result.b = b;
	result.a = a;
	return result;
}

draw_render_texture :: proc(render_texture: s_render_texture)
{
	color := make_color_r(255);
	src : s_rect;
	dst : s_rect;

	src.width = c_window_size.x;
	src.height = -c_window_size.y;

	dst.width = c_window_size.x;
	dst.height = c_window_size.y;

	rl.DrawTexturePro(render_texture.texture, src, dst, v2_1(0), 0, color);
}

do_particles :: proc(pos: s_v2, count: i32, data: s_particle_data)
{
	for i in 0..<count {
		p: s_particle;
		p.pos = pos;
		p.spawn_timestamp = g_game.update_time;
		p.duration = math.lerp(data.min_duration, data.max_duration, rand.float32());
		p.speed = math.lerp(data.min_speed, data.max_speed, rand.float32());
		p.start_color = data.start_color;
		p.end_color = data.end_color;
		p.size = lerp_v2(data.min_size, data.max_size, rand.float32());
		p.shrink = data.shrink;
		p.slowdown = data.slowdown;
		rand_angle := math.lerp(data.min_angle, data.max_angle, rand.float32());
		p.dir = v2_from_angle(rand_angle);
		list_add(&g_game.particle_arr, p);
	}
}

make_particle_data :: proc() -> s_particle_data
{
	data: s_particle_data;
	data.min_duration = 0;
	data.max_duration = 1;
	data.min_speed = 32;
	data.max_speed = 64;
	data.min_angle = 0;
	data.max_angle = tau;
	data.start_color = make_color_r(255);
	data.end_color = make_color_ra(255, 0);
	data.min_size = v2(4, 4);
	data.max_size = v2(8, 8);
	data.shrink = 1;
	return data;
}