extends Control

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

# ————— DANE (fake na razie) —————
var players = []
const PLAYERS_PER_PAGE = 100
var current_page = 0
var total_players = 300  # np. 3 strony

# ————— READY —————

func _ready():
	await get_tree().process_frame
	
	# Pivot nav
	for btn in [btn_prev, btn_next]:
		if btn:
			btn.pivot_offset = btn.size / 2
	
	# Generuj fake dane
	_generate_fake_players()
	
	# Załaduj pierwszą stronę
	_load_page(0)
	_update_nav_buttons()

# ————— FAKE DANE —————

func _generate_fake_players():
	players.clear()
	for i in range(total_players):
		players.append({
			"position": i + 1,
			"name": "Player_%d" % (i + 1),
			"score": randi_range(100000, 9999999),
			"wins": randi_range(10, 500),
			"loses": randi_range(5, 300),
		})
	# Posortuj po score malejąco
	players.sort_custom(func(a, b): return a["score"] > b["score"])
	# Zaktualizuj pozycje po sortowaniu
	for i in range(players.size()):
		players[i]["position"] = i + 1

# ————— ŁADOWANIE STRONY —————

func _load_page(page: int):
	for child in vbox_players.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	var start = page * PLAYERS_PER_PAGE
	var end = min(start + PLAYERS_PER_PAGE, players.size())
	
	label_subtitle.text = "Players %d-%d" % [start + 1, end]
	
	for i in range(start, end):
		var player = players[i]
		var row = player_row_scene.instantiate()
		vbox_players.add_child(row)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_setup_player_row(row, player)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox_players.add_child(spacer)
	
	# Czekaj 2 klatki żeby Godot obliczył rozmiary
	await get_tree().process_frame
	await get_tree().process_frame
	_update_progress_bars(start, end)
	
func _update_progress_bars(start: int, end: int):
	var rows = vbox_players.get_children()
	for i in range(rows.size()):
		if start + i >= players.size():
			break
		var player = players[start + i]
		var total = player["wins"] + player["loses"]
		var ratio = float(player["wins"]) / float(total) if total > 0 else 0.0
		var panel_fill = rows[i].get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG/MarginContainer/Panel_Fill")
		if panel_fill:
			panel_fill.custom_minimum_size.x = BAR_WIDTH * ratio

func _setup_player_row(row: Control, player: Dictionary):
	# Tło zależne od pozycji
	var bg_tex = tex_bg1
	match player["position"]:
		1: bg_tex = tex_bg4
		2: bg_tex = tex_bg3
		3: bg_tex = tex_bg2
	
	var bg = row.get_node_or_null("TextureRect_BG")
	if bg:
		bg.texture = bg_tex
	
	# Pozycja i nazwa
	var label_pos = row.get_node_or_null("HBoxContainer/Label_Position")
	if label_pos:
		label_pos.text = "%d." % player["position"]
	
	var label_name = row.get_node_or_null("HBoxContainer/Label_Name")
	if label_name:
		label_name.text = player["name"]
	
	# Score
	var label_score_title = row.get_node_or_null("ScoreContainer/Label_ScoreTitle")
	if label_score_title:
		label_score_title.text = "Score"
	
	var label_score = row.get_node_or_null("ScoreContainer/Label_Score")
	if label_score:
		label_score.text = str(player["score"])
	
	# Stats
	var label_stats = row.get_node_or_null("ScoreContainer2/Label_Stats")
	if label_stats:
		label_stats.text = "%d win / %d loses" % [player["wins"], player["loses"]]
	
	# Progress bar
	var total_games = player["wins"] + player["loses"]
	var win_ratio = float(player["wins"]) / float(total_games) if total_games > 0 else 0.0
	_setup_progress_bar(row, win_ratio)

func _setup_progress_bar(row: Control, win_ratio: float):
	var panel_bg = row.get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG")
	var margin_container = row.get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG/MarginContainer")
	var panel_fill = row.get_node_or_null("ScoreContainer2/Control_Bar/Panel_BG/MarginContainer/Panel_Fill")
	var panel_border = row.get_node_or_null("ScoreContainer2/Control_Bar/PanelBorder")
	
	# Styl tła (przegrane - czerwony)
	if panel_bg:
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color("#FE4B60")
		style_bg.corner_radius_top_left = 8
		style_bg.corner_radius_top_right = 8
		style_bg.corner_radius_bottom_left = 8
		style_bg.corner_radius_bottom_right = 8
		panel_bg.add_theme_stylebox_override("panel", style_bg)
	
	# Border
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
	
	# Fill (wygrane - niebieski) — szerokość przez size_flags
	if panel_fill:
		var style_fill = StyleBoxFlat.new()
		style_fill.bg_color = Color("#4CDAFE")
		style_fill.corner_radius_top_left = 8
		style_fill.corner_radius_top_right = 8
		style_fill.corner_radius_bottom_left = 8
		style_fill.corner_radius_bottom_right = 8
		panel_fill.add_theme_stylebox_override("panel", style_fill)
		# Ustaw szerokość fill przez custom_minimum_size
		await get_tree().process_frame
		if panel_bg:
			var bar_width = panel_bg.size.x * win_ratio
			panel_fill.custom_minimum_size.x = bar_width

# ————— PREV / NEXT —————

func _on_previous_pressed():
	if current_page == 0:
		return
	sound_click.play()
	current_page -= 1
	_load_page(current_page)
	_update_nav_buttons()

func _on_next_pressed():
	var max_page = (players.size() - 1) / PLAYERS_PER_PAGE
	if current_page >= max_page:
		return
	sound_click.play()
	current_page += 1
	_load_page(current_page)
	_update_nav_buttons()

func _update_nav_buttons():
	var max_page = (players.size() - 1) / PLAYERS_PER_PAGE
	btn_prev.disabled = (current_page == 0)
	btn_prev.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 0 else Color(1, 1, 1, 1)
	btn_next.disabled = (current_page >= max_page)
	btn_next.modulate = Color(0.5, 0.5, 0.5, 1) if current_page >= max_page else Color(1, 1, 1, 1)

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
