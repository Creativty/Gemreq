package gemreq

import "core:fmt"
import "core:strings"
import "vendor:raylib"

Text_Options :: struct {
	font_name: string,
	font_size: Font_Size,
	spacing: f32,
	color: raylib.Color,
}

Line :: struct {
	text: string,
	size: [2]f32,
}

text_wrap :: proc(browser: ^Browser, source: string, config: Text_Options, width: f64) -> []Line {
	lines := make([dynamic]Line)
	reader := reader_make(source)
	if len(source) == 0 do return lines[:]

	font := browser.fonts[config.font_name][config.font_size]
	for {
		token := strings.trim_space(reader_peek_token(&reader))
		text := strings.clone_to_cstring(token, context.temp_allocator)
		measure := raylib.MeasureTextEx(font, text, font_size_float(config.font_size), config.spacing)
		char := reader_peek(&reader)
		if cast(f64)measure.x >= width || char == rune(0) {
			line := strings.trim_space(reader_consume(&reader))
			if len(line) > 0 do append(&lines, Line{ line, measure })
			if char == rune(0) do break
		}
		reader_next(&reader)
	}
	return lines[:]
}
