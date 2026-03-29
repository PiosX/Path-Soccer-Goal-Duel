extends CanvasLayer

# ————— FADE TRANSITION —————
# Dodaj tę scenę jako AutoLoad w Project Settings:
# Nazwa: SceneTransition, Ścieżka: res://scenes/scene_transition.tscn
#
# Użycie zamiast get_tree().change_scene_to_file():
#   SceneTransition.go_to("res://scenes/play.tscn")

@onready var rect = $ColorRect

const FADE_OUT_TIME = 0.25   # czas fade do czerni
const FADE_IN_TIME  = 0.3    # czas fade z czerni

var _is_transitioning: bool = false

func _ready():
	layer = 10  # nad wszystkim
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0

# Główna funkcja do zmiany sceny z fade
func go_to(path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	rect.mouse_filter = Control.MOUSE_FILTER_STOP  # blokuj kliknięcia podczas przejścia

	# Fade do czerni
	var tw_out = create_tween()
	tw_out.tween_property(rect, "color", Color(0, 0, 0, 1), FADE_OUT_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw_out.finished

	# Zmień scenę
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame

	# Fade z czerni
	var tw_in = create_tween()
	tw_in.tween_property(rect, "color", Color(0, 0, 0, 0), FADE_IN_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw_in.finished

	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false

# Instant fade in (np. po wczytaniu gry — zacznij od czerni i rozjaśnij)
func fade_in_only() -> void:
	rect.color = Color(0, 0, 0, 1)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().process_frame
	var tw = create_tween()
	tw.tween_property(rect, "color", Color(0, 0, 0, 0), FADE_IN_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
