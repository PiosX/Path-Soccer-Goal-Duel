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
@onready var label_searching = $Control_Online/Control_Search/Label_Searching
@onready var btn_cancel = $Control_Online/Control_Search/TextureButton_Cancel

# ————— POZIOMY — 2 gridy —————
@onready var grid_page1 = $Control_Main/GridContainer_Page1
@onready var grid_page2 = $Control_Main/GridContainer_Page2
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
var current_page = 0  # 0 = strona 1, 1 = strona 2
const LEVELS_PER_PAGE = 20
const TOTAL_LEVELS = 40
const LEVEL_UNLOCKED = 2
const GRID_X = 52.0
const GRID_Y = 315.0

var level_states = []
var search_timer: float = 0.0
var is_searching = false

# ————— READY —————

func _ready():
	await get_tree().process_frame
	
	# Pivot strzałki i nav
	var btns = [
		get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Main/HBoxContainer_Top/TextureButton_ArrowRight"),
		get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Online/HBoxContainer_Top/TextureButton_ArrowRight"),
		btn_prev,
		btn_next,
		btn_find,
	]
	for btn in btns:
		if btn:
			btn.pivot_offset = btn.size / 2
	
	await get_tree().process_frame
	if btn_cancel:
		btn_cancel.pivot_offset = btn_cancel.size / 2
	
	# Pivot + hover na przyciskach poziomów (oba gridy)
	for btn in grid_page1.get_children() + grid_page2.get_children():
		btn.pivot_offset = btn.size / 2
		btn.mouse_entered.connect(_on_level_mouse_entered.bind(btn))
		btn.mouse_exited.connect(_on_level_mouse_exited.bind(btn))
		btn.pressed.connect(_on_level_pressed.bind(btn))
	
	# Inicjalizuj stany poziomów
	for i in range(TOTAL_LEVELS):
		if i < LEVEL_UNLOCKED - 1:
			level_states.append(1)   # ukończony
		elif i == LEVEL_UNLOCKED - 1:
			level_states.append(2)   # aktualny
		else:
			level_states.append(0)   # zablokowany
	
	panel_campaign.visible = true
	panel_online.visible = false
	search_panel.visible = false
	grid_page2.visible = false
	
	_update_dots()
	_apply_level_states()
	_update_nav_buttons()

# ————— PROCESS —————

func _process(delta):
	if is_searching:
		search_timer += delta
		var minutes = int(search_timer) / 60
		var seconds = int(search_timer) % 60
		label_searching.text = "Finding match... %d:%02d" % [minutes, seconds]

# ————— STRZAŁKI PANELI — kierunkowe —————

func _on_arrow_left_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, 1)   # do online, animacja w lewo
	else:
		_switch_panels(false, 1)  # do campaign, animacja w lewo

func _on_arrow_right_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, -1)    # do online, animacja w prawo
	else:
		_switch_panels(false, -1)   # do campaign, animacja w prawo

func _switch_panels(go_to_online: bool, direction: int):
	if go_to_online:
		current_panel = 1
		_animate_panels(panel_campaign, panel_online, direction)
	else:
		current_panel = 0
		_animate_panels(panel_online, panel_campaign, direction)
	_update_dots()

func _animate_panels(panel_out: Control, panel_in: Control, direction: int):
	# direction: -1 = animacja w lewo, 1 = animacja w prawo
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

# ————— POZIOMY — aplikuj stany do obu gridów —————

func _on_level_pressed(btn: TextureButton):
	if btn.disabled:
		return
	sound_click.play()

func _apply_level_states():
	var all_buttons_page1 = grid_page1.get_children()
	var all_buttons_page2 = grid_page2.get_children()
	
	for i in range(all_buttons_page1.size()):
		_apply_state_to_button(all_buttons_page1[i], level_states[i])
	
	for i in range(all_buttons_page2.size()):
		var level_index = LEVELS_PER_PAGE + i
		if level_index < TOTAL_LEVELS:
			_apply_state_to_button(all_buttons_page2[i], level_states[level_index])

func _apply_state_to_button(btn: TextureButton, state: int):
	var label = btn.get_node_or_null("Label")
	match state:
		0:  # disabled
			btn.texture_normal = tex_disabled
			btn.disabled = true
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_DISABLED)
		1:  # ukończony
			btn.texture_normal = tex_completed
			btn.disabled = false
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_COMPLETED)
		2:  # aktualny
			btn.texture_normal = tex_current
			btn.disabled = false
			if label:
				label.add_theme_color_override("font_color", COLOR_FONT)
				label.add_theme_color_override("font_outline_color", COLOR_CURRENT)

func _update_nav_buttons():
	btn_prev.disabled = (current_page == 0)
	btn_prev.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 0 else Color(1, 1, 1, 1)
	btn_next.disabled = (current_page == 1)
	btn_next.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 1 else Color(1, 1, 1, 1)

# ————— PREV / NEXT — slide między gridami —————

func _on_previous_pressed():
	if current_page == 0:
		return
	sound_click.play()
	current_page = 0
	_slide_grids(grid_page2, grid_page1, 1)   # slide w prawo

func _on_next_pressed():
	if current_page == 1:
		return
	sound_click.play()
	current_page = 1
	_slide_grids(grid_page1, grid_page2, -1)  # slide w lewo

func _slide_grids(grid_out: Control, grid_in: Control, direction: int):
	var target_pos = grid_in.position  # pozycja z anchorów — już jest poprawna
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
	grid_out.position = Vector2(grid_out.position.x - (grid_out.size.x * direction), grid_out.position.y)  # reset
	grid_out.modulate.a = 1.0

# ————— ONLINE —————

func _on_find_game_pressed():
	sound_click.play()
	btn_find.visible = false
	search_panel.visible = true
	is_searching = true
	search_timer = 0.0
	TimerManager.start_search()

func _on_cancel_pressed():
	sound_click.play()
	is_searching = false
	search_panel.visible = false
	btn_find.visible = true
	TimerManager.stop_search()

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

# ————— HOVER POZIOMY (przez bind w _ready) —————

func _on_level_mouse_entered(btn: TextureButton):
	_scale_button(btn, 0.9)

func _on_level_mouse_exited(btn: TextureButton):
	_scale_button(btn, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
