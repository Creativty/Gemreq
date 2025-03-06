package gemreq

import "core:fmt"
import "core:strings"
import "vendor:raylib"

Wrap_Config :: struct {
	font_name: string,
	font_size: Font_Size,
	spacing: f32,
	color: raylib.Color,
}

text_wrap :: proc(browser: ^Browser, source: string, config: Wrap_Config, width: f64) -> []string {
	lines := make([dynamic]string)
	reader := reader_make(source)
	if len(source) == 0 do return lines[:]


	font := browser.fonts[config.font_name][config.font_size]
	for {
		text := strings.clone_to_cstring(reader_peek_token(&reader), context.temp_allocator)
		measure := raylib.MeasureTextEx(font, text, font_size_float(config.font_size), config.spacing)
		if cast(f64)measure.x >= width {
			line := reader_consume(&reader)
			append(&lines, strings.trim_space(line))
		}

		char := reader_peek(&reader)
		if char == rune(0) do break
		reader_next(&reader)
	}
	free_all(context.temp_allocator)
	if len(lines) == 0 do append(&lines, source)
	return lines[:]
}
