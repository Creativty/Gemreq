package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

Environment :: struct {
	fonts: Font_Group,
	scroll, scroll_target: f32,
	document: Gemini_Document,
	document_is_loaded: bool,
	element_active: Maybe(Gemini_Element),
	history: [dynamic]Gemini_Endpoint,
	error: Gemini_Error,
	is_debug: bool,
}

// env_load_fonts :: proc(env: ^Environment) {
// 	using raylib
// 
// 	font_size := i32(math.floor(HEIGHT_CHAR))
// 	env.fonts[.Normal][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", font_size, nil, -1)
// 	env.fonts[.Bold][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", font_size, nil, -1)
// 	env.fonts[.Bold][.Heading] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", i32(f32(font_size) * CHAR_FACTOR_HEADING), nil, -1)
// }
// 
// env_unload_fonts :: proc(env: ^Environment) {
// 	using raylib
// 
// 	UnloadFont(env.fonts[.Normal][.Paragraph])
// 	UnloadFont(env.fonts[.Bold][.Paragraph])
// 	UnloadFont(env.fonts[.Bold][.Heading])
// }
// 
// env_delete :: proc(env: ^Environment) {
// 	for &endpoint in env.history do endpoint_delete(endpoint)
// 	gemini_delete(&env.document)
// }

env_make :: proc(allocator := context.allocator) -> (env: Environment) {
	using raylib

	font_size := i32(math.floor(HEIGHT_CHAR))
	env.history = make([dynamic]Gemini_Endpoint, allocator = allocator)
	env.fonts[.Normal][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Heading] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", i32(f32(font_size) * CHAR_FACTOR_HEADING), nil, -1)
	return
}

env_endpoint :: proc(env: ^Environment) -> Gemini_Endpoint {
	assert(len(env.history) > 0, "calling env_endpoint without a history")
	return env.history[len(env.history) - 1]
}

env_delete :: proc(env: ^Environment) {
	using raylib

	UnloadFont(env.fonts[.Normal][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Heading])

	for &endpoint in env.history do endpoint_delete(endpoint)
	gemini_delete(&env.document)
}

env_update :: proc(env: ^Environment) {
	using raylib

	if !env.document_is_loaded do return

	if env.element_active != nil { // Trigger navigation
		#partial switch element in env.element_active.(Gemini_Element) {
		case Gemini_Element_Link:
			env_history_navigate_link(env, element)
		}
		env.element_active = nil
	}

	key_navigate_back := (IsKeyDown(.LEFT_SUPER) || IsKeyDown(.RIGHT_SUPER)) && IsKeyPressed(.LEFT)
	if key_navigate_back do env_history_pop(env)

	key_debug := IsKeyPressed(.F1)
	if key_debug do env.is_debug = !env.is_debug
		
	env.scroll_target += -GetMouseWheelMove() * SCROLL_SPEED
	env.scroll_target = math.max(env.scroll_target, 0)
	env.scroll = math.lerp(env.scroll, env.scroll_target, f32(.1))
}
