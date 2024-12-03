
package game

import "core:c/libc"
import "core:math"


e_animator :: enum
{
	curve,
	float,
	point,
	color,
	position,
};

e_ease :: enum
{
	linear,
	in_expo,
	in_quad,
	out_quad,
	out_expo,
	out_elastic,
	out_elastic2,
	out_back,
}

s_animator_curve :: struct
{
	a: s_v2,
	b: s_v2,
	pivot: s_v2,
}

s_animator_color :: struct
{
	a: s_color,
	b: s_color,
}

s_animator_float :: struct
{
	a: f32,
	b: f32,
}

s_animator_point :: struct
{
	a: s_v2,
}

s_animator_position :: struct
{
	a: s_v2,
	b: s_v2,
}

s_idk :: struct #raw_union
{
	curve: s_animator_curve,
	color: s_animator_color,
	nfloat: s_animator_float,
	point: s_animator_point,
	position: s_animator_position,
}

s_animator_property :: struct
{
	type : e_animator,
	ease_mode : e_ease,
	duration : f32,
	delay : f32,
	ptr: rawptr,
	value : s_idk,
};

s_animator :: struct
{
	needs_wait_call : bool,

	step_start_time_arr: [8]f32,
	result_on_end: [8]i32,
	step_count: i32,
	curr_step: i32,
	total_duration: f32,
	step_duration_arr: [8]f32,
	property_arr: [8]s_list(s_animator_property, 8),
};




update_animator :: proc(animator : ^s_animator, time_ptr : ^f32, speed : f32, loop: bool) -> i32
{
	assert(animator.step_count > 0);
	assert(speed > 0);

	// #if defined(m_debug)
	assert(!animator.needs_wait_call);
	// #endif // m_debug

	result : i32 = 0;
	if(time_ptr^ * speed >= animator.total_duration) {
		result = -1;
	}

	t : f32;
	if loop {
		t = libc.fmodf(time_ptr^ * speed, animator.total_duration);
	}
	else {
		t = min(time_ptr^ * speed, animator.total_duration);
	}

	step_index : i32 = -1;
	for step_i in 0..<animator.step_count {
		start := animator.step_start_time_arr[step_i];
		if t >= start && t <= start + animator.step_duration_arr[step_i] {
			step_index = step_i;
			break;
		}
	}
	assert(step_index >= 0);
	if(result == 0 && step_index > 0) {
		result = animator.result_on_end[step_index - 1];
	}

	for step_i in 0..<step_index + 1 {
		step_start := animator.step_start_time_arr[step_i];
		for property, _ in to_slice(&animator.property_arr[step_i]) {
			interp_dt := ilerp_clamp(step_start + property.delay, step_start + property.delay + property.duration, t);

			switch property.ease_mode {
				case .linear: interp_dt = ease_linear(interp_dt);
				case .in_expo: interp_dt = ease_in_expo(interp_dt);
				case .in_quad: interp_dt = ease_in_quad(interp_dt);
				case .out_quad: interp_dt = ease_out_quad(interp_dt);
				case .out_expo: interp_dt = ease_out_expo(interp_dt);
				case .out_elastic: interp_dt = ease_out_elastic(interp_dt);
				case .out_elastic2: interp_dt = ease_out_elastic2(interp_dt);
				case .out_back: interp_dt = ease_out_back(interp_dt);
			}

			switch property.type {
				case .curve: {
					p := bezier(property.value.curve.a, property.value.curve.b, property.value.curve.pivot, interp_dt);
					(cast(^s_v2)property.ptr)^ = p;
					// *(s_v2*)property.ptr = p;
				} break;

				case .color: {
					p := lerp_color(property.value.color.a, property.value.color.b, interp_dt);
					(cast(^s_color)property.ptr)^ = p;
				} break;

				case .float: {
					p := math.lerp(property.value.nfloat.a, property.value.nfloat.b, interp_dt);
					(cast(^f32)property.ptr)^ = p;
				} break;

				case .point: {
					(cast(^s_v2)property.ptr)^ = property.value.point.a;
				} break;

				case .position: {
					p := lerp_v2(property.value.position.a, property.value.position.b, interp_dt);
					(cast(^s_v2)property.ptr)^ = p;
				} break;
			}
		}
	}
	if(loop) {
		time_ptr^ = libc.fmodf(time_ptr^, animator.total_duration / speed);
	}
	else {
		time_ptr^ = min(time_ptr^, animator.total_duration / speed);
	}
	return result;
}

animator_wait_completed :: proc(animator : ^s_animator, delay: f32)
{
	animator_wait_completed_ex(animator, delay, 0);
}

animator_wait_completed_ex :: proc(animator : ^s_animator, delay: f32, result_on_end: i32)
{
	assert(delay >= 0);
	assert(animator.property_arr[animator.curr_step].count > 0);
	animator.curr_step += 1;
	animator.step_count += 1;
	animator.step_start_time_arr[animator.curr_step] = animator.step_start_time_arr[animator.curr_step - 1] + animator.step_duration_arr[animator.curr_step - 1] + delay;
	animator.total_duration += animator.step_duration_arr[animator.curr_step - 1] + delay;
	animator.step_duration_arr[animator.curr_step - 1] += delay;
	animator.result_on_end[animator.curr_step - 1] = result_on_end;

	// #ifdef m_debug
	animator.needs_wait_call = false;
	// #endif // m_debug
}

add_curve :: proc(animator: ^s_animator, a: s_v2, b: s_v2, pivot: s_v2, duration: f32, delay: f32, ptr: ^s_v2, ease_mode: e_ease)
{
	assert(ptr != nil);

	// #ifdef m_debug
	animator.needs_wait_call = true;
	// #endif // m_debug

	max_by_ptr(&animator.step_duration_arr[animator.curr_step], delay + duration);
	p: s_animator_property = {};
	p.type = .curve;
	p.ease_mode = ease_mode;
	p.duration = duration;
	p.delay = delay;
	p.ptr = ptr;
	p.value.curve.a = a;
	p.value.curve.b = b;
	p.value.curve.pivot = pivot;
	list_add(&animator.property_arr[animator.curr_step], p);
}

add_position :: proc(animator: ^s_animator, a: s_v2, b: s_v2, duration: f32, delay: f32, ptr: ^s_v2, ease_mode: e_ease)
{
	assert(ptr != nil);

	// #ifdef m_debug
	animator.needs_wait_call = true;
	// #endif // m_debug

	max_by_ptr(&animator.step_duration_arr[animator.curr_step], delay + duration);
	p: s_animator_property = {};
	p.type = .position;
	p.ease_mode = ease_mode;
	p.duration = duration;
	p.delay = delay;
	p.ptr = ptr;
	p.value.position.a = a;
	p.value.position.b = b;
	list_add(&animator.property_arr[animator.curr_step], p);
}

add_color :: proc(animator: ^s_animator, a: s_color, b: s_color, duration: f32, delay: f32, ptr: ^s_color, ease_mode: e_ease)
{
	assert(ptr != nil);

	// #ifdef m_debug
	animator.needs_wait_call = true;
	// #endif // m_debug

	max_by_ptr(&animator.step_duration_arr[animator.curr_step], delay + duration);
	p: s_animator_property = {};
	p.ease_mode = ease_mode;
	p.type = .color;
	p.duration = duration;
	p.delay = delay;
	p.ptr = ptr;
	p.value.color.a = a;
	p.value.color.b = b;
	list_add(&animator.property_arr[animator.curr_step], p);
}

add_point :: proc(animator: ^s_animator, a: s_v2, duration: f32, delay: f32, ptr: ^s_v2, ease_mode: e_ease)
{
	assert(ptr != nil);

	// #ifdef m_debug
	animator.needs_wait_call = true;
	// #endif // m_debug

	max_by_ptr(&animator.step_duration_arr[animator.curr_step], delay + duration);
	p: s_animator_property = {};
	p.ease_mode = ease_mode;
	p.type = .point;
	p.duration = duration;
	p.delay = delay;
	p.ptr = ptr;
	p.value.point.a = a;
	list_add(&animator.property_arr[animator.curr_step], p);
}

add_float :: proc(animator: ^s_animator, a: f32, b: f32, duration: f32, delay: f32, ptr: ^f32, ease_mode: e_ease)
{
	assert(ptr != nil);

	// #ifdef m_debug
	animator.needs_wait_call = true;
	// #endif // m_debug

	max_by_ptr(&animator.step_duration_arr[animator.curr_step], delay + duration);
	p: s_animator_property = {};
	p.ease_mode = ease_mode;
	p.type = .float;
	p.duration = duration;
	p.delay = delay;
	p.ptr = ptr;
	p.value.nfloat.a = a;
	p.value.nfloat.b = b;
	list_add(&animator.property_arr[animator.curr_step], p);
}
