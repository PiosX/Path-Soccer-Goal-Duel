extends Control

# ————— DANE GRACZY —————
var player1_name = "PLAYER_1"
var player1_rank = "#42"
var player2_name = "PLAYER_2"
var player2_rank = "#87"

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
	# Ustaw dane graczy
	label_name1.text = player1_name
	label_rank1.text = player1_rank
	label_name2.text = player2_name
	label_rank2.text = player2_rank
	
	# Ukryj wszystko na start
	tex_red.position.y = -SCREEN_H
	tex_blue.position.y = SCREEN_H + 432.0
	panel_line.modulate.a = 0.0
	panel_vs.modulate.a = 0.0
	panel_vs.scale = Vector2(0.0, 0.0)
	ctrl1.modulate.a = 0.0
	ctrl2.modulate.a = 0.0
	
	await get_tree().process_frame
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

	# KROK 4 — gracze wjeżdżają (0.4s)
	# Player1 z lewej
	var p1_target_x = ctrl1.position.x
	ctrl1.position.x = -400.0
	# Player2 z prawej
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

	# KROK 5 — pauza i przejście do gry
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file("res://scenes/game.tscn")
