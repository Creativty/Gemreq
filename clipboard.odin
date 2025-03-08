package gemreq

import "core:c"
import "core:fmt"
import "core:strings"
import "vendor:x11/xlib"

clipboard_get :: proc() -> (clipboard: string, ok: bool) {
	display := xlib.OpenDisplay(nil)
	if display == nil do return clipboard, false

	X11_SELECTION_RAW	:: "CLIPBOARD"
	selection := xlib.InternAtom(display, X11_SELECTION_RAW, false)
	selection_owner := xlib.GetSelectionOwner(display, selection)
	if selection_owner == xlib.None do return clipboard, false

	screen := xlib.DefaultScreen(display)
	window_root		:= xlib.RootWindow(display, screen)

	DUMMY_SELECTION :: "CLIPBOARD_HOLDER"

	window_dummy	:= xlib.CreateSimpleWindow(display, window_root, -10, -10, 1, 1, 0, 0, 0)
	property_dummy	:= xlib.InternAtom(display, DUMMY_SELECTION, false)

	X11_SELECTION_UTF8	:: "UTF8_STRING"
	atom_utf8 := xlib.InternAtom(display, X11_SELECTION_UTF8, false)

    xlib.ConvertSelection(display, selection, atom_utf8, property_dummy, window_dummy, 0);

	// TODO(XENOBAS): Implement timeout
	for {
		event: xlib.XEvent
		xlib.NextEvent(display, &event)
		if event.type == xlib.EventType.SelectionNotify {
			selection_event := event.xselection
			if selection_event.property == xlib.None do return clipboard, false

			{
				type, data: xlib.Atom
				format: c.int
				nitems, bytes_after: uint
				property: rawptr

				xlib.GetWindowProperty(display, window_dummy, property_dummy, 0, 0, false, xlib.AnyPropertyType, &type, &format, &nitems, &bytes_after, &property)
				xlib.Free(property)

				X11_INCREMENT :: "INCR"
				incr := xlib.InternAtom(display, X11_INCREMENT, false);
				if type == incr {
					fmt.println("clipboard: data too large: unimplemented INCR X11 mechanism.")
					return clipboard, false
				}

				xlib.GetWindowProperty(display, window_dummy, property_dummy, 0, int(bytes_after), false, xlib.AnyPropertyType, &data, &format, &nitems, &bytes_after, &property);
				clipboard = strings.clone_from_cstring(cstring(property))
				xlib.Free(property)

				xlib.DeleteProperty(display, window_dummy, property_dummy);

				return clipboard, true
			}
		}
	}
}
