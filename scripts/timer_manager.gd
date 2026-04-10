extends CanvasLayer

var is_searching = false
var search_time = 0.0
var timer_ui: Control
var label: Label
var _modes_active: bool = false

func _ready():
	timer_ui = $SearchTimerUI
	label = $SearchTimerUI/Label
	timer_ui.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	
	_reposition_timer()
	
	PlayerData.matchmaking_found.connect(_on_matchmaking_found)
	PlayerData.matchmaking_timeout.connect(_on_matchmaking_timeout)

func _reposition_timer():
	var nav2 = get_tree().root.find_child("TextureButton_Nav2", true, false)
	if nav2:
		var pos = nav2.get_screen_position()
		var h = get_viewport().get_visible_rect().size.y
		var nav2_y_ratio = pos.y / h
		
		# Podaj ręcznie rozmiar SearchTimerUI z edytora
		var timer_w = 64.0  # ← zmień na rzeczywistą szerokość
		var timer_h = 28.0   # ← zmień na rzeczywistą wysokość
		
		timer_ui.position = Vector2(
			pos.x + (nav2.size.x / 2) - (timer_w / 2),
			h * nav2_y_ratio - timer_h + 16
		)
	else:
		var h = get_viewport().get_visible_rect().size.y
		timer_ui.position = Vector2(181 + 65, h * (1092.0 / 1280.0))

func _process(delta):
	if is_searching:
		search_time += delta
		var minutes = int(search_time) / 60
		var seconds = int(search_time) % 60
		label.text = "%02d:%02d" % [minutes, seconds]

func start_search():
	is_searching = true
	search_time = 0.0
	timer_ui.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_reposition_timer()

func stop_search():
	is_searching = false
	timer_ui.visible = false

func on_modes_enter():
	_modes_active = true

func on_modes_exit():
	_modes_active = false

func _on_matchmaking_found():
	if _modes_active:
		return  # modes obsłuży to sam przez swój CONNECT_ONE_SHOT
	stop_search()
	PlayerData.launch_online_duel()

func _on_matchmaking_timeout():
	if _modes_active:
		return  # modes obsłuży to sam
	stop_search()
	PlayerData.online_opponent_name = ""
	PlayerData.launch_online_duel()
