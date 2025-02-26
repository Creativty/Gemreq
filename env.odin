package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

Gemreq :: struct {
	assets: struct {
		fonts: Font_Collection,
	},
	scroll, scroll_target: f32,
	document: Gemini_Document,
	document_is_loaded: bool,
	link: Maybe(Gemini_Element_Link),
	history: [dynamic]Gemini_Endpoint,
	error: Gemini_Error,
	is_debug: bool,
}

font_size_from_style :: proc(font_style: Font_Style) -> i32 {
	switch font_style {
	case .Bold, .Italic, .Paragraph, .Bold_Italic:
		return i32(HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH)
	case .Heading_1:
		return i32(HEIGHT_CHAR * CHAR_FACTOR_HEADING_1)
	case .Heading_2:
		return i32(HEIGHT_CHAR * CHAR_FACTOR_HEADING_2)
	case .Heading_3:
		return i32(HEIGHT_CHAR * CHAR_FACTOR_HEADING_3)
	}
	return i32(HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH)
}

env_make :: proc(allocator := context.allocator) -> (env: Gemreq) {
	using raylib

	font_size := math.floor(HEIGHT_CHAR)
	env.history = make([dynamic]Gemini_Endpoint, allocator = allocator)

	env.assets.fonts[.Bold] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", font_size_from_style(.Bold), nil, -1)
	env.assets.fonts[.Italic] = LoadFontEx("font/ttf/DejaVuSerif-Italic.ttf", font_size_from_style(.Italic), nil, -1)
	env.assets.fonts[.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", font_size_from_style(.Paragraph), nil, -1)
	env.assets.fonts[.Bold_Italic] = LoadFontEx("font/ttf/DejaVuSerif-BoldItalic.ttf", font_size_from_style(.Bold_Italic), nil, -1)

	env.assets.fonts[.Heading_1] = LoadFontEx("font/ttf/DejaVuSerifCondensed-Bold.ttf", font_size_from_style(.Heading_1), nil, -1)
	env.assets.fonts[.Heading_2] = LoadFontEx("font/ttf/DejaVuSerifCondensed-Bold.ttf", font_size_from_style(.Heading_2), nil, -1)
	env.assets.fonts[.Heading_3] = LoadFontEx("font/ttf/DejaVuSerifCondensed-Bold.ttf", font_size_from_style(.Heading_3), nil, -1)

	return
}

env_delete :: proc(env: ^Gemreq) {
	using raylib

	for font in env.assets.fonts do UnloadFont(font)
	for &endpoint in env.history do endpoint_delete(endpoint)

	gemini_delete(&env.document)
	delete(env.history)
}

env_update :: proc(env: ^Gemreq) {
	using raylib

	if !env.document_is_loaded do return

	env.scroll			 = math.lerp(env.scroll, env.scroll_target, SCROLL_TAUX)

	key_scroll_up		:= IsKeyPressed(.PAGE_UP)
	key_scroll_down		:= IsKeyPressed(.PAGE_DOWN)
	if key_scroll_up do env.scroll_target -= SCROLL_SPEED * 10
	if key_scroll_down do env.scroll_target += SCROLL_SPEED * 10

	env.scroll_target	-= GetMouseWheelMove() * SCROLL_SPEED
	env.scroll_target	 = math.max(env.scroll_target, 0)

	key_navigate_back := (IsKeyDown(.LEFT_SUPER) || IsKeyDown(.RIGHT_SUPER)) && IsKeyPressed(.LEFT)
	if key_navigate_back do env_history_pop(env)

	key_debug := IsKeyPressed(.F1)
	if key_debug do env.is_debug = !env.is_debug

	// NOTE(XENOBAS): Navigate to active link
	if env.link != nil {
		link := env.link.(Gemini_Element_Link)
		env_history_navigate_link(env, link)
		env.link = nil
	}
}

env_endpoint :: proc(env: ^Gemreq) -> Gemini_Endpoint {
	assert(len(env.history) > 0, "calling env_endpoint without a history")

	return env.history[len(env.history) - 1]
}
