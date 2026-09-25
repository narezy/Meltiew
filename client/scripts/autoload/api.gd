extends Node
## Thin async wrapper over the Meltiew REST API.
## Usage: var r := await Api.request("GET", "/api/me"); if r.ok: ...

const BASE_URL := "https://meltiew.narez.xyz"
const TIMEOUT_SEC := 12.0

signal unauthorized


func request(method: String, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	http.use_threads = OS.get_name() != "Web"
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if Session.token != "":
		headers.append("Authorization: Bearer " + Session.token)
	var methods := {
		"GET": HTTPClient.METHOD_GET,
		"POST": HTTPClient.METHOD_POST,
		"PATCH": HTTPClient.METHOD_PATCH,
		"DELETE": HTTPClient.METHOD_DELETE,
	}
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(BASE_URL + path, headers, methods.get(method, HTTPClient.METHOD_GET), payload)
	if err != OK:
		http.queue_free()
		return _fail(0, "network", "Не получилось отправить запрос")
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var raw: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail(0, "network", "Нет связи с сервером. Проверь интернет")
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	if code == 401 and Session.token != "" and path != "/api/login":
		unauthorized.emit()
	if code >= 200 and code < 300:
		return {"ok": true, "status": code, "data": data}
	return _fail(code, str(data.get("error", "http")), str(data.get("message", "Ошибка сервера (%d)" % code)))


func _fail(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "error": code, "message": message, "data": {}}


func ws_url() -> String:
	return BASE_URL.replace("https://", "wss://").replace("http://", "ws://") + "/ws?token=" + Session.token.uri_encode()
