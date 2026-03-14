extends CanvasLayer

var is_searching = false
var search_time = 0.0
var timer_ui: Control
var label: Label

func _ready():
	timer_ui = $SearchTimerUI
	label = $SearchTimerUI/Label
	timer_ui.visible = false
	await get_tree().process_frame
	timer_ui.position = Vector2(181 + 65, 1072+20)


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
