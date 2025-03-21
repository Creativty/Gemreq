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

Thread :: thread.Thread
Channel_Request :: chan.Chan(Endpoint)
Channel_Document :: chan.Chan(Result_Document)

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

Result_Document :: union {
	Gemini_Error,
	Document,
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

resolve :: proc(browser: ^Browser, location: uri.URI) -> (endpoint: Endpoint, ok: bool) {
	assert(location.opaque == "")
	assert(location.scheme == "" || location.scheme == "gemini")
	sync.mutex_lock(&browser.endpoint_mutex)
	defer sync.mutex_unlock(&browser.endpoint_mutex)

	endpoint.path = make([dynamic]string)
	if ep_ctx, ctx_exists := browser.endpoint.(Endpoint); ctx_exists && location.host == "" {
		endpoint.port = ep_ctx.port
		endpoint.host = strings.clone(ep_ctx.host)

		if !strings.has_prefix(location.path, "/") {
			path_capacity	:= len(ep_ctx.path)
			if len(ep_ctx.path) > 0 && strings.has_suffix(slice.last(ep_ctx.path[:]), ".gmi") do path_capacity -= 1
			path_ctx		:= strings.join(ep_ctx.path[:path_capacity], "/")
			path_rel		:= strings.join({ path_ctx, location.path }, "/")
			path			:= slashpath.clean(path_rel)
			components		:= strings.split(path, "/")
			defer {
				delete(components)
				delete(path_ctx)
				delete(path_rel)
				delete(path)
			}

			for component in components {
				if len(component) == 0 do continue
				append(&endpoint.path, strings.clone(component))
			}
		} else {
			path		:= slashpath.clean(location.path)
			components	:= strings.split(path, "/")
			defer {
				delete(components)
				delete(path)
			}

			for component in components {
				if len(component) == 0 do continue
				append(&endpoint.path, strings.clone(component))
			}
		}
	} else {
		log.assertf(location.host != "", "location %#v", location)
		endpoint.port = 1965
		endpoint.host = strings.clone(location.host)
		if len(location.port) > 0 do endpoint.port = strconv.parse_int(location.port) or_return
		path := slashpath.clean(location.path)
		components := strings.split(path, "/")
		defer {
			delete(path)
			delete(components)
		}
		for component in components {
			if len(component) == 0 do continue
			append(&endpoint.path, strings.clone(component))
		}
	}
	return endpoint, true
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

			if sync.mutex_guard(&browser.endpoint_mutex) do browser.endpoint = endpoint

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
	free_all(context.temp_allocator)
}
