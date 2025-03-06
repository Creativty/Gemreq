package gemreq

import "core:math"
import "core:strings"
import "core:text/edit"
import "vendor:raylib"

Text_Edit_State :: edit.State

Omnibar :: struct {
	visible: bool,
	disabled: bool,
	state: Text_Edit_State,
	builder: strings.Builder,

	caret: f32,
	error: Maybe(cstring),
}

launch_omnibar :: proc(omnibar: ^Omnibar) {
	edit.init(&omnibar.state, context.allocator, context.allocator)
	strings.builder_init(&omnibar.builder)

	edit.begin(&omnibar.state, 1, &omnibar.builder)

	omnibar.visible = true
	omnibar.disabled = false

	edit.input_text(&omnibar.state, "gemini://geminiprotocol.net")
	omnibar.caret = cast(f32)omnibar.state.selection.x / 2
}

unload_omnibar :: proc(omnibar: ^Omnibar) {
	omnibar.visible = false
	omnibar.disabled = false

	edit.end(&omnibar.state)

	edit.destroy(&omnibar.state)
	strings.builder_destroy(&omnibar.builder)
}

update_omnibar :: proc(browser: ^Browser, dt: f64) {
	omnibar := &browser.omnibar
	if !omnibar.visible do return

	if !omnibar.disabled {
		for {
			char := raylib.GetCharPressed()
			if char == rune(0) do break

			text := strings.to_string(omnibar.builder)
			if char != rune(0) && len(text) <= 60 do edit.input_rune(&omnibar.state, char)
		}

		key_goto := raylib.IsKeyPressed(.ENTER)
		key_control := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)

		if key_goto {
			url_pre_process := strings.trim_space(strings.to_string(omnibar.builder))
			if key_control && len(url_pre_process) > 0 {
				PROTOCOL	:: "gemini://"
				DOMAINS		:: []string{ ".com", ".net", ".io", ".dev", "." }

				must_add_domain := true
				for domain in DOMAINS {
					if strings.has_suffix(url_pre_process, domain) {
						must_add_domain = false
						break
					}
				}
				if must_add_domain do edit.input_text(&omnibar.state, ".net")

				must_add_protocol := !strings.has_prefix(url_pre_process, PROTOCOL)
				if must_add_protocol do edit.insert(&omnibar.state, 0, PROTOCOL)
			}

			url_post_process := strings.trim_space(strings.to_string(omnibar.builder))
			navigate(browser, url_post_process)

			return
		} else {
			key_left := raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT)
			key_right := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT)
			key_delete := raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE)
			key_paste := raylib.IsKeyPressed(.V)

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
		}
		omnibar.caret = cast(f32)math.lerp(cast(f64)omnibar.caret, cast(f64)omnibar.state.selection.x, 0.3)
	}
}

import "core:fmt"

draw_omnibar :: proc(browser: ^Browser) {
	using raylib

	omnibar := &browser.omnibar

	// Frame
	input_height := f32(48)
	input_frame := Rectangle{ WINDOW_PAD_X, WINDOW_PAD_Y, VIEW_WIDTH, input_height }
	DrawRectangleRounded(input_frame, 0.6, 16, GetColor(0xe6e6e6ff) if omnibar.disabled else WHITE)
	DrawRectangleRoundedLinesEx(pad(input_frame, { 1.5, 1.5 }), 0.6, 16, 2.0, GRAY)

	// Text
	text := strings.to_cstring(&omnibar.builder)
	spacing := f32(1.2)
	font_size := Font_Size.Large
	font_size_f32 := cast(f32)font_size_int(font_size)

	font := browser.fonts[FONT_SANS_BOLD][font_size]
	text_measure := MeasureTextEx(font, text, font_size_f32, spacing)

	text_area := pad(input_frame, [2]f32{ 1, 1 } * (text_measure.y - input_height) / 2)
	DrawTextEx(font, text, { text_area.x, text_area.y }, font_size_f32, spacing, GetColor(0x5f5f5aff if omnibar.disabled else 0x292929FF))

	// Error
	if error_text, error_present := omnibar.error.(cstring); error_present {
		error_size := Font_Size.Small
		error_font := browser.fonts[FONT_SANS_BOLD][error_size]
		error_spacing := f32(16)
		error_size_f32 := cast(f32)font_size_int(error_size)
		error_position := [2]f32{ WINDOW_PAD_X, input_frame.y + input_frame.height + error_spacing }
		DrawTextEx(error_font, error_text, error_position, error_size_f32, 1.0, GetColor(0xFF0033FF))
	}

	// Caret
	if !omnibar.disabled {
		text_slice := strings.to_string(omnibar.builder)[:omnibar.state.selection.x]
		text := strings.clone_to_cstring(text_slice)
		defer delete(text)

		text_measure := MeasureTextEx(font, text, font_size_f32, spacing)
		DrawRectangle(cast(i32)(text_area.x + text_measure.x * (omnibar.caret / cast(f32)omnibar.state.selection.x) + 0.8), cast(i32)text_area.y, 1, cast(i32)text_measure.y, GetColor(0x292929ff))
	}
}
