package gemreq

import "core:strings"
import "vendor:raylib"

WINDOW_PAD_X	:: 32
WINDOW_PAD_Y	:: 16

VIEW_WIDTH		:: 500
VIEW_HEIGHT		:: 500

WINDOW_WIDTH	:: (WINDOW_PAD_X * 2) + VIEW_WIDTH
WINDOW_HEIGHT	:: (WINDOW_PAD_Y * 2) + VIEW_HEIGHT

Document :: struct {
	status: int,
	location: Maybe(string),
	media_type: Maybe(string),
}

Browser :: struct {
	fonts: map[string]Font_Asset,
	document: Maybe(Document),
	omnibar: Omnibar,
}

launch :: proc(browser: ^Browser) {
	browser.document = nil

	browser.fonts = make(map[string]Font_Asset)
	font_load(browser, FONT_SANS_REGULAR, "../font/ttf/DejaVuSans.ttf")
	font_load(browser, FONT_SANS_BOLD, "../font/ttf/DejaVuSans-Bold.ttf")

	launch_omnibar(&browser.omnibar)
}

unload :: proc(browser: ^Browser) {
	for _, asset in browser.fonts {
		for font in asset do raylib.UnloadFont(font)
	}

	unload_omnibar(&browser.omnibar)
	delete(browser.fonts)
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
