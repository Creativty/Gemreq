package gemreq

import "core:strings"
import "vendor:raylib"

raylib_make_text_options :: proc(browser: ^Browser, text: string, options: Text_Options) -> (ctext: cstring, measure: [2]f32) {
	size := font_size_float(options.font_size)
	font := browser.fonts[options.font_name][options.font_size]
	ctext = strings.clone_to_cstring(text, context.temp_allocator)
	measure = raylib.MeasureTextEx(font, ctext, size, options.spacing)
	return ctext, measure
}

raylib_make_text :: proc(browser: ^Browser, text: string, asset: Font_Asset, font_size := Font_Size.Regular, spacing := 1.0) -> (ctext: cstring, measure: [2]f32) {
	size := font_size_float(font_size)
	ctext = strings.clone_to_cstring(text, context.temp_allocator)
	measure = raylib.MeasureTextEx(asset[font_size], ctext, size, f32(spacing))
	return ctext, measure
}
