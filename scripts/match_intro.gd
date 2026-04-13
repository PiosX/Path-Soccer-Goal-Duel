extends Control

# ————— WĘZŁY —————
@onready var tex_bg = $TextureRect
@onready var panel_vs = $Panel_VS
@onready var ctrl1 = $Control_Player1
@onready var ctrl2 = $Control_Player2
@onready var label_name1 = $Control_Player1/VBoxContainer/Label_Name1
@onready var label_rank1 = $Control_Player1/VBoxContainer/Label_Rank1
@onready var label_name2 = $Control_Player2/VBoxContainer/Label_Name2
@onready var label_rank2 = $Control_Player2/VBoxContainer/Label_Rank2
@onready var sound_intro = $AudioStreamPlayer_Intro

const INTRO_SOUND_OFFSET: float = 0.1

func _ready():
	tex_bg.modulate.a = 0.0
	panel_vs.modulate.a = 0.0
	panel_vs.scale = Vector2(0.0, 0.0)
	ctrl1.modulate.a = 0.0
	ctrl2.modulate.a = 0.0

	await get_tree().process_frame

	if PlayerData.my_rank == "#0":
		await PlayerData.fetch_my_rank()

	if not PlayerData.player1_decided:
		PlayerData.player1_is_me = (randi() % 2 == 0)
		PlayerData.player1_decided = true

	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var my_nick = cfg.get_value("session", "nick", "YOU")
	var opponent_name = PlayerData.online_opponent_name if PlayerData.online_opponent_name != "" else "BOT"
	var opponent_rank = PlayerData.online_opponent_rank if PlayerData.online_opponent_name != "" else "#0"

	if PlayerData.player1_is_me:
		label_name1.text = opponent_name
		label_rank1.text = opponent_rank
		label_name2.text = my_nick
		label_rank2.text = PlayerData.my_rank
	else:
		label_name1.text = my_nick
		label_rank1.text = PlayerData.my_rank
		label_name2.text = opponent_name
		label_rank2.text = opponent_rank

	SceneTransition.fade_in_only()
	_run_intro()

func _run_intro():
	var fade_duration = 0.7

	if INTRO_SOUND_OFFSET < 0.0 and sound_intro:
		sound_intro.play()
		await get_tree().create_timer(-INTRO_SOUND_OFFSET).timeout

	# KROK 1 — tło fade in
	var tween1 = create_tween()
	tween1.tween_property(tex_bg, "modulate:a", 1.0, fade_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if INTRO_SOUND_OFFSET >= 0.0:
		tween1.tween_callback(func():
			if sound_intro:
				sound_intro.play()
		).set_delay(fade_duration + INTRO_SOUND_OFFSET)

	await tween1.finished

	# KROK 2 — VS wyskakuje
	var tween2 = create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(panel_vs, "modulate:a", 1.0, 0.2)
	tween2.tween_property(panel_vs, "scale", Vector2(1.0, 1.0), 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween2.finished

	# KROK 3 — gracze wjeżdżają z boków
	var p1_target_x = ctrl1.position.x
	ctrl1.position.x = -400.0
	var p2_target_x = ctrl2.position.x
	ctrl2.position.x = 1200.0

	var tween3 = create_tween()
	tween3.set_parallel(true)
	tween3.tween_property(ctrl1, "modulate:a", 1.0, 0.4)
	tween3.tween_property(ctrl1, "position:x", p1_target_x, 0.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween3.tween_property(ctrl2, "modulate:a", 1.0, 0.4)
	tween3.tween_property(ctrl2, "position:x", p2_target_x, 0.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween3.finished

	# KROK 4 — pauza i przejście do gry
	await get_tree().create_timer(1.2).timeout
	SceneTransition.go_to("res://scenes/game.tscn")
