
package game

c_updates_per_second :: 30;
c_game_speed :: 1.0;
c_update_delay :: 1.0 / c_updates_per_second;
c_num_tiles :: 30
c_max_towers :: 1024
c_max_enemies :: 1024
c_tile_size :: 24;
c_window_width :: c_num_tiles * c_tile_size
c_window_height :: c_num_tiles * c_tile_size
c_spawn_delay :: 0.1
c_total_tiles :: c_num_tiles * c_num_tiles;
c_start_tile :: s_v2i{0, c_num_tiles / 2};
c_end_tile :: s_v2i{c_num_tiles - 1, 0};
c_max_projectiles :: 4096;
c_tower_shoot_delay :: 1.0;
c_proj_duration :: 2;
c_enemy_size :: s_v2{c_tile_size - 8, c_tile_size - 8};
c_proj_size :: s_v2{c_tile_size * 0.5, c_tile_size * 0.5};
c_enemy_health : i32 : 10;
c_proj_speed : f32 : 1024;
c_window_size :: s_v2{c_window_width, c_window_height};
c_max_particles :: 4096;
c_replay_memory : i32 : 1024 * 1024 * 1024;
zero_float: f32 : 0.0
one_float: f32 : 1.0
pi :: cast(f32)3.1415926;
half_pi :: pi * 0.5;
quarter_pi :: pi * 0.25;
tau :: cast(f32)6.28318530717958647692;
epsilon :: cast(f32)0.000001;

// @Note(tkap, 03/12/2024): We need this because if we play the same sound twice and we set the pitch on each play the second pitch change will affect the first sound
c_sound_duplicates :: 8;