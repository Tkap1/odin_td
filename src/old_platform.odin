
package platform;

import "core:fmt"
import "core:dynlib"
import "core:time"
import "core:mem"
import "core:os"
// import "core:os/os2"
import "core:c/libc"
import "base:runtime"

s_game_api :: struct {
	lib: dynlib.Library,
	do_game: proc(rawptr) -> bool,
	modification_time: os.File_Time,
	api_version: int,
}


main :: proc()
{
	// dll, ok := dynlib.load_library("game.dll", true);
	// assert(ok);


	memory, ok2 := mem.alloc(10 * runtime.Megabyte);
	assert(ok2 == .None);

	game_api_version := 0
	api, _ := load_game_api(game_api_version);
	game_api_version += 1;

	// before := time.tick_now();
	for {
		// now := time.tick_now();
		// fmt.printf("%i\n", foo._nsec);
		// time.sleep(1000);
		dll_time, dll_time_err := os.last_write_time_by_name("game.dll");
		assert(dll_time_err == 0);
		if dll_time > api.modification_time {
			unload_game_api(&api);
			time.sleep(1 * time.Second);
			api, _ = load_game_api(game_api_version);
			game_api_version += 1;
		}

		should_exit := api.do_game(memory);
		if should_exit {
			break;
		}
	}
}

load_game_api :: proc(api_version: int) -> (api: s_game_api, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name("game.dll")
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of game.dll, error code: {1}",
			mod_time_error,
		)
		return
	}

	// NOTE: this needs to be a relative path for Linux to work.
	game_dll_name := fmt.tprintf("{0}game_{1}.dll", "./" when ODIN_OS != .Windows else "", api_version)
	copy_dll(game_dll_name) or_return

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}


unload_game_api :: proc(api: ^s_game_api) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("game_{0}.dll", api.api_version)) != nil {
		fmt.printfln("Failed to remove game_{0}.dll" + " copy", api.api_version)
	}
}

copy_dll :: proc(to: string) -> bool {
	exit: i32
	exit = libc.system(fmt.ctprintf("copy game.dll {0}", to))

	if exit != 0 {
		fmt.printfln("Failed to copy game.dll to {0}", to)
		return false
	}

	return true
}
