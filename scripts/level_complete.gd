extends Control

# ————— DANE (ustaw przed instancjonowaniem) —————
var level_name = "LEVEL 1"
var score = 12500
var reward = 200
var completed_level_index: int = 1
var is_online_mode: bool = false

# ————— TEXTURY —————
var tex_btn_ok = preload("res://ui/common/ok-btn.png")

# ————— WĘZŁY —————
@onready var sound_click = $"../SoundClick"
@onready var sound_win = $"../AudioStreamPlayer_Win"  # <-- NOWY: sounds/win.mp3, bus=Sound
@onready var overlay = $ColorRect_Overlay
@onready var popup = $Control_Popup
@onready var rays = $Control_Popup/TextureRect_Rays
@onready var label_level = $Control_Popup/Label_LevelName
@onready var label_complete = $Control_Popup/Label_Complete
@onready var label_score = $Control_Popup/VBoxContainer/VBoxContainer/Panel_ScoreBG/Label_Score
@onready var label_amount = $Control_Popup/VBoxContainer/VBoxContainer2/HBoxContainer_Reward/Label_Amount
@onready var btn_next = $Control_Popup/TextureButton_Next
@onready var sound_win2 = $"../AudioStreamPlayer_Win2"

# ————— FONT —————
var font = preload("res://fonts/Digitalt.ttf")
var tex_rays = preload("res://ui/common/intersect-win.png")

func _ready():
	# Ustaw teksturę promieni
	rays.texture = tex_rays
	rays.pivot_offset = rays.size / 2

	# W trybie online zmień przycisk Next na OK → modes
	if is_online_mode:
		btn_next.texture_normal = tex_btn_ok

	# Ustaw dane
	label_level.text = level_name
	label_score.text = "0"
	label_amount.text = "0"
	label_score.modulate.a = 0.0
	label_amount.modulate.a = 0.0
	
	# Ukryj na start
	overlay.modulate.a = 0.0
	popup.scale = Vector2(0.0, 0.0)
	popup.pivot_offset = popup.size / 2
	rays.modulate.a = 0.0
	
	# Pivot przycisku
	await get_tree().process_frame
	popup.pivot_offset = popup.size / 2
	rays.pivot_offset = rays.size / 2
	btn_next.pivot_offset = btn_next.size / 2

	# Odegraj dźwięk wygranej
	if sound_win:
		sound_win.play()
	
	if sound_win2:
		sound_win2.play(15.0)
		get_tree().create_timer(22.0).timeout.connect(func(): if is_instance_valid(sound_win2): sound_win2.stop())

	# Wycisz muzykę w tle
	MusicManager.stop_music()
	
	_run_intro()

func _run_intro():
	# KROK 1 — overlay fade in (0.3s)
	var tween1 = create_tween()
	tween1.tween_property(overlay, "modulate:a", 0.7, 0.3)
	await tween1.finished

	# KROK 2 — popup wyskakuje z bounce (0.5s)
	var tween2 = create_tween()
	tween2.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween2.finished

	# KROK 3 — promienie się pojawiają i zaczynają kręcić
	_start_rays_rotation()
	var tween3 = create_tween()
	tween3.tween_property(rays, "modulate:a", 1.0, 0.4)
	await tween3.finished

	# KROK 4 — licznik score (1.5s)
	await get_tree().create_timer(0.2).timeout
	label_score.modulate.a = 1.0
	_animate_counter(label_score, 0, score, 1.5)
	await get_tree().create_timer(0.5).timeout

	# KROK 5 — licznik reward (1.5s)
	label_amount.modulate.a = 1.0
	_animate_counter(label_amount, 0, reward, 1.5)

# ————— ROTACJA PROMIENI —————

func _start_rays_rotation():
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rays, "rotation_degrees", 360.0, 6.0)\
		.set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): rays.rotation_degrees = 0.0)

# ————— ANIMOWANY LICZNIK —————

func _animate_counter(label: Label, from: int, to: int, duration: float):
	var tween = create_tween()
	tween.tween_method(
		func(v: float): label.text = str(int(v)),
		float(from), float(to), duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ————— PRZYCISK NEXT —————

var scene_rating = preload("res://scenes/rating.tscn")

# Zapisz co zrobic po zamknieciu rating popup
var _next_level_after_rating: int = 0
var _online_after_rating: bool = false

func _on_next_pressed():
	if sound_win and sound_win.playing:
		sound_win.stop()
	if sound_win2 and sound_win2.playing:
		sound_win2.stop()
	sound_click.play()
	queue_free()
	# Pokaż Rate Us po 5. poziomie kampanii (nie w online)
	if not is_online_mode and completed_level_index >= 5 and RatingNode.should_show():
		_next_level_after_rating = completed_level_index + 1
		_show_rating_popup()
		return
	_go_next()

func _go_next():
	if is_online_mode:
		PlayerData.online_mode = false
		SceneTransition.go_to("res://scenes/modes.tscn")
	else:
		var next_level = completed_level_index + 1
		PlayerData.launch_level(next_level)

func _show_rating_popup():
	var rating_node = scene_rating.instantiate()
	# Podłącz sygnał zamknięcia — po zamknięciu popupu przejdź dalej
	rating_node.connect("closed", Callable(self, "_on_rating_closed"))
	get_tree().root.add_child(rating_node)

func _on_rating_closed():
	if is_online_mode:
		PlayerData.online_mode = false
		SceneTransition.go_to("res://scenes/modes.tscn")
	else:
		PlayerData.launch_level(_next_level_after_rating)

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
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
