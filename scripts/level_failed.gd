extends Control

# ————— DANE —————
var level_name = "LEVEL 1"
var score = 0
var is_online_mode: bool = false

# ————— WĘZŁY —————
@onready var overlay = $ColorRect_Overlay
@onready var popup = $Control_Popup
@onready var label_level = $Control_Popup/Label_LevelName
@onready var label_score = $Control_Popup/VBoxContainer/VBoxContainer/Panel_ScoreBG/Label_Score
@onready var btn_replay = $Control_Popup/TextureButton_Replay
@onready var btn_exit = $Control_Popup/TextureButton_Exit
@onready var sound_click = $"../SoundClick"
@onready var sound_lose = $"../AudioStreamPlayer_Lose"  # <-- NOWY: sounds/lose.mp3, bus=Sound
@onready var sound_lose2 = $"../AudioStreamPlayer_Lose2"

func _ready():
	label_level.text = level_name
	label_score.text = "0"
	label_score.modulate.a = 0.0
	
	overlay.modulate.a = 0.0
	popup.scale = Vector2(0.0, 0.0)
	popup.pivot_offset = popup.size / 2
	
	await get_tree().process_frame
	popup.pivot_offset = popup.size / 2
	btn_replay.pivot_offset = btn_replay.size / 2
	btn_exit.pivot_offset = btn_exit.size / 2

	# Odegraj dźwięk przegranej
	if sound_lose:
		sound_lose.play()
	if sound_lose2:
		sound_lose2.play()

	# Wycisz muzykę w tle
	MusicManager.stop_music()
	
	_run_intro()

func _run_intro():
	# Overlay fade in
	var tween1 = create_tween()
	tween1.tween_property(overlay, "modulate:a", 0.7, 0.3)
	await tween1.finished
	
	# Popup bounce
	var tween2 = create_tween()
	tween2.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween2.finished
	# Pokaż i policz score
	label_score.modulate.a = 1.0
	_animate_counter(label_score, 0, score, 1.2)

# ————— LICZNIK —————

func _animate_counter(label: Label, from: int, to: int, duration: float):
	var tween = create_tween()
	tween.tween_method(
		func(v: float): label.text = str(int(v)),
		float(from), float(to), duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ————— PRZYCISKI —————

func _on_replay_pressed():
	if sound_lose and sound_lose.playing:
		sound_lose.stop()
	if sound_lose2 and sound_lose2.playing:
		sound_lose2.stop()
	sound_click.play()
	await sound_click.finished
	queue_free()
	if is_online_mode:
		PlayerData.online_mode = false
		SceneTransition.go_to("res://scenes/modes.tscn")
	else:
		PlayerData.launch_level(PlayerData.current_level_index)

func _on_replay_mouse_entered():
	_scale_button(btn_replay, 0.9)

func _on_replay_mouse_exited():
	_scale_button(btn_replay, 1.0)

func _on_exit_pressed():
	if sound_lose and sound_lose.playing:
		sound_lose.stop()
	if sound_lose2 and sound_lose2.playing:
		sound_lose2.stop()
	sound_click.play()
	await sound_click.finished
	PlayerData.online_mode = false
	SceneTransition.go_to("res://scenes/play.tscn")

func _on_exit_mouse_entered():
	_scale_button(btn_exit, 0.9)

func _on_exit_mouse_exited():
	_scale_button(btn_exit, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
