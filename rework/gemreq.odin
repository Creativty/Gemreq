package gemreq

import "core:fmt"
import "core:thread"
import "core:strings"
import "vendor:raylib"

Thread :: thread.Thread

LERP_FACTOR		:: 0.3

WINDOW_PAD_X	:: 32
WINDOW_PAD_Y	:: 16

VIEW_WIDTH		:: 500
VIEW_HEIGHT		:: 640

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
	font_load(browser, FONT_SANS_REGULAR, "../font/ttf/DejaVuSans.ttf")
	font_load(browser, FONT_SANS_BOLD, "../font/ttf/DejaVuSans-Bold.ttf")

	launch_omnibar(&browser.omnibar)
}

unload :: proc(browser: ^Browser) {
	if thread_gemini, ok := &browser.threads.gemini.(Thread); ok do thread.join(thread_gemini)

	for _, asset in browser.fonts {
		for font in asset do raylib.UnloadFont(font)
	}

	unload_omnibar(&browser.omnibar)
	delete(browser.fonts)
}

navigate_click :: proc(browser: ^Browser, url: string) {
	browser.navigate_queue = url
}

navigate_string :: proc(browser: ^Browser, url: string) {
	// TODO(XENOBAS): move this into its own thread
	omnibar := &browser.omnibar

	omnibar.disabled = true
	defer omnibar.disabled = false

	if error_string, error_present := omnibar.error.(cstring); error_present {
		delete(error_string)
		omnibar.error = nil
	}

	if ep_old, ep_old_present := browser.endpoint.(Endpoint); ep_old_present {
		delete_endpoint(ep_old)
	}
	ep := parse_endpoint(url)
	browser.endpoint = ep

	resp, err := request_document(ep)
	if err != nil {
		omnibar.error = fmt.caprintf("%v", err)
		return
	}
	
	document := parse_document(browser, resp)

	if doc_old, doc_exists := browser.document.(Document); doc_exists {
		browser.scroll.target = 0
		browser.scroll.current = 0
		delete_document(doc_old)
	}
	browser.document = document
	omnibar.visible = false
}

navigate_endpoint :: proc(browser: ^Browser, ep: Endpoint, edit_history := false) {
	omnibar := &browser.omnibar

	omnibar.disabled = true
	defer omnibar.disabled = false

	if error_string, error_present := omnibar.error.(cstring); error_present {
		delete(error_string)
		omnibar.error = nil
	}

	if edit_history {
		if ep_old, ep_old_present := browser.endpoint.(Endpoint); ep_old_present {
			delete_endpoint(ep_old)
		}
		browser.endpoint = ep
	}

	resp, err := request_document(ep)
	if err != nil {
		omnibar.error = fmt.caprintf("%v", err)
		return
	}
	
	document := parse_document(browser, resp)

	if doc_old, doc_exists := browser.document.(Document); doc_exists {
		browser.scroll.target = 0
		browser.scroll.current = 0
		delete_document(doc_old)
	}
	browser.document = document
	omnibar.visible = false
}

navigate :: proc {
	navigate_string,
	navigate_endpoint,
}

resolve_endpoint :: proc(browser: ^Browser, url: string)
{
	url := url
	endpoint := &browser.endpoint.(Endpoint)

	if strings.has_prefix(url, "+") do url = url[1:]

	if strings.has_prefix(url, "/") {
		for part in endpoint.path do delete(part)
		clear(&endpoint.path)
	}

	if len(endpoint.path) > 0 && strings.has_suffix(endpoint.path[len(endpoint.path) - 1], ".gmi") {
		delete(pop(&endpoint.path))
	}

	parts := strings.split(url, "/")
	defer delete(parts)
	for part in parts do append(&endpoint.path, strings.clone(part))
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

	SetTraceLogLevel(.WARNING)
	SetTargetFPS(60)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })

	InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Gemreq: Gemini browser")
	defer CloseWindow()

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
	}
}
