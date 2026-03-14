extends Control

# ————— PANELE —————
@onready var panel_collection = $Control_Collection
@onready var panel_premium = $Control_Premium

# ————— GRIDY —————
@onready var grid_page1 = $Control_Collection/GridContainer_Page1
@onready var grid_page2 = $Control_Collection/GridContainer_Page2

# ————— NAV —————
@onready var btn_prev = $Control_Collection/HBoxContainer_Nav2/TextureButton_Previous
@onready var btn_next = $Control_Collection/HBoxContainer_Nav2/TextureButton_Next

# ————— KROPKI —————
@onready var dot1 = $HBoxContainer_Dots/Panel_Dot1
@onready var dot2 = $HBoxContainer_Dots/Panel_Dot2

# ————— SOUND —————
@onready var sound_click = $"../SoundClick"

# ————— TEXTURY PRZYCISKÓW —————
var tex_buy = preload("res://ui/shop/pay-200.png")
var tex_equip = preload("res://ui/shop/equip.png")
var tex_active = preload("res://ui/shop/active.png")

# ————— STAN —————
var current_panel = 0
var current_page = 0
const GRID_X = 52.0
const GRID_Y = 315.0

var skin_states = []
const TOTAL_SKINS = 24
var active_skin_index = 0
var active_tween: Tween = null
var active_skin_ctrl: Control = null
var active_skin_base_y: float = 0.0

func _ready():
	await get_tree().process_frame
	
	var btns = [
		get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowRight"),
		get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowLeft"),
		get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowRight"),
		btn_prev,
		btn_next,
	]
	for btn in btns:
		if btn:
			btn.pivot_offset = btn.size / 2
	
	skin_states.append(2)
	skin_states.append(1)
	for i in range(TOTAL_SKINS - 2):
		skin_states.append(0)
	
	active_skin_index = 0
	
	await get_tree().process_frame
	_setup_skin_grid(grid_page1, 0)
	_setup_skin_grid(grid_page2, 12)
	
	await get_tree().process_frame
	_setup_premium_grid()
	
	panel_collection.visible = true
	panel_premium.visible = false
	grid_page2.visible = false
	
	_update_dots()
	_update_nav_buttons()
	_apply_skin_states()
	
	# Start animacji dla domyślnie aktywnego skina
	var first_skin = grid_page1.get_child(0)
	if first_skin:
		active_skin_ctrl = first_skin
		active_skin_base_y = first_skin.position.y
		_start_active_animation(first_skin)

# ————— SETUP GRIDU —————

func _setup_skin_grid(grid: Control, offset: int):
	for i in range(grid.get_child_count()):
		var skin_ctrl = grid.get_child(i)
		var skin_index = offset + i
		skin_ctrl.pivot_offset = skin_ctrl.size / 2
		
		var btn_buy = skin_ctrl.get_node_or_null("TextureButton_Buy")
		if btn_buy:
			btn_buy.pivot_offset = btn_buy.size / 2
			# Hover TYLKO na przycisku
			btn_buy.mouse_entered.connect(_on_buy_btn_mouse_entered.bind(btn_buy))
			btn_buy.mouse_exited.connect(_on_buy_btn_mouse_exited.bind(btn_buy))
			btn_buy.pressed.connect(_on_buy_pressed.bind(skin_index, skin_ctrl))

# ————— STANY SKINÓW —————

func _apply_skin_states():
	_apply_grid_states(grid_page1, 0)
	_apply_grid_states(grid_page2, 12)

func _apply_grid_states(grid: Control, offset: int):
	for i in range(grid.get_child_count()):
		var skin_ctrl = grid.get_child(i)
		var skin_index = offset + i
		if skin_index >= TOTAL_SKINS:
			break
		var btn_buy = skin_ctrl.get_node_or_null("TextureButton_Buy")
		if not btn_buy:
			continue
		match skin_states[skin_index]:
			0:
				btn_buy.texture_normal = tex_buy
				btn_buy.disabled = false
				btn_buy.modulate = Color(1, 1, 1, 1)
			1:
				btn_buy.texture_normal = tex_equip
				btn_buy.disabled = false
				btn_buy.modulate = Color(1, 1, 1, 1)
			2:
				btn_buy.texture_normal = tex_active
				btn_buy.disabled = true
				btn_buy.modulate = Color(0.6, 0.6, 0.6, 1)

func _on_buy_pressed(skin_index: int, skin_ctrl: Control):
	sound_click.play()
	var state = skin_states[skin_index]
	match state:
		0:
			skin_states[skin_index] = 1
		1:
			# Zatrzymaj animację poprzedniego aktywnego
			if skin_states[active_skin_index] == 2:
				skin_states[active_skin_index] = 1
				_stop_active_animation()
			skin_states[skin_index] = 2
			active_skin_index = skin_index
			active_skin_ctrl = skin_ctrl
			active_skin_base_y = skin_ctrl.position.y
			_start_active_animation(skin_ctrl)
		2:
			return
	_apply_skin_states()

# ————— ANIMACJA AKTYWNEGO SKINA —————

func _start_active_animation(skin_ctrl: Control):
	_stop_active_animation()
	var base_y = skin_ctrl.position.y
	active_tween = create_tween()
	active_tween.set_loops()
	active_tween.tween_property(skin_ctrl, "position:y", base_y - 8.0, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	active_tween.tween_property(skin_ctrl, "position:y", base_y, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_active_animation():
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		active_tween = null
	if active_skin_ctrl:
		active_skin_ctrl.position.y = active_skin_base_y

# ————— HOVER TYLKO NA PRZYCISKU —————

func _on_buy_btn_mouse_entered(btn: TextureButton):
	_scale_button(btn, 0.9)

func _on_buy_btn_mouse_exited(btn: TextureButton):
	_scale_button(btn, 1.0)

# ————— STRZAŁKI PANELI —————

func _on_arrow_left_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, -1)
	else:
		_switch_panels(false, -1)

func _on_arrow_right_pressed():
	sound_click.play()
	if current_panel == 0:
		_switch_panels(true, 1)
	else:
		_switch_panels(false, 1)

func _switch_panels(go_to_premium: bool, direction: int):
	if go_to_premium:
		current_panel = 1
		_animate_panels(panel_collection, panel_premium, direction)
	else:
		current_panel = 0
		_animate_panels(panel_premium, panel_collection, direction)
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

# ————— PREV / NEXT —————

func _on_previous_pressed():
	if current_page == 0:
		return
	sound_click.play()
	current_page = 0
	_slide_grids(grid_page2, grid_page1, 1)

func _on_next_pressed():
	if current_page == 1:
		return
	sound_click.play()
	current_page = 1
	_slide_grids(grid_page1, grid_page2, -1)

func _slide_grids(grid_out: Control, grid_in: Control, direction: int):
	grid_in.visible = true
	grid_in.position = Vector2(GRID_X + (grid_in.size.x * -direction), GRID_Y)
	grid_in.modulate.a = 0.0
	_update_nav_buttons()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(grid_out, "position:x", GRID_X + (grid_out.size.x * direction), 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(grid_out, "modulate:a", 0.0, 0.2)
	tween.tween_property(grid_in, "position:x", GRID_X, 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(grid_in, "modulate:a", 1.0, 0.2)
	await tween.finished
	grid_out.visible = false
	grid_out.position = Vector2(GRID_X, GRID_Y)
	grid_out.modulate.a = 1.0

func _update_nav_buttons():
	btn_prev.disabled = (current_page == 0)
	btn_prev.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 0 else Color(1, 1, 1, 1)
	btn_next.disabled = (current_page == 1)
	btn_next.modulate = Color(0.5, 0.5, 0.5, 1) if current_page == 1 else Color(1, 1, 1, 1)

# ————— HOVER STRZAŁKI —————

func _on_arrow_left_collection_mouse_entered():
	_scale_button(get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowLeft"), 0.9)

func _on_arrow_left_collection_mouse_exited():
	_scale_button(get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowLeft"), 1.0)

func _on_arrow_right_collection_mouse_entered():
	_scale_button(get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowRight"), 0.9)

func _on_arrow_right_collection_mouse_exited():
	_scale_button(get_node_or_null("Control_Collection/HBoxContainer_Top/TextureButton_ArrowRight"), 1.0)

func _on_arrow_left_premium_mouse_entered():
	_scale_button(get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowLeft"), 0.9)

func _on_arrow_left_premium_mouse_exited():
	_scale_button(get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowLeft"), 1.0)

func _on_arrow_right_premium_mouse_entered():
	_scale_button(get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowRight"), 0.9)

func _on_arrow_right_premium_mouse_exited():
	_scale_button(get_node_or_null("Control_Premium/HBoxContainer_Top/TextureButton_ArrowRight"), 1.0)

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


# ————— PREMIUM —————

func _setup_premium_grid():
	var grid = get_node_or_null("Control_Premium/GridContainer_Premium")
	if not grid:
		return
	for item in grid.get_children():
		item.pivot_offset = item.size / 2
		
		# Obracające się promienie
		var rays = item.get_node_or_null("Control_Icon/TextureRect_Rays")
		if rays:
			rays.pivot_offset = rays.size / 2
			_start_rays_rotation(rays)
		
		# Hover + animacja na przycisk
		var btn = item.get_node_or_null("TextureButton_Buy")
		if btn:
			btn.pivot_offset = btn.size / 2
			btn.mouse_entered.connect(_on_buy_btn_mouse_entered.bind(btn))
			btn.mouse_exited.connect(_on_buy_btn_mouse_exited.bind(btn))
			btn.pressed.connect(_on_premium_buy_pressed.bind(item))

func _start_rays_rotation(rays: TextureRect):
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rays, "rotation_degrees", 360.0, 4.0)\
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(rays, "rotation_degrees", 0.0, 0.0)

func _on_premium_buy_pressed(item: Control):
	sound_click.play()
	_squish_item(item)

func _squish_item(item: Control):
	var tween = create_tween()
	tween.tween_property(item, "scale", Vector2(1.1, 0.9), 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", Vector2(1.0, 1.0), 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
