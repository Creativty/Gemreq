package uri

import "core:log"
import "core:testing"

SOURCE_LIST :: [?]string{
	"news:comp.infosystems.www.servers.unix",
	"http://username:password@localhost:8080/about#contact",
	"telnet://192.0.2.16:80/",
	"tel:+1-816-555-1212",
	"https://youtube.com:443/watch?v=3b3f9087a",
	"mongodb+srv://myDatabaseUser:D1fficultPassw0rd@server.example.com/",
	"gemini://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:1965",
	"file:///etc/hosts.conf",
}

@(test)
test_parse_scheme :: proc(t: ^testing.T) {
	scheme_list := [?]string{
		"news",
		"http",
		"telnet",
		"tel",
		"https",
		"mongodb+srv",
		"gemini",
		"file",
	}
	for uri_source, index in SOURCE_LIST {
		uri, ok := parse(uri_source)
		defer destroy(uri)

		testing.expect_value(t, ok, true)
		testing.expect_value(t, uri.scheme, scheme_list[index])
	}
}

@(test)
test_parse_authority :: proc(t: ^testing.T) {
	host_list := [?]string{
		"",
		"localhost",
		"192.0.2.16",
		"",
		"youtube.com",
		"server.example.com",
		"[2001:0db8:85a3:0000:0000:8a2e:0370:7334]",
		"",
		"",
	}
	port_list := [?]string{
		"",
		"8080",
		"80",
		"",
		"443",
		"",
		"1965",
		"",
		"",
	}
	user_info_list := [?]string{
		"",
		"username:password",
		"",
		"",
		"",
		"myDatabaseUser:D1fficultPassw0rd",
		"",
		"",
		"",
	}
	for uri_source, index in SOURCE_LIST {
		uri, ok := parse(uri_source)
		defer destroy(uri)

		testing.expect_value(t, ok, true)
		if len(port_list[index]) == 0 && len(host_list[index]) == 0 {
			testing.expect_value(t, uri.authority, nil)
		} else if authority, ok := uri.authority.(Authority); testing.expect_value(t, ok, true) {
			testing.expect_value(t, authority.port, port_list[index])
			testing.expect_value(t, authority.host, host_list[index])
			testing.expect_value(t, authority.user_info, user_info_list[index])
		}
	}
}

@(test)
test_parse_path :: proc(t: ^testing.T) {
	path_list := [?]string{
		"",
		"/about",
		"/",
		"",
		"/watch?v=3b3f9087a",
		"/",
		"",
		"/etc/hosts.conf",
	}
	for uri_source, index in SOURCE_LIST {
		uri, ok := parse(uri_source)
		defer destroy(uri)

		testing.expect_value(t, ok, true)
		testing.expect_value(t, uri.path, path_list[index])
	}
}

@(test)
test_parse :: proc(t: ^testing.T) {
	uri_empty, uri_empty_ok := parse("")
	defer destroy(uri_empty)
	testing.expect_value(t, uri_empty_ok, false)

	uri_ipv6_unterminated, uri_ipv6_unterminated_ok := parse("gemini://[2001:0db8:85a3:0000:0000:8a2e:0370:7334")
	defer destroy(uri_ipv6_unterminated)
	testing.expect_value(t, uri_ipv6_unterminated_ok, false)
	testing.expect_value(t, uri_ipv6_unterminated.scheme, "gemini")
}
