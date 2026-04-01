extends Control

# ————— PLAYFAB —————
const PLAYFAB_URL = "https://139617.playfabapi.com"
const LEADERBOARD_NAME = "rating_score"
const PAGE_SIZE = 100

# ————— WĘZŁY —————
@onready var vbox_players = $MarginContainer/ScrollContainer/VBoxContainer_Players
@onready var label_subtitle = $Panel_Subtitle/Label_Subtitle
@onready var btn_prev = $HBoxContainer_Nav2/TextureButton_Previous
@onready var btn_next = $HBoxContainer_Nav2/TextureButton_Next
@onready var sound_click = $"../SoundClick"

const BAR_WIDTH = 98.0

# ————— TEXTURY —————
var tex_bg1 = preload("res://ui/scores/bg-1.png")
var tex_bg2 = preload("res://ui/scores/bg-2.png")
var tex_bg3 = preload("res://ui/scores/bg-3.png")
var tex_bg4 = preload("res://ui/scores/bg-4.png")

# ————— SCENA GRACZA —————
var player_row_scene = preload("res://scenes/player_row.tscn")

# ————— STAN —————
var players = []
var current_page = 0
var is_loading = false

# ————— READY —————

func _ready():
	await get_tree().process_frame
	MusicManager.play_music("res://sounds/music.mp3")

	for btn in [btn_prev, btn_next]:
		if btn:
			btn.pivot_offset = btn.size / 2

	_update_nav_buttons()
	_fetch_leaderboard(0)

# ——————————————————————————————————————————
#  PLAYFAB — pobierz leaderboard
# ——————————————————————————————————————————

func _fetch_leaderboard(start_position: int) -> void:
	if is_loading:
		return
	is_loading = true
	label_subtitle.text = "Loading..."
	
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		label_subtitle.text = "Not logged in"
		is_loading = false
		return

	var ticket = cfg.get_value("session", "ticket", "")
	if ticket == "":
		label_subtitle.text = "Not logged in"
		is_loading = false
		return

	var body = {
		"StatisticName": LEADERBOARD_NAME,
		"StartPosition": start_position,
		"MaxResultsCount": PAGE_SIZE,
		"ProfileConstraints": {
			"ShowDisplayName": true,
			"ShowStatistics": true
		}
	}
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/GetLeaderboard",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()
	is_loading = false
	
	print("HTTP status: ", response[1])
	print("Body: ", response[3].get_string_from_utf8().substr(0, 300))

	if response[1] != 200:
		label_subtitle.text = "Connection error"
		return

	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK:
		label_subtitle.text = "Parse error"
		return

	var parsed = json.get_data()
	if parsed.get("code", 0) != 200:
		label_subtitle.text = "Server error"
		return

	var leaderboard = parsed.get("data", {}).get("Leaderboard", [])
	_build_players_from_leaderboard(leaderboard, start_position)
	_load_page()
	_update_nav_buttons()

func _build_players_from_leaderboard(leaderboard: Array, start_position: int) -> void:
	players.clear()
	for entry in leaderboard:
		var rating = entry.get("StatValue", 0)
		# Odczytaj wins/loses/score z profilu gracza jeśli dostępne
		var stats = entry.get("Profile", {}).get("Statistics", [])
		var wins  = 0
		var loses = 0
		var score = 0
		for stat in stats:
			match stat.get("Name", ""):
				"wins":  wins  = stat.get("Value", 0)
				"losses": loses = stat.get("Value", 0)
				"score": score = stat.get("Value", 0)
		players.append({
			"position": entry.get("Position", 0) + 1,
			"name":     entry.get("DisplayName", entry.get("PlayFabId", "Unknown")),
			"rating":   rating,
			"score":    score,
			"wins":     wins,
			"loses":    loses,
		})

# ————— ŁADOWANIE STRONY —————

func _load_page() -> void:
	for child in vbox_players.get_children():
		child.queue_free()

	await get_tree().process_frame

	if players.is_empty():
		label_subtitle.text = "No players yet"
		return

	var start = current_page * PAGE_SIZE
	var end_pos = mini(start + PAGE_SIZE, players.size())
	label_subtitle.text = "Players %d-%d" % [start + 1, end_pos]

	for i in range(players.size()):
		var row = player_row_scene.instantiate()
		vbox_players.add_child(row)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_setup_player_row(row, players[i])

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox_players.add_child(spacer)

	await get_tree().process_frame
	await get_tree().process_frame
	_update_progress_bars()

func _update_progress_bars() -> void:
	var rows = vbox_players.get_children()
	for i in range(mini(rows.size(), players.size())):
		var player = players[i]
		var total = player["wins"] + player["loses"]
		var ratio = float(player["wins"]) / float(total) if total > 0 else 0.0
		var panel_fill = rows[i].get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG/MarginContainer/Panel_Fill")
		if panel_fill:
			panel_fill.custom_minimum_size.x = BAR_WIDTH * ratio

func _setup_player_row(row: Control, player: Dictionary) -> void:
	var bg_tex = tex_bg1
	match player["position"]:
		1: bg_tex = tex_bg4
		2: bg_tex = tex_bg3
		3: bg_tex = tex_bg2

	var bg = row.get_node_or_null("TextureRect_BG")
	if bg:
		bg.texture = bg_tex

	var label_pos = row.get_node_or_null("HBoxContainer/Label_Position")
	if label_pos:
		label_pos.text = "%d." % player["position"]

	var label_name = row.get_node_or_null("HBoxContainer/Label_Name")
	if label_name:
		label_name.text = player["name"]

	var label_score_title = row.get_node_or_null("ScoreContainer/Label_ScoreTitle")
	if label_score_title:
		label_score_title.text = "Score"

	var label_score = row.get_node_or_null("ScoreContainer/Label_Score")
	if label_score:
		label_score.text = str(player["score"])

	var label_stats = row.get_node_or_null("ScoreContainer2/Label_Stats")
	if label_stats:
		if player["wins"] == 0 and player["loses"] == 0:
			label_stats.text = "No PvP games"
		else:
			label_stats.text = "%d W / %d L" % [player["wins"], player["loses"]]

	var total_games = player["wins"] + player["loses"]
	var win_ratio = float(player["wins"]) / float(total_games) if total_games > 0 else 0.0
	_setup_progress_bar(row, win_ratio)

func _setup_progress_bar(row: Control, win_ratio: float) -> void:
	var panel_bg     = row.get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG")
	var panel_fill   = row.get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG/MarginContainer/Panel_Fill")
	var panel_border = row.get_node_or_null("ScoreContainer2/Control_Bar/PanelBorder")

	if panel_bg:
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color("#FE4B60")
		style_bg.corner_radius_top_left = 8
		style_bg.corner_radius_top_right = 8
		style_bg.corner_radius_bottom_left = 8
		style_bg.corner_radius_bottom_right = 8
		panel_bg.add_theme_stylebox_override("panel", style_bg)

	if panel_border:
		var style_border = StyleBoxFlat.new()
		style_border.bg_color = Color(0, 0, 0, 0)
		style_border.border_color = Color.WHITE
		style_border.border_width_left = 2
		style_border.border_width_right = 2
		style_border.border_width_top = 2
		style_border.border_width_bottom = 2
		style_border.corner_radius_top_left = 8
		style_border.corner_radius_top_right = 8
		style_border.corner_radius_bottom_left = 8
		style_border.corner_radius_bottom_right = 8
		panel_border.add_theme_stylebox_override("panel", style_border)

	if panel_fill:
		var style_fill = StyleBoxFlat.new()
		style_fill.bg_color = Color("#4CDAFE")
		style_fill.corner_radius_top_left = 8
		style_fill.corner_radius_top_right = 8
		style_fill.corner_radius_bottom_left = 8
		style_fill.corner_radius_bottom_right = 8
		panel_fill.add_theme_stylebox_override("panel", style_fill)
		await get_tree().process_frame
		if panel_bg:
			panel_fill.custom_minimum_size.x = panel_bg.size.x * win_ratio

# ————— PREV / NEXT — nowa strona z PlayFab —————

func _on_previous_pressed():
	if current_page == 0 or is_loading:
		return
	sound_click.play()
	current_page -= 1
	_fetch_leaderboard(current_page * PAGE_SIZE)

func _on_next_pressed():
	if is_loading:
		return
	sound_click.play()
	current_page += 1
	_fetch_leaderboard(current_page * PAGE_SIZE)

func _update_nav_buttons():
	btn_prev.disabled = (current_page == 0)
	btn_prev.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 0 else Color(1, 1, 1, 1)
	# Next: zablokuj jeśli ostatnia strona zwróciła mniej niż PAGE_SIZE wyników
	var has_more = players.size() >= PAGE_SIZE
	btn_next.disabled = not has_more
	btn_next.modulate = Color(0.5, 0.5, 0.5, 1) if not has_more else Color(1, 1, 1, 1)

# ————— HOVER NAV —————

func _on_previous_mouse_entered():
	_scale_button(btn_prev, 0.9)

func _on_previous_mouse_exited():
	_scale_button(btn_prev, 1.0)

func _on_next_mouse_entered():
	_scale_button(btn_next, 0.9)

func _on_next_mouse_exited():
	_scale_button(btn_next, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
