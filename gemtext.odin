package gemreq

import "core:strings"

Gemtext_Kind :: enum {
	Empty,
	Text,
	Link,
	Heading_1,
	Heading_2,
	Heading_3,
	List,
	Blockquote,
	Preformatting_Delimiter,
}

Gemtext_Link :: struct {
	text: string,
	url: string,
}

Gemtext_Data :: union {
	string,
	Gemtext_Link,
}

Gemtext :: struct {
	kind: Gemtext_Kind,
	data: Gemtext_Data,
}

// TODO(XENOBAS): Rename this function
gemtext_options :: proc(browser: ^Browser, kind: Gemtext_Kind) -> Text_Options {
	#partial switch kind {
	case .Heading_1, .Heading_2:
		return { FONT_SANS_BOLD, .Extra_Large, 1.2, color_text }
	case .Heading_3:
		return { FONT_SANS_BOLD, .Large, 1.2, color_text }
	case .Link:
		return { FONT_SANS_BOLD, .Regular, 1.0, color_link }
	}
	return { FONT_SANS_REGULAR, .Regular, 1.0, color_text }
}

gemtext_parse :: proc(src: string, preformatted := false) -> Gemtext {
	if !preformatted {
		switch {
		case len(src) == 0:
			return { .Empty, nil }
		case strings.has_prefix(src, ">"):
			return { .Blockquote, strings.trim_space(src[1:]) }
		case strings.has_prefix(src, ">"):
			return { .Blockquote, strings.trim_space(src[1:]) }
		case strings.has_prefix(src, "* "):
			return { .List, strings.trim_space(src[2:]) }
		case strings.has_prefix(src, "```"):
			return { .Preformatting_Delimiter, nil }
		case strings.has_prefix(src, "=>"):
			e: Gemtext
			r := reader_make(strings.trim_space(src[2:]))
			// url := reader_read_delimiter(&r, "\t")
			url  := reader_read_delimiter_whitespace(&r)
			text := url
			if !strings.has_prefix(r.buffer[r.index_curr:], "\r\n") {
				text = reader_read_delimiter(&r, "\r\n")
			}

			e.kind = .Link
			e.data = Gemtext_Link{ text, url }

			return e
		case strings.has_prefix(src, "###"):
			return { .Heading_3, strings.trim_space(src[3:]) }
		case strings.has_prefix(src, "##"):
			return { .Heading_2, strings.trim_space(src[2:]) }
		case strings.has_prefix(src, "#"):
			return { .Heading_1, strings.trim_space(src[1:]) }
		}
	}
	if strings.has_prefix(src, "```") {
		return { .Preformatting_Delimiter, nil }
	}
	return { .Text, strings.trim_space(src) }
}

gemtext_get_text :: proc(gemtext: Gemtext) -> string {
	if gemtext.kind == .Link do return gemtext.data.(Gemtext_Link).text
	if gemtext.kind == .Empty || gemtext.kind == .Preformatting_Delimiter do return ""
	return gemtext.data.(string)
}
