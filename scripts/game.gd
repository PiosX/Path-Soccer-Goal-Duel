extends Control

@onready var sound_click = $SoundClick
@onready var btn_settings = $VBoxContainer/Button_Settings

var settings_popup_scene = preload("res://scenes/settings.tscn")

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame  # dwa frame'y — layout musi być policzony

	if btn_settings:
		btn_settings.pivot_offset = btn_settings.size / 2

	# Fade in po wczytaniu sceny
	if SceneTransition:
		SceneTransition.fade_in_only()

	await _update_ui()

func _update_ui():
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	var my_nick = cfg.get_value("session", "nick", "Player")
	var gold    = cfg.get_value("session", "gold", 0)

	# Coiny
	var label_coins = get_node_or_null("HBoxContainer_Coins/Label")
	if label_coins:
		label_coins.text = str(gold)
		
	await PlayerData.fetch_my_rank()

	if PlayerData.online_mode:
		# ————— TRYB ONLINE —————
		# Losuj kto jest Player1 (niebieski, zaczyna) — 50/50
		# Zapisz wynik w PlayerData żeby board i match_intro mogły go użyć
		if not PlayerData.player1_decided:
			PlayerData.player1_is_me = (randi() % 2 == 0)
			PlayerData.player1_decided = true

		var me_is_p1 = PlayerData.player1_is_me
		var opponent_name = PlayerData.online_opponent_name if PlayerData.online_opponent_name != "" else "BOT"
		var opponent_rank = PlayerData.online_opponent_rank if PlayerData.online_opponent_name != "" else "#0"

		# Player1 = niebieski (zaczyna), Player2 = czerwony
		var p1_name = my_nick   if me_is_p1 else opponent_name
		var p1_rank = PlayerData.my_rank if me_is_p1 else opponent_rank
		var p2_name = opponent_name if me_is_p1 else my_nick
		var p2_rank = opponent_rank if me_is_p1 else PlayerData.my_rank

		_set_label("HBoxContainer_Players/VBoxContainer_Player1/Player1_Name", p1_name)
		_set_label("HBoxContainer_Players/VBoxContainer_Player1/Player1_Rank", p1_rank)
		_set_label("HBoxContainer_Players/VBoxContainer_Player2/Player2_Name", p2_name)
		_set_label("HBoxContainer_Players/VBoxContainer_Player2/Player2_Rank", p2_rank)
	else:
		# ————— TRYB KAMPANII —————
		_set_label("HBoxContainer_Players/VBoxContainer_Player1/Player1_Name", my_nick)
		_set_label("HBoxContainer_Players/VBoxContainer_Player1/Player1_Rank", PlayerData.my_rank)
		_set_label("HBoxContainer_Players/VBoxContainer_Player2/Player2_Name", "BOT")
		_set_label("HBoxContainer_Players/VBoxContainer_Player2/Player2_Rank", "#0")

func _set_label(path: String, text: String):
	var lbl = get_node_or_null(path)
	if lbl:
		lbl.text = text

func _on_button_settings_pressed():
	sound_click.play()
	var popup = settings_popup_scene.instantiate()
	add_child(popup)

func _on_button_settings_mouse_entered():
	_scale_button(btn_settings, 0.9)

func _on_button_settings_mouse_exited():
	_scale_button(btn_settings, 1.0)

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
