class_name SiGuestSession
extends Node
## Hand-written helper (not generated): `POST /api/v1/sessions/guest` over HTTP. The generated
## client covers only the WebSocket; pass the token to `SiClient.send_authenticate`.
## Add it to the scene tree, then call `request("http://127.0.0.1:8080", "Ada")`.

signal succeeded(token: String, user: SiUser)
signal failed(reason: String)


func request(base_url: String, user_name: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_completed.bind(http))
	var body := JSON.stringify({"name": user_name})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := http.request(base_url + "/api/v1/sessions/guest", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		failed.emit("request failed to start: %d" % error)


func _on_completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		failed.emit("guest session failed: result %d, status %d" % [result, status])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has("token") or not data.has("user"):
		failed.emit("guest session reply is malformed")
		return
	succeeded.emit(data["token"], SiUser.from_dict(data["user"]))
