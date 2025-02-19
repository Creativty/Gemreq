package gemini

import "core:os"
import "core:fmt"
import "core:strings"
import "vendor:raylib"

PADDING			:: 24
WIDTH_CHAR		:: 9
WIDTH_TEXT		:: WIDTH_CHAR * 70
WIDTH			:: PADDING + WIDTH_TEXT + PADDING
HEIGHT_CHAR 	:: 18
HEIGHT_VIEW		:: HEIGHT_CHAR * 50
HEIGHT			:: PADDING + HEIGHT_VIEW + PADDING

HEIGHT_DIVIDER	:: PADDING * 1.2

CHAR_SPACING			:: 1
CHAR_FACTOR_PARAGRAPH	:: 1
CHAR_FACTOR_HEADING		:: 2

COLOR_BG	:= raylib.GetColor(0xFFFFFFFF)
COLOR_TEXT	:= raylib.GetColor(0x444444FF)
COLOR_LINK	:= raylib.GetColor(0x578E7EFF)

Font_Weight :: enum {
	Thin,
    Extra_Light,
    Light,
    Normal,
    Medium,
    Semi_Bold,
    Bold,
    Extra_Bold,
    Black,
}

Font_Size :: enum {
	Paragraph,
	Heading,
}

Font_Group :: [Font_Weight][Font_Size]raylib.Font

text_wrap :: proc(text: string, target_width: f32, allocator := context.allocator) -> (lines: [dynamic]string) {
	lines = make([dynamic]string, allocator = allocator)
	return
}

main :: proc() {
	hostname := "geminiprotocol.net"
	hostname_c := strings.clone_to_cstring(hostname)
	defer delete(hostname_c)

	doc_bytes, err := gemini_fetch(hostname)
	if err != nil {
	 	fmt.eprintfln("gemini: error %v", err)
	 	os.exit(1)
	}
	defer delete(doc_bytes)

	doc, err_doc := gemini_parse(doc_bytes)
	if err_doc != nil {
	 	fmt.eprintfln("gemini: error %v", err)
	 	os.exit(1)
	}
	defer gemini_delete(doc)

	fmt.printfln("%#v", doc)
	if doc.status != .Success || len(doc.elements) == 0 do return

	// Initialize raylib
	using raylib
	SetTraceLogLevel(.WARNING)
	SetTargetFPS(60)
	SetConfigFlags({ .MSAA_4X_HINT, .BORDERLESS_WINDOWED_MODE, .INTERLACED_HINT })

	// Startup window
	scroll_y := 0
	InitWindow(WIDTH, HEIGHT, hostname_c)

	// Load fonts
	fonts_deja_vu: Font_Group
	fonts_deja_vu[.Normal][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", HEIGHT_CHAR, nil, -1)
	defer UnloadFont(fonts_deja_vu[.Normal][.Paragraph])
	fonts_deja_vu[.Bold][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", HEIGHT_CHAR, nil, -1)
	defer UnloadFont(fonts_deja_vu[.Bold][.Paragraph])
	fonts_deja_vu[.Bold][.Heading] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", HEIGHT_CHAR * CHAR_FACTOR_HEADING, nil, -1)
	defer UnloadFont(fonts_deja_vu[.Bold][.Heading])

	for !WindowShouldClose() {
		BeginDrawing()
		defer EndDrawing()

		ClearBackground(COLOR_BG)
		render_offset := f32(0)
		for element_untyped in doc.elements {
			if render_offset >= HEIGHT do break
			switch element in element_untyped {
			case Gemini_Element_Text:
				font := fonts_deja_vu[.Bold if element.heading > 0 else .Normal][.Heading if element.heading > 0 else .Paragraph]
				size := f32(HEIGHT_CHAR * (CHAR_FACTOR_HEADING if element.heading > 0 else CHAR_FACTOR_PARAGRAPH))
				text := strings.clone_to_cstring(element.text)
				defer delete(text)

				measure := MeasureTextEx(font, text, size, CHAR_SPACING)

				if element.heading == 1 {
					DrawTextPro(font, text, { WIDTH / 2, PADDING + render_offset }, { measure.x / 2, 0 }, 0.0, size, CHAR_SPACING, COLOR_TEXT)
				} else {
					DrawTextEx(font, text, { PADDING, PADDING + render_offset }, size, CHAR_SPACING, COLOR_TEXT)
				}
				render_offset += measure.y + HEIGHT_DIVIDER
			case Gemini_Element_Link:
				size := f32(HEIGHT_CHAR * CHAR_FACTOR_PARAGRAPH)
				font := fonts_deja_vu[.Bold][.Paragraph]
				text := strings.clone_to_cstring(element.text)
				defer delete(text)

				measure := MeasureTextEx(font, text, size, CHAR_SPACING)

				DrawTextEx(font, text, { PADDING, PADDING + render_offset }, size, CHAR_SPACING, COLOR_LINK)
				render_offset += measure.y
				DrawLine(PADDING, i32(PADDING + render_offset), i32(PADDING + measure.x), i32(PADDING + render_offset), COLOR_LINK)
				render_offset += HEIGHT_DIVIDER
			}
		}
	}
}
