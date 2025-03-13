package gemreq

import "core:log"
import "core:math"
import "core:time"
import "core:strings"
import "vendor:raylib"

clear_document_layout :: proc(document: ^Document) {
	document.height = 0
	clear(&document.elements)
	resize(&document.elements, len(document.gemtexts))
}

update_document_layout :: proc(browser: ^Browser, document: ^Document) {
	// Timing
	timing: time.Stopwatch
	time.stopwatch_start(&timing)
	defer {
		time.stopwatch_stop(&timing)

		timing_duration := time.stopwatch_duration(timing)
		log.debugf("took %v.", timing_duration)
	}

	in_preformat: bool
	clear_document_layout(document)
	ui := ui_scaling_pixels()
	config_empty := gemtext_options(browser, .Empty)
	for gemtext in document.gemtexts {
		switch gemtext.kind {
		case .Text, .Blockquote, .List, .Heading_1, .Heading_2, .Heading_3:
			config := gemtext_options(browser, gemtext.kind)
			lines := text_wrap(browser, gemtext.data.(string), config, f64(ui.view.x))
			for line in lines {
				gemtext_line := Gemtext{ gemtext.kind, line.text }
				append(&document.elements, Element{ line.size, document.height, gemtext_line, in_preformat })
				document.height += line.size.y
				document.height += font_size_float(config_empty.font_size) * 0.4
			}
		case .Link:
			config := gemtext_options(browser, .Link)
			gemtext := gemtext.data.(Gemtext_Link)
			lines := text_wrap(browser, gemtext.text, config, f64(ui.view.x))
			for line in lines {
				gemtext_line := Gemtext{ .Link, Gemtext_Link{ line.text, gemtext.url } }
				append(&document.elements, Element{ line.size, document.height, gemtext_line, in_preformat })
				document.height += line.size.y
				document.height += font_size_float(config_empty.font_size) * 0.4
			}
		case .Empty, .Preformatting_Delimiter:
			if gemtext.kind == .Preformatting_Delimiter do in_preformat = !in_preformat
			height := font_size_float(config_empty.font_size) if gemtext.kind == .Empty else 0.0
			append(&document.elements, Element{ { 0, height }, document.height, gemtext, in_preformat })
			document.height += height
		}
	}
}

update_document :: proc(browser: ^Browser, dt: f64, must_update_layout := false) {
	ui := ui_scaling_pixels()

	document, document_is_loaded := &browser.document.(Document)
	if !document_is_loaded || browser.omnibar.visible do return

	if must_update_layout do update_document_layout(browser, document)

	SCROLL_POWER := f64(ui.window.y) * SCROLL_FACTOR
	key_shift := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)
	key_wheel := -f64(raylib.GetMouseWheelMove()) * SCROLL_POWER * (1 if key_shift else .1)
	key_scroll_up := raylib.IsKeyPressed(.PAGE_UP) || raylib.IsKeyPressedRepeat(.PAGE_UP)
	key_scroll_down := raylib.IsKeyPressed(.PAGE_DOWN) || raylib.IsKeyPressedRepeat(.PAGE_DOWN)
	if key_scroll_up do browser.scroll.target -= SCROLL_POWER
	if key_scroll_down do browser.scroll.target += SCROLL_POWER
	browser.scroll.target += f64(key_wheel)
	browser.scroll.target  = max(min(browser.scroll.target, f64(document.height - ui.view.y)), 0)
	browser.scroll.current = math.lerp(browser.scroll.current, browser.scroll.target, LERP_FACTOR)
}

draw_document :: proc(browser: ^Browser, document: Document) {
	if document.status != 20 do return

	ui := ui_scaling_pixels()
	for element in document.elements {
		offset, gemtext := element.offset - f32(browser.scroll.current), element.gemtext
		if offset < -(ui.padding.y * 2) do continue
		if offset > +(ui.padding.y * 2 + ui.view.y) do break
		if gemtext.kind == .Empty || gemtext.kind == .Preformatting_Delimiter do continue

		config	:= gemtext_options(browser, gemtext.kind)
		text	:= strings.clone_to_cstring(gemtext_get_text(gemtext), context.temp_allocator)

		size	:= font_size_float(config.font_size)
		font	:= browser.fonts[config.font_name][config.font_size]
		x		:= ui.padding.x
		if gemtext.kind == .Heading_1 do x = max(ui.padding.x, (ui.window.x - element.size.x) / 2)
		raylib.DrawTextEx(font, text, { x, ui.padding.y + offset }, size, config.spacing, config.color)
		if gemtext.kind == .Link {
			box := raylib.Rectangle{ ui.padding.x, ui.padding.y + offset, element.size.x, element.size.y }
			url := gemtext.data.(Gemtext_Link).url
			mouse := raylib.GetMousePosition()
			hover_url, hover_matches := browser.hover.(string)
			hover_collision := raylib.CheckCollisionPointRec(mouse, box)
			if hover_collision || (hover_matches && hover_url == url) {
				browser.hover = url
				raylib.DrawRectangleRec({ ui.padding.x, ui.padding.y + offset + element.size.y, element.size.x, 1.0 }, config.color)
				// Instigate navigation
				if raylib.IsMouseButtonPressed(.LEFT) && hover_collision do navigate_click(browser, url)
			}
		}
	}

	// Draw url preview
	if url, url_visible := browser.hover.(string); url_visible do draw_preview_url(browser, url)
	if browser.omnibar.disabled {
		time := raylib.GetTime() - browser.omnibar.disabled_timestamp
		sine := f32(math.sin(time * 2.0)) * 0.5 + 0.5
		axis := min(ui.padding.x, ui.padding.y)
		radius := sine * axis / 5.0
		raylib.DrawCircleV({ ui.window.x - axis / 2.0, ui.window.y - axis / 2.0 }, radius, color_link)
	}
}

draw_preview_url :: proc(browser: ^Browser, url: string) {
	ui := ui_scaling_pixels()
	size := Font_Size.Small
	asset := browser.fonts[FONT_SANS_REGULAR]
	spacing := 1.0
	size_f32 := font_size_float(size)
	text, measure := raylib_make_text(browser, url, asset, size, spacing)

	padding := [2]f32{ size_f32, size_f32 / 3.0 * 2.0 }
	box_preview := raylib.Rectangle{
		0,
		ui.window.y - measure.y - padding.y * 2,
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
