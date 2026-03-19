extends Control

@onready var sound_click = $SoundClick
@onready var btn_settings = $VBoxContainer/Button_Settings

var settings_popup_scene = preload("res://scenes/settings.tscn")

func _ready():
	await get_tree().process_frame
	if btn_settings:
		btn_settings.pivot_offset = btn_settings.size / 2

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
