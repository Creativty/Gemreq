package gemreq

import "core:os"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import "vendor:raylib"

main :: proc() {
	when false {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// Initialize raylib
	using raylib
	SetTargetFPS(60)
	SetTraceLogLevel(.WARNING)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })

	// Startup window
	InitWindow(i32(WIDTH), i32(HEIGHT), "Gemreq")
	SetExitKey(.ESCAPE)

	env := env_make()
	defer env_delete(&env)

	env_history_navigate_absolute(&env, "geminiprotocol.net")
	if env.document.status != .Success || len(env.document.elements) == 0 do os.exit(1)

	for !WindowShouldClose() {
		env_update(&env)

		BeginDrawing()
		defer EndDrawing()

		ClearBackground(COLOR_BG)
		env_render(&env)
	}
}
