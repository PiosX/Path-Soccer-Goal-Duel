extends Control

# ————— ZASOBY —————
var quad_f1 = preload("res://scenes/quad_f1.tscn")
var quad_f2 = preload("res://scenes/quad_f2.tscn")
var quad_f3 = preload("res://scenes/quad_f3.tscn")  # niebieskie — bramka gracza (dół)
var quad_f4 = preload("res://scenes/quad_f4.tscn")  # czerwone — bramka AI (góra)
var tex_skin = preload("res://ui/skins/skin1.png")
var scene_complete = preload("res://scenes/level_complete.tscn")
var scene_failed  = preload("res://scenes/level_failed.tscn")

# ————— WYMIARY —————
const QUAD_SIZE = 90.0
const COLS = 6
const ROWS = 8
const GOAL_COL_START = 2
const GOAL_COLS = 2
const BORDER = 8.0
const PADDING = 9.0
const RADIUS = 30.0
const FIELD_COLOR = Color("#448B47")
const BORDER_COLOR = Color.WHITE
const GAP = 9.0

# ————— KOLORY GRY —————
const DOT_COLOR       = Color(1.0, 1.0, 1.0, 0.5)
const DOT_ACTIVE_COLOR = Color(1.0, 0.9, 0.0, 1.0)
const TRAIL_P1_COLOR  = Color("#FFFFFF")
const TRAIL_P2_COLOR  = Color("#FFD700")

# ————— STAN GRY —————
var ball_grid_pos: Vector2i        # bieżąca pozycja piłki w siatce
var current_player: int = 1        # 1 lub 2
var used_edges: Dictionary = {}    # edge_key -> true
var bounce_active: bool = false    # odbicie = ten sam gracz rusza znowu
var move_history: Array = []       # [{from, to, edge_key, player, line_node}]
var score: int = 0                 # aktualny wynik gracza
var combo_count: int = 0           # ile ruchów z rzędu w tej turze
var combo_label: Label = null      # etykieta COMBO nad piłką

# ————— TRYB GRY —————
var VS_AI: bool = true             # ustaw z zewnątrz przed _ready
const AI_PLAYER: int = 2
const AI_DEPTH: int = 3
var ai_thinking: bool = false

# ————— TIMER (tryb 2 graczy) —————
const TURN_TIME: float = 15.0
var turn_timer: float = TURN_TIME
var timer_running: bool = false
var timer_node: Timer = null       # Godot Timer do tickowania

# ————— WĘZŁY UI —————
var ball_node: Sprite2D
var dot_nodes: Array = []   # [{node, gx, gy}]
var active_moves: Array = []

# ————— WĘZŁY TIMERA (pobierane z drzewa sceny nadrzędnej) —————
var ui_turn_label: Label = null        # Label "Turn" / "15s"
var ui_panel_timer: Panel = null       # Panel z paskiem
var ui_panel_color: Panel = null       # Kolorowy pasek
var ui_timer_container: Control = null # Cały kontener timera (do hide/show)

var field_w: float
var field_h: float
var goal_w: float
var goal_h: float
var inner: float

# ——————————————————————————————————————————
#  HELPERS
# ——————————————————————————————————————————

# Pozycja węzła siatki w pikselach (lokalnych)
func grid_to_pixel(gx: int, gy: int) -> Vector2:
	var px = inner + gx * (QUAD_SIZE + GAP) - GAP / 2.0
	var py = goal_h + inner + gy * (QUAD_SIZE + GAP) - GAP / 2.0
	return Vector2(px, py)

# Klucz krawędzi (nieskierowany)
func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]

# Czy węzeł jest w bounds (pole + bramki)
func is_valid_node(gx: int, gy: int) -> bool:
	if gx >= 0 and gx <= COLS and gy >= 0 and gy <= ROWS:
		return true
	# bramka górna
	if gy == -1 and gx >= GOAL_COL_START and gx <= GOAL_COL_START + GOAL_COLS:
		return true
	# bramka dolna
	if gy == ROWS + 1 and gx >= GOAL_COL_START and gx <= GOAL_COL_START + GOAL_COLS:
		return true
	return false

# Czy krawędź jest niedozwolona (leży wzdłuż ściany lub przez nią)
func is_wall_edge(a: Vector2i, b: Vector2i) -> bool:
	# Lewa ściana (x=0): żaden ruch z/do x=0 równolegle do ściany
	if a.x == 0 and b.x == 0: return true
	# Prawa ściana (x=COLS)
	if a.x == COLS and b.x == COLS: return true
	# Górna ściana (y=0) poza bramką — blokuj ruch poziomy wzdłuż niej
	if a.y == 0 and b.y == 0:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS):
			return true
	# Dolna ściana (y=ROWS) poza bramką
	if a.y == ROWS and b.y == ROWS:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS):
			return true
	# Blokuj przekątne przez narożniki ścian
	if abs(a.x - b.x) == 1 and abs(a.y - b.y) == 1:
		var side_a = Vector2i(b.x, a.y)
		var side_b = Vector2i(a.x, b.y)
		if not is_valid_node(side_a.x, side_a.y) or not is_valid_node(side_b.x, side_b.y):
			return true
		# Blokuj też gdy oba sąsiednie węzły leżą na ścianie (narożnik boiska)
		var side_a_on_wall = (side_a.x == 0 or side_a.x == COLS or side_a.y == 0 or side_a.y == ROWS)
		var side_b_on_wall = (side_b.x == 0 or side_b.x == COLS or side_b.y == 0 or side_b.y == ROWS)
		if side_a_on_wall and side_b_on_wall:
			return true
	# Blokuj ruch wzdłuż bocznej ściany bramki (prosto w górę/dół z krawędzi bramki)
	# Z węzła na krawędzi bramki (x==GOAL_COL_START lub x==GOAL_COL_START+GOAL_COLS)
	# można wejść do bramki tylko po przekątnej (do środka), nie prosto
	if a.x == b.x and abs(a.y - b.y) == 1:
		var bx = a.x
		# Lewa krawędź bramki
		if bx == GOAL_COL_START:
			var min_y = mini(a.y, b.y); var max_y = maxi(a.y, b.y)
			# Ruch z gy=0 do gy=-1 lub z gy=ROWS do gy=ROWS+1 po lewej krawędzi = niedozwolony
			if (min_y == -1 and max_y == 0) or (min_y == ROWS and max_y == ROWS + 1):
				return true
		# Prawa krawędź bramki
		if bx == GOAL_COL_START + GOAL_COLS:
			var min_y = mini(a.y, b.y); var max_y = maxi(a.y, b.y)
			if (min_y == -1 and max_y == 0) or (min_y == ROWS and max_y == ROWS + 1):
				return true
	return false

# Możliwe ruchy z danej pozycji
func get_valid_moves(pos: Vector2i) -> Array:
	var moves = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if not is_valid_node(nb.x, nb.y): continue
			if used_edges.has(edge_key(pos, nb)): continue
			if is_wall_edge(pos, nb): continue
			moves.append(nb)
	return moves

func _get_moves_with_edges(pos: Vector2i, edges: Dictionary) -> Array:
	var moves = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if not is_valid_node(nb.x, nb.y): continue
			if edges.has(edge_key(pos, nb)): continue
			if is_wall_edge(pos, nb): continue
			moves.append(nb)
	return moves

# Odbicie = węzeł był już odwiedzony lub jest węzłem ściany (ściana = naturalna bariera)
func node_has_any_trail(pos: Vector2i) -> bool:
	var count = 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if used_edges.has(edge_key(pos, nb)):
				count += 1
	# Każda ściana boiska przylegająca do węzła liczy jako osobna bariera
	if pos.x == 0: count += 1
	if pos.x == COLS: count += 1
	if pos.y == 0: count += 1
	if pos.y == ROWS: count += 1
	return count >= 2

# ——————————————————————————————————————————
#  INICJALIZACJA
# ——————————————————————————————————————————

func _ready():
	_build_board()
	_setup_game()

func _setup_game():
	ball_grid_pos = Vector2i(COLS / 2, ROWS / 2)
	current_player = 1
	used_edges.clear()
	bounce_active = false
	active_moves.clear()
	move_history.clear()

	_draw_grid_dots()

	# Piłka
	ball_node = Sprite2D.new()
	ball_node.texture = tex_skin
	ball_node.z_index = 10
	ball_node.scale = Vector2(36.0 / 88.0, 36.0 / 88.0)
	ball_node.position = grid_to_pixel(ball_grid_pos.x, ball_grid_pos.y)
	add_child(ball_node)

	# Etykieta COMBO
	if combo_label and is_instance_valid(combo_label):
		combo_label.queue_free()
	combo_label = Label.new()
	combo_label.add_theme_font_override("font", load("res://fonts/Digitalt.ttf"))
	combo_label.add_theme_font_size_override("font_size", 28)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	combo_label.add_theme_constant_override("outline_size", 3)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.z_index = 20
	combo_label.visible = false
	combo_label.text = ""
	add_child(combo_label)
	score = 0
	combo_count = 0

	_init_timer_ui()
	_refresh_active_dots()

# ——————————————————————————————————————————
#  SIATKA KROPEK
# ——————————————————————————————————————————

func _draw_grid_dots():
	# Węzły pola głównego
	for gx in range(COLS + 1):
		for gy in range(ROWS + 1):
			var dot = _make_dot(grid_to_pixel(gx, gy), false)
			dot_nodes.append({"node": dot, "gx": gx, "gy": gy})
	# Węzły górnej bramki (gy = -1)
	for gx in range(GOAL_COL_START, GOAL_COL_START + GOAL_COLS + 1):
		var dot = _make_dot(grid_to_pixel(gx, -1), false)
		dot_nodes.append({"node": dot, "gx": gx, "gy": -1})
	# Węzły dolnej bramki (gy = ROWS + 1)
	for gx in range(GOAL_COL_START, GOAL_COL_START + GOAL_COLS + 1):
		var dot = _make_dot(grid_to_pixel(gx, ROWS + 1), false)
		dot_nodes.append({"node": dot, "gx": gx, "gy": ROWS + 1})

func _make_dot(pos: Vector2, active: bool) -> Node2D:
	var dot = Node2D.new()
	dot.position = pos
	dot.z_index = 6
	dot.set_meta("active", active)
	dot.set_meta("pulse_scale", 1.0)
	dot.draw.connect(_on_dot_draw.bind(dot))
	add_child(dot)
	dot.queue_redraw()
	return dot

func _on_dot_draw(dot: Node2D):
	var is_active: bool = dot.get_meta("active")
	var ps: float = dot.get_meta("pulse_scale")
	if is_active:
		dot.draw_circle(Vector2.ZERO, 10.0 * ps, Color(1.0, 0.9, 0.0, 0.55 * ps))
		dot.draw_circle(Vector2.ZERO, 5.5 * ps, Color(1.0, 0.95, 0.2, 0.95))
	else:
		dot.draw_circle(Vector2.ZERO, 4.0, DOT_COLOR)

func _refresh_active_dots():
	active_moves = get_valid_moves(ball_grid_pos)

	# Brak ruchów = natychmiastowy rollback
	if active_moves.is_empty():
		call_deferred("_auto_rollback")
		return

	for entry in dot_nodes:
		var gpos = Vector2i(entry["gx"], entry["gy"])
		var is_active = gpos in active_moves
		var was_active: bool = entry["node"].get_meta("active")
		entry["node"].set_meta("active", is_active)
		entry["node"].set_meta("pulse_scale", 1.0)
		entry["node"].queue_redraw()
		if is_active and not was_active:
			_start_pulse(entry["node"])

func _auto_rollback():
	# Pokaż miganie na ostatniej linii przed cofnięciem
	if not move_history.is_empty():
		var last_line = move_history.back().get("line")
		if last_line and is_instance_valid(last_line):
			_flash_trail_red(last_line)
			await get_tree().create_timer(0.5).timeout
	await _rollback_until_moves()

func _start_pulse(dot: Node2D):
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tween.tween_method(func(v): 
		if not is_instance_valid(dot): return
		if not dot.get_meta("active"): 
			tween.kill()
			dot.set_meta("pulse_scale", 1.0)
			dot.queue_redraw()
			return
		dot.set_meta("pulse_scale", v)
		dot.queue_redraw()
	, 1.0, 1.25, 0.55)
	tween.tween_method(func(v):
		if not is_instance_valid(dot): return
		dot.set_meta("pulse_scale", v)
		dot.queue_redraw()
	, 1.25, 1.0, 0.55)

# ——————————————————————————————————————————
#  INPUT
# ——————————————————————————————————————————

func _input(event: InputEvent):
	var pressed = false
	var click_pos = Vector2.ZERO

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		click_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		click_pos = event.position

	if not pressed:
		return

	if ai_thinking:
		return

	_try_move(get_global_transform().affine_inverse() * click_pos)

func _try_move(local_pos: Vector2):
	var tap_radius = (QUAD_SIZE + GAP) * 0.55
	var best_dist = tap_radius
	var best_move: Variant = null

	for move in active_moves:
		var d = local_pos.distance_to(grid_to_pixel(move.x, move.y))
		if d < best_dist:
			best_dist = d
			best_move = move

	if best_move == null:
		return

	_do_move(best_move)

# ——————————————————————————————————————————
#  LOGIKA RUCHU
# ——————————————————————————————————————————

func _do_move(target: Vector2i):
	var from = ball_grid_pos
	var ek = edge_key(from, target)

	# Zablokuj krawędź
	used_edges[ek] = true

	# Ślad — zapamiętaj referencję na wypadek cofnięcia
	var trail_line = _draw_trail(from, target)

	# Zapisz historię
	move_history.append({"from": from, "to": target, "ek": ek, "player": current_player, "line": trail_line})

	# Sprawdź gol przed animacją
	var scored = _check_goal(target)

	# Animuj do celu
	_animate_ball(target, scored)
	ball_grid_pos = target

	if scored:
		_show_combo(target, true)
		return

	# Odbicie jeśli węzeł ma już ślady
	bounce_active = node_has_any_trail(target)
	if bounce_active:
		combo_count += 1
		score += combo_count * 10
		_show_combo(target, false)
		# Odbicie — ten sam gracz gra dalej, przedłuż timer o 3s (max do TURN_TIME)
		if not VS_AI:
			turn_timer = minf(turn_timer + 3.0, TURN_TIME)
	else:
		combo_count = 0
		_hide_combo()
		current_player = 2 if current_player == 1 else 1
		# Zmiana tury — restart timera
		if not VS_AI:
			_start_turn_timer()

	var moves = get_valid_moves(ball_grid_pos)

	# ————— ŚLEPY ZAUŁEK — cofnij piłkę —————
	if moves.is_empty():
		_stop_turn_timer()
		await get_tree().create_timer(0.15).timeout
		_flash_trail_red(trail_line)
		await get_tree().create_timer(0.5).timeout
		await _rollback_until_moves()
		return

	_refresh_active_dots()
	_check_cutoff()

	# AI rusza gdy to jego kolej
	if VS_AI and current_player == AI_PLAYER:
		ai_thinking = true
		_hide_active_dots()
		# Czekaj aż animacja piłki się skończy (ok 0.25s) zanim AI zacznie liczyć
		await get_tree().create_timer(0.28).timeout
		_ai_take_turn()

var _just_rolled_back: bool = false  # blokuje _check_cutoff tuż po rollbacku

# Cofa ruchy dopóki jest pozycja z możliwymi ruchami
func _rollback_until_moves() -> void:
	var safety = 0
	while true:
		safety += 1
		if safety > 50 or move_history.is_empty():
			_game_over(0)
			return

		var last = move_history.back()
		move_history.pop_back()

		# Krawędź i linia ZOSTAJĄ — zaułek blokuje to miejsce na stałe
		# used_edges.erase(last["ek"])  # celowo nie usuwamy

		# Cofnij piłkę
		_animate_ball(last["from"], false)
		ball_grid_pos = last["from"]
		bounce_active = false
		combo_count = 0
		_hide_combo()

		# Przywróć gracza który wykonał ten ruch
		current_player = last["player"]

		await get_tree().create_timer(0.2).timeout

		var moves = get_valid_moves(ball_grid_pos)
		if not moves.is_empty():
			# Wejście w zaułek = strata tury — oddaj grę przeciwnikowi
			current_player = 2 if current_player == 1 else 1
			_just_rolled_back = true
			ai_thinking = false
			_refresh_active_dots()
			# Jeśli po zmianie tury gra AI — niech ruszy
			if VS_AI and current_player == AI_PLAYER:
				ai_thinking = true
				_hide_active_dots()
				await get_tree().create_timer(0.2).timeout
				_ai_take_turn()
			else:
				_start_turn_timer()
			return

func _flash_trail_red(line: Line2D):
	if not is_instance_valid(line): return
	var original_color = line.default_color
	var tween = create_tween()
	for i in range(3):
		tween.tween_property(line, "default_color", Color(1, 0, 0, 1), 0.1)
		tween.tween_property(line, "default_color", Color(1, 0, 0, 0.2), 0.1)
	tween.tween_property(line, "default_color", original_color, 0.15)

func _hide_active_dots():
	for entry in dot_nodes:
		entry["node"].set_meta("active", false)
		entry["node"].queue_redraw()

# ——————————————————————————————————————————
#  ANIMACJA PIŁKI
# ——————————————————————————————————————————

func _animate_ball(target: Vector2i, is_goal: bool):
	var target_px = grid_to_pixel(target.x, target.y)
	var base_scale = 36.0 / 88.0
	var tween = create_tween().set_parallel(false)

	# Ruch + spłaszczenie (kopnięcie)
	tween.tween_property(ball_node, "position", target_px, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(ball_node, "scale", Vector2(base_scale * 1.25, base_scale * 0.75), 0.07)
	tween.tween_property(ball_node, "scale", Vector2(base_scale, base_scale), 0.08).set_ease(Tween.EASE_OUT)

	if is_goal:
		tween.tween_callback(Callable(self, "_on_goal_anim"))

# ——————————————————————————————————————————
#  ŚLAD
# ——————————————————————————————————————————

func _draw_trail(from: Vector2i, to: Vector2i) -> Line2D:
	var line = Line2D.new()
	line.add_point(grid_to_pixel(from.x, from.y))
	line.add_point(grid_to_pixel(to.x, to.y))
	line.width = 5.5
	line.default_color = TRAIL_P1_COLOR if current_player == 1 else TRAIL_P2_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 7
	add_child(line)
	return line

# ——————————————————————————————————————————
#  GOL / KONIEC GRY
# ——————————————————————————————————————————

func _check_goal(pos: Vector2i) -> bool:
	if pos.y < 0 and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return true
	if pos.y > ROWS and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return true
	return false

func _on_goal_anim():
	var scorer = current_player
	print("GOL! Gracz %d strzelił!" % scorer)
	_hide_combo()
	# Górna bramka (y<0) = bramka AI, więc gracz 1 strzelił
	# Dolna bramka (y>ROWS) = bramka gracza, więc AI strzelił
	var player_scored = (ball_grid_pos.y < 0)  # gracz 1 strzelił AI
	if player_scored:
		score += 500  # bonus za gola
		_show_popup_win()
	else:
		_show_popup_fail()

func _game_over(winner: int):
	print("Koniec gry! Wygrywa gracz %d" % winner)
	_hide_combo()
	if winner == 1:
		_show_popup_win()
	else:
		_show_popup_fail()

func _show_popup_win():
	ai_thinking = true
	var popup = scene_complete.instantiate()
	# Ustaw przed add_child — _ready odczyta i animuje od 0 do tych wartości
	var ctrl = popup.get_node("Control")
	ctrl.score = score
	ctrl.reward = score / 100
	get_tree().root.add_child(popup)

func _show_popup_fail():
	ai_thinking = true
	var popup = scene_failed.instantiate()
	var ctrl = popup.get_node("Control")
	ctrl.score = score
	get_tree().root.add_child(popup)

# ——————————————————————————————————————————
#  AI — MINIMAX
# ——————————————————————————————————————————

func _ai_take_turn():
	# Uruchom minimax w wątku żeby nie blokować animacji
	var pos_snap = ball_grid_pos
	var edges_snap = used_edges.duplicate()
	var result_holder = [null]
	var thread = Thread.new()
	thread.start(func():
		result_holder[0] = _minimax_root(pos_snap, edges_snap, AI_PLAYER, AI_DEPTH)
	)
	# Czekaj na wątek bez blokowania głównego wątku
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
	var best = result_holder[0]
	if best == null:
		ai_thinking = false
		_refresh_active_dots()
		return

	_do_move_silent(best)

# Ruch bez odpalania AI na końcu (używany przez AI samo w sobie)
func _do_move_silent(target: Vector2i):
	var from = ball_grid_pos
	var ek = edge_key(from, target)
	used_edges[ek] = true
	var trail_line = _draw_trail(from, target)

	# Zapisz historię
	move_history.append({"from": from, "to": target, "ek": ek, "player": current_player, "line": trail_line})

	var scored = _check_goal(target)
	_animate_ball(target, scored)
	ball_grid_pos = target

	if scored:
		ai_thinking = false
		return

	bounce_active = node_has_any_trail(target)
	if bounce_active:
		combo_count += 1
		score += combo_count * 10
		_show_combo(target, false)
	else:
		combo_count = 0
		_hide_combo()
		current_player = 2 if current_player == 1 else 1

	var moves = get_valid_moves(ball_grid_pos)

	if moves.is_empty():
		await get_tree().create_timer(0.15).timeout
		_flash_trail_red(trail_line)
		await get_tree().create_timer(0.5).timeout
		await _rollback_until_moves()
		return

	await get_tree().create_timer(0.12).timeout

	if current_player == AI_PLAYER:
		await get_tree().create_timer(0.12).timeout
		_ai_take_turn()
	else:
		ai_thinking = false
		_refresh_active_dots()
		# Tura gracza
		ai_thinking = false
		_refresh_active_dots()

# Korzeń minimax — zwraca najlepszy ruch
func _minimax_root(pos: Vector2i, edges: Dictionary, player: int, depth: int) -> Variant:
	var moves = _get_moves_pure(pos, edges)
	if moves.is_empty():
		return null

	# Rozdziel ruchy na: bezpieczne (po nich są dalsze ruchy) i zaułki
	var safe_moves = []
	var deadend_moves = []
	for move in moves:
		var test_edges = edges.duplicate()
		test_edges[edge_key(pos, move)] = true
		var after = _get_moves_pure(move, test_edges)
		if after.is_empty():
			deadend_moves.append(move)
		else:
			safe_moves.append(move)

	# Oceniaj tylko bezpieczne jeśli istnieją, wpadnij do zaułków tylko gdy nie ma innego wyjścia
	var eval_moves = safe_moves if not safe_moves.is_empty() else deadend_moves

	var best_score = -INF
	var best_move = eval_moves[0]

	for move in eval_moves:
		var new_edges = edges.duplicate()
		new_edges[edge_key(pos, move)] = true

		var bounce = _node_has_trail_pure(move, new_edges)
		var next_player = player if bounce else (2 if player == 1 else 1)

		var score = _minimax(move, new_edges, next_player, depth - 1, -INF, INF, false)

		# Dodatkowa kara w root za zaułki (na wypadek gdybyśmy musieli oceniać deadend_moves)
		if move in deadend_moves:
			score -= 150.0

		if score > best_score:
			best_score = score
			best_move = move

	return best_move

# Minimax z alpha-beta pruning
# maximizing = true gdy AI (gracz 2) jest na ruchu
func _minimax(pos: Vector2i, edges: Dictionary, player: int, depth: int, alpha: float, beta: float, maximizing: bool) -> float:
	# Sprawdź terminal: gol
	# Górna bramka (y<0) = bramka AI — kto tu wchodzi strzela AI gola (źle dla AI)
	# Dolna bramka (y>ROWS) = bramka gracza — kto tu wchodzi strzela graczowi gola (dobrze dla AI)
	# Górna bramka (y<0) = bramka AI — piłka tu = GOL GRACZA = źle dla AI
	if pos.y < 0 and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return -10000.0 - depth  # Zawsze źle dla AI niezależnie kto wchodził
	# Dolna bramka (y>ROWS) = bramka gracza — piłka tu = GOL AI = świetnie dla AI
	if pos.y > ROWS and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return 10000.0 + depth   # Zawsze świetnie dla AI

	if depth == 0:
		return _heuristic(pos, edges)

	var moves = _get_moves_pure(pos, edges)
	if moves.is_empty():
		# Brak ruchów = zaułek = strata tury (nie przegrana!)
		# Przeciwnik przejmuje ruch z tej samej pozycji
		# Kara: tracimy turę = -200 dla AI, +200 dla gracza
		return -200.0 if maximizing else 200.0

	if maximizing:
		var best = -INF
		for move in moves:
			var new_edges = edges.duplicate()
			new_edges[edge_key(pos, move)] = true
			var bounce = _node_has_trail_pure(move, new_edges)
			var next_max = true if bounce else false  # odbicie = ten sam gracz
			var score = _minimax(move, new_edges, player, depth - 1, alpha, beta, next_max if bounce else not maximizing)
			best = maxf(best, score)
			alpha = maxf(alpha, best)
			if beta <= alpha:
				break
		return best
	else:
		var best = INF
		for move in moves:
			var new_edges = edges.duplicate()
			new_edges[edge_key(pos, move)] = true
			var bounce = _node_has_trail_pure(move, new_edges)
			var score = _minimax(move, new_edges, player, depth - 1, alpha, beta, bounce if not bounce else maximizing)
			best = minf(best, score)
			beta = minf(beta, best)
			if beta <= alpha:
				break
		return best

# Heurystyka z perspektywy AI — tylko tanie obliczenia, bez BFS
func _heuristic(pos: Vector2i, edges: Dictionary) -> float:
	var goal_center_x = float(GOAL_COL_START) + float(GOAL_COLS) / 2.0

	# Pozycja: AI atakuje dolną bramkę (duże y), broni górnej
	var dist_to_attack = abs(pos.x - goal_center_x) * 0.5 + float(ROWS - pos.y)
	var dist_to_defend = abs(pos.x - goal_center_x) * 0.5 + float(pos.y)
	var position_score = (dist_to_defend - dist_to_attack) * 12.0

	# Mobilność — ile ruchów z obecnej pozycji (O(8), bardzo tanie)
	var my_moves = _get_moves_pure(pos, edges)
	var mobility = float(my_moves.size())

	# Kara za zaułki wśród dostępnych ruchów (sprawdź ile ruchów zostaje po każdym)
	# Ograniczamy do max 4 ruchów żeby nie robić 8x8=64 sprawdzeń
	var deadend_penalty = 0.0
	var check_count = mini(my_moves.size(), 4)
	for i in range(check_count):
		var move = my_moves[i]
		var test_edges = edges.duplicate()
		test_edges[edge_key(pos, move)] = true
		var after_count = _count_moves_pure(move, test_edges)
		if after_count == 0:
			deadend_penalty += 10.0
		elif after_count == 1:
			deadend_penalty += 3.0

	return position_score + mobility * 4.0 - deadend_penalty

# Szybkie liczenie ruchów bez tworzenia tablicy
func _count_moves_pure(pos: Vector2i, edges: Dictionary) -> int:
	var count = 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if not is_valid_node(nb.x, nb.y): continue
			if edges.has(edge_key(pos, nb)): continue
			if is_wall_edge(pos, nb): continue
			count += 1
	return count


func _bfs_reachable_pure(start: Vector2i, edges: Dictionary) -> int:
	var visited: Dictionary = {}
	var queue: Array = [start]
	visited[start] = true
	var count = 0
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		count += 1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(pos.x + dx, pos.y + dy)
				if visited.has(nb): continue
				if not is_valid_node(nb.x, nb.y): continue
				if edges.has(edge_key(pos, nb)): continue
				if is_wall_edge(pos, nb): continue
				visited[nb] = true
				queue.append(nb)
	return count

# ————— Czyste funkcje (bez side effects, na kopii stanu) —————

func _get_moves_pure(pos: Vector2i, edges: Dictionary) -> Array:
	var moves = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if not is_valid_node(nb.x, nb.y): continue
			if edges.has(edge_key(pos, nb)): continue
			if is_wall_edge(pos, nb): continue
			moves.append(nb)
	return moves

func _node_has_trail_pure(pos: Vector2i, edges: Dictionary) -> bool:
	var count = 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if edges.has(edge_key(pos, nb)):
				count += 1
	if pos.x == 0: count += 1
	if pos.x == COLS: count += 1
	if pos.y == 0: count += 1
	if pos.y == ROWS: count += 1
	return count >= 2

func _is_goal_pure(pos: Vector2i) -> bool:
	if pos.y < 0 and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return true
	if pos.y > ROWS and pos.x >= GOAL_COL_START and pos.x <= GOAL_COL_START + GOAL_COLS:
		return true
	return false

# ——————————————————————————————————————————
#  DETEKCJA ODCIĘCIA
# ——————————————————————————————————————————

# BFS od pozycji piłki — czy można dotrzeć do dowolnego węzła bramki górnej (y<0) lub dolnej (y>ROWS)
func _can_reach_goal(target_is_top: bool) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [ball_grid_pos]
	visited[ball_grid_pos] = true
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		# Sprawdź czy to węzeł bramki szukanej strony
		if target_is_top and pos.y < 0:
			return true
		if not target_is_top and pos.y > ROWS:
			return true
		# Sąsiedzi po wolnych krawędziach
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(pos.x + dx, pos.y + dy)
				if visited.has(nb): continue
				if not is_valid_node(nb.x, nb.y): continue
				if used_edges.has(edge_key(pos, nb)): continue
				if is_wall_edge(pos, nb): continue
				visited[nb] = true
				queue.append(nb)
	return false

# Sprawdź po każdym ruchu czy któraś bramka jest odcięta
func _check_cutoff():
	# Nie sprawdzaj tuż po rollbacku — zostawiona linia mogłaby fałszywie blokować
	if _just_rolled_back:
		_just_rolled_back = false
		return
	var can_top = _can_reach_goal(true)    # czy piłka może dotrzeć do górnej bramki (AI)
	var can_bot = _can_reach_goal(false)   # czy piłka może dotrzeć do dolnej bramki (gracz)
	if can_top and can_bot:
		return  # obie osiągalne — gra trwa
	# Odcięcie — piłka może iść tylko w jedną stronę
	if not can_top and not can_bot:
		# Totalnie uwięziona — przegrywa ten kto ostatnio ruszał
		var loser = current_player
		if loser == 1:
			_show_popup_fail()
		else:
			_show_popup_win()
		return
	if not can_top:
		# Nie można dotrzeć do górnej bramki (bramka AI) — gracz 1 przegrywa
		_show_popup_fail()
	else:
		# Nie można dotrzeć do dolnej bramki (bramka gracza) — AI/gracz2 przegrywa = gracz wygrywa
		_show_popup_win()

# ——————————————————————————————————————————
#  TIMER (tryb gracz vs gracz)
# ——————————————————————————————————————————

func _init_timer_ui():
	# Szukamy węzłów w scenie nadrzędnej (BoardContainer jest dzieckiem ScrollContainer itd.)
	var root = get_tree().root
	ui_turn_label     = _find_node_by_name(root, "Turn")
	ui_panel_timer    = _find_node_by_name(root, "Panel_Timer")
	ui_panel_color    = _find_node_by_name(root, "Panel_Color")
	ui_timer_container = ui_panel_timer  # kontener to sam Panel_Timer

	if VS_AI:
		# Tryb AI — ukryj cały timer
		if ui_panel_timer: ui_panel_timer.get_parent().visible = false
		if ui_turn_label: ui_turn_label.visible = false
		timer_running = false
	else:
		# Tryb 2 graczy — pokaż i wystartuj
		if ui_panel_timer: ui_panel_timer.get_parent().visible = true
		if ui_turn_label: ui_turn_label.visible = true
		_start_turn_timer()

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

func _start_turn_timer():
	if VS_AI:
		return
	turn_timer = TURN_TIME
	timer_running = true
	_update_timer_ui(TURN_TIME)
	_set_timer_color()

func _stop_turn_timer():
	timer_running = false

func _process(delta: float):
	if not timer_running or VS_AI:
		return
	turn_timer -= delta
	if turn_timer <= 0.0:
		turn_timer = 0.0
		timer_running = false
		_on_timer_expired()
		return
	_update_timer_ui(turn_timer)

func _update_timer_ui(time_left: float):
	if ui_turn_label and is_instance_valid(ui_turn_label):
		if current_player == 1:
			ui_turn_label.text = "YOUR TURN: %ds" % int(ceil(time_left))
		else:
			ui_turn_label.text = "RIVAL TURN: %ds" % int(ceil(time_left))
	if ui_panel_color and is_instance_valid(ui_panel_color):
		# Stały offset 4px od lewej, max szerokość 242px
		const BAR_MAX_W = 242.0
		const BAR_OFFSET_X = 4.0
		const BAR_OFFSET_Y = 4.0
		var ratio = clampf(time_left / TURN_TIME, 0.0, 1.0)
		ui_panel_color.position.x = BAR_OFFSET_X
		ui_panel_color.position.y = BAR_OFFSET_Y
		ui_panel_color.size.x = BAR_MAX_W * ratio
		# Kolor gracza
		var col: Color
		if current_player == 1:
			col = Color("#06c3f6")
		else:
			col = Color("#fe4b60")
		# Migotanie gdy mało czasu (< 4s)
		if time_left < 4.0:
			var flash = abs(sin(time_left * 6.0))
			col.a = lerpf(0.3, 1.0, flash)
		else:
			col.a = 1.0
		# Aktualizuj tylko kolor w istniejącym stylu — nie twórz nowego co klatkę
		var style = ui_panel_color.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.bg_color = col
		else:
			var new_style = StyleBoxFlat.new()
			new_style.bg_color = col
			new_style.corner_radius_top_left = 1000
			new_style.corner_radius_top_right = 1000
			new_style.corner_radius_bottom_left = 1000
			new_style.corner_radius_bottom_right = 1000
			ui_panel_color.add_theme_stylebox_override("panel", new_style)

func _set_timer_color():
	_update_timer_ui(turn_timer)

func _on_timer_expired():
	# Czas minął — przekaż turę przeciwnikowi
	combo_count = 0
	_hide_combo()
	current_player = 2 if current_player == 1 else 1
	_refresh_active_dots()
	_start_turn_timer()

# ——————————————————————————————————————————
#  COMBO LABEL
# ——————————————————————————————————————————

func _show_combo(target: Vector2i, is_goal: bool):
	# Każdy napis to osobny Label żeby animacje nie nakładały się
	var lbl = Label.new()
	lbl.add_theme_font_override("font", load("res://fonts/Digitalt.ttf"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 20
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))

	var px = grid_to_pixel(target.x, target.y)
	# Ustaw stały szeroki rozmiar i wyśrodkuj względem px
	lbl.custom_minimum_size = Vector2(160, 60)
	lbl.size = Vector2(160, 60)
	lbl.position = px + Vector2(-80, -55)

	if is_goal:
		lbl.text = "GOAL!\n+500"
		lbl.add_theme_font_size_override("font_size", 32)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	elif combo_count >= 8:
		lbl.text = "COMBO x%d\n+%d" % [combo_count, combo_count * 10]
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.1, 0.0, 1.0))
	elif combo_count >= 5:
		lbl.text = "COMBO x%d\n+%d" % [combo_count, combo_count * 10]
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.0, 1.0))
	elif combo_count >= 3:
		lbl.text = "COMBO x%d\n+%d" % [combo_count, combo_count * 10]
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.0, 1.0))
	elif combo_count >= 2:
		lbl.text = "COMBO x%d\n+%d" % [combo_count, combo_count * 10]
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.2, 1.0))
	else:
		lbl.text = "+%d" % (combo_count * 10)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))

	add_child(lbl)

	# Animacja: stała prędkość lotu do góry, zanik dopiero po chwili
	var fly_duration = 1.4
	var fade_delay = 0.55  # tyle czasu widoczny zanim zacznie znikać
	var tween = create_tween().set_parallel(true)
	# Liniowy lot — bez zwalniania, zero zatrzymań
	tween.tween_property(lbl, "position", px + Vector2(-80, -145), fly_duration).set_trans(Tween.TRANS_LINEAR)
	# Zanik startuje po fade_delay
	tween.tween_property(lbl, "modulate:a", 0.0, fly_duration - fade_delay).set_delay(fade_delay).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

func _hide_combo():
	pass  # teraz każdy napis jest samodzielny i sam znika

# ——————————————————————————————————————————
#  BUDOWANIE PLANSZY (bez zmian)
# ——————————————————————————————————————————

func _build_board():
	inner = BORDER + PADDING
	field_w = COLS * QUAD_SIZE + (COLS - 1) * GAP
	field_h = ROWS * QUAD_SIZE + (ROWS - 1) * GAP + PADDING
	goal_w = GOAL_COLS * QUAD_SIZE + (GOAL_COLS - 1) * GAP
	goal_h = QUAD_SIZE

	var board_w = field_w + inner * 2
	var board_h = field_h + goal_h * 2 + inner * 2
	custom_minimum_size = Vector2(board_w, board_h)

	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -board_w / 2.0
	offset_right = board_w / 2.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_top = -board_h / 2.0
	offset_bottom = board_h / 2.0

	var goal_panel_w = BORDER * 2 + PADDING * 2 + goal_w
	goal_h = BORDER + QUAD_SIZE

	board_h = field_h + goal_h * 2 + inner * 2 + PADDING + PADDING
	custom_minimum_size = Vector2(board_w, board_h)

	var goal_x = (board_w - goal_panel_w) / 2.0
	var goal_quad_x = goal_x + BORDER + PADDING

	_add_goal_bg(true, goal_x, goal_panel_w)
	_add_goal_bg(false, goal_x, goal_panel_w)
	_add_field_bg(board_w)

	var connector_x = goal_x + BORDER
	var connector_w = goal_panel_w - BORDER * 2

	var top_con = Panel.new()
	top_con.position = Vector2(connector_x, goal_h - 1)
	top_con.size = Vector2(connector_w, BORDER + 2)
	var s1 = StyleBoxFlat.new(); s1.bg_color = FIELD_COLOR
	top_con.add_theme_stylebox_override("panel", s1)
	add_child(top_con)

	var bot_con = Panel.new()
	bot_con.position = Vector2(connector_x, goal_h + inner * 2 + field_h - 1)
	bot_con.size = Vector2(connector_w, BORDER + 2)
	var s2 = StyleBoxFlat.new(); s2.bg_color = FIELD_COLOR
	bot_con.add_theme_stylebox_override("panel", s2)
	add_child(bot_con)

	var bot_con2 = Panel.new()
	bot_con2.position = Vector2(connector_x, goal_h + inner + field_h + inner - 2 * PADDING - 1)
	bot_con2.size = Vector2(connector_w, BORDER + 2 + PADDING)
	var s3 = StyleBoxFlat.new(); s3.bg_color = FIELD_COLOR
	bot_con2.add_theme_stylebox_override("panel", s3)
	add_child(bot_con2)

	# Górna bramka — AI (czerwona, quad_f4)
	for i in range(GOAL_COLS):
		_place_quad_type(Vector2(goal_quad_x + i * (QUAD_SIZE + GAP), BORDER + PADDING - 1), quad_f4)

	for row in range(ROWS):
		for col in range(COLS):
			var use_f2 = (row + col) % 2 == 1
			_place_quad(Vector2(
				inner + col * (QUAD_SIZE + GAP),
				goal_h + inner + row * (QUAD_SIZE + GAP)
			), use_f2)

	# Dolna bramka — gracz (niebieska, quad_f3)
	var bot_quad_y = goal_h + inner * 2 + field_h + BORDER + 1 - 3 * PADDING
	for i in range(GOAL_COLS):
		_place_quad_type(Vector2(goal_quad_x + i * (QUAD_SIZE + GAP), bot_quad_y), quad_f3)

func _place_quad(pos: Vector2, use_f2: bool):
	var quad = quad_f2.instantiate() if use_f2 else quad_f1.instantiate()
	quad.position = pos
	add_child(quad)

func _place_quad_type(pos: Vector2, quad_scene) -> void:
	var quad = quad_scene.instantiate()
	quad.position = pos
	add_child(quad)

func _add_field_bg(board_w: float):
	var panel = Panel.new()
	panel.position = Vector2(0, goal_h)
	panel.size = Vector2(board_w, field_h + inner * 2 - PADDING)
	var style = StyleBoxFlat.new()
	style.bg_color = FIELD_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = int(BORDER)
	style.border_width_right = int(BORDER)
	style.border_width_top = int(BORDER)
	style.border_width_bottom = int(BORDER)
	style.corner_radius_top_left = int(RADIUS)
	style.corner_radius_top_right = int(RADIUS)
	style.corner_radius_bottom_left = int(RADIUS)
	style.corner_radius_bottom_right = int(RADIUS)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

func _add_goal_bg(is_top: bool, goal_x: float, goal_panel_w: float):
	var goal_y = 0.0 if is_top else goal_h + inner * 2 + field_h - 2 * PADDING
	var panel = Panel.new()
	panel.position = Vector2(goal_x, goal_y)
	panel.size = Vector2(goal_panel_w, goal_h + BORDER)
	var style = StyleBoxFlat.new()
	style.bg_color = FIELD_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = int(BORDER)
	style.border_width_right = int(BORDER)
	style.border_width_top = int(BORDER) if is_top else 0
	style.border_width_bottom = 0 if is_top else int(BORDER)
	style.corner_radius_top_left = int(RADIUS) if is_top else 0
	style.corner_radius_top_right = int(RADIUS) if is_top else 0
	style.corner_radius_bottom_left = 0 if is_top else int(RADIUS)
	style.corner_radius_bottom_right = 0 if is_top else int(RADIUS)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
