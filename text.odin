package gemini

import "core:strings"
import "vendor:raylib"

Font_Weight :: enum {
	Thin,
    Extra_Light,
    Light,
    Normal,
    Medium,
    Semi_Bold,
    Bold,
    Extra_Bold,
    Black,
}

Font_Size :: enum {
	Paragraph,
	Heading,
}

Font :: raylib.Font

Font_Group :: [Font_Weight][Font_Size]Font

text_measure :: proc(font: Font, text: string, size, width, spacing: f32, allocator := context.allocator) -> [2]f32 {
	ctext := strings.clone_to_cstring(text, allocator)
	defer delete(ctext)

	measure := raylib.MeasureTextEx(font, ctext, size, spacing)
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
		// last_width	: f32
		// start, length, last_length: int
		// for start < len(text) && text[start] == ' ' do start += 1
		// for length <= len(text[start:]) {
		// 	measure := text_measure(font, text[start:][:length], size, width, spacing, allocator)
		// 	if measure.x < width {
		// 		last_length  = length
		// 		last_width = measure.x
		// 	} else do break
		// 	length += 1
		// }

		// append(&lines, text[start:][:last_length])
	return
}

element_draw_text :: proc(env: ^Environment, element: Gemini_Element_Text,
	offset: f32,
	width: f32,
	allocator := context.allocator) -> (height: f32)
{
	using raylib

	font := env.fonts[.Bold if element.heading > 0 else .Normal][.Heading if element.heading > 0 else .Paragraph]
	size := f32(HEIGHT_CHAR * (CHAR_FACTOR_HEADING if element.heading > 0 else CHAR_FACTOR_PARAGRAPH))
	spacing := f32(CHAR_SPACING)

	lines := text_wrap(font, element.text, size, width, spacing, allocator)
	defer delete(lines)
	
	offset_local: f32
	for line in lines {
		text := strings.clone_to_cstring(line)
		defer delete(text)

		measure := MeasureTextEx(font, text, size, spacing)
		if element.heading == 1 {
			DrawTextPro(font, text, { WIDTH / 2, PADDING + offset + offset_local }, { measure.x / 2, 0 }, 0.0, size, spacing, COLOR_TEXT)
		} else {
			DrawTextEx(font, text, { PADDING, PADDING + offset + offset_local }, size, spacing, COLOR_TEXT)
		}
		offset_local += measure.y
	}

	// text := strings.clone_to_cstring(element.text)
	// defer delete(text)
	// measure := MeasureTextEx(font, text, size, CHAR_SPACING)

	// if element.heading == 1 {
	// 	DrawTextPro(font, text, { WIDTH / 2, PADDING + offset }, { measure.x / 2, 0 }, 0.0, size, CHAR_SPACING, COLOR_TEXT)
	// } else {
	// 	DrawTextEx(font, text, { PADDING, PADDING + offset }, size, CHAR_SPACING, COLOR_TEXT)
	// }
	return offset_local + HEIGHT_DIVIDER
}
