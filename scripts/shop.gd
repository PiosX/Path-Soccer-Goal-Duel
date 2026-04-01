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
# tex_buy jest ładowany dynamicznie per skin (wg ceny) — patrz _get_price_texture()
var tex_equip = preload("res://ui/shop/equip.png")
var tex_active = preload("res://ui/shop/active.png")

# Cache tekstur cen — klucz = cena (int), wartość = Texture2D
var _price_tex_cache: Dictionary = {}

func _get_price_texture(price: int) -> Texture2D:
	if _price_tex_cache.has(price):
		return _price_tex_cache[price]
	var path = "res://ui/shop/prices/%d.png" % price
	var tex = load(path)
	if tex == null:
		# Fallback — pierwsza dostępna tekstura ceny
		tex = load("res://ui/shop/prices/100.png")
	_price_tex_cache[price] = tex
	return tex

# ————— CENY SKINÓW —————
# Skin 1 jest zawsze darmowy (domyślny). Skiny 2-8 = rarity1, 9-16 = rarity2, 17-20 = rarity3
# Max gold z premium = 10 000. Za wygraną ~50-200 gold.
# Rarity1 (2-8):  tanie, dostępne szybko
# Rarity2 (9-16): średnie, kilka godzin gry
# Rarity3 (17-20): premium, długi grind lub premium shop
const SKIN_PRICES = [
	0,     # skin 1  — domyślny, zawsze odblokowany
	100,   # skin 2  — rarity1
	150,   # skin 3  — rarity1
	200,   # skin 4  — rarity1
	300,   # skin 5  — rarity1
	350,   # skin 6  — rarity1
	400,   # skin 7  — rarity1
	450,   # skin 8  — rarity1
	600,   # skin 9  — rarity2
	800,  # skin 10 — rarity2
	1000,  # skin 11 — rarity2
	1100,  # skin 12 — rarity2
	1200,  # skin 13 — rarity2
	1300,  # skin 14 — rarity2
	1500,  # skin 15 — rarity2
	1700,  # skin 16 — rarity2
	2100,  # skin 17 — rarity3
	2500,  # skin 18 — rarity3
	3000,  # skin 19 — rarity3
	4000,  # skin 20 — rarity3
]

# ————— STAN —————
var current_panel = 0
var current_page = 0

var skin_states = []   # 0=locked, 1=owned, 2=equipped
const TOTAL_SKINS = 20
var active_skin_index = 0
var active_tween: Tween = null
var active_skin_ctrl: Control = null
var active_skin_base_y: float = 0.0
var player_gold: int = 0

func _ready():
	await get_tree().process_frame
	MusicManager.play_music("res://sounds/music.mp3")

	# Wczytaj gold z session.cfg
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") == OK:
		player_gold = cfg.get_value("session", "gold", 0)

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

	# Wczytaj stany skinów (owned + equipped) z PlayFab/session
	_load_skin_states()

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

	# Start animacji dla aktywnego skina
	var page = 0 if active_skin_index < 12 else 1
	var grid = grid_page1 if page == 0 else grid_page2
	var idx_in_grid = active_skin_index if page == 0 else active_skin_index - 12
	if idx_in_grid < grid.get_child_count():
		var skin_ctrl = grid.get_child(idx_in_grid)
		active_skin_ctrl = skin_ctrl
		active_skin_base_y = skin_ctrl.position.y
		_start_active_animation(skin_ctrl)

# ————— WCZYTAJ STANY SKINÓW —————

func _load_skin_states():
	skin_states.clear()
	for i in range(TOTAL_SKINS):
		skin_states.append(0)

	# Skin 1 zawsze odblokowany
	skin_states[0] = 1

	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		skin_states[0] = 2
		active_skin_index = 0
		return

	# Wczytaj kupione skiny
	var owned_str: String = cfg.get_value("session", "owned_skins", "0")
	for part in owned_str.split(","):
		var idx = int(part.strip_edges())
		if idx >= 0 and idx < TOTAL_SKINS:
			skin_states[idx] = 1

	# Wczytaj aktywny skin
	var equipped = cfg.get_value("session", "equipped_skin", 0)
	if equipped >= 0 and equipped < TOTAL_SKINS and skin_states[equipped] >= 1:
		active_skin_index = equipped
		skin_states[equipped] = 2
	else:
		active_skin_index = 0
		skin_states[0] = 2

# ————— SETUP GRIDU —————

func _setup_skin_grid(grid: Control, offset: int):
	for i in range(grid.get_child_count()):
		var skin_ctrl = grid.get_child(i)
		var skin_index = offset + i
		if skin_index >= TOTAL_SKINS:
			break
		skin_ctrl.pivot_offset = skin_ctrl.size / 2

		var btn_buy = skin_ctrl.get_node_or_null("TextureButton_Buy")
		if btn_buy:
			btn_buy.pivot_offset = btn_buy.size / 2
			btn_buy.mouse_entered.connect(_on_buy_btn_mouse_entered.bind(btn_buy))
			btn_buy.mouse_exited.connect(_on_buy_btn_mouse_exited.bind(btn_buy))
			btn_buy.pressed.connect(_on_buy_pressed.bind(skin_index, skin_ctrl))

		# Ustaw teksturę ceny (lub domyślną)
		_update_price_label(skin_ctrl, skin_index)

# ————— ETYKIETA CENY —————

func _update_price_label(skin_ctrl: Control, skin_index: int):
	var lbl = skin_ctrl.get_node_or_null("Label_Price")
	if lbl:
		var price = SKIN_PRICES[skin_index]
		if price == 0:
			lbl.text = "FREE"
		else:
			lbl.text = str(price) + " g"

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
		var price = SKIN_PRICES[skin_index]
		match skin_states[skin_index]:
			0:  # do kupienia
				btn_buy.texture_normal = _get_price_texture(price)
				if player_gold >= price:
					btn_buy.disabled = false
					btn_buy.modulate = Color(1, 1, 1, 1)
				else:
					btn_buy.disabled = true
					btn_buy.modulate = Color(0.5, 0.5, 0.5, 1)
			1:  # kupiony, można założyć
				btn_buy.texture_normal = tex_equip
				btn_buy.disabled = false
				btn_buy.modulate = Color(1, 1, 1, 1)
			2:  # aktywny
				btn_buy.texture_normal = tex_active
				btn_buy.disabled = true
				btn_buy.modulate = Color(0.6, 0.6, 0.6, 1)

func _on_buy_pressed(skin_index: int, skin_ctrl: Control):
	sound_click.play()
	var state = skin_states[skin_index]
	var price = SKIN_PRICES[skin_index]
	match state:
		0:  # kup za gold
			if player_gold < price:
				return
			player_gold -= price
			skin_states[skin_index] = 1
			# Zapisz gold do session.cfg
			var cfg = ConfigFile.new()
			cfg.load("user://session.cfg")
			cfg.set_value("session", "gold", player_gold)
			# Dodaj do owned_skins
			var owned_str: String = cfg.get_value("session", "owned_skins", "0")
			var owned_set: Array = []
			for part in owned_str.split(","):
				var idx = int(part.strip_edges())
				if not owned_set.has(idx):
					owned_set.append(idx)
			if not owned_set.has(skin_index):
				owned_set.append(skin_index)
			cfg.set_value("session", "owned_skins", _owned_to_string(owned_set))
			cfg.save("user://session.cfg")
			# Zaktualizuj label goldów jeśli jest na scenie
			var label_coins = get_node_or_null("HBoxContainer_Coins/Label")
			if label_coins:
				label_coins.text = str(player_gold)
			# Wyślij do PlayFab
			PlayerData.save_skin_data_to_playfab()
		1:  # załóż skin
			if skin_states[active_skin_index] == 2:
				skin_states[active_skin_index] = 1
				_stop_active_animation()
			skin_states[skin_index] = 2
			active_skin_index = skin_index
			active_skin_ctrl = skin_ctrl
			active_skin_base_y = skin_ctrl.position.y
			_start_active_animation(skin_ctrl)
			# Zapisz equipped skin
			var cfg = ConfigFile.new()
			cfg.load("user://session.cfg")
			cfg.set_value("session", "equipped_skin", skin_index)
			cfg.save("user://session.cfg")
			# Wyślij do PlayFab
			PlayerData.save_skin_data_to_playfab()
		2:
			return
	_apply_skin_states()

func _owned_to_string(arr: Array) -> String:
	var parts = []
	for v in arr:
		parts.append(str(v))
	return ",".join(parts)

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
	grid_out.position.x = target_pos.x
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
