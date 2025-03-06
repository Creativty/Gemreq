package gemreq

import "vendor:raylib"

Wrap_Config :: struct {
	font: raylib.Font,
	size: Font_Size,
	spacing: f32,
}

text_wrap :: proc(source: string, config: Wrap_Config, width: f64) -> []string {
	lines := make([dynamic]string)
	reader := reader_make(source)
	width_current := f64(0)
	for {
		char := reader_peek(&reader)
		if char == rune(0) do break

		g_info  := raylib.GetGlyphInfo(config.font, char)
		g_index := raylib.GetGlyphIndex(config.font, char)

		if config.font.glyphs[g_index].advanceX > 0 do width_current += cast(f64)config.font.glyphs[g_index].advanceX
		else do width_current += f64(config.font.recs[g_index].width + cast(f32)config.font.glyphs[g_index].offsetX)

		if width_current >= width {
			width_current = 0
			append(&lines, reader_consume(&reader))
		}

		reader_next(&reader)
	}
	return lines[:]
}
