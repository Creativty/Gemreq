package gemreq

import "core:fmt"
import "core:thread"
import "core:strings"
import "vendor:raylib"

Thread :: thread.Thread

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

	if error_string, error_present := omnibar.error.(cstring); error_present {
		delete(error_string)
		omnibar.error = nil
	}

	ep := parse_endpoint(url)
	defer delete_endpoint(ep)

	resp, err := request_document(ep)
	if err != nil {
		omnibar.error = fmt.caprintf("%v", err)
		return
	}
	
	document := parse_document(browser, resp)

	if doc_old, doc_exists := browser.document.(Document); doc_exists do delete_document(doc_old)
	browser.document = document
	omnibar.visible = false
}

update :: proc(browser: ^Browser, dt: f64) {
	browser.omnibar.visible = (browser.omnibar.visible || browser.document == nil)

	update_omnibar(browser, dt)
	// else do update_document(browser, browser.document.(Document))
}

draw :: proc(browser: ^Browser) {
	using raylib

	ClearBackground(color_background)
	if document, exists := browser.document.(Document); exists {
		draw_document(browser, document)
	}
	if browser.omnibar.visible {
		DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, GetColor(0x0000002f))
		draw_omnibar(browser)
	}
}

draw_document :: proc(browser: ^Browser, document: Document) {
	if document.status != 20 do return
	offset_y := f32(0)
	config_empty := gemtext_wrap_config(browser, .Empty)
	for node in document.gemtext {
		if node.kind == .Empty || node.kind == .Preformatting_Delimiter {
			offset_y += font_size_float(config_empty.font_size)
			continue
		}

		config := gemtext_wrap_config(browser, node.kind)
		repr := gemtext_get_text(node)
		text := strings.clone_to_cstring(repr, context.temp_allocator)
		size := font_size_float(config.font_size)
		font := browser.fonts[config.font_name][config.font_size]
		measure := raylib.MeasureTextEx(font, text, size, config.spacing)
		offset_y += measure.y
		raylib.DrawTextEx(font, text, { WINDOW_PAD_X, WINDOW_PAD_Y + offset_y }, size, config.spacing, config.color)
		offset_y += font_size_float(config_empty.font_size) * 0.3
		if offset_y > VIEW_HEIGHT do break
	}
	free_all(context.temp_allocator)
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
