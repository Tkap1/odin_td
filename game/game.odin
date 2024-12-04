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

import "core:fmt"
import "core:math"
import "core:os/os2"
import rl "vendor:raylib"
import "vendor:zlib"
import "core:math/rand"
import "base:intrinsics"

g_game: ^s_game
g_replay_data: rawptr;
g_circular : s_circular;
g_replay: s_replay;
g_wave_count : i32;

update :: proc() {

	delta := cast(f32)c_update_delay;
	g_game.update_time += delta;
	play := &g_game.play;

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update waves start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for wave_i in 0..<play.curr_wave {
		info := &play.live_wave_info_arr[wave_i];
		wave := c_wave_arr[wave_i];
		if info.finished { continue; }
		passed := g_game.update_time - info.last_spawn_timestamp;
		for passed >= wave.data.data[info.index].delay {
			passed -= wave.data.data[info.index].delay;
			make_enemy(wave.data.data[info.index].type, tile_index_to_pos_center(c_start_tile));
			info.how_many_spawned += 1;
			info.last_spawn_timestamp = g_game.update_time;
			if equal(info.how_many_spawned, wave.data.data[info.index].to_spawn) {
				info.index += 1;
				info.how_many_spawned = 0;
				if equal(info.index, wave.data.count) {
					info.finished = true;
					break;
				}
			}
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		update waves end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update towers start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_towers {
		if !play.tower_arr.active[i] { continue; }
		tower := &play.tower_arr.data[i];
		tower_pos := tile_index_to_pos_center(tower.pos);

		target : i32 = -1;
		passed := g_game.update_time - tower.shot_timestamp;
		if passed >= c_tower_shoot_delay {
			for j in 0..<cast(i32)c_max_enemies {
				if !play.enemy_arr.active[j] { continue; }
				target = j;
				break;
			}
		}
		if target >= 0 {
			enemy := &play.enemy_arr.data[target];
			tower.shot_timestamp = g_game.update_time;
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
		if !play.proj_arr.active[i] { continue; }
		proj := &play.proj_arr.data[i];
		remove_proj := false;
		proj.prev_pos = proj.pos;
		proj.pos += proj.dir * v2_1(c_proj_speed) * delta;

		for j in 0..<cast(i32)c_max_enemies {
			if !play.enemy_arr.active[j] { continue; }
			enemy := &play.enemy_arr.data[j];
			enemy_data := c_enemy_data[enemy.type];
			if rect_collides_rect_center(proj.pos, c_proj_size, enemy.pos, c_enemy_size) {
				remove_proj = true;

				enemy.damage_taken += proj.damage;
				enemy.last_hit_time = g_game.update_time;
				if enemy.damage_taken >= enemy.max_health {

					// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		enemy death start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
					{
						for child_i in 0..<enemy_data.child_count {
							for _ in 0..<enemy_data.children[child_i].count {
								child_pos := enemy.pos;
								child_pos.x += rand_snorm() * 8;
								child_pos.y += rand_snorm() * 8;
								make_enemy(enemy_data.children[child_i].type, child_pos);
							}
						}
						play.gold += 1;
						remove_entity(&play.enemy_arr, j);
					}
					// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		enemy death end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

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

					play_sound(.pop);
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

		passed := g_game.update_time - proj.spawn_timestamp;
		if passed >= c_proj_duration {
			remove_proj = true;
		}

		if remove_proj {
			remove_entity(&play.proj_arr, i);
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		update projectiles end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		update enemies start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_enemies {
		if !play.enemy_arr.active[i] { continue; }
		enemy := &play.enemy_arr.data[i];
		enemy.prev_pos = enemy.pos;
		data := c_enemy_data[enemy.type];

		movement := data.speed * delta;
		for movement > 0 {
			curr_tile := pos_to_tile_index(enemy.pos);
			target_tile : s_v2i;
			if play.path_mask[curr_tile.y][curr_tile.x] {
				target_tile = play.next_path_tile[curr_tile.y][curr_tile.x];
			}
			else {
				target_tile = c_start_tile;
			}
			if compare_v2i(curr_tile, c_end_tile) {
				remove_entity(&play.enemy_arr, i);
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

	if !g_replay.replaying && g_game.speed_index <= c_base_game_speed_index {
		data, len := get_compressed_game_state();
		base := intrinsics.ptr_offset(cast(^u8)g_replay_data, (g_game.max_compress_size + 4) * g_circular.end);
		base2 := intrinsics.ptr_offset(base, 4);
		intrinsics.mem_copy(base, &len, 4);
		intrinsics.mem_copy(base2, &data[0], len);
		delete(data);
		circular_add(&g_circular);
	}
	g_game.update_count += 1;
}

render :: proc(interp_dt: f32) -> bool {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	delta := rl.GetFrameTime();
	mouse := rl.GetMousePosition();

	play := &g_game.play;
	ui_y : i32 = 32;
	ui_font_size : i32 : 32;
	ui_advance := ui_font_size + 8;

	can_start_placing_tower := !g_replay.replaying;

	if rl.IsKeyPressed(.F7) {
		write_game_state("state.tk");
	}

	if rl.IsKeyPressed(.F8) {
		load_game_state("state.tk");
	}
	if rl.IsKeyPressed(.F9) {
		do_replay();
	}

	if rl.IsKeyPressed(.M) {
		g_game.disable_sounds = !g_game.disable_sounds;
	}

	if rl.IsKeyPressed(.KP_ADD) {
		g_game.speed_index = circular_index(g_game.speed_index + 1, cast(i32)len(c_game_speed_arr));
	}

	if rl.IsKeyPressed(.KP_SUBTRACT) {
		g_game.speed_index = circular_index(g_game.speed_index - 1, cast(i32)len(c_game_speed_arr));
	}

	if can_start_placing_tower {
		if rl.IsKeyPressed(.ONE) {
			play.tower_to_place = 0;
		}
		if rl.IsKeyPressed(.ESCAPE) {
			play.tower_to_place = nil;
		}
	}

	mouse_index := s_v2i{cast(i32)math.floor(mouse.x / c_tile_size), cast(i32)math.floor(mouse.y / c_tile_size)};
	can_place_tower := !g_replay.replaying && is_valid_tile_index_for_tower(mouse_index) && play.tile_info[mouse_index.y][mouse_index.x].id.id <= 0 &&
		play.gold >= c_tower_gold_cost;

	can_start_wave := play.curr_wave < g_wave_count;
	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		start wave start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	if can_start_wave && rl.IsKeyPressed(.SPACE) {
		play.live_wave_info_arr[play.curr_wave].last_spawn_timestamp = g_game.update_time;
		play.curr_wave += 1;
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		start wave end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

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

	multiply_light_arr: s_list(s_light, 1024);
	add_light_arr: s_list(s_light, 1024);

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render towers start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<c_max_towers {
		if !play.tower_arr.active[i] { continue; }
		tower := &play.tower_arr.data[i];

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

		draw_rect_center(pos, c_tower_size, rl.GREEN);
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render towers end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	enemy_flash_arr: s_list(s_v2, c_max_enemies);

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render enemies start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<c_max_enemies {
		if !play.enemy_arr.active[i] { continue; }
		enemy := play.enemy_arr.data[i];
		pos := lerp_v2(enemy.prev_pos, enemy.pos, interp_dt);
		passed := get_render_time(interp_dt) - enemy.last_hit_time;
		data := c_enemy_data[enemy.type];

		if passed < 0.2 {
			list_add(&enemy_flash_arr, pos);
		}
		else {
			draw_rect_center(pos, c_enemy_size, data.color);
		}

		{
			light: s_light;
			light.pos = pos;
			light.radius = c_tile_size * 2;
			light.color = data.color;
			light.color.a = 50;
			list_add(&multiply_light_arr, light);
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render enemies end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render projectiles start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	for i in 0..<cast(i32)c_max_projectiles {
		if !play.proj_arr.active[i] { continue; }
		proj := &play.proj_arr.data[i];
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
			for light, _ in to_slice(&multiply_light_arr) {
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
			percent := clamp_01(passed / p.duration);
			color := lerp_color(p.start_color, p.end_color, percent);
			size := p.size;
			shrink := clamp_01(1 - percent * p.shrink);
			size.x *= shrink;
			size.y *= shrink;
			slowdown := clamp_01(1 - percent * p.slowdown);
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

	if play.tower_to_place != nil {
		pos := tile_index_to_pos_center(mouse_index);
		color := rl.GREEN;
		if !can_place_tower {
			color = rl.RED;
		}
		color = set_alpha(color, 200);
		draw_rect_center(pos, c_tower_size, color);

		if can_place_tower && rl.IsMouseButtonDown(.LEFT) {
			make_tower(mouse_index);
			play.gold -= c_tower_gold_cost;

			{
				data := make_particle_data();
				data.start_color = rl.WHITE;
				data.end_color = rl.GREEN;
				do_particles(pos, 32, data);
			}

		}
	}

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
			for light, _ in to_slice(&add_light_arr) {
				rl.DrawCircleV(light.pos, light.radius, light.color);
			}
			rl.EndBlendMode();
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		additive lights end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	for flash, _ in to_slice(&enemy_flash_arr) {
		draw_rect_center(flash, c_enemy_size, make_color_r(255));
	}

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		render ui start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	{
		rl.DrawText(fmt.ctprintf("Gold: {}", play.gold), 4, ui_y, ui_font_size, rl.RAYWHITE);
		ui_y += ui_advance;

		rl.DrawText(fmt.ctprintf("Wave: {} / {}", play.curr_wave, g_wave_count), 4, ui_y, ui_font_size, rl.RAYWHITE);
		ui_y += ui_advance;

		if g_game.speed_index != c_base_game_speed_index {
			rl.DrawText(fmt.ctprintf("Speed: {:0.2f}", get_game_speed()), 4, ui_y, ui_font_size, rl.RAYWHITE);
			ui_y += ui_advance;
		}
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		render ui end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv		replay start		vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
	if g_replay.replaying {
		rl.DrawText(fmt.ctprintf("Update {} / {}", circular_get_as_linear(g_circular, g_circular.curr), circular_count(g_circular) - 1), 4, ui_y, ui_font_size, rl.RAYWHITE);
		ui_y += ui_advance;
		if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) {
			circular_curr_go_back(&g_circular);
		}

		if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) {
			circular_curr_go_forward(&g_circular);
		}

		pos := wxy(0.0, 0.95);
		size := wxy(1.0, 0.05);
		mouse_percent := ilerp(pos.x, pos.x + size.x, mouse.x);
		mouse_percent = clamp_01(mouse_percent);
		temp_curr := circular_get_curr_from_percent(g_circular, mouse_percent);
		if mouse_collides_rect_topleft(mouse, pos, size) && rl.IsMouseButtonPressed(.LEFT) {
			g_replay.in_slider = true;
		}
		if !rl.IsMouseButtonDown(.LEFT) {
			g_replay.in_slider = false;
		}

		if g_replay.in_slider {
			g_circular.curr = temp_curr;
		}

		c := rl.RED;
		c.a = 50;
		draw_rect_topleft(pos, size, c);
		c.a = 255;
		percent := ilerp(cast(f32)g_circular.start, cast(f32)g_circular.end, cast(f32)g_circular.curr);
		draw_rect_topleft(wxy(0.0, 0.95), wxy(percent, 0.05), c);
	}
	// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^		replay end		^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

	rl.DrawFPS(4, 4);

	rl.EndDrawing()
	keep_running := !rl.WindowShouldClose();
	return keep_running;
}

@(export)
game_update :: proc() -> bool {
	if !is_game_paused() {
		g_game.accumulator += rl.GetFrameTime() * get_game_speed();
	}
	if g_replay.replaying {
		len_ptr := cast(^i32)intrinsics.ptr_offset(cast(^u8)g_replay_data, g_circular.curr * (g_game.max_compress_size + 4));
		len := len_ptr^;
		src_ptr := intrinsics.ptr_offset(cast(^u8)g_replay_data, g_circular.curr * (g_game.max_compress_size + 4) + 4);
		src := ([^]byte)(src_ptr)[:len]
		dst_len := cast(u32)size_of(s_game);
		dst := ([^]byte)(g_game)[:size_of(s_game)];
		zlib.uncompress(&dst[0], &dst_len, &src[0], auto_cast len);
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
	rl.SetExitKey(.KEY_NULL);
}

@(export)
game_init :: proc() {
	g_game = new(s_game)
	g_game^ = s_game {}
	g_replay_data = rl.MemAlloc(auto_cast c_replay_memory);

	g_game.speed_index = c_base_game_speed_index;

	play := &g_game.play;

	init_waves();

	play.gold = c_base_gold;

	g_game.max_compress_size = auto_cast zlib.compressBound(size_of(s_game));
	g_game.max_states = c_replay_memory / (g_game.max_compress_size + 4);
	g_circular = {}
	g_circular.count = g_game.max_states;

	init_entity_arr(&g_game.play.tower_arr);
	init_entity_arr(&g_game.play.enemy_arr);
	init_entity_arr(&g_game.play.proj_arr);

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
			play.next_path_tile[p.y][p.x] = next_p;
			play.path_mask[p.y][p.x] = true;
			play.path_mask[next_p.y][next_p.x] = true;
		}
	}

	g_game.render_texture = rl.LoadRenderTexture(c_window_width, c_window_height);
	for i in 0..<c_sound_duplicates {
		sound := rl.LoadSound("assets/pop.wav");
		rl.SetSoundVolume(sound, 0.25);
		g_game.sound_arr[e_sound.pop][i] = sound;
	}

}

@(export)
game_shutdown :: proc() {
	free(g_game);
	rl.MemFree(g_replay_data);
}

@(export)
game_game_memory :: proc() -> rawptr {
	return g_game
}

@(export)
game_replay_memory :: proc() -> rawptr {
	return g_replay_data
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(s_game)
}

@(export)
game_hot_reloaded :: proc(game_mem, replay_mem: rawptr) {
	g_game = (^s_game)(game_mem)
	g_replay_data = replay_mem;

	g_circular = {}
	g_circular.count = g_game.max_states;

	init_waves();
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

is_valid_tower_index :: proc(index: s_entity_id) -> bool
{
	using g_game.play;
	assert(index.index >= 0);
	assert(index.index < c_max_towers);
	assert(index.id >= 0);
	if index.id <= 0 { return false; }
	if !tower_arr.active[index.index] { return false; }
	if tower_arr.data.id[index.index] != index.id { return false; }
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
	using g_game.play;
	assert(tower_arr.count < c_max_towers);

	index := make_entity(&tower_arr);

	tower := &tower_arr.data[index];

	tower.pos = tile_index;

	play.tile_info[tile_index.y][tile_index.x].id = tower_to_entity_index(index);
	g_game.node_arr[tile_index.y][tile_index.x].occupied = true;

	path := get_path(c_start_tile, c_end_tile);
	path_mask = {};

	for i in 0..<path.length - 1 {
		p := path.pos_arr[i];
		next_p := path.pos_arr[i + 1];
		play.next_path_tile[p.y][p.x] = next_p;
		play.path_mask[p.y][p.x] = true;
		play.path_mask[next_p.y][next_p.x] = true;
	}

	return index;
}

make_enemy :: proc(type: e_enemy, pos: s_v2) -> i32
{
	using g_game.play;
	assert(enemy_arr.count < c_max_enemies);

	index := make_entity(&enemy_arr);

	enemy := &enemy_arr.data[index];
	enemy.type = type;
	enemy.pos = pos;
	enemy.max_health = c_enemy_health;

	return index;
}

make_proj :: proc(pos: s_v2, dir: s_v2) -> i32
{
	using g_game.play;
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
	play := &g_game.play;
	result : s_entity_id;
	result.index = tower_index;
	result.id = play.tower_arr.data[tower_index].id;
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

get_compressed_game_state :: proc() -> ([]byte, i32)
{
	ptr := cast(rawptr)g_game;
	data := ([^]byte)(ptr)[:size_of(s_game)];
	dst_len := cast(u32)g_game.max_compress_size;
	dst := make([]byte, dst_len);
	zlib.compress(&dst[0], &dst_len, &data[0], size_of(s_game));
	return dst, auto_cast dst_len;
}

write_game_state :: proc(name: string)
{
	data, len := get_compressed_game_state();

	file, _ := os2.create(name);
	os2.write(file, data[:len]);
	os2.truncate(file, auto_cast len);
	os2.close(file);

	delete(data);
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

draw_rect_center_rot :: proc(pos, size: s_v2, color: s_color, in_rotation: f32)
{
	rotation := in_rotation * rl.RAD2DEG;
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
		g_circular.curr = circular_index(g_circular.end - 1, g_circular.count);
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
	result := ilerp(start, end, clamp(start, end, value));
	return result;
}

clamp :: proc(min_val, max_val, current: $T) -> T
{
	result := at_most(max_val, at_least(min_val, current));
	return result;
}

clamp_01 :: proc(current: $T) -> T
{
	result := clamp(zero_float, one_float, current);
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
	for _ in 0..<count {
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

circular_add :: proc(circular : ^s_circular)
{
	assert(circular.count > 1);
	circular.end = (circular.end + 1) % circular.count;
	if circular.end == circular.start {
		circular.start = (circular.end + 1) % circular.count;
	}
}

circular_count :: proc(circular: s_circular) -> i32
{
	assert(circular.count > 1);
	if circular.end >= circular.start {
		return circular.end;
	}
	return circular.count;
}

circular_curr_go_back :: proc(circular: ^s_circular)
{
	using circular;
	assert(count > 1);
	curr -= 1;
	if curr < start {
		curr = end;
	}
	if curr == end && !circular_is_full(circular^) {
		curr = end - 1;
	}
}

circular_curr_go_forward :: proc(circular: ^s_circular)
{
	using circular;
	assert(count > 1);

	curr += 1;
	if curr > circular_count(circular^) {
		curr = start;
	}
	if !circular_is_full(circular^) && curr == end {
		curr = start;
	}
}

circular_get_as_linear :: proc(circular: s_circular, index: i32) -> i32
{
	using circular;
	assert(count > 1);
	assert(index >= 0);
	assert(index < count);

	result := circular_index(index - start, count);
	return result;
}

circular_index :: proc(index, size: i32) -> i32
{
	assert(size > 0);
	if index >= 0 {
		return index % size;
	}
	return (size - 1) - ((-index - 1) % size);
}

circular_is_full :: proc(circular: s_circular) -> bool
{
	using circular;
	assert(count > 1);
	result := circular_count(circular) == count;
	return result;
}

circular_get_curr_from_percent :: proc(circular: s_circular, percent: f32) -> i32
{
	using circular;
	assert(count > 1);
	assert(percent >= 0);
	assert(percent <= 1);

	result := cast(i32)math.floor(math.lerp(cast(f32)start, cast(f32)end, percent));
	if !circular_is_full(circular) && result == end {
		result = end - 1;
	}

	return result;
}

play_sound :: proc(id: e_sound)
{
	if g_game.disable_sounds { return; }

	index := g_game.sound_play_index_arr[id];
	rl.SetSoundPitch(g_game.sound_arr[id][index], 0.7 + rand.float32() * 0.6);
	rl.PlaySound(g_game.sound_arr[id][index]);
	g_game.sound_play_index_arr[id] = (index + 1) % c_sound_duplicates;
}

set_alpha :: proc(color: s_color, alpha: u8) -> s_color
{
	result := color;
	result.a = alpha;
	return result;
}

init_waves :: proc()
{
	g_wave_count = 0;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 20, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 35, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 25, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 5, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 35, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 18, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 5, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 27, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 15, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 15, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.green, 4, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 20, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 20, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.green, 5, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.red, 10, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 20, 1.0});
	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.green, 14, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.green, 30, 1.0});
	g_wave_count += 1;

	list_add(&c_wave_arr[g_wave_count].data, s_wave_spawn_data{.blue, 102, 0.2});
	g_wave_count += 1;

}

equal :: proc(a, b: $T) -> bool
{
	result := a >= b;
	if result {
		assert(a == b);
	}
	return result;
}

rand_snorm :: proc() -> f32
{
	result := rand.float32() * 2 - 1;
	return result;
}

get_game_speed :: proc() -> f32
{
	result := c_game_speed_arr[g_game.speed_index];
	return result;
}