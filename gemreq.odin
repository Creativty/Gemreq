package gemreq

import "uri"
import "core:c"
import "core:fmt"
import "core:log"
import "core:sync"
import "core:slice"
import "core:thread"
import "core:strconv"
import "core:strings"
import "core:sync/chan"
import "core:path/slashpath"
import "vendor:raylib"

LERP_FACTOR		:= 0.2
SCROLL_FACTOR	:= 0.6

color_text := raylib.GetColor(0xE8EAEDFF)
color_link := raylib.GetColor(0x4C97FFFF)
color_background := raylib.GetColor(0x101218FF)

Browser :: struct {
	fonts: map[string]Font_Asset,
	debug: bool,
	hover: Maybe(string),
	omnibar: Omnibar,
	document: Maybe(Document),
	endpoint: Maybe(Endpoint),
	endpoint_mutex: sync.Mutex,
	navigate_queue: Maybe(string),
	network_thread: ^Thread,
	cursor_shape: raylib.MouseCursor,
	scroll: struct {
		current: f64,
		target: f64,
	},
	channels: struct {
		request: Channel_Request,
		document: Channel_Document,
	},
}

launch :: proc(browser: ^Browser) {
	browser.document = nil
	browser.cursor_shape = .DEFAULT

	browser.fonts = make(map[string]Font_Asset)
	font_load(browser, FONT_SANS_REGULAR, "font/NotoSans-Regular.ttf")
	font_load(browser, FONT_SANS_BOLD, "font/NotoSans-Bold.ttf")

	launch_omnibar(&browser.omnibar)
}

unload :: proc(browser: ^Browser) {
	for name, asset in browser.fonts {
		for font in asset do raylib.UnloadFont(font)
		log.infof("font %s unloaded", name)
	}
	delete(browser.fonts)
	unload_omnibar(&browser.omnibar)
}

update :: proc(browser: ^Browser, dt: f64) {
	must_reload_layout := ui_scaling_update()

	cursor_shape := raylib.MouseCursor.DEFAULT
	if browser.hover != nil do cursor_shape = .POINTING_HAND
	if cursor_shape  != browser.cursor_shape {
		raylib.SetMouseCursor(cursor_shape)
		browser.cursor_shape = cursor_shape
	}

	if text, queued := browser.navigate_queue.(string); queued {
		navigate(browser, text)
		browser.navigate_queue = nil
	}

	update_omnibar(browser, dt)
	update_document(browser, dt, must_reload_layout)

	key_debug := raylib.IsKeyPressed(.F3)
	if key_debug do browser.debug = !browser.debug

	browser.hover = nil
	browser.omnibar.visible = (browser.omnibar.visible || browser.document == nil)
}

draw :: proc(browser: ^Browser) {
	using raylib

	ClearBackground(color_background)
	if document, exists := browser.document.(Document); exists do draw_document(browser, document)
	if browser.omnibar.visible do draw_omnibar(browser)
	if browser.debug {
		ui := ui_scaling_pixels()
		text := fmt.ctprintf("FPS: %d", GetFPS())
		font := browser.fonts[FONT_SANS_REGULAR][.Small]
		measure := MeasureTextEx(font, text, 24.0, 1.0)
		DrawTextEx(font, text, ui.padding / 4, 24.0, 1.0, WHITE)
	}
}

// TODO(XENOBAS): Add a custom border with .WINDOW_UNDECORATED with resize and title close functionality
main :: proc() {
	using raylib

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	SetTraceLogLevel(.WARNING)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT, .WINDOW_RESIZABLE })
	SetTargetFPS(120)

	InitWindow(i32(WINDOW_WIDTH), i32(WINDOW_HEIGHT), "Gemreq - Gemini browser")
	log.infof("window created %02.2fx%02.2f", WINDOW_WIDTH, WINDOW_HEIGHT)
	defer {
		log.info("browser loop completed")
		CloseWindow()
	}

	SetExitKey(.KEY_NULL)

	browser: Browser
	launch(&browser)
	defer unload(&browser)

	routine_network_init(&browser)
	defer routine_network_destroy(&browser)

	browser.network_thread = thread.create_and_start_with_poly_data(&browser, routine_network, init_context = context)
	defer routine_network_terminate(&browser)

	for {
		must_close := WindowShouldClose()
		if must_close do break

		dt := cast(f64)GetFrameTime()
		update(&browser, dt)

		BeginDrawing()
			draw(&browser)
		EndDrawing()
		free_all(context.temp_allocator)
	}
	free_all(context.temp_allocator)
}
