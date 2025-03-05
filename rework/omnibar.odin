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
			url := strings.to_string(omnibar.builder)
			if key_control && len(strings.trim_space(url)) > 0 {
				DOMAINS :: []string{ ".com", ".net", ".io", ".dev", "." }
				must_add_domain := true
				for domain in DOMAINS {
					if strings.has_suffix(url, domain) {
						must_add_domain = false
						break
					}
				}
				if must_add_domain do edit.input_text(&omnibar.state, ".net")

				PROTOCOL :: "gemini://"
				must_add_protocol := !strings.has_prefix(url, PROTOCOL)
				if must_add_protocol do edit.insert(&omnibar.state, 0, PROTOCOL)
			}
			omnibar.disabled = true
		} else {
			key_left := raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT)
			key_right := raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT)
			key_delete := raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE)

			if key_left		do edit.move_to(&omnibar.state, .Word_Left if key_control else .Left)
			if key_right	do edit.move_to(&omnibar.state, .Word_Right if key_control else .Right)
			if key_delete	do edit.delete_to(&omnibar.state, .Word_Left if key_control else .Left)
		}
		omnibar.caret = cast(f32)math.lerp(cast(f64)omnibar.caret, cast(f64)omnibar.state.selection.x, 0.3)
	}
}

import "core:fmt"

draw_omnibar :: proc(browser: ^Browser) {
	using raylib

	omnibar := &browser.omnibar

	input_height := f32(48)
	input_frame := Rectangle{ WINDOW_PAD_X, WINDOW_PAD_Y, VIEW_WIDTH, input_height }
	DrawRectangleRounded(input_frame, 0.6, 16, GetColor(0xe6e6e6ff) if omnibar.disabled else WHITE)
	DrawRectangleRoundedLinesEx(pad(input_frame, { 1.5, 1.5 }), 0.6, 16, 2.0, GRAY)

	text := strings.to_cstring(&omnibar.builder)
	spacing := f32(1.2)
	font_size := Font_Size.Large
	font_size_i32 := cast(f32)font_size_int(font_size)

	font := browser.fonts[FONT_SANS_BOLD][font_size]
	text_measure := MeasureTextEx(font, text, font_size_i32, spacing)

	text_area := pad(input_frame, [2]f32{ 1, 1 } * (text_measure.y - input_height) / 2)
	DrawTextEx(font, text, { text_area.x, text_area.y }, font_size_i32, spacing, GetColor(0x5f5f5aff if omnibar.disabled else 0x292929FF))

	if !omnibar.disabled {
		text_slice := strings.to_string(omnibar.builder)[:omnibar.state.selection.x]
		text := strings.clone_to_cstring(text_slice)
		defer delete(text)

		text_measure := MeasureTextEx(font, text, font_size_i32, spacing)
		DrawRectangle(cast(i32)(text_area.x + text_measure.x * (omnibar.caret / cast(f32)omnibar.state.selection.x) + 0.8), cast(i32)text_area.y, 1, cast(i32)text_measure.y, GetColor(0x292929ff))
	}
}
