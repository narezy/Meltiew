extends Node
## Thin async wrapper over the Meltiew REST API.
## Usage: var r := await Api.request("GET", "/api/me"); if r.ok: ...

const DEFAULT_URL := "https://meltiew.narez.xyz"
const TIMEOUT_SEC := 12.0

signal unauthorized
## The server refused this app version; carries the download page URL.
signal update_required(message: String, url: String)

## Override with `-- --server=http://127.0.0.1:7350` for local testing.
var BASE_URL := DEFAULT_URL


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			BASE_URL = arg.trim_prefix("--server=").trim_suffix("/")


func request(method: String, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	http.use_threads = OS.get_name() != "Web"
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"X-Lang: " + L.lang,
		"X-Client: app",
		"X-Client-Version: " + version(),
	])
	if Session.token != "":
		headers.append("Authorization: Bearer " + Session.token)
	var methods := {
		"GET": HTTPClient.METHOD_GET,
		"POST": HTTPClient.METHOD_POST,
		"PUT": HTTPClient.METHOD_PUT,
		"PATCH": HTTPClient.METHOD_PATCH,
		"DELETE": HTTPClient.METHOD_DELETE,
	}
	# An unknown method must fail, not quietly turn into a GET that "succeeds".
	assert(methods.has(method), "unsupported HTTP method " + method)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(BASE_URL + path, headers, methods[method], payload)
	if err != OK:
		http.queue_free()
		return _fail(0, "network", L.t("err_request"))
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var raw: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail(0, "network", L.t("err_network"))
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	if code == 426:
		update_required.emit(str(data.get("message", "")), str(data.get("download", BASE_URL + "/download")))
	if code == 401 and Session.token != "" and path != "/api/login":
		unauthorized.emit()
	if code >= 200 and code < 300:
		return {"ok": true, "status": code, "data": data}
	return _fail(code, str(data.get("error", "http")), str(data.get("message", L.t("err_server", [code]))))


func _fail(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "error": code, "message": message, "data": {}}


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func avatar_url(user_id: int) -> String:
	return "%s/api/avatar/%d.png" % [BASE_URL, user_id]


func ws_url() -> String:
	return BASE_URL.replace("https://", "wss://").replace("http://", "ws://") + "/ws?token=" + Session.token.uri_encode() + "&lang=" + L.lang + "&v=" + version() + ("&luau=1" if ClassDB.class_exists("LuauVM") else "")
