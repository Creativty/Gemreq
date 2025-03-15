package gemreq

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
	font := browser.fonts[config.font_name][config.font_size]
	font_size := font_size_float(config.font_size)
	lines := make([dynamic]Line)
	reader := reader_make(source)
	if len(source) == 0 do return lines[:]

	is_whitespace :: proc(_: int, c: rune) -> bool {
		return c == ' ' || c == '\t' || c == '\f' || c == '\v'
	}
	is_not_whitespace :: proc(_: int, c: rune) -> bool {
		return c != ' ' && c != '\t' && c != '\f' && c != '\v'
	}

	for !reader_eof(&reader) {
		text_best_fit: cstring
		index_best_fit: int
		measure_best_fit: [2]f32

		reader_skip_whitespace(&reader)
		for !reader_eof(&reader) {
			word_length := reader_next_while(&reader, is_not_whitespace)
			token	:= strings.trim_space(reader_peek_token(&reader))
			text	:= strings.clone_to_cstring(token, context.temp_allocator)
			measure	:= raylib.MeasureTextEx(font, text, font_size, config.spacing)
			if f64(measure.x) >= width {
				index_best_fit = reader.index_curr - word_length
				break
			}
			text_best_fit = text
			measure_best_fit = measure
			reader_next_while(&reader, is_whitespace)
		}
		if text_best_fit == nil do break
		if index_best_fit != 0 do reader.index_curr = index_best_fit
		if len(text_best_fit) > 0 {
			token := strings.trim_space(reader_consume(&reader))
			line := Line{ token, measure_best_fit }
			append(&lines, line)
		}
	}
	return lines[:]
}
