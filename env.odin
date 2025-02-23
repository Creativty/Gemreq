package gemini

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

env_delete :: proc(env: ^Environment) {
	for &endpoint in env.history do endpoint_delete(endpoint)
	gemini_delete(&env.document)
}

env_load_fonts :: proc(env: ^Environment) {
	using raylib

	font_size := i32(math.floor(HEIGHT_CHAR))
	env.fonts[.Normal][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Heading] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", i32(f32(font_size) * CHAR_FACTOR_HEADING), nil, -1)
}

env_unload_fonts :: proc(env: ^Environment) {
	using raylib

	UnloadFont(env.fonts[.Normal][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Heading])
}

env_endpoint :: proc(env: ^Environment) -> Gemini_Endpoint {
	assert(len(env.history) > 0, "calling env_endpoint without a history")
	return env.history[len(env.history) - 1]
}

env_history_navigate_absolute :: proc(env: ^Environment, url: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	host, port, path, url_ok := gemini_parse_url(url)
	if !url_ok {
		env.error = strings.clone_to_cstring("failed parsing url", allocator)
		return false
	}
	return env_history_navigate_endpoint(env, { host = host, path = path, port = port }, history_append, allocator)
}

env_history_navigate_relative :: proc(env: ^Environment, path: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	assert(env.document_is_loaded, "calling env_history_navigate_path without a parent document")

	endpoint := env_endpoint(env)
	endpoint.host = strings.clone(endpoint.host, allocator)
	endpoint.path = strings.clone(path, allocator)
	return env_history_navigate_endpoint(env, endpoint, history_append, allocator)
}

env_history_navigate_link :: proc(env: ^Environment, element: Gemini_Element_Link) {
	url := element.url
	if strings.has_prefix(url, "https://") do fmt.eprintfln("gemreq: todo!: HTTPS links are not supported %s", url)
	else if strings.has_prefix(url, "gopher://") do fmt.eprintfln("gemreq: todo!: Gopher links are not supported %s", url)
	else if strings.has_prefix(url, "gemini://") do env_history_navigate_absolute(env, url)
	else if strings.has_prefix(url, "/") do env_history_navigate_relative(env, url)
	else {
		// BUG(XENOBAS): navigating from .../docs/faq.gmi -> faq-section-4.gmi
		// results in .../docs/faq.gmifaq-section-4.gmi
		endpoint := env_endpoint(env)
		path := strings.join({ endpoint.path, url }, "")

		env_history_navigate_relative(env, path)
		delete(path)
	}
}

env_history_navigate_endpoint :: proc(env: ^Environment, endpoint: Gemini_Endpoint, history_append := true, allocator := context.allocator) -> (ok: bool) {
	fmt.printfln("gemreq: attempting navigating to %s:%d%s", endpoint.host, endpoint.port, endpoint.path)

	// Cleanup previous navigation
	if env.document_is_loaded do gemini_delete(&env.document)
	env.document_is_loaded = false

	// Send a Gemini request
	bytes, error_fetch := gemini_fetch(endpoint.host, endpoint.port, endpoint.path, allocator)
	if error_fetch != nil {
		fmt.eprintfln("gemreq: error during fetch %v", error_fetch)
		env.error = error_fetch
		return false
	}
	defer delete(bytes)

	if history_append do append(&env.history, endpoint)
	env.scroll_target = 0

	// Parse the Gemini document for display
	document, error_parse := gemini_parse(bytes)
	if error_parse != nil {
		fmt.eprintfln("gemreq: error during parsing %v", error_parse)
		env.error = error_parse
		return false
	}
	env.document = document
	env.document_is_loaded = true

	if gemini_status_is_redirect(document.status) && document.location != nil {
		location := document.location.(string)
		return env_history_navigate_absolute(env, location, false, allocator)
	}
	return true
}

env_history_pop :: proc(env: ^Environment) {
	if len(env.history) > 1 {
		endpoint_delete(pop(&env.history))
		endpoint := env_endpoint(env)
		env_history_navigate_endpoint(env, endpoint, false)
	}
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

env_render_document :: proc(env: ^Environment, allocator := context.allocator) {
	using raylib

	render_offset: f32
	is_something_hover: bool
	for element_untyped in env.document.elements {
		if render_offset - env.scroll > HEIGHT_VIEW do break
		switch element in element_untyped {
		case Gemini_Element_Text:
			height := draw_text_element(env, element, render_offset, WIDTH_TEXT, allocator)
			render_offset += height
		case Gemini_Element_Link: // BUG(XENOBAS): Does not have wrapping
			height: f32
			height, is_something_hover = draw_element_link(env, element, render_offset, WIDTH_TEXT, allocator)
			render_offset += height
		}
	}
}

env_render_document_error :: proc(env: ^Environment, allocator := context.allocator) {
	using raylib

	offset := Vector2{ WIDTH / 2.0, HEIGHT / 4.0 }
	render_title: {
		font := env.fonts[.Bold][.Heading]
		size := HEIGHT_CHAR * CHAR_FACTOR_HEADING
		width := WIDTH_TEXT
		spacing := CHAR_SPACING

		source := gemini_status_to_text(env.document.status)

		blocks := text_wrap(font, source, size, width, spacing, allocator)
		defer delete(blocks)

		local_offset_y: f32
		for block in blocks {
			text := strings.clone_to_cstring(block, allocator)
			defer delete(text)

			measure := MeasureTextEx(font, text, size, spacing)
			origin := Vector2{ measure.x / 2.0, 0 }
			position := Vector2{ offset.x, offset.y + local_offset_y }
			DrawTextPro(font, text, position, origin, 0.0, size, spacing, COLOR_DANGER)

			local_offset_y += measure.y
		}
		local_offset_y += HEIGHT_DIVIDER
	}

	render_description: {
		font := env.fonts[.Normal][.Paragraph]
		size := HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH
		width := WIDTH_TEXT / 5 * 4
		spacing := CHAR_SPACING

		description := gemini_status_to_description(env.document.status)
		source := strings.clone(description, allocator)
		defer delete(source)

		blocks := text_wrap(font, source, size, width, spacing, allocator)
		defer delete(blocks)

		offset.y += PADDING + (HEIGHT_CHAR + CHAR_FACTOR_HEADING)
		local_offset_y: f32
		for block in blocks {
			text := strings.clone_to_cstring(block, allocator)
			defer delete(text)

			measure := MeasureTextEx(font, text, size, spacing)
			origin := Vector2{ measure.x / 2.0, 0 }
			position := Vector2{ offset.x, offset.y + local_offset_y }
			DrawTextPro(font, text, position, origin, 0.0, size, spacing, COLOR_TEXT)

			local_offset_y += measure.y
		}
		local_offset_y += HEIGHT_DIVIDER
	}
}

env_render_debug :: proc(env: ^Environment, allocator := context.allocator) {
	using raylib

	text := fmt.caprintf("FPS: %d", GetFPS(), allocator = allocator)
	defer delete(text)

	font	:= env.fonts[.Normal][.Paragraph]
	size	:= HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH
	spacing	:= CHAR_SPACING
	measure := MeasureTextEx(font, text, size, spacing)

	DrawRectangle(0, 0, i32(measure.x + PADDING), i32(measure.y + PADDING), BLACK)
	DrawText(text, i32(PADDING / 2.0), i32(PADDING / 2.0), i32(size), WHITE)
}

env_render :: proc(env: ^Environment, allocator := context.allocator) {
	using raylib

	if !env.document_is_loaded do return
	#partial switch env.document.status {
	case .Success:
		env_render_document(env, allocator)
	case:
		env_render_document_error(env, allocator)
	}
	if env.is_debug do env_render_debug(env, allocator)
}
