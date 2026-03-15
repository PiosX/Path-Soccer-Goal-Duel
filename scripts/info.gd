extends CanvasLayer

@onready var sound_click = $MarginContainer/Control/SoundClick
@onready var btn_privacy = $MarginContainer/Control/ScrollContainer/VBoxContainer/TextureButton_Privacy

func _ready():
	await get_tree().process_frame
	if btn_privacy:
		btn_privacy.pivot_offset = btn_privacy.size / 2

func _on_privacy_pressed():
	sound_click.play()
	OS.shell_open("https://redmoongames.carrd.co/")

func _on_privacy_mouse_entered():
	_scale_button(btn_privacy, 0.9)

func _on_privacy_mouse_exited():
	_scale_button(btn_privacy, 1.0)

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
