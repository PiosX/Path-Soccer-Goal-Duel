extends Control

@onready var overlay    = $ColorRect_Overlay
@onready var popup      = $Control_Popup
@onready var btn_close  = $Control_Popup/TextureButton_Close
@onready var btn_sound  = $Control_Popup/HBoxContainer/VBoxContainer_Sound/TextureButton_Sound
@onready var btn_music  = $Control_Popup/HBoxContainer/VBoxContainer_Music/TextureButton_Music
@onready var btn_shop   = $Control_Popup/TextureButton_Shop
@onready var btn_restart = $Control_Popup/TextureButton_Restart
@onready var btn_leave  = $Control_Popup/TextureButton_Leave
@onready var sound_click = $"../SoundClick"

var tex_sound_on  = preload("res://ui/settings/checked.png")
var tex_sound_off = preload("res://ui/settings/unchecked.png")
var tex_music_on  = preload("res://ui/settings/checked.png")
var tex_music_off = preload("res://ui/settings/unchecked.png")

func _ready():
	# FIX: overlay blokuje myszkę — kliknięcie w tło nie przechodzi do gry
	mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	overlay.modulate.a = 0.0
	popup.scale = Vector2(0.0, 0.0)
	btn_sound.texture_pressed = null
	btn_music.texture_pressed = null
	await get_tree().process_frame
	popup.pivot_offset = popup.size / 2
	for btn in [btn_close, btn_sound, btn_music, btn_shop, btn_restart, btn_leave]:
		if btn: btn.pivot_offset = btn.size / 2
	_refresh_switches()
	_run_intro()

func _refresh_switches():
	btn_sound.texture_normal = tex_sound_on  if MusicManager.is_sound_enabled() else tex_sound_off
	btn_music.texture_normal = tex_music_on  if MusicManager.is_music_enabled() else tex_music_off

func _run_intro():
	var t1 = create_tween()
	t1.tween_property(overlay, "modulate:a", 0.7, 0.3)
	await t1.finished
	var t2 = create_tween()
	t2.tween_property(popup, "scale", Vector2(1.0,1.0), 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t2.finished

func _on_close_pressed():
	sound_click.play()
	# Znajdź board i odblokuj
	var board = get_tree().root.find_child("BoardContainer", true, false)
	if board:
		board._popup_open = false
	queue_free()
	
func _on_close_mouse_entered(): _scale_button(btn_close, 0.9)
func _on_close_mouse_exited():  _scale_button(btn_close, 1.0)

func _on_sound_pressed():
	var enabling = not MusicManager.is_sound_enabled()
	MusicManager.set_sound_enabled(enabling)
	if enabling: sound_click.play()
	_refresh_switches()
func _on_sound_mouse_entered(): _scale_button(btn_sound, 0.9)
func _on_sound_mouse_exited():  _scale_button(btn_sound, 1.0)

func _on_music_pressed():
	sound_click.play()
	var enabling = not MusicManager.is_music_enabled()
	MusicManager.set_music_enabled(enabling)
	_refresh_switches()
func _on_music_mouse_entered(): _scale_button(btn_music, 0.9)
func _on_music_mouse_exited():  _scale_button(btn_music, 1.0)

func _on_shop_pressed():
	sound_click.play()
	await sound_click.finished
	SceneTransition.go_to("res://scenes/shop.tscn")
func _on_shop_mouse_entered(): _scale_button(btn_shop, 0.9)
func _on_shop_mouse_exited():  _scale_button(btn_shop, 1.0)

func _on_restart_pressed():
	sound_click.play()
	await sound_click.finished
	queue_free()
	# Restart aktualnego poziomu — tak samo jak PlayerData.launch_level
	if PlayerData.online_mode:
		# W trybie online restart = wróć do modes
		PlayerData.online_mode = false
		SceneTransition.go_to("res://scenes/modes.tscn")
	else:
		PlayerData.launch_level(PlayerData.current_level_index)
func _on_restart_mouse_entered(): _scale_button(btn_restart, 0.9)
func _on_restart_mouse_exited():  _scale_button(btn_restart, 1.0)

func _on_leave_pressed():
	sound_click.play()
	await sound_click.finished
	if PlayerData.online_mode:
		PlayerData.save_game_result(false, 0, 0, false)
		PlayerData.online_mode = false
	SceneTransition.go_to("res://scenes/play.tscn")
func _on_leave_mouse_entered(): _scale_button(btn_leave, 0.9)
func _on_leave_mouse_exited():  _scale_button(btn_leave, 1.0)

func _scale_button(btn: Control, target_scale: float):
	if btn == null: return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
