package gemreq

import "uri"
import "core:fmt"
import "core:log"
import "core:sync/chan"

navigate_enqueue :: proc(browser: ^Browser, url: string) {
	browser.navigate_queue = url
}

navigate_uri :: proc(browser: ^Browser, location: uri.URI) {
	channel := browser.channels.request
	destination, ok := resolve_uri(browser, location)
	if ok {
		if !chan.send(channel, destination) {
			log.errorf("could not send location `%v`", destination)
		}
	} else do log.errorf("could not resolve `%v`", location)
}

navigate_string :: proc(browser: ^Browser, text: string) {
	location, ok := uri.parse(text)
	defer uri.destroy(location)

	if ok {
		navigate_uri(browser, location)
	} else do log.errorf("could not parse `%v`", text)
}

navigate :: proc {
	navigate_uri,
	navigate_string,
}
