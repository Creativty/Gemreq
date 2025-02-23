package gemreq

import "core:strings"
import "vendor:raylib"

text_measure :: proc(font: Font, source: string, size, width, spacing: f32, allocator := context.allocator) -> [2]f32 {
	text := strings.clone_to_cstring(source, allocator)
	defer delete(text)

	measure := raylib.MeasureTextEx(font, text, size, spacing)
	return measure
}

text_wrap :: proc(font: Font, text: string, size, width, spacing: f32, allocator := context.allocator)	-> (lines: [dynamic]string)
{
	text := strings.trim(text, "\r\n \t")
	lines = make([dynamic]string, allocator = allocator)

	for i := 0; i < len(text); {
		width_last: f32
		start, length, length_last: int

		for text[i] == ' ' do i += 1 // skip spaces
		for length <= len(text[i:]) {
			measure := text_measure(font, text[i:][:length], size, width, spacing, allocator)
			if measure.x >= width do break

			width_last = measure.x
			length_last = length
			length += 1
		}
		append(&lines, text[i:][:length_last])
		i += length_last
	}
	return
}

draw_text_element :: proc(env: ^Gemreq,
	element: Gemini_Element_Text,
	offset: f32,
	width: f32,
	allocator := context.allocator) -> (height: f32)
{
	using raylib

	// TODO(XENOBAS): Use a function to determin text display options, instead of this mess.
	style	:= font_style_from_element(element)
	font	:= env.assets.fonts[style]
	size	:= cast(f32)font_size_from_style(style)
	spacing	:= CHAR_SPACING

	lines := text_wrap(font, element.text, size, width, spacing, allocator)
	defer delete(lines)

	if offset - env.scroll > HEIGHT_VIEW do return
	
	offset_local: f32
	for line in lines {
		text := strings.clone_to_cstring(line, allocator)
		defer delete(text)

		measure := MeasureTextEx(font, text, size, spacing)
		if measure.y + offset_local + offset < env.scroll - 100 {
			offset_local += measure.y
			continue
		}
		if measure.y + offset_local + offset - env.scroll > HEIGHT_VIEW do break
		if element.heading == 1 {
			DrawTextPro(font, text, { WIDTH / 2, PADDING + offset + offset_local - env.scroll }, { measure.x / 2, 0 }, 0.0, size, spacing, COLOR_TEXT)
		} else {
			DrawTextEx(font, text, { PADDING, PADDING + offset + offset_local - env.scroll }, size, spacing, COLOR_TEXT)
		}
		offset_local += measure.y
	}
	return offset_local + HEIGHT_DIVIDER
}

draw_element_link :: proc(env: ^Gemreq,
		element: Gemini_Element_Link,
		offset, width: f32,
		allocator := context.allocator) -> (height: f32, is_something_hover: bool)
{
	using raylib


	style	:= font_style_from_element(element)
	size	:= cast(f32)font_size_from_style(style)
	font	:= env.assets.fonts[style]
	mouse := GetMousePosition()
	spacing	:= CHAR_SPACING

	lines := text_wrap(font, element.text, size, width, spacing, allocator)
	defer delete(lines)

	offset_local: f32
	for line in lines {
		text := strings.clone_to_cstring(line, allocator)
		defer delete(text)

		measure := MeasureTextEx(font, text, size, spacing)
		if measure.y + offset_local + offset < env.scroll {
			offset_local += measure.y + HEIGHT_DIVIDER
			continue
		}
		if measure.y + offset_local + offset - env.scroll > HEIGHT_VIEW do break
		text_bounds := Rectangle{
			x = PADDING,
			y = PADDING + offset + offset_local - env.scroll,
			width = measure.x,
			height = measure.y
		}

		is_hover := CheckCollisionPointRec(mouse, text_bounds)
		is_something_hover = is_something_hover || is_hover
		if is_hover && IsMouseButtonPressed(.LEFT) do env.link = element

		color := is_hover ? COLOR_LINK : COLOR_TEXT

		DrawTextEx(font, text, { PADDING, PADDING + offset + offset_local - env.scroll }, size, CHAR_SPACING, color)
		offset_local += measure.y
		DrawLine(i32(PADDING), i32(PADDING + offset + offset_local - env.scroll), i32(PADDING + measure.x), i32(PADDING + offset + offset_local - env.scroll), color)
		offset_local += HEIGHT_DIVIDER
	}

	return offset_local, is_something_hover
}
