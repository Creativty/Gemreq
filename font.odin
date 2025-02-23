package gemreq

import "vendor:raylib"

Font	:: raylib.Font
Color	:: raylib.Color

Font_Style :: enum {
	Bold,
	Italic,
	Bold_Italic,
	Paragraph,
	Heading_1,
	Heading_2,
	Heading_3,
}

Font_Collection :: [Font_Style]Font

font_style_from_element :: proc(element_generic: Gemini_Element) -> Font_Style {
	switch element in element_generic {
	case Gemini_Element_Link:
		return .Bold_Italic
	case Gemini_Element_Text:
		if element.heading == 1 do return .Heading_1
		if element.heading == 2 do return .Heading_2
		if element.heading == 3 do return .Heading_3
	}
	return .Paragraph
}
