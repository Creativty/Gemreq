package gemreq

import "core:math"
import "vendor:raylib"

SCALE					: f32 : 1.0

PADDING					:= math.floor(24  * SCALE)
                		                  
WIDTH_CHAR				:= math.floor( 9  * SCALE)
WIDTH_TEXT				:= math.floor(70  * WIDTH_CHAR * SCALE)
                		                  
HEIGHT_CHAR 			:= math.floor(18  * SCALE)
HEIGHT_VIEW				:= math.floor(50  * HEIGHT_CHAR * SCALE)
                		
WIDTH					:= math.floor(PADDING + WIDTH_TEXT + PADDING)
HEIGHT					:= math.floor(PADDING + HEIGHT_VIEW + PADDING)
                		
HEIGHT_DIVIDER			:= math.floor(1.2 * PADDING)

CHAR_SPACING			:= f32(1.00 * SCALE)
CHAR_FACTOR_PARAGRAPH	:= f32(1.00 * SCALE)

CHAR_FACTOR_HEADING		:= f32(3.00 * SCALE)
CHAR_FACTOR_HEADING_1	:= f32(1.00 * CHAR_FACTOR_HEADING)
CHAR_FACTOR_HEADING_2	:= f32(0.75 * CHAR_FACTOR_HEADING)
CHAR_FACTOR_HEADING_3	:= f32(0.50 * CHAR_FACTOR_HEADING)

SCROLL_TAUX				:= f32(0.3)
SCROLL_SPEED			:= math.floor(100 * SCALE)

COLOR_BG				:= raylib.GetColor(0xFFFFFFFF)
COLOR_TEXT				:= raylib.GetColor(0x444444FF)
COLOR_LINK				:= raylib.GetColor(0x578E7EFF)
COLOR_DANGER			:= raylib.GetColor(0x8E5762FF)
