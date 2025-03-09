package gemreq

import "core:fmt"
import "core:log"
import "core:thread"
import "core:strings"
import "vendor:raylib"

Thread :: thread.Thread

TEXT_FACTOR		:= f64(1.0)
LERP_FACTOR		:= f64(0.3)
SCROLL_FACTOR	:: VIEW_HEIGHT / 3 * 2

WINDOW_PAD_X	:: 32
WINDOW_PAD_Y	:: 16

VIEW_WIDTH		:: 500
VIEW_HEIGHT		:: 600

WINDOW_WIDTH	:: (WINDOW_PAD_X * 2) + VIEW_WIDTH
WINDOW_HEIGHT	:: (WINDOW_PAD_Y * 2) + VIEW_HEIGHT

color_text := raylib.GetColor(0xE8EAEDFF)
color_link := raylib.GetColor(0x4C97FFFF)
color_background := raylib.GetColor(0x101218FF)

Browser :: struct {
	fonts: map[string]Font_Asset,
	debug: bool,
	document: Maybe(Document),
	endpoint: Maybe(Endpoint),
	navigate_queue: Maybe(string),
	scroll: struct {
		current: f64,
		target: f64,
	},
	omnibar: Omnibar,
	threads: struct {
		gemini: Maybe(Thread),
	},
}

launch :: proc(browser: ^Browser) {
	browser.document = nil

	browser.fonts = make(map[string]Font_Asset)
	font_load(browser, FONT_SANS_REGULAR, "font/ttf/DejaVuSans.ttf")
	font_load(browser, FONT_SANS_BOLD, "font/ttf/DejaVuSans-Bold.ttf")

	launch_omnibar(&browser.omnibar)
}

unload :: proc(browser: ^Browser) {
	if thread_gemini, ok := &browser.threads.gemini.(Thread); ok do thread.join(thread_gemini)
	log.debug("threads joined")

	for name, asset in browser.fonts {
		for font in asset do raylib.UnloadFont(font)
		log.debugf("font %s unloaded", name)
	}
	delete(browser.fonts)

	unload_omnibar(&browser.omnibar)
}

update :: proc(browser: ^Browser, dt: f64) {
	browser.omnibar.visible = (browser.omnibar.visible || browser.document == nil)

	key_debug := raylib.IsKeyPressed(.F3)
	if key_debug do browser.debug = !browser.debug
	if url, queue_filled := browser.navigate_queue.(string); queue_filled {
		if strings.contains(url, "://") {
			if strings.has_prefix(url, "gemini://") do navigate(browser, url)
			else {
				url := strings.clone_to_cstring(url)
				defer delete(url)

				raylib.OpenURL(url)
			}
		} else {
			resolve_endpoint(browser, url)
			navigate(browser, browser.endpoint.(Endpoint))
		}
		browser.navigate_queue = nil
	}
	update_omnibar(browser, dt)
	update_document(browser, dt)
}

draw :: proc(browser: ^Browser) {
	using raylib

	ClearBackground(color_background)
	if document, exists := browser.document.(Document); exists {
		draw_document(browser, document)
	}
	if browser.omnibar.visible {
		draw_omnibar(browser)
	}
	if browser.debug {
		text := fmt.ctprintf("FPS: %d", GetFPS())
		measure := MeasureText(text, 24)
		DrawText(text, WINDOW_WIDTH - measure - WINDOW_PAD_X, WINDOW_HEIGHT - 24 - WINDOW_PAD_Y, 24, WHITE)
	}
}

main :: proc() {
	using raylib

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	SetTraceLogLevel(.WARNING)
	SetTargetFPS(120)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })

	InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Gemreq: Gemini browser")
	log.infof("window created %dx%d", WINDOW_WIDTH, WINDOW_HEIGHT)
	defer {
		log.info("browser loop completed")
		CloseWindow()
	}

	SetExitKey(.KEY_NULL)

	browser: Browser
	launch(&browser)
	defer unload(&browser)

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
}
