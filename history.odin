package gemreq

import "uri"
import "core:fmt"
import "core:log"
import "core:sync"
import "core:time"
import "core:strings"
import "vendor:raylib"

History_Entry :: struct {
	location: uri.URI,
	timestamp: time.Time,
}

History :: struct {
	active, visible: bool,
	mutex: sync.Mutex,
	index: int,
	entries: [dynamic]History_Entry,
}

make_history :: proc() -> (history: History) {
	history.entries = make([dynamic]History_Entry)
	log.debugf("history initialised")
	return
}

delete_history :: proc(history: ^History) {
	sync.mutex_guard(&history.mutex)

	history.index = 0
	for {
		if len(history.entries) == 0 do break

		entry := pop(&history.entries)
		uri.destroy(entry.location)
	}
	delete(history.entries)
	log.debugf("history deleted")
}

push_history_text :: proc(history: ^History, text: string) -> (entry: History_Entry, ok: bool) {
	// sync.mutex_guard(&history.mutex)

	location := uri.parse(text) or_return
	return push_history_location(history, location)
	// timestamp := time.now()
	// if len(history.entries) > 0 && history.index + 1 != len(history.entries) {
	// 	for i in 0..=(len(history.entries) - history.index) {
	// 		entry := pop(&history.entries)
	// 		uri.destroy(entry.location)
	// 	}
	// }
	// entry =  History_Entry{ location, timestamp }
	// append(&history.entries, entry)
	// history.index = len(history.entries) - 1
	// return entry, true
}

push_history_location :: proc(history: ^History, location: uri.URI) -> (entry: History_Entry, ok: bool) {
	sync.mutex_guard(&history.mutex)

	timestamp := time.now()
	if len(history.entries) > 0 && history.index + 1 != len(history.entries) {
		for i in 0..=(len(history.entries) - history.index) {
			entry := pop(&history.entries)
			uri.destroy(entry.location)
		}
	}
	entry =  History_Entry{ location, timestamp }
	append(&history.entries, entry)
	history.index = len(history.entries) - 1
	return entry, true
}

push_history :: proc {
	push_history_text,
	push_history_location,
}

pop_history :: proc(history: ^History) -> (entry: History_Entry, ok: bool) {
	sync.mutex_guard(&history.mutex)

	if len(history.entries) == 0 || history.index <= 0 do return entry, false
	history.index -= 1
	return history.entries[history.index], true
}

location_history :: proc(history: ^History) -> (entry: History_Entry, ok: bool) {
	sync.mutex_guard(&history.mutex)

	if len(history.entries) == 0 || history.index < 0 || history.index >= len(history.entries) do return entry, false
	return history.entries[history.index], true
}

update_history :: proc(browser: ^Browser, dt: f64) {
	history := &browser.history

	key_control := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
	key_toggle  := key_control && raylib.IsKeyPressed(.H)
	if key_toggle do history.visible = !history.visible

	if !history.active || browser.omnibar.visible do return
}

draw_history :: proc(browser: ^Browser) {
	ui := ui_scaling_pixels()
	history := &browser.history

	panel := raylib.Rectangle{
		0, 0,
		(ui.padding.x * 2) + ui.window.x * 0.4, ui.window.y
	}
	raylib.DrawRectangleRec({ 0, 0, ui.window.x, ui.window.y }, raylib.ColorAlpha(color_background, 0.666))
	raylib.DrawRectangleRec(panel, color_background)
	raylib.DrawLineV({ panel.width, 0 }, { panel.width, panel.height }, raylib.ColorBrightness(color_background, 0.2))

	offset := ui.padding
	{
		options := Text_Options {
			FONT_SANS_BOLD,
			Font_Size.Extra_Large,
			1.2,
			color_text,
		}
		font	:= browser.fonts[options.font_name][options.font_size]
		size	:= font_size_float(options.font_size)
		text	:= fmt.ctprint("HISTORY")
		measure	:= raylib.MeasureTextEx(font, text, size, options.spacing)
		raylib.DrawTextEx(font, text, { offset.x, offset.y }, size, options.spacing, options.color)
		offset.y += measure.y + measure.y * 1.4
	}
	{
		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		defer strings.builder_destroy(&builder)

		options := Text_Options {
			FONT_SANS_REGULAR,
			Font_Size.Regular,
			1.0,
			color_link,
		}
		font	:= browser.fonts[options.font_name][options.font_size]
		size	:= font_size_float(options.font_size)
		#reverse for entry in history.entries[:] {
			uri.write(&builder, entry.location, omit_scheme = true)

			text, _	:= strings.to_cstring(&builder)
			measure	:= raylib.MeasureTextEx(font, text, size, options.spacing)
			raylib.DrawTextEx(font, text, { offset.x, offset.y }, size, options.spacing, options.color)

			if !browser.omnibar.visible {
				bbox	:= raylib.Rectangle{ offset.x, offset.y, measure.x, measure.y }
				mouse	:= raylib.GetMousePosition()
				if raylib.CheckCollisionPointRec(mouse, bbox) {
					raylib.DrawRectangleRec({ bbox.x, bbox.y + bbox.height, bbox.width, 1.0 }, options.color)
					if raylib.IsMouseButtonPressed(.LEFT) do navigate(browser, entry.location)
				}
			}

			strings.builder_reset(&builder)
			offset.y += measure.y + measure.y * 0.4
		}
	}
}
