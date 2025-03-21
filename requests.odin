package gemreq

import "core:log"
import "core:sync"
import "core:thread"
import "core:sync/chan"

Thread :: thread.Thread
Channel_Request :: chan.Chan(Endpoint)
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
		endpoint, endpoint_queued := chan.try_recv(chan_in^)
		if !endpoint_queued do continue

		disable_omnibar(&browser.omnibar)
		defer activate_omnibar(&browser.omnibar)

		bytes, err := request_document(endpoint)
		if err != nil {
			log.errorf("navigation to `%#v` failed because of %#v", endpoint, err)
			continue
		}
		if sync.mutex_guard(&browser.endpoint_mutex) {
			if endpoint_old, exists := browser.endpoint.(Endpoint); exists do delete_endpoint(endpoint_old)
			sync_omnibar(&browser.omnibar, endpoint)
			browser.endpoint = endpoint
		}

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
