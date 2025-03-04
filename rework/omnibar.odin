package gemreq

import "core:strings"
import "core:text/edit"
import "vendor:raylib"

Text_Edit_State :: edit.State

Omnibar :: struct {
	visible: bool,
	disabled: bool,
	state: Text_Edit_State,
	builder: strings.Builder,
}

launch_omnibar :: proc(omnibar: ^Omnibar) {
	edit.init(&omnibar.state, context.allocator, context.allocator)
	strings.builder_init(&omnibar.builder)

	edit.begin(&omnibar.state, 1, &omnibar.builder)

	omnibar.visible = true
	omnibar.disabled = false
	edit.input_text(&omnibar.state, "gemini://geminiprotocol.net")
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
		if raylib.IsKeyPressed(.BACKSPACE) || raylib.IsKeyPressedRepeat(.BACKSPACE) do edit.delete_to(&omnibar.state, .Left)
		if raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressedRepeat(.LEFT) do edit.move_to(&omnibar.state, .Left)
		if raylib.IsKeyPressed(.RIGHT) || raylib.IsKeyPressedRepeat(.RIGHT) do edit.move_to(&omnibar.state, .Right)
		if raylib.IsKeyPressed(.ENTER) {
			// Start thread for network request
			omnibar.disabled = true
		}
	}
}

import "core:fmt"

draw_omnibar :: proc(browser: ^Browser) {
	using raylib

	draw_input :: proc(browser: ^Browser) {
		omnibar := &browser.omnibar

		input_height := f32(32)
		input_frame := Rectangle{ WINDOW_PAD_X, WINDOW_PAD_Y, VIEW_WIDTH, input_height }
		DrawRectangleRounded(input_frame, 0.6, 16, GetColor(0xe6e6e6ff) if omnibar.disabled else WHITE)
		DrawRectangleRoundedLinesEx(pad(input_frame, { 1.5, 1.5 }), 0.6, 16, 2.0, GRAY)

		text := strings.to_cstring(&omnibar.builder)
		spacing := f32(1.0)
		font_size := Font_Size.Regular
		font_size_i32 := cast(f32)font_size_int(font_size)

		font := browser.fonts[FONT_SANS_BOLD][font_size]
		text_measure := MeasureTextEx(font, text, font_size_i32, spacing)

		text_area := pad(input_frame, [2]f32{ (text_measure.y - input_height) / 2, (text_measure.y - input_height) / 2  })
		DrawTextEx(font, text, { text_area.x, text_area.y }, font_size_i32, spacing, GetColor(0x5f5f5aff if omnibar.disabled else 0x292929FF))

		if !omnibar.disabled {
			text_slice := strings.to_string(omnibar.builder)[:omnibar.state.selection.x]
			text := strings.clone_to_cstring(text_slice)
			defer delete(text)

			text_measure := MeasureTextEx(font, text, font_size_i32, spacing)
			DrawRectangle(cast(i32)(text_area.x + text_measure.x), cast(i32)text_area.y, 2, cast(i32)text_measure.y, RED)
		}
	}

	draw_input(browser)

}
