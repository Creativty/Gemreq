package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

SCROLL_FACTOR :: VIEW_HEIGHT / 3 * 2

update_document :: proc(browser: ^Browser, dt: f64) {
	document, document_is_loaded := browser.document.(Document)
	if !document_is_loaded || browser.omnibar.visible do return

	key_shift := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)
	key_wheel := -raylib.GetMouseWheelMove() * SCROLL_FACTOR * (1 if key_shift else .1)
	key_scroll_up := raylib.IsKeyPressed(.PAGE_UP) || raylib.IsKeyPressedRepeat(.PAGE_UP)
	key_scroll_down := raylib.IsKeyPressed(.PAGE_DOWN) || raylib.IsKeyPressedRepeat(.PAGE_DOWN)
	if key_scroll_up do browser.scroll.target -= SCROLL_FACTOR
	if key_scroll_down do browser.scroll.target += SCROLL_FACTOR
	browser.scroll.target += f64(key_wheel)
	browser.scroll.target  = math.min(browser.scroll.target, f64(document.height - VIEW_HEIGHT))
	browser.scroll.target  = math.max(browser.scroll.target, 0)
	browser.scroll.current = math.lerp(browser.scroll.current, browser.scroll.target, LERP_FACTOR)
}

draw_document :: proc(browser: ^Browser, document: Document) {
	preview: Maybe(string)

	if document.status != 20 do return
	for element in document.elements {
		offset, gemtext := f64(element.offset) - browser.scroll.current, element.gemtext
		if offset < -WINDOW_PAD_Y * 2 do continue
		if offset > VIEW_HEIGHT do break
		if gemtext.kind == .Empty || gemtext.kind == .Preformatting_Delimiter do continue

		config	:= gemtext_options(browser, gemtext.kind)
		text	:= strings.clone_to_cstring(gemtext_get_text(gemtext), context.temp_allocator)

		size	:= font_size_float(config.font_size)
		font	:= browser.fonts[config.font_name][config.font_size]
		x		:= f32(WINDOW_PAD_X)
		if gemtext.kind == .Heading_1 do x = max(WINDOW_PAD_X, (WINDOW_WIDTH - element.size.x) / 2)
		raylib.DrawTextEx(font, text, { x, WINDOW_PAD_Y + f32(offset) }, size, config.spacing, config.color)
		if gemtext.kind == .Link {
			box := raylib.Rectangle{ WINDOW_PAD_X, WINDOW_PAD_Y + f32(offset), element.size.x, element.size.y }
			mouse := raylib.GetMousePosition()
			if raylib.CheckCollisionPointRec(mouse, box) {
				raylib.DrawRectangle(WINDOW_PAD_X, i32(WINDOW_PAD_Y + f32(offset) + element.size.y), i32(element.size.x), 1, config.color)
				url := gemtext.data.(Gemtext_Link).url
				preview = url
				// Instigate navigation
				if raylib.IsMouseButtonPressed(.LEFT) do navigate_click(browser, url)
			}
		}
	}

	// Draw url preview
	if url, url_visible := preview.(string); url_visible do draw_preview_url(browser, url)
}

draw_preview_url :: proc(browser: ^Browser, url: string) {
	size := Font_Size.Small
	asset := browser.fonts[FONT_SANS_REGULAR]
	spacing := 1.0
	size_f32 := font_size_float(size)
	text, measure := raylib_make_text(browser, url, asset, size, spacing)

	padding := [2]f32{ size_f32, size_f32 / 3.0 * 2.0 }
	box_preview := raylib.Rectangle{
		0,
		WINDOW_HEIGHT - measure.y - padding.y * 2,
		measure.x + padding.x * 2,
		measure.y + padding.y * 2,
	}
	// Background
	raylib.DrawRectangleRec(box_preview, raylib.GetColor(0x191919FF))
	// Text
	raylib.DrawTextEx(asset[size], text, { box_preview.x, box_preview.y } + padding, size_f32, 1.0, color_text)
	// Border
	raylib.DrawRectangleLinesEx(box_preview, 1.0, raylib.GetColor(0x000000FF))
}
