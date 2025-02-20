package gemini

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

	// hostname := "geminiprotocol.net"
	// defer delete(hostname_c)

	// doc_bytes, err := gemini_fetch(hostname)
	// if err != nil {
	///  	fmt.eprintfln("gemini: error %v", err)
	//  	os.exit(1)
	// }
	// defer delete(doc_bytes)

	// doc, err_doc := gemini_parse(doc_bytes)
	// if err_doc != nil {
	//  	fmt.eprintfln("gemini: error %v", err)
	//  	os.exit(1)
	// }
	// defer gemini_delete(doc)

	env: Environment
	env_navigate(&env, "geminiprotocol.net")
	if env.document.status != .Success || len(env.document.elements) == 0 {
		// fmt.eprintfln("Failed loading the document %#v", env)
		os.exit(1)
	}

	// Initialize raylib
	using raylib
	SetTraceLogLevel(.WARNING)
	SetTargetFPS(60)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })

	// Startup window
	InitWindow(i32(WIDTH), i32(HEIGHT), "Gemreq")

	// Load fonts
	env_load_fonts(&env)
	defer env_unload_fonts(&env)

	for !WindowShouldClose() {
		if env.document_is_loaded {
			if env.element_active != nil {
				#partial switch element in env.element_active.(Gemini_Element) {
				case Gemini_Element_Link:
					url := element.url
					if strings.has_prefix(url, "https://") {
						fmt.eprintfln("gemreq: todo!: HTTPS links are not supported %s", url)
					} else if strings.has_prefix(url, "gemini://") {
						env_navigate(&env, url)
					} else if strings.has_prefix(url, "/") { // Absolute path
						env_navigate_path(&env, url)
					} else { // Relative path
						path := strings.join({ env.endpoint.path, url }, "")
						defer delete(path)

						env_navigate_path(&env, path)
					}
				}
			}
			env.element_active = nil
		}
		mouse := GetMousePosition()

		BeginDrawing()
		defer EndDrawing()

		ClearBackground(COLOR_BG)
		if env.document_is_loaded {
			render_offset := f32(0)
			for element_untyped in env.document.elements {
				if render_offset >= HEIGHT do break
				switch element in element_untyped {
				case Gemini_Element_Text:
					height := element_draw_text(&env, element, render_offset, WIDTH_TEXT)
					render_offset += height
				case Gemini_Element_Link:
					size := f32(HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH)
					font := env.fonts[.Bold][.Paragraph]
					text := strings.clone_to_cstring(element.text)
					defer delete(text)

					measure := MeasureTextEx(font, text, size, CHAR_SPACING)
					text_bounds := Rectangle{
						x = PADDING,
						y = PADDING + render_offset,
						width = measure.x,
						height = measure.y
					}
					is_hover := CheckCollisionPointRec(mouse, text_bounds)
					if is_hover && IsMouseButtonPressed(.LEFT) {
						env.element_active = element_untyped
						fmt.println(element.text)
					}

					DrawTextEx(font, text, { PADDING, PADDING + render_offset }, size, CHAR_SPACING, COLOR_LINK)
					render_offset += measure.y
					DrawLine(i32(PADDING), i32(PADDING + render_offset), i32(PADDING + measure.x), i32(PADDING + render_offset), is_hover ? COLOR_TEXT : COLOR_LINK)
					render_offset += HEIGHT_DIVIDER
				}
			}
		}
	}
}
