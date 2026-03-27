extends Control

# ————— STAN —————
var sound_on = true
var music_on = true

# ————— WĘZŁY —————
@onready var overlay = $ColorRect_Overlay
@onready var popup = $Control_Popup
@onready var btn_close = $Control_Popup/TextureButton_Close
@onready var btn_sound = $Control_Popup/HBoxContainer/VBoxContainer_Sound/TextureButton_Sound
@onready var btn_music = $Control_Popup/HBoxContainer/VBoxContainer_Music/TextureButton_Music
@onready var btn_shop = $Control_Popup/TextureButton_Shop
@onready var btn_restart = $Control_Popup/TextureButton_Restart
@onready var btn_leave = $Control_Popup/TextureButton_Leave
@onready var sound_click = $"../SoundClick"

# ————— TEXTURY TOGGLE —————
var tex_sound_on = preload("res://ui/settings/checked.png")
var tex_sound_off = preload("res://ui/settings/unchecked.png")
var tex_music_on = preload("res://ui/settings/checked.png")
var tex_music_off = preload("res://ui/settings/unchecked.png")

func _ready():
	overlay.modulate.a = 0.0
	popup.scale = Vector2(0.0, 0.0)
	btn_sound.texture_pressed = null
	btn_music.texture_pressed = null
	await get_tree().process_frame
	popup.pivot_offset = popup.size / 2
	for btn in [btn_close, btn_sound, btn_music, btn_shop, btn_restart, btn_leave]:
		if btn:
			btn.pivot_offset = btn.size / 2
	btn_sound.texture_normal = tex_sound_on if sound_on else tex_sound_off
	btn_music.texture_normal = tex_music_on if music_on else tex_music_off
	_run_intro()

func _run_intro():
	var tween1 = create_tween()
	tween1.tween_property(overlay, "modulate:a", 0.7, 0.3)
	await tween1.finished

	var tween2 = create_tween()
	tween2.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween2.finished

# ————— CLOSE —————

func _on_close_pressed():
	sound_click.play()
	queue_free()

func _on_close_mouse_entered():
	_scale_button(btn_close, 0.9)

func _on_close_mouse_exited():
	_scale_button(btn_close, 1.0)

# ————— SOUND TOGGLE —————

func _on_sound_pressed():
	sound_click.play()
	sound_on = !sound_on
	btn_sound.texture_normal = tex_sound_on if sound_on else tex_sound_off
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Sound"), !sound_on)

func _on_sound_mouse_entered():
	_scale_button(btn_sound, 0.9)

func _on_sound_mouse_exited():
	_scale_button(btn_sound, 1.0)

# ————— MUSIC TOGGLE —————

func _on_music_pressed():
	sound_click.play()
	music_on = !music_on
	btn_music.texture_normal = tex_music_on if music_on else tex_music_off
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), !music_on)

func _on_music_mouse_entered():
	_scale_button(btn_music, 0.9)

func _on_music_mouse_exited():
	_scale_button(btn_music, 1.0)

# ————— SHOP —————

func _on_shop_pressed():
	sound_click.play()
	await sound_click.finished
	get_tree().change_scene_to_file("res://scenes/shop.tscn")

func _on_shop_mouse_entered():
	_scale_button(btn_shop, 0.9)

func _on_shop_mouse_exited():
	_scale_button(btn_shop, 1.0)

# ————— RESTART —————

func _on_restart_pressed():
	sound_click.play()
	await sound_click.finished
	queue_free()
	PlayerData.launch_level(PlayerData.current_level_index)

func _on_restart_mouse_entered():
	_scale_button(btn_restart, 0.9)

func _on_restart_mouse_exited():
	_scale_button(btn_restart, 1.0)

# ————— LEAVE —————

func _on_leave_pressed():
	sound_click.play()
	await sound_click.finished
	get_tree().change_scene_to_file("res://scenes/play.tscn")

func _on_leave_mouse_entered():
	_scale_button(btn_leave, 0.9)

func _on_leave_mouse_exited():
	_scale_button(btn_leave, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
