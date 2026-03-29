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
	timer_ui.position = Vector2(181 + 65, 1072+20)
	# Permanentne nasłuchiwanie — odpali się tylko gdy modes NIE jest aktywne
	PlayerData.matchmaking_found.connect(_on_matchmaking_found)
	PlayerData.matchmaking_timeout.connect(_on_matchmaking_timeout)

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
