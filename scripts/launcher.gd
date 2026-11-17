## The Overheat launcher. Players install the kit once (Overheat.exe = stock Godot 4.7.2 for
## Windows, plus Overheat.pck = this launcher). Every start it:
##   1. updates itself: channels/launcher.json names the newest launcher pack; the kit's launcher
##      downloads it and hands over to it ("--inner"), so the kit never needs reinstalling;
##   2. reads channels/<stable|dev>.json, downloads the newest game pack for that channel
##      (checked by SHA-256) and shows its date and notes;
##   3. PLAY starts the game pack with that channel's server, pilot name and tester token.
## Dev needs a tester token (the server checks it; only the player's own token is stored here).
## This repo is public: no server code, no secrets, ever.
extends Control

const LAUNCHER_VERSION := 1
const RAW := "https://raw.githubusercontent.com/TheNasky/Overheat-Launcher/main/channels/"
const GAME_DIR := "user://game/"
const LAUNCHER_DIR := "user://launcher/"
const CONFIG := "user://launcher.json"
const GREEN := Color(0.36, 1.0, 0.54)
const DIM := Color(0.62, 0.74, 0.66)
const WARN := Color(1.0, 0.72, 0.3)
const BG := Color(0.035, 0.05, 0.04)

var cfg := {"channel": "stable", "name": "", "token": ""}
var manifest := {}
var local := {}            # user://game/<channel>/version.json: the pack we have
var raw := RAW             # --channels=<base url> for tests
var http: HTTPRequest
var dl: HTTPRequest
var _dl_kind := ""         # "game" or "launcher"
var _pending_launcher := {}

var status_lbl: Label
var ver_lbl: Label
var notes_box: RichTextLabel
var bar: ProgressBar
var play_btn: Button
var check_btn: Button
var ch_btns := {}
var login_box: Control
var name_edit: LineEdit
var token_edit: LineEdit

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(GAME_DIR)
	DirAccess.make_dir_recursive_absolute(LAUNCHER_DIR)
	var c = _read_json(CONFIG)
	if c is Dictionary:
		cfg.merge(c, true)
	var uargs := OS.get_cmdline_user_args()
	for a in uargs:
		if a.begins_with("--channels="):
			raw = a.substr(11).trim_suffix("/") + "/"
		elif a.begins_with("--channel="):
			cfg.channel = a.substr(10)
	# the kit's launcher hands over to a newer launcher we already downloaded
	var mine = _read_json(LAUNCHER_DIR + "version.json")
	if not "--inner" in uargs and _from_pack() and mine is Dictionary \
			and int(mine.get("launcher", 0)) > LAUNCHER_VERSION and FileAccess.file_exists(LAUNCHER_DIR + str(mine.pck)):
		_relaunch(LAUNCHER_DIR + str(mine.pck))
		return
	http = HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	dl = HTTPRequest.new()
	dl.download_chunk_size = 256 * 1024
	add_child(dl)
	dl.request_completed.connect(_on_download)
	_build_ui()
	_select_channel(str(cfg.channel), false)
	_check_launcher()

func _from_pack() -> bool:
	return not FileAccess.file_exists("res://project.godot")

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _write_json(path: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _fetch(url: String, cb: Callable) -> void:
	http.cancel_request()
	for c in http.request_completed.get_connections():
		http.request_completed.disconnect(c.callable)
	http.request_completed.connect(cb, CONNECT_ONE_SHOT)
	if http.request(url + "?t=%d" % Time.get_unix_time_from_system()) != OK:
		cb.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

static func _parse(result: int, code: int, body: PackedByteArray) -> Variant:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return null
	return JSON.parse_string(body.get_string_from_utf8())

# ------------------------------------------------------------------ 1. launcher self-update
func _check_launcher() -> void:
	_status("Checking for launcher updates...")
	_fetch(raw + "launcher.json", func(r, c, _h, b):
		var m = _parse(r, c, b)
		if m is Dictionary and int(m.get("launcher", 0)) > LAUNCHER_VERSION and str(m.get("pck_url", "")) != "" and _from_pack():
			_pending_launcher = m
			_download("launcher", str(m.pck_url), LAUNCHER_DIR + "launcher-%d.part" % int(m.launcher))
		else:
			_check_game())

func _relaunch(pck: String) -> void:
	var args := ["--main-pack", ProjectSettings.globalize_path(pck), "--", "--inner"]
	for a in OS.get_cmdline_user_args():
		if a != "--inner":
			args.append(a)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit.call_deferred()

# ------------------------------------------------------------------ 2. game pack for the channel
func _channel_dir() -> String:
	return GAME_DIR + str(cfg.channel) + "/"

func _local_pck() -> String:
	return _channel_dir() + str(local.get("pck", "game.pck"))

func _check_game() -> void:
	manifest = {}
	_status("Checking for %s updates..." % str(cfg.channel))
	_fetch(raw + str(cfg.channel) + ".json", _on_manifest)

func _on_manifest(r: int, c: int, _h: PackedStringArray, b: PackedByteArray) -> void:
	var m = _parse(r, c, b)
	if not (m is Dictionary) or not m.has("version"):
		_offline("Could not reach the update server%s." % ((" (%d)" % c) if c > 0 else ""))
		return
	if str(m.get("pack_url", "")) == "":
		_show_notes(m)
		_offline("No %s build has been published yet." % str(cfg.channel))
		return
	manifest = m
	_show_notes(m)
	if str(local.get("version", "")) == str(m.version) and FileAccess.file_exists(_local_pck()):
		_ready_to_play("Up to date. Latest %s build: %s" % [str(cfg.channel), when(m)])
		return
	_status("Downloading %s build %s..." % [str(cfg.channel), m.version])
	_download("game", str(m.pack_url), _channel_dir() + str(m.version) + ".part")

func _download(kind: String, url: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	_dl_kind = kind
	bar.visible = true
	bar.value = 0
	dl.cancel_request()
	dl.download_file = to
	if dl.request(url) != OK:
		_on_download(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _on_download(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	bar.visible = false
	var part := dl.download_file
	var m: Dictionary = _pending_launcher if _dl_kind == "launcher" else manifest
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if ok and str(m.get("sha256", "")) != "" and FileAccess.get_sha256(part) != str(m.sha256):
		ok = false
	if not ok:
		DirAccess.remove_absolute(part)
		if _dl_kind == "launcher":
			_check_game()   # a failed launcher update never blocks playing
		else:
			_offline("The download failed or was damaged (%s). Press CHECK FOR UPDATE to retry." % str(code))
		return
	var final := part.get_basename() + ".pck"
	DirAccess.remove_absolute(final)
	DirAccess.rename_absolute(part, final)
	if _dl_kind == "launcher":
		_write_json(LAUNCHER_DIR + "version.json", {"launcher": int(m.launcher), "pck": final.get_file()})
		_relaunch(final)
		return
	local = {"version": m.version, "pck": final.get_file(), "server": m.get("server", ""),
		"published_unix": int(m.get("published_unix", 0))}
	_write_json(_channel_dir() + "version.json", local)
	_cleanup_old_packs()
	_ready_to_play("Updated. Latest %s build: %s" % [str(cfg.channel), when(m)])

func _cleanup_old_packs() -> void:
	var keep := str(local.get("pck", ""))
	for f in DirAccess.get_files_at(_channel_dir()):
		if (f.ends_with(".pck") or f.ends_with(".part")) and f != keep:
			DirAccess.remove_absolute(_channel_dir() + f)   # a running game keeps its file locked: fine

func _offline(why: String) -> void:
	if FileAccess.file_exists(_local_pck()):
		_ready_to_play(why + " You can play the build you have (%s)." % str(local.get("version", "")))
	else:
		_status(why)
		_refresh()

func _ready_to_play(msg: String) -> void:
	_status(msg)
	_refresh()
	if "--auto-play" in OS.get_cmdline_user_args():   # tests: play as soon as the pack is ready
		_play()

# ------------------------------------------------------------------ 3. play
func _server() -> String:
	return str(manifest.get("server", local.get("server", "")))

func _play() -> void:
	if cfg.channel == "dev" and str(cfg.token) == "":
		_status("Dev needs your tester code. Paste it above, then PLAY.", true)
		return
	var args := ["--main-pack", ProjectSettings.globalize_path(_local_pck()), "--", "--channel=" + str(cfg.channel)]
	if _server() != "":
		args.append("--server-url=" + _server())
	if str(cfg.name) != "":
		args.append("--name=" + str(cfg.name))
	if str(cfg.token) != "":
		args.append("--token=" + str(cfg.token))
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()

## "Tue 17 Nov 2026, 03:10 (2 h ago)" in this PC's time zone.
static func when(m: Dictionary) -> String:
	var t := int(m.get("published_unix", 0))
	if t <= 0:
		return str(m.get("date", "unknown date"))
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(t + bias)
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var s := "%s %d %s %d, %02d:%02d" % [days[d.weekday], d.day, months[d.month - 1], d.year, d.hour, d.minute]
	var ago := int(Time.get_unix_time_from_system()) - t
	if ago >= 0:
		s += " (%s ago)" % ("%d min" % maxi(1, ago / 60) if ago < 3600 else ("%d h" % (ago / 3600) if ago < 86400 else "%d d" % (ago / 86400)))
	return s

# ------------------------------------------------------------------ UI
func _select_channel(ch: String, recheck := true) -> void:
	if ch != "dev":
		ch = "stable"
	cfg.channel = ch
	_write_json(CONFIG, cfg)
	var lv = _read_json(_channel_dir() + "version.json")
	local = lv if lv is Dictionary else {}
	for k in ch_btns:
		ch_btns[k].button_pressed = k == ch
	login_box.visible = ch == "dev"
	_refresh()
	if recheck:
		_check_game()

func _save_login(_t := "") -> void:
	cfg.name = name_edit.text.strip_edges().left(24)
	cfg.token = token_edit.text.strip_edges()
	_write_json(CONFIG, cfg)

func _refresh() -> void:
	play_btn.disabled = not FileAccess.file_exists(_local_pck())
	ver_lbl.text = "launcher %d  ·  %s build %s%s" % [LAUNCHER_VERSION, str(cfg.channel), str(local.get("version", "none yet")),
		("  ·  server %s" % _server()) if _server() != "" else ""]

func _status(t: String, warn := false) -> void:
	status_lbl.text = t
	status_lbl.add_theme_color_override("font_color", WARN if warn else GREEN)
	print("[launcher] ", t)

func _show_notes(m: Dictionary) -> void:
	var txt := "[color=#5dff8a]%s BUILD  ·  %s[/color]\n[color=#8fa897]%s[/color]\n\n" % [
		str(cfg.channel).to_upper(), when(m).to_upper(), str(m.get("version", ""))]
	for l in m.get("notes", []):
		txt += "•  %s\n" % str(l)
	notes_box.text = txt

func _process(_dt: float) -> void:
	if dl and dl.get_http_client_status() == HTTPClient.STATUS_BODY and dl.get_body_size() > 0:
		bar.value = 100.0 * dl.get_downloaded_bytes() / dl.get_body_size()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(80, 56)
	col.custom_minimum_size = Vector2(760, 0)
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	col.add_child(_label("OVERHEAT", 72, GREEN))
	col.add_child(_label("PLAYTEST LAUNCHER", 15, DIM))
	var chrow := HBoxContainer.new()
	chrow.add_theme_constant_override("separation", 10)
	col.add_child(chrow)
	for ch in ["stable", "dev"]:
		var b := _button(chrow, ch.to_upper(), func(): _select_channel(ch), false)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 40)
		ch_btns[ch] = b
	login_box = HBoxContainer.new()
	login_box.add_theme_constant_override("separation", 10)
	col.add_child(login_box)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "pilot name"
	name_edit.custom_minimum_size = Vector2(220, 38)
	name_edit.text = str(cfg.name)
	name_edit.text_changed.connect(_save_login)
	login_box.add_child(name_edit)
	token_edit = LineEdit.new()
	token_edit.placeholder_text = "tester code (OH-...)"
	token_edit.secret = true
	token_edit.custom_minimum_size = Vector2(380, 38)
	token_edit.text = str(cfg.token)
	token_edit.text_changed.connect(_save_login)
	login_box.add_child(token_edit)
	notes_box = RichTextLabel.new()
	notes_box.bbcode_enabled = true
	notes_box.custom_minimum_size = Vector2(760, 280)
	notes_box.add_theme_color_override("default_color", Color(0.85, 0.92, 0.87))
	notes_box.add_theme_font_size_override("normal_font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.07)
	sb.border_color = Color(GREEN, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_content_margin_all(16)
	notes_box.add_theme_stylebox_override("normal", sb)
	notes_box.text = "Loading..."
	col.add_child(notes_box)
	bar = ProgressBar.new()
	bar.visible = false
	bar.custom_minimum_size = Vector2(760, 16)
	col.add_child(bar)
	status_lbl = _label("", 16, GREEN)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.custom_minimum_size = Vector2(760, 0)
	col.add_child(status_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	play_btn = _button(row, "PLAY", _play, true)
	check_btn = _button(row, "CHECK FOR UPDATE", _check_game, false)
	_button(row, "QUIT", func(): get_tree().quit(), false)
	ver_lbl = _label("", 13, Color(DIM, 0.7))
	ver_lbl.position = Vector2(80, 680)
	add_child(ver_lbl)

func _label(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(p: Control, text: String, cb: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240 if primary else 200, 56 if primary else 48)
	b.add_theme_font_size_override("font_size", 26 if primary else 16)
	var base := Color(0.16, 0.55, 0.28) if primary else Color(0.08, 0.12, 0.09)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = {"normal": base, "hover": base.lightened(0.12), "pressed": base.lightened(0.25), "disabled": Color(0.1, 0.12, 0.1)}[st]
		s.border_color = Color(GREEN, 0.9 if primary or st == "pressed" else 0.3)
		s.set_border_width_all(2 if primary or st == "pressed" else 1)
		s.set_corner_radius_all(2)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", Color(0.92, 1.0, 0.94))
	b.add_theme_color_override("font_pressed_color", GREEN)
	b.pressed.connect(cb)
	p.add_child(b)
	return b
