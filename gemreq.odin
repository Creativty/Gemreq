package gemreq

import "core:fmt"
import "core:log"
import "core:thread"
import "core:sync/chan"
import "core:strings"
import "vendor:raylib"

Thread :: thread.Thread
Channel_Request :: chan.Chan(Endpoint)
Channel_Document :: chan.Chan(Result_Document)

Result_Document :: union {
	Gemini_Error,
	Document,
}

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
	network_thread: ^Thread,
	channels: struct {
		request: Channel_Request,
		document: Channel_Document,
	},
	omnibar: Omnibar,
}

launch :: proc(browser: ^Browser) {
	browser.document = nil

	browser.fonts = make(map[string]Font_Asset)
	font_load(browser, FONT_SANS_REGULAR, "font/NotoSans-Regular.ttf")
	font_load(browser, FONT_SANS_BOLD, "font/NotoSans-Bold.ttf")

	launch_omnibar(&browser.omnibar)
}

unload :: proc(browser: ^Browser) {
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
		endpoint, endpoint_external := resolve_endpoint(browser, url)
		if endpoint_external {
			log.debugf("external url %s", url)
			url_cstring := strings.clone_to_cstring(url, context.temp_allocator)
			raylib.OpenURL(url_cstring)
		} else {
			navigate(browser, endpoint)
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

	if channel, err := chan.create_unbuffered(Channel_Request, context.allocator); err == nil do browser.channels.request = channel
	else do log.panicf("failure: could not create channel for `request` because of %v", err)
	log.debugf("channel `request` created")
	defer chan.destroy(browser.channels.request)

	if channel, err := chan.create_unbuffered(Channel_Document, context.allocator); err == nil do browser.channels.document = channel
	else do log.panicf("failure: could not create channel for `document` because of %v", err)
	log.debugf("channel `document` created")
	defer chan.destroy(browser.channels.document)

	main_network :: proc(data: rawptr) {
		browser := cast(^Browser)data
		channel_in := &browser.channels.request
		for !chan.is_closed(channel_in) {
			endpoint, endpoint_present := chan.try_recv(channel_in^)
			if !endpoint_present do continue

			browser.omnibar.disabled = true
			browser.omnibar.disabled_timestamp = raylib.GetTime()
			defer browser.omnibar.disabled = false

			// Fetch document bytes
			resp, resp_err := request_document(endpoint)
			if resp_err != nil {
				browser.omnibar.error = fmt.caprintf("%#v", resp_err)
				continue
			} else if str, exists := browser.omnibar.error.(cstring); exists {
				delete(str)
				browser.omnibar.error = nil
			}

			browser.endpoint = endpoint

			document := parse_document(browser, resp)
			if document_old, document_exists := browser.document.(Document); document_exists {
				browser.scroll.target = 0
				browser.scroll.current = 0
				delete_document(document_old)
			}

			browser.document = document
			browser.omnibar.visible = false
		}
	}
	 
	browser.network_thread = thread.create_and_start_with_data(&browser, main_network, init_context = context)
	defer {
		chan.close(&browser.channels.request)
		chan.close(&browser.channels.document)
		thread.join(browser.network_thread)
		thread.destroy(browser.network_thread)
	}

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
