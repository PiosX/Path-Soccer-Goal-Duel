extends Control

# ————— WĘZŁY —————
@onready var overlay = $ColorRect_Overlay
@onready var popup = $Control_Popup
@onready var btn_yes = $Control_Popup/HBoxContainer/TextureButton_Yes
@onready var btn_no = $Control_Popup/HBoxContainer/TextureButton_No
@onready var sound_click = $"../SoundClick"

func _ready():
	overlay.modulate.a = 0.0
	popup.scale = Vector2(0.0, 0.0)
	
	await get_tree().process_frame
	popup.pivot_offset = popup.size / 2
	btn_yes.pivot_offset = btn_yes.size / 2
	btn_no.pivot_offset = btn_no.size / 2
	
	_run_intro()

func _run_intro():
	var tween1 = create_tween()
	tween1.tween_property(overlay, "modulate:a", 0.7, 0.3)
	await tween1.finished
	
	var tween2 = create_tween()
	tween2.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween2.finished

# ————— PRZYCISKI —————

func _on_yes_pressed():
	sound_click.play()

func _on_yes_mouse_entered():
	_scale_button(btn_yes, 0.9)

func _on_yes_mouse_exited():
	_scale_button(btn_yes, 1.0)

func _on_no_pressed():
	sound_click.play()

func _on_no_mouse_entered():
	_scale_button(btn_no, 0.9)

func _on_no_mouse_exited():
	_scale_button(btn_no, 1.0)

# ————— HELPER —————

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
