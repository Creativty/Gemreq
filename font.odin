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
		return i32(f64(8) * TEXT_FACTOR)
	case .Small:
		return i32(f64(12) * TEXT_FACTOR)
	case .Regular:
		return i32(f64(16) * TEXT_FACTOR)
	case .Large:
		return i32(f64(20) * TEXT_FACTOR)
	case .Extra_Large:
		return i32(f64(24) * TEXT_FACTOR)
	case:
		return i32(f64(16) * TEXT_FACTOR)
	}
}

font_size_float :: proc(size: Font_Size) -> f32 {
	return cast(f32)font_size_int(size)
}

font_load :: proc(browser: ^Browser, name: string, path: cstring) {
	asset: Font_Asset

	for _, size in asset {
		using raylib
		asset[size] = LoadFontEx(path, font_size_int(size), nil, 4497)
		SetTextureFilter(asset[size].texture, .BILINEAR)
	}
	browser.fonts[name] = asset
	log.debugf("name %s path \"%s\" loaded", name, path)
}
