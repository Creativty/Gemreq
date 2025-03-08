package gemreq

import "core:c"
import "vendor:raylib"

Rectangle :: raylib.Rectangle

scale :: proc(rect: Rectangle, scale: c.float) -> Rectangle {
	rect_scaled: Rectangle

	rect_scaled.width = rect.width * scale
	rect_scaled.height = rect.height * scale
	rect_scaled.x = rect.x - (rect_scaled.width - rect.width) / 2
	rect_scaled.y = rect.y - (rect_scaled.height - rect.height) / 2
	return rect_scaled
}

pad :: proc(rect: Rectangle, padding: [2]c.float) -> Rectangle {
	rect_padded: Rectangle

	rect_padded.x		= rect.x - padding.x
	rect_padded.y		= rect.y - padding.y
	rect_padded.width	= rect.width + padding.x * 2
	rect_padded.height	= rect.height + padding.y * 2
	return rect_padded
}
