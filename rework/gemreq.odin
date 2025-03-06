package gemreq

import "core:fmt"
import "core:thread"
import "core:strings"
import "vendor:raylib"

Thread :: thread.Thread

WINDOW_PAD_X	:: 32
WINDOW_PAD_Y	:: 16

VIEW_WIDTH		:: 500
VIEW_HEIGHT		:: 500

WINDOW_WIDTH	:: (WINDOW_PAD_X * 2) + VIEW_WIDTH
WINDOW_HEIGHT	:: (WINDOW_PAD_Y * 2) + VIEW_HEIGHT

Browser :: struct {
	fonts: map[string]Font_Asset,
	document: Maybe(Document),
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

navigate :: proc(browser: ^Browser, url: string) {
	// TODO(XENOBAS): move this into its own thread
	omnibar := &browser.omnibar

	omnibar.disabled = true
	defer omnibar.disabled = false

	if error_string, has_error := omnibar.error.(cstring); has_error {
		delete(error_string)
		omnibar.error = nil
	}

	ep := parse_endpoint(url)
	defer delete_endpoint(ep)

	resp, err := gemini_request(ep)
	if err != nil {
		omnibar.error = fmt.caprintf("%v", err)
		return
	}
	
	document := gemini_parse(resp)
	fmt.printfln("%#v", document)
}

update :: proc(browser: ^Browser, dt: f64) {
	browser.omnibar.visible = (browser.omnibar.visible || browser.document == nil)

	update_omnibar(browser, dt)
	// else do update_document(browser, browser.document.(Document))
}

draw :: proc(browser: ^Browser) {
	using raylib

	if browser.omnibar.visible {
		DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, GetColor(0x0000002f))
		draw_omnibar(browser)
		return
	} else do draw_document(browser, browser.document.(Document))
}

draw_document :: proc(browser: ^Browser, document: Document) {
}

main :: proc() {
	using raylib

	SetTraceLogLevel(.WARNING)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })
	SetTargetFPS(60)

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
			ClearBackground(WHITE)
			draw(&browser)
		EndDrawing()
	}
}
