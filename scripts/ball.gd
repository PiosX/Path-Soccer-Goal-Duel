extends Control

# ————— WĘZŁY —————
@onready var ball = $TextureRect_Ball
@onready var shadow = $TextureRect_Shadow

# ————— USTAWIENIA —————
const MARGIN_TOP = 30.0
const BALL_START_Y = 520.0 + MARGIN_TOP
const BALL_BOTTOM_Y = 600.0 + MARGIN_TOP
const SHADOW_Y = 696.0 + MARGIN_TOP

const SHADOW_MAX_SCALE = 0.8     # skala cienia gdy piłka na dole
const SHADOW_MIN_SCALE = 0.2     # skala cienia gdy piłka na górze

const BOUNCE_DURATION = 0.45     # czas spadania w dół
const SQUISH_X = 1.3             # rozciągnięcie poziome przy odbiciu
const SQUISH_Y = 0.7             # spłaszczenie pionowe przy odbiciu
const SQUISH_DURATION = 0.08     # czas trwania squish

# ————— READY —————

func _ready():
	await get_tree().process_frame
	ball.pivot_offset = ball.size / 2
	shadow.pivot_offset = Vector2(shadow.size.x / 2, shadow.size.y / 2)
	
	# Ustaw pozycje Y
	ball.position.y = BALL_START_Y
	shadow.position.y = SHADOW_Y
	
	# Wyśrodkuj X względem Control_Ball (Full Rect = cały ekran)
	ball.position.x = (size.x / 2) - (ball.size.x / 2)
	shadow.position.x = (size.x / 2) - (shadow.size.x / 2)
	
	_bounce_down()

# ————— ANIMACJA BOUNCE —————

func _bounce_down():
	var tween = create_tween()
	tween.tween_property(ball, "position:y", BALL_BOTTOM_Y, BOUNCE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_update_shadow, 0.0, 1.0, BOUNCE_DURATION)
	await tween.finished
	_squish()

func _squish():
	# Spłaszczenie przy kontakcie z ziemią
	var tween = create_tween()
	tween.tween_property(ball, "scale", Vector2(SQUISH_X, SQUISH_Y), SQUISH_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	await tween.finished
	_bounce_up()

func _bounce_up():
	var tween = create_tween()
	tween.tween_property(ball, "position:y", BALL_START_Y, BOUNCE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	# Przywróć normalną skalę
	tween.parallel().tween_property(ball, "scale", Vector2(1.0, 1.0), BOUNCE_DURATION * 0.3)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(_update_shadow, 1.0, 0.0, BOUNCE_DURATION)
	await tween.finished
	_bounce_down()

# ————— CIEŃ —————

func _update_shadow(progress: float):
	# progress 0.0 = piłka na górze, 1.0 = piłka na dole
	var s = lerp(SHADOW_MIN_SCALE, SHADOW_MAX_SCALE, progress)
	shadow.scale = Vector2(s, s)
