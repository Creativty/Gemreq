package gemreq

import "core:os"
import "vendor:raylib"

TEXT_FACTOR			:= 1.2 // TODO(XENOBAS): Fix text scaling.

WINDOW_PAD_X		:= 0.060
WINDOW_PAD_Y		:= 0.045

WINDOW_VIEW_WIDTH	:= 1.0 - (WINDOW_PAD_X * 2.0)
WINDOW_VIEW_HEIGHT	:= 1.0 - (WINDOW_PAD_Y * 2.0)

WINDOW_BASE_WIDTH  := f64(600)
WINDOW_BASE_HEIGHT := f64(600)

WINDOW_PIXELS		:= [2]f64{ WINDOW_BASE_WIDTH, WINDOW_BASE_HEIGHT }
                	
WINDOW_WIDTH		:= (WINDOW_VIEW_WIDTH  + WINDOW_PAD_X * 2.0) * WINDOW_BASE_WIDTH
WINDOW_HEIGHT		:= (WINDOW_VIEW_HEIGHT + WINDOW_PAD_Y * 2.0) * WINDOW_BASE_HEIGHT

UI_Scaling :: struct {
	view: [2]f32,
	window: [2]f32,
	padding: [2]f32,
}

ui_scaling_pixels :: proc() -> (ui: UI_Scaling) {
	ui.view.x = f32(WINDOW_VIEW_WIDTH  * WINDOW_WIDTH)
	ui.view.y = f32(WINDOW_VIEW_HEIGHT * WINDOW_HEIGHT)
	ui.padding.x = f32(WINDOW_PAD_X * WINDOW_WIDTH)
	ui.padding.y = f32(WINDOW_PAD_Y * WINDOW_HEIGHT)
	ui.window.x = f32(WINDOW_WIDTH)
	ui.window.y = f32(WINDOW_HEIGHT)
	return ui
}

// TODO(XENOBAS): Add color palette
// TODO(XENOBAS): Load and save preferences

ui_scaling_update :: proc() -> (must_update_layout: bool) {
	using raylib

	window_pixels_current := [2]f64{ f64(raylib.GetScreenWidth()), f64(raylib.GetScreenHeight()) }
	if window_pixels_current != WINDOW_PIXELS {
		must_update_layout = (window_pixels_current.x != WINDOW_PIXELS.x)
		WINDOW_WIDTH	= (WINDOW_VIEW_WIDTH  + WINDOW_PAD_X * 2.0) * cast(f64)raylib.GetScreenWidth()
		WINDOW_HEIGHT	= (WINDOW_VIEW_HEIGHT + WINDOW_PAD_Y * 2.0) * cast(f64)raylib.GetScreenHeight()
		WINDOW_PIXELS	= window_pixels_current
	}
	return must_update_layout
}
