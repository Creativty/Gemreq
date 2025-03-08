package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

update_document :: proc(browser: ^Browser, dt: f64) {
	document, document_is_loaded := browser.document.(Document)
	if !document_is_loaded || browser.omnibar.visible do return

	key_shift := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)
	key_wheel := -cast(f64)raylib.GetMouseWheelMove() * (VIEW_HEIGHT / 10) * (10 if key_shift else 1)
	browser.scroll.target += key_wheel
	browser.scroll.target = math.max(0, browser.scroll.target)
	browser.scroll.current = math.lerp(browser.scroll.current, browser.scroll.target, LERP_FACTOR)
}

draw_document :: proc(browser: ^Browser, document: Document) {
	if document.status != 20 do return
	preview: Maybe(string)
	offset_y := f32(-browser.scroll.current)
	config_empty := gemtext_wrap_config(browser, .Empty)
	for node in document.gemtext {
		if node.kind == .Empty || node.kind == .Preformatting_Delimiter {
			offset_y += font_size_float(config_empty.font_size)
			continue
		}

		config := gemtext_wrap_config(browser, node.kind)
		repr := gemtext_get_text(node)
		text := strings.clone_to_cstring(repr, context.temp_allocator)
		size := font_size_float(config.font_size)
		font := browser.fonts[config.font_name][config.font_size]
		measure := raylib.MeasureTextEx(font, text, size, config.spacing)

		if cast(f64)offset_y + WINDOW_PAD_Y * 4 >= 0 {
			raylib.DrawTextEx(font, text, { WINDOW_PAD_X, WINDOW_PAD_Y + offset_y }, size, config.spacing, config.color)
			if node.kind == .Link {
				box := raylib.Rectangle{ WINDOW_PAD_X, WINDOW_PAD_Y + offset_y, measure.x, measure.y }
				mouse := raylib.GetMousePosition()
				if raylib.CheckCollisionPointRec(mouse, box) {
					raylib.DrawRectangle(WINDOW_PAD_X, i32(WINDOW_PAD_Y + offset_y + measure.y), i32(measure.x), 1, color_link)
					url := node.data.(Gemtext_Link).url
					preview = url
					// Instigate navigation
					if raylib.IsMouseButtonPressed(.LEFT) do navigate_click(browser, url)
				}
			}
		}
		offset_y += measure.y
		offset_y += font_size_float(config_empty.font_size) * 0.5

		if offset_y > VIEW_HEIGHT do break
	}
	// Draw url preview
	if url, preview_visible := preview.(string); preview_visible {
		text := strings.clone_to_cstring(url, context.temp_allocator)
		size := font_size_float(Font_Size.Extra_Small)
		font := browser.fonts[FONT_SANS_REGULAR][Font_Size.Extra_Small]
		measure := raylib.MeasureTextEx(font, text, size, 1.0)
		padding := [2]f32{ size, size }
		box_preview := raylib.Rectangle{
			0,
			WINDOW_HEIGHT - measure.y - padding.y * 2,
			measure.x + padding.x * 2,
			measure.y + padding.y * 2,
		}
		// raylib.DrawRectangleRec(box_preview, raylib.GetColor(0xF1F1F1FF))
		raylib.DrawRectangleRec(box_preview, raylib.GetColor(0x191919FF))
		raylib.DrawTextEx(font, text, { box_preview.x, box_preview.y } + padding, size, 1.0, color_text)
		raylib.DrawRectangleLinesEx(box_preview, 1.0, raylib.GetColor(0x000000FF))
	}
	free_all(context.temp_allocator)
}
