extends Control

# ————— WĘZŁY —————
@onready var ball = $TextureRect_Ball
@onready var shadow = $TextureRect_Shadow
@onready var ground = $TextureRect_Ground
@onready var sound_bounce = $AudioStreamPlayer_Bounce
@onready var title = $"../TextureRect_Title"

# ————— PROPORCJE (względem wysokości ekranu 1280px) —————
const BALL_START_Y_RATIO  = 0.42
const BALL_BOTTOM_Y_RATIO = 0.50
const SHADOW_Y_RATIO      = 0.567
const GROUND_Y_RATIO      = 0.564   # 722 / 1280
const TITLE_Y_RATIO = 0.164

const SHADOW_MAX_SCALE = 0.8
const SHADOW_MIN_SCALE = 0.2

const BOUNCE_DURATION = 0.45
const SQUISH_X = 1.3
const SQUISH_Y = 0.7
const SQUISH_DURATION = 0.08

var _ball_start_y: float
var _ball_bottom_y: float
var _shadow_y: float

# ————— READY —————

func _ready():
	await get_tree().process_frame
	_apply_equipped_skin()

	ball.pivot_offset   = Vector2(66, 66)
	shadow.pivot_offset = Vector2(shadow.size.x / 2, shadow.size.y / 2)

	var h = get_viewport_rect().size.y

	# Ustaw podest na stałej proporcji ekranu
	ground.position.y = h * GROUND_Y_RATIO
	ground.position.x = (size.x / 2) - (ground.size.x / 2)

	# Piłka i cień relative do wysokości ekranu
	_ball_start_y  = h * BALL_START_Y_RATIO
	_ball_bottom_y = h * BALL_BOTTOM_Y_RATIO
	_shadow_y      = h * SHADOW_Y_RATIO

	ball.position.y   = _ball_start_y
	shadow.position.y = _shadow_y
	ball.position.x   = (size.x / 2) - (ball.size.x / 2)
	shadow.position.x = (size.x / 2) - (shadow.size.x / 2)
	
	title.position.y = h * TITLE_Y_RATIO
	title.position.x = (size.x / 2) - (title.size.x / 2)

	_bounce_down()

# ————— SKIN —————

func _apply_equipped_skin():
	var skin_index = PlayerData.get_equipped_skin()
	var skin_num = skin_index + 1
	var path = "res://ui/skins/skin%d.png" % skin_num
	var tex = load(path)
	if tex:
		ball.texture = tex
	ball.ignore_texture_size = true
	ball.stretch_mode = TextureRect.STRETCH_SCALE
	ball.custom_minimum_size = Vector2(132, 132)
	ball.size = Vector2(132, 132)
	ball.pivot_offset = Vector2(66, 66)

# ————— ANIMACJA BOUNCE —————

func _bounce_down():
	var tween = create_tween()
	tween.tween_property(ball, "position:y", _ball_bottom_y, BOUNCE_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_update_shadow, 0.0, 1.0, BOUNCE_DURATION)
	await tween.finished
	_squish()

func _squish():
	if sound_bounce:
		sound_bounce.stop()
		sound_bounce.play()
	var tween = create_tween()
	tween.tween_property(ball, "scale", Vector2(SQUISH_X, SQUISH_Y), SQUISH_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	_bounce_up()

func _bounce_up():
	var tween = create_tween()
	tween.tween_property(ball, "position:y", _ball_start_y, BOUNCE_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ball, "scale", Vector2(1.0, 1.0), BOUNCE_DURATION * 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(_update_shadow, 1.0, 0.0, BOUNCE_DURATION)
	await tween.finished
	_bounce_down()

# ————— CIEŃ —————

func _update_shadow(progress: float):
	var s = lerp(SHADOW_MIN_SCALE, SHADOW_MAX_SCALE, progress)
	shadow.scale = Vector2(s, s)
