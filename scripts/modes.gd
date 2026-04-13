extends Control

# ————— PANELE —————
@onready var panel_campaign = $Control_Main
@onready var panel_online = $Control_Online

# ————— KROPKI —————
@onready var dot1 = $HBoxContainer_Dots/Panel_Dot1
@onready var dot2 = $HBoxContainer_Dots/Panel_Dot2

# ————— ONLINE —————
@onready var btn_find = $Control_Online/TextureButton_FindGame
@onready var search_panel = $Control_Online/Control_Search
@onready var label_searching = $Control_Online/Label_Searching
@onready var btn_cancel = $Control_Online/Control_Search/TextureButton_Cancel

# ————— POZIOMY — 4 gridy —————
@onready var grid_page1 = $Control_Main/GridContainer_Page1
@onready var grid_page2 = $Control_Main/GridContainer_Page2
@onready var grid_page3 = $Control_Main/GridContainer_Page3
@onready var grid_page4 = $Control_Main/GridContainer_Page4
@onready var btn_prev = $Control_Main/HBoxContainer_Nav2/TextureButton_Previous
@onready var btn_next = $Control_Main/HBoxContainer_Nav2/TextureButton_Next

# ————— SOUND —————
@onready var sound_click = $"../SoundClick"

# ————— TEXTURY —————
var tex_completed = preload("res://ui/modes/level-completed.png")
var tex_current = preload("res://ui/modes/level-current.png")
var tex_disabled = preload("res://ui/modes/level-disabled.png")

# ————— KOLORY LABELÓW —————
const COLOR_COMPLETED = Color("#098aee")
const COLOR_CURRENT = Color("#6dc300")
const COLOR_DISABLED = Color("#7f7f7f")
const COLOR_FONT = Color.WHITE

# ————— STAN —————
var current_panel = 0
var current_page = 0
const LEVELS_PER_PAGE = 20
const TOTAL_LEVELS = 80

var level_states = []
var search_timer: float = 0.0
var is_searching = false
var _ready_done: bool = false
var queue_count: int = 0
var _queue_poll_timer: float = 0.0
const QUEUE_POLL_INTERVAL = 5.0

# ————— READY —————

func _ready():
	await get_tree().process_frame
	MusicManager.play_music("res://sounds/music.mp3")

	var btns = [
		get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowRight"),
		get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowRight"),
		btn_prev, btn_next, btn_find,
	]
	for btn in btns:
		if btn: btn.pivot_offset = btn.size / 2

	await get_tree().process_frame
	if btn_cancel: btn_cancel.pivot_offset = btn_cancel.size / 2

	for btn in grid_page1.get_children() + grid_page2.get_children() + grid_page3.get_children() + grid_page4.get_children():
		btn.pivot_offset = btn.size / 2
		btn.mouse_entered.connect(_on_level_mouse_entered.bind(btn))
		btn.mouse_exited.connect(_on_level_mouse_exited.bind(btn))
		btn.pressed.connect(_on_level_pressed.bind(btn))

	panel_campaign.visible = true
	panel_online.visible = false
	search_panel.visible = false
	label_searching.visible = true
	grid_page2.visible = false
	grid_page3.visible = false
	grid_page4.visible = false

	_update_dots()
	_update_nav_buttons()

	_ready_done = true
	_refresh_level_states()
	TimerManager.on_modes_enter()
	# Jeśli matchmaking trwał zanim opuściliśmy scenę — przywróć stan UI
	_restore_search_state()

# ————— ODŚWIEŻANIE STANÓW —————

func _notification(what: int):
	if what == NOTIFICATION_ENTER_TREE and _ready_done:
		_refresh_level_states()
		TimerManager.on_modes_enter()
		_restore_search_state()
	elif what == NOTIFICATION_EXIT_TREE:
		TimerManager.on_modes_exit()

func _restore_search_state():
	if PlayerData._matchmaking_active:
		is_searching = true
		search_timer = TimerManager.search_time
		# Wznów TimerManager jeśli był zatrzymany podczas nieobecności w scenie
		if not TimerManager.is_searching:
			TimerManager.is_searching = true
			TimerManager.timer_ui.visible = true
		# Pokaż panel online z anulowaniem
		panel_campaign.visible = false
		panel_online.visible = true
		current_panel = 1
		_update_dots()
		search_panel.visible = true
		btn_find.visible = false
		# Podłącz sygnały (rozłącz najpierw żeby nie było duplikatów)
		if PlayerData.matchmaking_found.is_connected(_on_match_found):
			PlayerData.matchmaking_found.disconnect(_on_match_found)
		if PlayerData.matchmaking_timeout.is_connected(_on_match_timeout):
			PlayerData.matchmaking_timeout.disconnect(_on_match_timeout)
		PlayerData.matchmaking_found.connect(_on_match_found, CONNECT_ONE_SHOT)
		PlayerData.matchmaking_timeout.connect(_on_match_timeout, CONNECT_ONE_SHOT)
	else:
		is_searching = false

func _refresh_level_states():
	if not _ready_done: return
	level_states.clear()
	var current_level = PlayerData.get_current_level()
	for i in range(TOTAL_LEVELS):
		var level_num = i + 1
		if level_num < current_level:
			level_states.append(1)
		elif level_num == current_level:
			level_states.append(2)
		else:
			level_states.append(0)
	_apply_level_states()

# ————— PROCESS —————

func _process(delta):
	if is_searching:
		search_timer += delta
		var minutes = int(search_timer) / 60
		var seconds = int(search_timer) % 60
		label_searching.text = "Finding match... %d:%02d" % [minutes, seconds]
	else:
		_queue_poll_timer += delta
		if _queue_poll_timer >= QUEUE_POLL_INTERVAL:
			_queue_poll_timer = 0.0
			_fetch_queue_count()
		label_searching.text = "Take on real opponents"

# ————— STRZAŁKI PANELI —————

func _on_arrow_left_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, 1)
	else:
		_switch_panels(false, 1)

func _on_arrow_right_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, -1)
	else:
		_switch_panels(false, -1)

func _switch_panels(go_to_online: bool, direction: int):
	if go_to_online:
		current_panel = 1
		_animate_panels(panel_campaign, panel_online, direction)
	else:
		current_panel = 0
		_animate_panels(panel_online, panel_campaign, direction)
	_update_dots()

func _animate_panels(panel_out: Control, panel_in: Control, direction: int):
	panel_in.visible = true
	panel_in.position.x = size.x * -direction
	panel_in.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel_out, "position:x", size.x * direction, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(panel_out, "modulate:a", 0.0, 0.3)
	tween.tween_property(panel_in, "position:x", 0.0, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(panel_in, "modulate:a", 1.0, 0.3)
	await tween.finished
	panel_out.visible = false
	panel_out.position.x = 0
	panel_out.modulate.a = 1.0

# ————— KROPKI —————

func _update_dots():
	var style1 = StyleBoxFlat.new()
	style1.corner_radius_top_left = 16
	style1.corner_radius_top_right = 16
	style1.corner_radius_bottom_left = 16
	style1.corner_radius_bottom_right = 16
	style1.border_width_left = 4
	style1.border_width_right = 4
	style1.border_width_top = 4
	style1.border_width_bottom = 4
	style1.border_color = Color.WHITE
	style1.shadow_size = 2
	style1.shadow_offset = Vector2(0, 2)
	var style2 = style1.duplicate()
	if current_panel == 0:
		style1.bg_color = Color("#08B9FF")
		style2.bg_color = Color("#4CDAFE")
	else:
		style1.bg_color = Color("#4CDAFE")
		style2.bg_color = Color("#08B9FF")
	dot1.add_theme_stylebox_override("panel", style1)
	dot2.add_theme_stylebox_override("panel", style2)

# ————— POZIOMY —————

func _on_level_pressed(btn: TextureButton):
	if btn.disabled: return
	sound_click.play()
	# Kliknięcie poziomu anuluje matchmaking
	if is_searching or PlayerData._matchmaking_active:
		_cancel_search()
	var level_index: int
	var idx_in_page1 = grid_page1.get_children().find(btn)
	var idx_in_page2 = grid_page2.get_children().find(btn)
	var idx_in_page3 = grid_page3.get_children().find(btn)
	if idx_in_page1 != -1:
		level_index = idx_in_page1 + 1
	elif idx_in_page2 != -1:
		level_index = LEVELS_PER_PAGE + idx_in_page2 + 1
	elif idx_in_page3 != -1:
		level_index = LEVELS_PER_PAGE * 2 + idx_in_page3 + 1
	else:
		level_index = LEVELS_PER_PAGE * 3 + grid_page4.get_children().find(btn) + 1
	await get_tree().create_timer(0.1).timeout
	PlayerData.launch_level(level_index)

func _apply_level_states():
	var all1 = grid_page1.get_children()
	var all2 = grid_page2.get_children()
	var all3 = grid_page3.get_children()
	var all4 = grid_page4.get_children()
	for i in range(all1.size()):
		_apply_state_to_button(all1[i], level_states[i])
	for i in range(all2.size()):
		var li = LEVELS_PER_PAGE + i
		if li < TOTAL_LEVELS:
			_apply_state_to_button(all2[i], level_states[li])
	for i in range(all3.size()):
		var li = LEVELS_PER_PAGE * 2 + i
		if li < TOTAL_LEVELS:
			_apply_state_to_button(all3[i], level_states[li])
	for i in range(all4.size()):
		var li = LEVELS_PER_PAGE * 3 + i
		if li < TOTAL_LEVELS:
			_apply_state_to_button(all4[i], level_states[li])

func _apply_state_to_button(btn: TextureButton, state: int):
	var label = btn.get_node_or_null("Label")
	match state:
		0:
			btn.texture_normal = tex_disabled
			btn.disabled = true
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_DISABLED)
		1:
			btn.texture_normal = tex_completed
			btn.disabled = false
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_COMPLETED)
		2:
			btn.texture_normal = tex_current
			btn.disabled = false
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_CURRENT)

func _update_nav_buttons():
	btn_prev.disabled = (current_page == 0)
	btn_prev.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 0 else Color(1, 1, 1, 1)
	btn_next.disabled = (current_page == 3)
	btn_next.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 3 else Color(1, 1, 1, 1)

# ————— PREV / NEXT GRID —————

func _on_previous_pressed():
	if current_page == 0: return
	sound_click.play()
	var grids = [grid_page1, grid_page2, grid_page3, grid_page4]
	var old_page = current_page
	current_page -= 1
	_slide_grids(grids[old_page], grids[current_page], 1)

func _on_next_pressed():
	if current_page == 3: return
	sound_click.play()
	var grids = [grid_page1, grid_page2, grid_page3, grid_page4]
	var old_page = current_page
	current_page += 1
	_slide_grids(grids[old_page], grids[current_page], -1)

func _slide_grids(grid_out: Control, grid_in: Control, direction: int):
	var target_pos = grid_in.position
	grid_in.visible = true
	grid_in.position = Vector2(target_pos.x + (grid_in.size.x * -direction), target_pos.y)
	grid_in.modulate.a = 0.0
	_update_nav_buttons()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(grid_out, "position:x", grid_out.position.x + (grid_out.size.x * direction), 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(grid_out, "modulate:a", 0.0, 0.2)
	tween.tween_property(grid_in, "position:x", target_pos.x, 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(grid_in, "modulate:a", 1.0, 0.2)
	await tween.finished
	grid_out.visible = false
	grid_out.position = Vector2(grid_out.position.x - (grid_out.size.x * direction), grid_out.position.y)
	grid_out.modulate.a = 1.0

# ————— ONLINE —————

func _on_find_game_pressed():
	sound_click.play()
	btn_find.visible = false
	search_panel.visible = true
	is_searching = true
	search_timer = 0.0
	TimerManager.start_search()

	if PlayerData.matchmaking_found.is_connected(_on_match_found):
		PlayerData.matchmaking_found.disconnect(_on_match_found)
	if PlayerData.matchmaking_timeout.is_connected(_on_match_timeout):
		PlayerData.matchmaking_timeout.disconnect(_on_match_timeout)
	PlayerData.matchmaking_found.connect(_on_match_found, CONNECT_ONE_SHOT)
	PlayerData.matchmaking_timeout.connect(_on_match_timeout, CONNECT_ONE_SHOT)

	# Pobierz aktualną rangę przed matchmakingiem — żeby przeciwnik ją zobaczył
	await PlayerData.fetch_my_rank()

	var ok = await PlayerData.start_matchmaking()
	if not ok:
		await get_tree().create_timer(1.0).timeout
		_on_match_timeout()

func _on_cancel_pressed():
	sound_click.play()
	_cancel_search()

func _cancel_search():
	is_searching = false
	search_panel.visible = false
	label_searching.visible = true
	btn_find.visible = true
	PlayerData.stop_matchmaking()
	TimerManager.stop_search()
	if PlayerData.matchmaking_found.is_connected(_on_match_found):
		PlayerData.matchmaking_found.disconnect(_on_match_found)
	if PlayerData.matchmaking_timeout.is_connected(_on_match_timeout):
		PlayerData.matchmaking_timeout.disconnect(_on_match_timeout)

func _on_match_found():
	is_searching = false
	search_panel.visible = false
	label_searching.visible = true
	btn_find.visible = true
	TimerManager.stop_search()
	PlayerData.launch_online_duel()

func _on_match_timeout():
	if not is_searching: return
	is_searching = false
	search_panel.visible = false
	label_searching.visible = true
	btn_find.visible = true
	TimerManager.stop_search()
	PlayerData.online_opponent_name = ""
	PlayerData.launch_online_duel()
	
func _fetch_queue_count():
	var ticket = PlayerData.get_ticket()
	if ticket == "": return
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(
		PlayerData.PLAYFAB_URL + "/Match/GetQueueStatistics",
		headers, HTTPClient.METHOD_POST,
		JSON.stringify({"QueueName": PlayerData.MATCHMAKING_QUEUE})
	)
	var response = await http.request_completed
	http.queue_free()
	if response[1] != 200: return
	var json = JSON.new()
	if json.parse(response[3].get_string_from_utf8()) != OK: return
	var data = json.get_data().get("data", {})
	queue_count = data.get("NumPlayersMatching", 0)

# ————— HOVER STRZAŁKI —————

func _on_arrow_left_campaign_mouse_entered():
	_scale_button(get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowLeft"), 0.9)
func _on_arrow_left_campaign_mouse_exited():
	_scale_button(get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowLeft"), 1.0)
func _on_arrow_right_campaign_mouse_entered():
	_scale_button(get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowRight"), 0.9)
func _on_arrow_right_campaign_mouse_exited():
	_scale_button(get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowRight"), 1.0)
func _on_arrow_left_online_mouse_entered():
	_scale_button(get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowLeft"), 0.9)
func _on_arrow_left_online_mouse_exited():
	_scale_button(get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowLeft"), 1.0)
func _on_arrow_right_online_mouse_entered():
	_scale_button(get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowRight"), 0.9)
func _on_arrow_right_online_mouse_exited():
	_scale_button(get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowRight"), 1.0)

# ————— HOVER NAV —————

func _on_previous_mouse_entered():
	_scale_button(btn_prev, 0.9)
func _on_previous_mouse_exited():
	_scale_button(btn_prev, 1.0)
func _on_next_mouse_entered():
	_scale_button(btn_next, 0.9)
func _on_next_mouse_exited():
	_scale_button(btn_next, 1.0)

# ————— HOVER ONLINE —————

func _on_find_game_mouse_entered():
	_scale_button(btn_find, 0.9)
func _on_find_game_mouse_exited():
	_scale_button(btn_find, 1.0)
func _on_cancel_mouse_entered():
	_scale_button(btn_cancel, 0.9)
func _on_cancel_mouse_exited():
	_scale_button(btn_cancel, 1.0)

# ————— HOVER POZIOMY —————

func _on_level_mouse_entered(btn: TextureButton):
	_scale_button(btn, 0.9)
func _on_level_mouse_exited(btn: TextureButton):
	_scale_button(btn, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null: return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
