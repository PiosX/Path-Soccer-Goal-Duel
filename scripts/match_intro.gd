extends Control

# ————— WĘZŁY —————
@onready var tex_red = $TextureRect_Red
@onready var tex_blue = $TextureRect_Blue
@onready var panel_line = $Panel_Line
@onready var panel_vs = $Panel_VS
@onready var ctrl1 = $Control_Player1
@onready var ctrl2 = $Control_Player2
@onready var label_name1 = $Control_Player1/VBoxContainer/Label_Name1
@onready var label_rank1 = $Control_Player1/VBoxContainer/Label_Rank1
@onready var label_name2 = $Control_Player2/VBoxContainer/Label_Name2
@onready var label_rank2 = $Control_Player2/VBoxContainer/Label_Rank2

const SCREEN_H = 1280.0

func _ready():
	# Ukryj wszystko na start
	tex_red.position.y = -SCREEN_H
	tex_blue.position.y = SCREEN_H + 432.0
	panel_line.modulate.a = 0.0
	panel_vs.modulate.a = 0.0
	panel_vs.scale = Vector2(0.0, 0.0)
	ctrl1.modulate.a = 0.0
	ctrl2.modulate.a = 0.0

	await get_tree().process_frame

	# Pobierz moją rangę z PlayFab (jeśli jeszcze nie mamy)
	if PlayerData.my_rank == "#0":
		await PlayerData.fetch_my_rank()

	# Losuj kto jest Player1 (niebieski, zaczyna) — 50/50
	# player1_decided resetuje się w launch_online_duel co sesję gry
	if not PlayerData.player1_decided:
		PlayerData.player1_is_me = (randi() % 2 == 0)
		PlayerData.player1_decided = true

	# Ustaw dane graczy w UI
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var my_nick = cfg.get_value("session", "nick", "YOU")
	var opponent_name = PlayerData.online_opponent_name if PlayerData.online_opponent_name != "" else "BOT"
	var opponent_rank = PlayerData.online_opponent_rank if PlayerData.online_opponent_name != "" else "#0"

	# ctrl1 = góra-lewa (czerwona strona), ctrl2 = dół-prawa (niebieska strona)
	if PlayerData.player1_is_me:
		# Ja jestem niebieski (Player1, zaczyna) — idę do ctrl2 (dół-prawa/niebieski)
		label_name1.text = opponent_name
		label_rank1.text = opponent_rank
		label_name2.text = my_nick
		label_rank2.text = PlayerData.my_rank
	else:
		# Ja jestem czerwony (Player2) — idę do ctrl1 (góra-lewa/czerwony)
		label_name1.text = my_nick
		label_rank1.text = PlayerData.my_rank
		label_name2.text = opponent_name
		label_rank2.text = opponent_rank

	# Fade in po przejściu z modes
	SceneTransition.fade_in_only()
	_run_intro()

func _run_intro():
	# KROK 1 — tła wjeżdżają (0.7s)
	var tween1 = create_tween()
	tween1.set_parallel(true)
	tween1.tween_property(tex_red, "position:y", 0.0, 0.7)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween1.tween_property(tex_blue, "position:y", 432.0, 0.7)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween1.finished

	# KROK 2 — linia (0.25s)
	var tween2 = create_tween()
	tween2.tween_property(panel_line, "modulate:a", 1.0, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween2.finished

	# KROK 3 — VS wyskakuje (0.4s)
	var tween3 = create_tween()
	tween3.set_parallel(true)
	tween3.tween_property(panel_vs, "modulate:a", 1.0, 0.2)
	tween3.tween_property(panel_vs, "scale", Vector2(1.0, 1.0), 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween3.finished

	# KROK 4 — gracze wjeżdżają z boków (0.4s)
	var p1_target_x = ctrl1.position.x
	ctrl1.position.x = -400.0
	var p2_target_x = ctrl2.position.x
	ctrl2.position.x = 1200.0

	var tween4 = create_tween()
	tween4.set_parallel(true)
	tween4.tween_property(ctrl1, "modulate:a", 1.0, 0.4)
	tween4.tween_property(ctrl1, "position:x", p1_target_x, 0.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween4.tween_property(ctrl2, "modulate:a", 1.0, 0.4)
	tween4.tween_property(ctrl2, "position:x", p2_target_x, 0.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween4.finished

	# KROK 5 — pauza i przejście do gry (fade)
	await get_tree().create_timer(1.2).timeout
	SceneTransition.go_to("res://scenes/game.tscn")
