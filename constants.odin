package gemini

import "core:math"
import "vendor:raylib"

SCALE : f32 : 1.4

PADDING			:= math.floor(24 * SCALE)

WIDTH_CHAR		:= math.floor( 9 * SCALE)
WIDTH_TEXT		:= math.floor(70 * WIDTH_CHAR * SCALE)

HEIGHT_CHAR 	:= math.floor(18 * SCALE)
HEIGHT_VIEW		:= math.floor(50 * HEIGHT_CHAR * SCALE)

WIDTH			:= math.floor(SCALE * PADDING + WIDTH_TEXT + PADDING)
HEIGHT			:= math.floor(SCALE * PADDING + HEIGHT_VIEW + PADDING)

HEIGHT_DIVIDER	:= math.floor(SCALE * PADDING * 1.2)

CHAR_SPACING			:= math.floor(SCALE * 1)
CHAR_FACTOR_PARAGRAPH	:= math.floor(SCALE * 1)
CHAR_FACTOR_HEADING		:= math.floor(SCALE * 2)

COLOR_BG	:= raylib.GetColor(0xFFFFFFFF)
COLOR_TEXT	:= raylib.GetColor(0x444444FF)
COLOR_LINK	:= raylib.GetColor(0x578E7EFF)
