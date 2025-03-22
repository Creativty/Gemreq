package gemreq

import "uri"
import "core:log"
import "core:sync"
import "core:thread"
import "core:sync/chan"

Thread :: thread.Thread
Channel_Request :: chan.Chan(uri.URI)
Channel_Document :: chan.Chan(Document_Or_Error)
Document_Or_Error :: union {
	Gemini_Error,
	Document,
}

routine_network_init :: proc(browser: ^Browser) {
	// Incoming
	if channel, err := chan.create_buffered(Channel_Request, 8, context.allocator); err == nil {
		browser.channels.request = channel
	} else do log.panicf("could not create channel for requests: %v", err)
	// Outgoing
	if channel, err := chan.create_buffered(Channel_Document, 2, context.allocator); err == nil {
		browser.channels.document = channel
	} else do log.panicf("could not create channel for documents: %v", err)
}

routine_network_destroy :: proc(browser: ^Browser) {
	chan.destroy(browser.channels.request)
	chan.destroy(browser.channels.document)
}

routine_network_terminate :: proc(browser: ^Browser) {
	chan.close(&browser.channels.request)
	chan.close(&browser.channels.document)
	thread.join(browser.network_thread)
	thread.destroy(browser.network_thread)
}

routine_network :: proc(browser: ^Browser) {
	chan_in := &browser.channels.request
	for !chan.is_closed(chan_in) {
		in_location, received := chan.try_recv(chan_in^)
		if !received do continue

		location := uri.clone(in_location)
		uri.destroy(in_location)

		disable_omnibar(&browser.omnibar)
		defer activate_omnibar(&browser.omnibar)

		bytes, err := request_document_uri(location)
		if err != nil {
			log.errorf("navigation to `%#v` failed because of %#v", location, err)
			continue
		}
		if _, ok := push_history(&browser.history, location); ok do sync_omnibar(&browser.omnibar, location)

		document := parse_document(browser, bytes)
		if doc_old, exists := browser.document.(Document); exists {
			browser.scroll.target  = 0
			browser.scroll.current = 0
			delete_document(doc_old)
		}
		browser.document = document
		browser.omnibar.visible = false
	}
}
