extends Node
## Visual Testing Sandbox — in-process HTTP server for driving the game.
##
## Listens on 127.0.0.1:9080 in debug builds only. Accepts JSON commands over
## HTTP POST, dispatches them against the live scene tree, and returns JSON
## responses. See docs/testing-sandbox.md for the full protocol.
##
## The server runs entirely inside the Godot process: input is injected via
## Input.parse_input_event() and screenshots come from the active viewport,
## so the sandbox cannot affect any other window or application.
##
## TCPServer reference:
##   https://docs.godotengine.org/en/4.4/classes/class_tcpserver.html
## Input.parse_input_event reference:
##   https://docs.godotengine.org/en/4.4/classes/class_input.html#class-input-method-parse-input-event

const PORT: int = 9080
const BIND_HOST: String = "127.0.0.1"

## Hard cap on how much we'll buffer per client before giving up. The protocol
## only handles small JSON payloads, so anything larger is almost certainly a
## misbehaving client.
const MAX_REQUEST_BYTES: int = 1 << 20  # 1 MiB

var _server: TCPServer
## Per-client receive buffers. Key: StreamPeerTCP, Value: PackedByteArray.
## We need a buffer because TCP is a stream — a single HTTP request may arrive
## across multiple poll cycles.
var _clients: Dictionary = {}


func _ready() -> void:
	# Compile the server out of release builds. is_debug_build() is true for
	# editor runs and debug exports, false for release exports — exactly the
	# split we want.
	if not OS.is_debug_build():
		set_process(false)
		return

	_server = TCPServer.new()
	var err: int = _server.listen(PORT, BIND_HOST)
	if err != OK:
		push_error("[TestingServer] Failed to bind %s:%d (err=%d)" % [BIND_HOST, PORT, err])
		set_process(false)
		return
	print("[TestingServer] Listening on http://%s:%d" % [BIND_HOST, PORT])


func _process(_dt: float) -> void:
	# Accept any newly-connected clients.
	while _server.is_connection_available():
		var client: StreamPeerTCP = _server.take_connection()
		_clients[client] = PackedByteArray()

	# Drain reads from each connected client. We iterate over a copy of the
	# keys because handlers may close (and remove) clients mid-loop.
	for client in _clients.keys():
		_pump_client(client)


# ---------------------------------------------------------------------------
# HTTP plumbing
# ---------------------------------------------------------------------------

func _pump_client(client: StreamPeerTCP) -> void:
	client.poll()
	var status: int = client.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		_clients.erase(client)
		return

	var available: int = client.get_available_bytes()
	if available > 0:
		var chunk: Array = client.get_partial_data(available)
		# get_partial_data returns [error_code, PackedByteArray]
		if chunk[0] == OK:
			var buf: PackedByteArray = _clients[client]
			buf.append_array(chunk[1])
			_clients[client] = buf

	var buffer: PackedByteArray = _clients[client]
	if buffer.size() > MAX_REQUEST_BYTES:
		_send_response(client, 413, {"error": "request too large"})
		return

	var parsed: Dictionary = _try_parse_request(buffer)
	if not parsed.get("complete", false):
		return  # wait for more bytes

	# Detach the client from the dispatch so we can safely await without the
	# main loop re-entering on the same buffer.
	_clients.erase(client)
	_dispatch(client, parsed.get("body", ""))


## Parse a buffered HTTP request. Returns {"complete": false} if more bytes are
## needed, otherwise {"complete": true, "body": "<json string>"}.
func _try_parse_request(buffer: PackedByteArray) -> Dictionary:
	var as_text: String = buffer.get_string_from_utf8()
	var header_end: int = as_text.find("\r\n\r\n")
	if header_end == -1:
		return {"complete": false}

	var header_block: String = as_text.substr(0, header_end)
	var body_start: int = header_end + 4

	# Pull Content-Length so we know whether we have the full body yet.
	var content_length: int = 0
	for line in header_block.split("\r\n"):
		var lower: String = line.to_lower()
		if lower.begins_with("content-length:"):
			content_length = int(lower.substr("content-length:".length()).strip_edges())
			break

	var body_bytes: int = buffer.size() - body_start
	if body_bytes < content_length:
		return {"complete": false}

	var body: String = ""
	if content_length > 0:
		body = buffer.slice(body_start, body_start + content_length).get_string_from_utf8()
	return {"complete": true, "body": body}


## Format a JSON response and send it. Closes the connection afterwards — this
## is request/response, no keep-alive.
##
## TODO(perf): StreamPeerTCP.put_data() is blocking — it waits until every byte
## has been handed to the kernel. For small JSON on localhost this is
## effectively instant, but a screenshot response can be several MB of
## base64-encoded PNG; if the kernel send buffer fills before the client
## drains it, this stalls the main thread inside _process. If we ever need
## hard frame-time guarantees while the sandbox is active, switch to
## put_partial_data() with a per-client write queue drained from _process.
##   https://docs.godotengine.org/en/4.4/classes/class_streampeer.html#class-streampeer-method-put-data
func _send_response(client: StreamPeerTCP, status_code: int, payload: Dictionary) -> void:
	var body: String = JSON.stringify(payload)
	var body_bytes: PackedByteArray = body.to_utf8_buffer()
	var status_text: String = _status_text(status_code)
	var header: String = (
		"HTTP/1.1 %d %s\r\n" % [status_code, status_text]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body_bytes.size()
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	client.put_data(header.to_utf8_buffer())
	client.put_data(body_bytes)
	client.disconnect_from_host()


func _status_text(code: int) -> String:
	match code:
		200: return "OK"
		400: return "Bad Request"
		404: return "Not Found"
		413: return "Payload Too Large"
		500: return "Internal Server Error"
		_: return "OK"


# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------

func _dispatch(client: StreamPeerTCP, body: String) -> void:
	var parsed: Variant = JSON.parse_string(body) if body != "" else {}
	if not (parsed is Dictionary):
		_send_response(client, 400, {"error": "body must be a JSON object"})
		return

	var request: Dictionary = parsed
	var command: String = String(request.get("command", ""))
	if command == "":
		_send_response(client, 400, {"error": "missing command"})
		return

	var result: Dictionary
	# Each handler returns a Dictionary, optionally awaiting frames first.
	# We wrap dispatch in a match so adding a command is a one-line change.
	match command:
		"screenshot":
			result = _cmd_screenshot()
		"press_action":
			result = _cmd_press_action(request)
		"release_action":
			result = _cmd_release_action(request)
		"press_key":
			result = await _cmd_press_key(request)
		"mouse_button_press":
			result = _cmd_mouse_button_press(request)
		"mouse_button_release":
			result = _cmd_mouse_button_release(request)
		"mouse_move":
			result = _cmd_mouse_move(request)
		"get_game_state":
			result = _cmd_get_game_state()
		"get_node_property":
			result = _cmd_get_node_property(request)
		"emit_game_event":
			result = _cmd_emit_game_event(request)
		"load_scene":
			result = _cmd_load_scene(request)
		"wait_frames":
			result = await _cmd_wait_frames(request)
		"reset_state":
			result = _cmd_reset_state()
		_:
			_send_response(client, 404, {"error": "unknown command: %s" % command})
			return

	var status_code: int = 400 if result.has("error") else 200
	_send_response(client, status_code, result)


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

func _cmd_screenshot() -> Dictionary:
	# get_viewport() on an autoload returns the root SubViewport / Window.
	# get_texture() is GPU-side; get_image() reads it back to CPU memory.
	#
	# TODO(perf): three serialized main-thread stalls live in this handler:
	#   1. get_image() forces a GPU→CPU readback, blocking until the render
	#      pipeline catches up.
	#   2. save_png_to_buffer() is synchronous CPU PNG encoding.
	#   3. Marshalls.raw_to_base64() is another full pass over the buffer.
	# Fine for tests that don't measure frame time; if we ever screenshot
	# while measuring perf, move the encode + base64 onto a WorkerThreadPool
	# task and resolve the response from the worker.
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return {"error": "viewport texture unavailable"}
	var png: PackedByteArray = image.save_png_to_buffer()
	return {"image": Marshalls.raw_to_base64(png)}


func _cmd_press_action(request: Dictionary) -> Dictionary:
	var action: String = String(request.get("action", ""))
	if not InputMap.has_action(action):
		return {"error": "unknown action: %s" % action}
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	return {"ok": true}


func _cmd_release_action(request: Dictionary) -> Dictionary:
	var action: String = String(request.get("action", ""))
	if not InputMap.has_action(action):
		return {"error": "unknown action: %s" % action}
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	return {"ok": true}


func _cmd_press_key(request: Dictionary) -> Dictionary:
	var keycode: int = int(request.get("keycode", 0))
	var duration_frames: int = int(request.get("duration_frames", 1))
	if keycode == 0:
		return {"error": "keycode required"}

	var down: InputEventKey = InputEventKey.new()
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)

	for i in duration_frames:
		await get_tree().process_frame

	var up: InputEventKey = InputEventKey.new()
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	return {"ok": true}


func _cmd_mouse_button_press(request: Dictionary) -> Dictionary:
	var pos := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
	var button: int = int(request.get("button", MOUSE_BUTTON_LEFT))
	# Move the cursor to the press location first so any hover-driven UI state
	# (highlights, drag-source detection) sees the button-down at this point.
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)

	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = pos
	event.global_position = pos
	event.pressed = true
	Input.parse_input_event(event)
	return {"ok": true}


func _cmd_mouse_button_release(request: Dictionary) -> Dictionary:
	var pos := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
	var button: int = int(request.get("button", MOUSE_BUTTON_LEFT))
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = pos
	event.global_position = pos
	event.pressed = false
	Input.parse_input_event(event)
	return {"ok": true}


func _cmd_mouse_move(request: Dictionary) -> Dictionary:
	var pos := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	Input.parse_input_event(event)
	return {"ok": true}


func _cmd_get_game_state() -> Dictionary:
	var name: String = GameState.State.keys()[GameState.current_state]
	return {"state": name}


func _cmd_get_node_property(request: Dictionary) -> Dictionary:
	var path: String = String(request.get("path", ""))
	var property: String = String(request.get("property", ""))
	if path == "" or property == "":
		return {"error": "path and property required"}

	var scene: Node = get_tree().current_scene
	if scene == null:
		return {"error": "no current scene"}
	var node: Node = scene.get_node_or_null(path)
	if node == null:
		return {"error": "node not found: %s" % path}

	var value: Variant = node.get(property)
	# Some Variant types (Object, Resource, RID) don't survive JSON round-trips
	# meaningfully — stringify them so callers at least get a useful identifier.
	if value is Object or value is RID:
		value = str(value)
	return {"value": value}


func _cmd_emit_game_event(request: Dictionary) -> Dictionary:
	var signal_name: String = String(request.get("signal_name", ""))
	var args: Array = request.get("args", [])
	if signal_name == "":
		return {"error": "signal_name required"}
	if not GameEvents.has_signal(signal_name):
		return {"error": "GameEvents has no signal: %s" % signal_name}
	# callv unpacks the args array into the emit_signal call.
	GameEvents.callv("emit_signal", [signal_name] + args)
	return {"ok": true}


## TODO(perf): both ResourceLoader.exists() and change_scene_to_file() touch
## the filesystem synchronously on the main thread. Acceptable for scenario
## setup, but unsuitable for any test that measures frame time across a scene
## transition. Use ResourceLoader.load_threaded_request() if that ever matters.
func _cmd_load_scene(request: Dictionary) -> Dictionary:
	var path: String = String(request.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return {"error": "scene not found: %s" % path}
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		return {"error": "change_scene_to_file failed (err=%d)" % err}
	return {"ok": true}


func _cmd_wait_frames(request: Dictionary) -> Dictionary:
	var count: int = int(request.get("count", 1))
	for i in count:
		await get_tree().process_frame
	return {"ok": true}


## TODO(perf): reload_current_scene() reloads the scene from disk
## synchronously; same caveat as _cmd_load_scene.
func _cmd_reset_state() -> Dictionary:
	get_tree().reload_current_scene()
	GameState.current_state = GameState.State.PLAYING
	return {"ok": true}
