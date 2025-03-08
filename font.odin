package gemreq

import "core:log"
import "vendor:raylib"

FONT_SANS_BOLD		:: "sans_bold"
FONT_SANS_REGULAR	:: "sans_regular"

Font_Size :: enum {
	Extra_Small,
	Small,
	Regular,
	Large,
	Extra_Large,
}

Font_Asset :: [Font_Size]raylib.Font

font_size_int :: proc(size: Font_Size) -> i32 {
	switch (size) {
	case .Extra_Small:
		return 8
	case .Small:
		return 12
	case .Regular:
		return 16
	case .Large:
		return 20
	case .Extra_Large:
		return 24
	case:
		return 16
	}
}

font_size_float :: proc(size: Font_Size) -> f32 {
	return cast(f32)font_size_int(size)
}

font_load :: proc(browser: ^Browser, name: string, path: cstring) {
	asset: Font_Asset

	for _, size in asset {
		using raylib
		asset[size] = LoadFontEx(path, font_size_int(size), nil, -1)
	}
	browser.fonts[name] = asset
	log.debugf("font %s \"%s\" loaded", name, path)
}
