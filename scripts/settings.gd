extends Control

var buttons_visible = false
var sound_on = true
var music_on = true

# ————— SETTINGS TOGGLE —————

func _ready():
	await get_tree().process_frame
	
	var all_buttons = [
		get_node_or_null("VBoxContainer/Button_Settings"),
		get_node_or_null("VBoxContainer/Button_Sound"),
		get_node_or_null("VBoxContainer/Button_Music"),
		get_node_or_null("VBoxContainer/Button_Info"),
		get_node_or_null("TextureButton_Play"),
		get_node_or_null("HBoxContainer_Nav/TextureButton_Nav1"),
		get_node_or_null("HBoxContainer_Nav/TextureButton_Nav2"),
		get_node_or_null("HBoxContainer_Nav/TextureButton_Nav3"),
		get_node_or_null("HBoxContainer_Nav/TextureButton_Nav4"),
	]
	
	for btn in all_buttons:
		if btn != null:
			btn.pivot_offset = btn.size / 2

func _on_button_settings_pressed():
	$SoundClick.play()
	if buttons_visible:
		hide_side_buttons()
	else:
		show_side_buttons()
	buttons_visible = !buttons_visible

func show_side_buttons():
	$VBoxContainer/Button_Sound.visible = true
	$VBoxContainer/Button_Music.visible = true
	$VBoxContainer/Button_Info.visible = true
	
	for btn in [$VBoxContainer/Button_Sound,
				$VBoxContainer/Button_Music,
				$VBoxContainer/Button_Info]:
		btn.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(btn, "modulate:a", 1.0, 0.15)

func hide_side_buttons():
	var tween = create_tween()
	for btn in [$VBoxContainer/Button_Info,
				$VBoxContainer/Button_Music,
				$VBoxContainer/Button_Sound]:
		tween.tween_property(btn, "modulate:a", 0.0, 0.1)
	
	await tween.finished
	$VBoxContainer/Button_Sound.visible = false
	$VBoxContainer/Button_Music.visible = false
	$VBoxContainer/Button_Info.visible = false

# ————— SOUND TOGGLE —————

func _on_button_sound_pressed():
	$SoundClick.play()
	sound_on = !sound_on
	var btn = $VBoxContainer/Button_Sound
	if sound_on:
		btn.modulate = Color(1, 1, 1, 1)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Sound"), false)
	else:
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Sound"), true)

# ————— MUSIC TOGGLE —————

func _on_button_music_pressed():
	$SoundClick.play() 
	music_on = !music_on
	var btn = $VBoxContainer/Button_Music
	if music_on:
		btn.modulate = Color(1, 1, 1, 1)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), false)
	else:
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)

# ————— HOVER EFEKTY —————

func _on_button_settings_mouse_entered():
	_scale_button($VBoxContainer/Button_Settings, 0.9)

func _on_button_settings_mouse_exited():
	_scale_button($VBoxContainer/Button_Settings, 1.0)

func _on_button_sound_mouse_entered():
	_scale_button($VBoxContainer/Button_Sound, 0.9)

func _on_button_sound_mouse_exited():
	_scale_button($VBoxContainer/Button_Sound, 1.0)

func _on_button_music_mouse_entered():
	_scale_button($VBoxContainer/Button_Music, 0.9)

func _on_button_music_mouse_exited():
	_scale_button($VBoxContainer/Button_Music, 1.0)

func _on_button_info_mouse_entered():
	_scale_button($VBoxContainer/Button_Info, 0.9)

func _on_button_info_mouse_exited():
	_scale_button($VBoxContainer/Button_Info, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)


func _on_button_info_pressed() -> void:
	$SoundClick.play() 

# ————— PLAY BUTTON —————

func _on_texturebutton_play_pressed():
	$SoundClick.play()

func _on_texturebutton_play_mouse_entered():
	_scale_button($TextureButton_Play, 0.9)

func _on_texturebutton_play_mouse_exited():
	_scale_button($TextureButton_Play, 1.0)

# ————— NAV BUTTONS —————

func _on_nav1_mouse_entered():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav1, 0.9)

func _on_nav1_mouse_exited():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav1, 1.0)

func _on_nav1_pressed():
	await _play_and_wait()
	get_tree().change_scene_to_file("res://scenes/play.tscn")
	
func _on_nav2_mouse_entered():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav2, 0.9)

func _on_nav2_mouse_exited():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav2, 1.0)

func _on_nav2_pressed():
	await _play_and_wait()
	get_tree().change_scene_to_file("res://scenes/modes.tscn")

func _on_nav3_mouse_entered():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav3, 0.9)

func _on_nav3_mouse_exited():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav3, 1.0)

func _on_nav3_pressed():
	await _play_and_wait()
	get_tree().change_scene_to_file("res://scenes/shop.tscn")

func _on_nav4_mouse_entered():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav4, 0.9)

func _on_nav4_mouse_exited():
	_scale_button($HBoxContainer_Nav/TextureButton_Nav4, 1.0)

func _on_nav4_pressed():
	await _play_and_wait()
	get_tree().change_scene_to_file("res://scenes/scores.tscn")

func _play_and_wait():
	$SoundClick.play()
	await $SoundClick.finished
