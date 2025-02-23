package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

env_render :: proc(env: ^Gemreq, allocator := context.allocator) {
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

env_render_debug :: proc(env: ^Gemreq, allocator := context.allocator) {
	using raylib

	text := fmt.caprintf("FPS: %d", GetFPS(), allocator = allocator)
	defer delete(text)

	font	:= env.assets.fonts[.Paragraph]
	size	:= HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH
	spacing	:= CHAR_SPACING
	measure := MeasureTextEx(font, text, size, spacing)

	DrawRectangle(0, 0, i32(measure.x + PADDING), i32(measure.y + PADDING), BLACK)
	DrawText(text, i32(PADDING / 2.0), i32(PADDING / 2.0), i32(size), WHITE)
}

env_render_document :: proc(env: ^Gemreq, allocator := context.allocator) {
	using raylib

	render_offset: f32
	is_something_hover: bool
	for element_untyped in env.document.elements {
		if render_offset - env.scroll > HEIGHT_VIEW do break
		switch element in element_untyped {
		case Gemini_Element_Text:
			height := draw_text_element(env, element, render_offset, WIDTH_TEXT, allocator)
			render_offset += height
		case Gemini_Element_Link:
			height: f32
			height, is_something_hover = draw_element_link(env, element, render_offset, WIDTH_TEXT, allocator)
			render_offset += height
		}
	}
}

env_render_document_error :: proc(env: ^Gemreq, allocator := context.allocator) {
	using raylib

	offset := Vector2{ WIDTH / 2.0, PADDING }
	render_title: {
		font := env.assets.fonts[.Heading_1]
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
		font := env.assets.fonts[.Paragraph]
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
