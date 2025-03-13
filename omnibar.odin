package gemreq

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import "core:text/edit"
import "vendor:raylib"

Text_Edit_State :: edit.State

Omnibar :: struct {
	state: Text_Edit_State,
	builder: strings.Builder,

	error: Maybe(cstring),
	visible: bool,
	disabled: bool,
	disabled_timestamp: f64,

	caret: f32,
	caret_time: f64,
}

launch_omnibar :: proc(omnibar: ^Omnibar) {
	edit.init(&omnibar.state, context.allocator, context.allocator)
	strings.builder_init(&omnibar.builder)

	edit.begin(&omnibar.state, 1, &omnibar.builder)

	omnibar.visible = true
	omnibar.disabled = false

	edit.input_text(&omnibar.state, "gemini://geminiprotocol.net")

	omnibar.caret = cast(f32)omnibar.state.selection.x
	log.debug("omnibar initialised")
}

unload_omnibar :: proc(omnibar: ^Omnibar) {
	omnibar.visible = false
	omnibar.disabled = false

	edit.end(&omnibar.state)
	edit.destroy(&omnibar.state)

	strings.builder_destroy(&omnibar.builder)
	log.debug("omnibar unloaded")
}

update_omnibar :: proc(browser: ^Browser, dt: f64) {
	omnibar := &browser.omnibar
	if !omnibar.disabled {
		key_alt := raylib.IsKeyDown(.LEFT_ALT) || raylib.IsKeyDown(.RIGHT_ALT)
		key_control := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
		for {
			if key_control || key_alt do break
			char := raylib.GetCharPressed()
			if char == rune(0) do break

			text := strings.to_string(omnibar.builder)
			if char != rune(0) && len(text) <= 60 do edit.input_rune(&omnibar.state, char)
		}

		key_goto := raylib.IsKeyPressed(.ENTER)
		if key_goto {
			url_pre_process := strings.trim_space(strings.to_string(omnibar.builder))
			if key_control && len(url_pre_process) > 0 {
				PROTOCOL	:: "gemini://"
				DOMAINS		:: []string{ ".com", ".net", ".io", ".dev", "." }

				must_add_protocol := !strings.has_prefix(url_pre_process, PROTOCOL)
				if must_add_protocol do edit.insert(&omnibar.state, 0, PROTOCOL)

				must_add_domain := true
				for domain in DOMAINS {
					if strings.has_suffix(url_pre_process, domain) {
						must_add_domain = false
						break
					}
				}
				if must_add_domain do edit.input_text(&omnibar.state, ".net")
			}

			url_post_process := strings.trim_space(strings.to_string(omnibar.builder))
			navigate(browser, url_post_process)
		} else {
			key_left := raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT)
			key_right := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT)
			key_delete := raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE)
			key_paste := raylib.IsKeyPressed(.V) && key_control

			if key_left		do edit.move_to(&omnibar.state, .Word_Left if key_control else .Left)
			if key_right	do edit.move_to(&omnibar.state, .Word_Right if key_control else .Right)
			if key_delete	do edit.delete_to(&omnibar.state, .Word_Left if key_control else .Left)
			if key_paste {
				text, ok := clipboard_get()
				defer delete(text)

				if ok {
					edit.input_text(&omnibar.state, text)
				} else do fmt.eprintln("gemreq: error: could not read from clipboard.")
			}
			if key_left || key_right || key_delete || key_paste {
				omnibar.caret_time = raylib.GetTime()
			}
		}

		key_omnibar := key_control && raylib.IsKeyPressed(.L)
		if key_omnibar {
			omnibar.visible = !omnibar.visible || browser.document == nil
			omnibar.caret_time = raylib.GetTime()
		}

		omnibar.caret = cast(f32)math.lerp(cast(f64)omnibar.caret, cast(f64)omnibar.state.selection.x, LERP_FACTOR)
	}
}

draw_omnibar :: proc(browser: ^Browser) {
	using raylib

	ui := ui_scaling_pixels()
	omnibar := &browser.omnibar

	// Background
	DrawRectangleRec({ 0, 0, ui.window.x, ui.window.y }, ColorAlpha(color_background, 0.333))

	font_size := Font_Size.Regular
	font_size_f32 := font_size_float(font_size)

	// Frame
	input_pad := [2]f32{ font_size_f32 * 2.0, font_size_f32 } / 2.0
	input_height := font_size_f32 + input_pad.y * 2
	input_frame := Rectangle{ ui.padding.x, ui.padding.y, ui.view.x, input_height }
	DrawRectangleRec(input_frame, GetColor(0xE6E6E6FF) if omnibar.disabled else WHITE)
	DrawRectangleLinesEx(input_frame, 2.0, GetColor(0xE6E6FFFF) if omnibar.disabled else GetColor(0xE6D6FFFF))

	// Text
	text := strings.to_cstring(&omnibar.builder)
	spacing := f32(1.2)

	font := browser.fonts[FONT_SANS_BOLD][font_size]
	text_measure := MeasureTextEx(font, text, font_size_f32, spacing)

	text_area := pad(input_frame, [2]f32{ 1.0, (text_measure.y - input_height) / 2 })
	text_area.x += font_size_f32
	DrawTextEx(font, text, { text_area.x, text_area.y }, font_size_f32, spacing, GetColor(0x5f5f5aff if omnibar.disabled else 0x292929FF))

	// Error
	if error_text, error_present := omnibar.error.(cstring); error_present {
		error_size := Font_Size.Small
		error_font := browser.fonts[FONT_SANS_BOLD][error_size]
		error_spacing := f32(16)
		error_size_f32 := font_size_float(error_size)
		error_position := [2]f32{ f32(WINDOW_PAD_X), input_frame.y + input_frame.height + error_spacing }
		DrawTextEx(error_font, error_text, error_position, error_size_f32, 1.0, GetColor(0xFF0033FF))
	}

	// Caret
	if !omnibar.disabled {
		time := GetTime() - omnibar.caret_time
		color := ColorAlpha(GetColor(0x292929ff), cast(f32)math.cos(time * 5))
		text_slice := strings.to_string(omnibar.builder)[:omnibar.state.selection.x]
		text := strings.clone_to_cstring(text_slice)
		defer delete(text)

		text_measure := MeasureTextEx(font, text, font_size_f32, spacing)
		DrawRectangle(cast(i32)(text_area.x + text_measure.x * (omnibar.caret / cast(f32)omnibar.state.selection.x)), cast(i32)text_area.y, 2, cast(i32)text_measure.y, color)
	}
}
