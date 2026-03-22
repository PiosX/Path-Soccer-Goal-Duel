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
var COLS: int = 6
var ROWS: int = 8
var GOAL_COL_START: int = 2
var GOAL_COLS: int = 2

# ————— DANE POZIOMU —————
var level_data: Dictionary = {}
var obstacle_cells: Array = []   # [{row,col}] w układzie board (bez bramek)
var pre_lines_data: Array = []   # [{r1,c1,r2,c2}] węzły siatki
const BORDER = 8.0
const PADDING = 9.0
const RADIUS = 30.0
const CORNER_RADIUS = 22.0  # zaokrąglenie bordera boiska (takie jak w bramkach)
const FIELD_COLOR = Color("#448B47")
const BORDER_COLOR = Color.WHITE
const GAP = 9.0

# ————— KOLORY GRY —————
const DOT_COLOR       = Color(1.0, 1.0, 1.0, 0.5)
const DOT_ACTIVE_COLOR = Color(1.0, 0.9, 0.0, 1.0)
const TRAIL_P1_COLOR  = Color("#FFFFFF")
const TRAIL_P2_COLOR  = Color("#FFD700")
const PRE_LINE_COLOR  = Color("#aa44ff")  # fioletowe linie startowe

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

# ————— DRAG BOISKA —————
var _drag_active: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_scroll: Vector2 = Vector2.ZERO
var _scroll_container: ScrollContainer = null
var dot_nodes: Array = []   # [{node, gx, gy}]
var active_moves: Array = []
var _touch_moved: bool = false  # odróżnia drag od tapa na mobilce

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

# Czy węzeł jest w bounds (pole + bramki), z uwzględnieniem przeszkód
func is_valid_node(gx: int, gy: int) -> bool:
	if gx >= 0 and gx <= COLS and gy >= 0 and gy <= ROWS:
		return _node_accessible(gx, gy)
	if gy == -1 and gx >= GOAL_COL_START and gx <= GOAL_COL_START + GOAL_COLS:
		return true
	if gy == ROWS + 1 and gx >= GOAL_COL_START and gx <= GOAL_COL_START + GOAL_COLS:
		return true
	return false

# Czy komórka (row,col) jest przeszkodą lub poza boiskiem
func _cell_is_wall(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return true  # poza boiskiem = ściana
	return _is_obstacle(row, col)

# Czy krawędź jest niedozwolona (leży wzdłuż ściany lub przez nią)
func is_wall_edge(a: Vector2i, b: Vector2i) -> bool:
	# Lewa/prawa ściana — ruch równoległy wzdłuż niej
	if a.x == 0 and b.x == 0: return true
	if a.x == COLS and b.x == COLS: return true

	# Górna/dolna linia boiska — ruch poziomy wzdłuż niej poza zakresem bramki
	if a.y == 0 and b.y == 0:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS):
			return true
	if a.y == ROWS and b.y == ROWS:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS):
			return true

	# Ruch pionowy wzdłuż słupka bramki (między polem a wnętrzem bramki)
	if a.x == b.x and abs(a.y - b.y) == 1:
		var bx = a.x
		if bx == GOAL_COL_START or bx == GOAL_COL_START + GOAL_COLS:
			var miny = mini(a.y, b.y); var maxy = maxi(a.y, b.y)
			if (miny == -1 and maxy == 0) or (miny == ROWS and maxy == ROWS + 1):
				return true

	# Przekątna: blokuj gdy oba boczne węzły są na ścianie/obstacle
	# (używamy poprawionej _node_on_wall_or_obstacle która wyklucza interior bramki)
	if abs(a.x - b.x) == 1 and abs(a.y - b.y) == 1:
		var side_a = Vector2i(b.x, a.y)
		var side_b = Vector2i(a.x, b.y)
		if not is_valid_node(side_a.x, side_a.y) and not is_valid_node(side_b.x, side_b.y):
			return true
		if is_valid_node(side_a.x, side_a.y) and is_valid_node(side_b.x, side_b.y):
			if _node_on_wall_or_obstacle(side_a) and _node_on_wall_or_obstacle(side_b):
				return true
		# Jeden nieistniejący + drugi na ścianie = blokuj
		if not is_valid_node(side_a.x, side_a.y) and is_valid_node(side_b.x, side_b.y) and _node_on_wall_or_obstacle(side_b):
			return true
		if not is_valid_node(side_b.x, side_b.y) and is_valid_node(side_a.x, side_a.y) and _node_on_wall_or_obstacle(side_a):
			return true

	# Poziomy/pionowy ruch wzdłuż granicy obstacle
	var a_is_goal = (a.y < 0 or a.y > ROWS)
	var b_is_goal = (b.y < 0 or b.y > ROWS)
	if not a_is_goal and not b_is_goal:
		if abs(a.x - b.x) == 1 and a.y == b.y:
			if a.y == 0 or a.y == ROWS:
				pass  # już obsłużone wyżej (linie 123-130)
			else:
				var top_l = _cell_is_wall(a.y - 1, mini(a.x, b.x))
				var top_r = _cell_is_wall(a.y - 1, maxi(a.x, b.x) - 1)
				if top_l and top_r: return true
				var bot_l = _cell_is_wall(a.y, mini(a.x, b.x))
				var bot_r = _cell_is_wall(a.y, maxi(a.x, b.x) - 1)
				if bot_l and bot_r: return true
		elif a.x == b.x and abs(a.y - b.y) == 1:
			var lft_t = _cell_is_wall(mini(a.y, b.y),     a.x - 1)
			var lft_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x - 1)
			if lft_t and lft_b: return true
			var rgt_t = _cell_is_wall(mini(a.y, b.y),     a.x)
			var rgt_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x)
			if rgt_t and rgt_b: return true

	return false

# Czy węzeł (gx,gy) leży na ścianie boiska lub na granicy obstacle
func _node_on_wall_or_obstacle(n: Vector2i) -> bool:
	# Na ścianie zewnętrznej — ale węzły na linii y=0 lub y=ROWS WEWNĄTRZ bramki
	# (między słupkami, nie wliczając słupków) to otwarte wejście, nie ściana
	var in_goal_interior = (n.x > GOAL_COL_START and n.x < GOAL_COL_START + GOAL_COLS)
	if n.x == 0 or n.x == COLS: return true
	if (n.y == 0 or n.y == ROWS) and not in_goal_interior: return true
	# Na granicy obstacle
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var cr = n.y + dr; var cc = n.x + dc
			if cr >= 0 and cr < ROWS and cc >= 0 and cc < COLS:
				if _is_obstacle(cr, cc):
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

# Odbicie = węzeł był już odwiedzony lub jest węzłem ściany/obstacle (bariera)
func node_has_any_trail(pos: Vector2i) -> bool:
	var count = 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if used_edges.has(edge_key(pos, nb)):
				count += 1
	if pos.x == 0: count += 1
	if pos.x == COLS: count += 1
	# y=0/y=ROWS: ściana wszędzie poza wnętrzem bramki (między słupkami exclusive)
	var in_goal_interior = (pos.x > GOAL_COL_START and pos.x < GOAL_COL_START + GOAL_COLS)
	if pos.y == 0 and not in_goal_interior: count += 1
	if pos.y == ROWS and not in_goal_interior: count += 1
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var cr = pos.y + dr; var cc = pos.x + dc
			if cr >= 0 and cr < ROWS and cc >= 0 and cc < COLS:
				if _is_obstacle(cr, cc):
					count += 1
	return count >= 2

# ——————————————————————————————————————————
#  INICJALIZACJA
# ——————————————————————————————————————————

func _ready():
	if not level_data.is_empty():
		_apply_level_data()
	_build_board()
	_setup_game()
	# Postaw startowe linie PO _setup_game (który czyści used_edges)
	_place_pre_lines()

func _place_pre_lines():
	for ln in pre_lines_data:
		var a = Vector2i(ln.c1, ln.r1)
		var b = Vector2i(ln.c2, ln.r2)
		if a.x < 0 or a.x > COLS or a.y < 0 or a.y > ROWS: continue
		if b.x < 0 or b.x > COLS or b.y < 0 or b.y > ROWS: continue
		var ek = edge_key(a, b)
		if not used_edges.has(ek):
			used_edges[ek] = true
			_draw_trail_colored(a, b, PRE_LINE_COLOR)

func _draw_trail_colored(from: Vector2i, to: Vector2i, color: Color) -> Line2D:
	var line = Line2D.new()
	# grid_to_pixel zwraca środek węzła — linia wyśrodkowana na kropkach
	line.add_point(grid_to_pixel(from.x, from.y))
	line.add_point(grid_to_pixel(to.x, to.y))
	line.width = 6.0
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = 7
	add_child(line)
	return line

# Przetłumacz dane JSON na wymiary board.gd
# WAŻNE: w edytorze grid[0] i grid[rows-1] to bramki wliczone w rozmiar.
# W board.gd ROWS = liczba wierszy POLA (bez bramek), bramki są na gy=-1 i gy=ROWS+1.
# Więc: ROWS = editor_rows - 2, COLS = editor_cols
func _apply_level_data():
	var ed_cols = int(level_data.get("cols", 6))
	var ed_rows = int(level_data.get("rows", 10))
	var grid = level_data.get("grid", [])
	
	# Bramki zajmują wiersz 0 i wiersz ed_rows-1 w edytorze
	# Pole gry = wiersze 1..ed_rows-2 => ROWS = ed_rows - 2
	COLS = ed_cols
	ROWS = ed_rows - 2
	
	# Wykryj GOAL_COL_START i GOAL_COLS z wiersza bramki (wiersz 0 = GOAL_RED)
	var goal_cols = []
	if grid.size() > 0:
		for c in range((grid[0] as Array).size()):
			if int(grid[0][c]) == 3:  # GOAL_RED
				goal_cols.append(c)
	if goal_cols.size() > 0:
		goal_cols.sort()
		GOAL_COL_START = goal_cols[0]
		GOAL_COLS = goal_cols[-1] - goal_cols[0] + 1
	
	# Przeszkody — wiersze 1..ed_rows-2, przetłumacz na board row = editor_row - 1
	# EMPTY(0) też jest wyłączone — kształt boiska pochodzi z edytora
	obstacle_cells = []
	for er in range(1, ed_rows - 1):
		if er >= grid.size(): continue
		for c in range(ed_cols):
			var cell_val = int(grid[er][c])
			if cell_val == 4 or cell_val == 0:  # OBSTACLE lub EMPTY = wykluczone
				obstacle_cells.append({"row": er - 1, "col": c})
	
	# Linie startowe — węzły siatki (r,c) gdzie r=0 to góra pola (nad wierszem 1 edytora)
	# Węzeł r w edytorze odpowiada węzłowi r-1 w board (bo wiersz 0 edytora = bramka)
	pre_lines_data = []
	for ln in level_data.get("pre_lines", []):
		pre_lines_data.append({
			"r1": int(ln.get("r1",0)) - 1,
			"c1": int(ln.get("c1",0)),
			"r2": int(ln.get("r2",0)) - 1,
			"c2": int(ln.get("c2",0))
		})

func _setup_game():
	_kill_all_tweens()
	# Znajdź ScrollContainer przy starcie
	if not _scroll_container:
		_scroll_container = _find_scroll_parent()

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
	# Postaw startowe linie po każdym resecie (działa też przy reload)
	_place_pre_lines()

func _find_scroll_parent() -> ScrollContainer:
	var node = get_parent()
	while node:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null

# ——————————————————————————————————————————
#  SIATKA KROPEK
# ——————————————————————————————————————————

func _draw_grid_dots():
	# Węzły pola głównego — tylko te które mają co najmniej jedną aktywną sąsiednią komórkę
	for gx in range(COLS + 1):
		for gy in range(ROWS + 1):
			var dot
			if _dot_inside_field(gx, gy):
				dot = _make_dot(grid_to_pixel(gx, gy), false)
			else:
				dot = _make_dot_invisible(grid_to_pixel(gx, gy))
			dot_nodes.append({"node": dot, "gx": gx, "gy": gy})
	# Węzły bramek — widoczne tylko gdy aktywne
	for gx in range(GOAL_COL_START, GOAL_COL_START + GOAL_COLS + 1):
		var dot = _make_dot(grid_to_pixel(gx, -1), false)
		dot.set_meta("goal_node", true)
		dot_nodes.append({"node": dot, "gx": gx, "gy": -1})
	for gx in range(GOAL_COL_START, GOAL_COL_START + GOAL_COLS + 1):
		var dot = _make_dot(grid_to_pixel(gx, ROWS + 1), false)
		dot.set_meta("goal_node", true)
		dot_nodes.append({"node": dot, "gx": gx, "gy": ROWS + 1})

# Czy węzeł (gx,gy) powinien mieć widoczną kropkę.
# Pokaż jeśli co najmniej 2 z 4 przylegających komórek są aktywne.
# Zewnętrzny róg kształtu ma dokładnie 1 aktywną komórkę — ukryty.
# Wewnętrzny róg obstacle ma 2+ aktywne komórki — widoczny.
func _dot_inside_field(gx: int, gy: int) -> bool:
	var count = 0
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var r = gy + dr
			var c = gx + dc
			if c < 0 or c >= COLS:
				pass  # poza lewą/prawą ścianą — nie liczymy
			elif r < 0:
				# Powyżej pola — liczymy tylko jeśli kolumna jest wewnątrz bramki górnej
				if c >= GOAL_COL_START and c < GOAL_COL_START + GOAL_COLS:
					count += 1
			elif r >= ROWS:
				# Poniżej pola — liczymy tylko jeśli kolumna jest wewnątrz bramki dolnej
				if c >= GOAL_COL_START and c < GOAL_COL_START + GOAL_COLS:
					count += 1
			elif not _is_obstacle(r, c):
				count += 1
	return count >= 2

func _cell_active(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS: return false
	return not _is_obstacle(row, col)

# Węzeł niewidoczny — istnieje dla logiki gry ale nie rysowany
func _make_dot_invisible(pos: Vector2) -> Node2D:
	var dot = Node2D.new()
	dot.position = pos
	dot.z_index = 6
	dot.set_meta("active", false)
	dot.set_meta("pulse_scale", 1.0)
	dot.set_meta("invisible", true)
	dot.draw.connect(_on_dot_draw.bind(dot))
	add_child(dot)
	return dot

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
	if dot.get_meta("invisible", false): return
	var is_active: bool = dot.get_meta("active")
	var ps: float = dot.get_meta("pulse_scale")
	if is_active:
		dot.draw_circle(Vector2.ZERO, 10.0 * ps, Color(1.0, 0.9, 0.0, 0.55 * ps))
		dot.draw_circle(Vector2.ZERO, 5.5 * ps, Color(1.0, 0.95, 0.2, 0.95))
	elif not dot.get_meta("goal_node", false):
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

var _active_tweens: Array = []  # śledź tweeny żeby je killować przy reload

func _start_pulse(dot: Node2D):
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_active_tweens.append(tween)
	tween.tween_method(_pulse_up.bind(dot, tween), 1.0, 1.25, 0.55)
	tween.tween_method(_pulse_down.bind(dot), 1.25, 1.0, 0.55)

func _pulse_up(v: float, dot: Node2D, tween: Tween):
	if not is_instance_valid(dot):
		tween.kill()
		return
	if not dot.get_meta("active", false):
		tween.kill()
		dot.set_meta("pulse_scale", 1.0)
		dot.queue_redraw()
		return
	dot.set_meta("pulse_scale", v)
	dot.queue_redraw()

func _pulse_down(v: float, dot: Node2D):
	if not is_instance_valid(dot): return
	dot.set_meta("pulse_scale", v)
	dot.queue_redraw()

func _kill_all_tweens():
	for t in _active_tweens:
		if t and is_instance_valid(t): t.kill()
	_active_tweens.clear()

# ——————————————————————————————————————————
#  INPUT
# ——————————————————————————————————————————

func _input(event: InputEvent):
	# ── Drag boiska ────────────────────────────────────────────────────────
	if _scroll_container:
		var is_rmb        = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT
		var is_drag_mouse = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT)
		var is_touch      = event is InputEventScreenTouch
		var is_drag_touch = event is InputEventScreenDrag

		if is_rmb and event.pressed and not ai_thinking:
			_drag_active = true
			_drag_start_mouse = event.position
			_drag_start_scroll = Vector2(_scroll_container.scroll_horizontal, _scroll_container.scroll_vertical)
		if is_rmb and not event.pressed:
			_drag_active = false
		if _drag_active and is_drag_mouse:
			var delta = _drag_start_mouse - event.position
			_scroll_container.scroll_horizontal = int(_drag_start_scroll.x + delta.x)
			_scroll_container.scroll_vertical   = int(_drag_start_scroll.y + delta.y)
			get_viewport().set_input_as_handled()
			return

		if is_touch and event.pressed:
			_drag_active = true
			_touch_moved = false
			_drag_start_mouse = event.position
			_drag_start_scroll = Vector2(_scroll_container.scroll_horizontal, _scroll_container.scroll_vertical)
			return
		if is_drag_touch and _drag_active:
			var delta = _drag_start_mouse - event.position
			if delta.length() > 8.0:
				_touch_moved = true
			_scroll_container.scroll_horizontal = int(_drag_start_scroll.x + delta.x)
			_scroll_container.scroll_vertical   = int(_drag_start_scroll.y + delta.y)
			get_viewport().set_input_as_handled()
			return
		if is_touch and not event.pressed:
			_drag_active = false
			if not _touch_moved and not ai_thinking:
				_try_move(get_global_transform().affine_inverse() * event.position)
			_touch_moved = false
			get_viewport().set_input_as_handled()
			return

	var pressed = false
	var click_pos = Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		click_pos = event.position
	elif event is InputEventScreenTouch and event.pressed and not _scroll_container:
		pressed = true
		click_pos = event.position
	if not pressed: return
	if ai_thinking: return
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
	line.joint_mode = Line2D.LINE_JOINT_ROUND
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
	# Minimax bez wątku — używamy call_deferred żeby nie blokować animacji
	var best = _minimax_root(ball_grid_pos, used_edges.duplicate(), AI_PLAYER, AI_DEPTH)
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
	var in_goal_interior = (pos.x > GOAL_COL_START and pos.x < GOAL_COL_START + GOAL_COLS)
	if pos.y == 0 and not in_goal_interior: count += 1
	if pos.y == ROWS and not in_goal_interior: count += 1
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var cr = pos.y + dr; var cc = pos.x + dc
			if cr >= 0 and cr < ROWS and cc >= 0 and cc < COLS:
				if _is_obstacle(cr, cc):
					count += 1
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
		if target_is_top and pos.y < 0:
			return true
		if not target_is_top and pos.y > ROWS:
			return true
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(pos.x + dx, pos.y + dy)
				if visited.has(nb): continue
				if not is_valid_node(nb.x, nb.y): continue
				if used_edges.has(edge_key(pos, nb)): continue
				# BFS używa tylko FIZYCZNYCH barier — nie blokuje ruchów wzdłuż obstacle
				# (te są niedozwolone w grze ale nie tworzą fizycznej ściany dla BFS)
				if _is_physical_wall(pos, nb): continue
				visited[nb] = true
				queue.append(nb)
	return false

# Tylko twarde fizyczne bariery dla BFS (ściany boiska + przekątne przez nieaktywne węzły)
# NIE blokuje ruchów wzdłuż granicy obstacle — to zakaz gry, nie fizyczna ściana
func _is_physical_wall(a: Vector2i, b: Vector2i) -> bool:
	# Ściany zewnętrzne
	if a.x == 0 and b.x == 0: return true
	if a.x == COLS and b.x == COLS: return true
	if a.y == 0 and b.y == 0:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS): return true
	if a.y == ROWS and b.y == ROWS:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS): return true
	# Przekątna przez nieaktywny węzeł
	if abs(a.x - b.x) == 1 and abs(a.y - b.y) == 1:
		var sa = Vector2i(b.x, a.y); var sb = Vector2i(a.x, b.y)
		if not is_valid_node(sa.x, sa.y) or not is_valid_node(sb.x, sb.y): return true
	return false

# Sprawdź czy węzeł (gx,gy) jest dostępny — otoczony przynajmniej jedną niebędącą przeszkodą komórką
func _node_accessible(gx: int, gy: int) -> bool:
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var cr = gy + dr; var cc = gx + dc
			if cr < 0 or cr >= ROWS or cc < 0 or cc >= COLS:
				return true  # krawędź boiska
			if not _is_obstacle(cr, cc):
				return true
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

func _is_obstacle(row: int, col: int) -> bool:
	for obs in obstacle_cells:
		if obs.row == row and obs.col == col:
			return true
	return false

func _build_board():
	inner   = BORDER + PADDING
	field_w = COLS      * QUAD_SIZE + (COLS      - 1) * GAP
	field_h = ROWS      * QUAD_SIZE + (ROWS      - 1) * GAP
	goal_w  = GOAL_COLS * QUAD_SIZE + (GOAL_COLS - 1) * GAP

	# goal_h = dokładnie jeden krok siatki + inner (żeby bramka była odsunięta
	# od boiska o tyle samo co kafelki boiska od siebie)
	# Krok siatki = QUAD_SIZE + GAP, inner = BORDER + PADDING
	# goal_h to odległość od y=0 do pierwszego wiersza boiska
	# goal_h = QUAD_SIZE + GAP  →  row_cy(-1) = goal_h + inner - (QUAD_SIZE+GAP) = inner ✓
	# Kafelek bramki ląduje dokładnie na y=inner, identycznie jak place_quad_type
	goal_h = QUAD_SIZE + GAP

	var board_w = field_w + inner * 2
	var board_h = goal_h * 2 + inner * 2 + field_h
	# board_h = inner + bramka_górna(QUAD_SIZE+GAP) + inner + boisko + inner + bramka_dolna(QUAD_SIZE+GAP) + inner

	custom_minimum_size = Vector2(board_w, board_h)
	anchor_left = 0.5; anchor_right  = 0.5
	anchor_top  = 0.5; anchor_bottom = 0.5
	offset_left   = -board_w / 2.0; offset_right  = board_w / 2.0
	offset_top    = -board_h / 2.0; offset_bottom = board_h / 2.0

	# Szerokość panelu bramki: border + padding + kafelki bramki + padding + border
	var goal_panel_w = BORDER * 2 + PADDING * 2 + goal_w
	var goal_x       = (board_w - goal_panel_w) / 2.0
	var goal_quad_x  = goal_x + BORDER + PADDING

	_add_field_bg(board_w)

	# Kafelki górnej bramki: pozycja y = inner (padding od góry)
	# To odpowiada row=-1 w siatce: goal_h + inner + (-1)*(QUAD_SIZE+GAP) = inner
	for i in range(GOAL_COLS):
		_place_quad_type(Vector2(goal_quad_x + i * (QUAD_SIZE + GAP), inner), quad_f4)

	# Kafelki boiska
	for row in range(ROWS):
		for col in range(COLS):
			if _is_obstacle(row, col): continue
			var use_f2 = (row + col) % 2 == 1
			_place_quad(Vector2(
				inner + col * (QUAD_SIZE + GAP),
				goal_h + inner + row * (QUAD_SIZE + GAP)
			), use_f2)

	# Kafelki dolnej bramki: row=ROWS → goal_h + inner + ROWS*(QUAD_SIZE+GAP)
	var bot_quad_y = goal_h + inner + ROWS * (QUAD_SIZE + GAP)
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

func _add_field_bg(_board_w: float):
	_add_shaped_field_bg()

func _add_shaped_field_bg():
	# Tło: panel na każdą aktywną komórkę (boisko + bramki).
	# Rozszerzamy o GAP/2+1 w kierunku sąsiada żeby nie było szczelin.
	var ovr = GAP / 2.0 + 1.0

	# Pomocnik pozycji y dla wiersza (bramki to row=-1 i row=ROWS)
	var row_cy = func(row: int) -> float:
		return float(goal_h + inner + row * (QUAD_SIZE + GAP))

	# Boisko
	for row in range(ROWS):
		for col in range(COLS):
			if _is_obstacle(row, col): continue
			var cx = inner + col * (QUAD_SIZE + GAP)
			var cy = row_cy.call(row)
			var has_l = col > 0      and not _is_obstacle(row, col-1)
			var has_r = col < COLS-1 and not _is_obstacle(row, col+1)
			var has_t = row > 0      and not _is_obstacle(row-1, col)
			var has_b = row < ROWS-1 and not _is_obstacle(row+1, col)
			var goal_t = row == 0      and _is_goal_col(col)
			var goal_b = row == ROWS-1 and _is_goal_col(col)
			var el = ovr if has_l          else 1.0
			var er = ovr if has_r          else 1.0
			var et = ovr if (has_t or goal_t) else 1.0
			var eb = ovr if (has_b or goal_b) else 1.0
			var cell = Panel.new()
			cell.position = Vector2(cx - el, cy - et)
			cell.size     = Vector2(QUAD_SIZE + el + er, QUAD_SIZE + et + eb)
			var sty = StyleBoxFlat.new(); sty.bg_color = FIELD_COLOR
			cell.add_theme_stylebox_override("panel", sty)
			cell.z_index = 0
			add_child(cell)

	# Bramki (row=-1 i row=ROWS) — jeden szeroki panel na wszystkie kolumny bramki
	var goal_cx_start = inner + GOAL_COL_START * (QUAD_SIZE + GAP)
	var goal_cx_end   = inner + (GOAL_COL_START + GOAL_COLS - 1) * (QUAD_SIZE + GAP) + QUAD_SIZE
	var goal_bg_w     = goal_cx_end - goal_cx_start
	# Górna: od cy_top-1 do cy_0 + QUAD_SIZE + ovr
	var cy_top = row_cy.call(-1)
	var cy_0   = row_cy.call(0)
	var gt = Panel.new()
	gt.position = Vector2(goal_cx_start - 1.0, cy_top - 1.0)
	gt.size     = Vector2(goal_bg_w + 2.0, (cy_0 + QUAD_SIZE + ovr) - (cy_top - 1.0) + 1.0)
	var st = StyleBoxFlat.new(); st.bg_color = FIELD_COLOR
	gt.add_theme_stylebox_override("panel", st); gt.z_index = 0; add_child(gt)
	# Dolna: od cy_last + QUAD_SIZE - ovr do cy_bot + QUAD_SIZE + 1
	var cy_bot  = row_cy.call(ROWS)
	var cy_last = row_cy.call(ROWS - 1)
	var gb = Panel.new()
	gb.position = Vector2(goal_cx_start - 1.0, cy_last + QUAD_SIZE - ovr - 1.0)
	gb.size     = Vector2(goal_bg_w + 2.0, (cy_bot + QUAD_SIZE + 1.0) - (cy_last + QUAD_SIZE - ovr - 1.0))
	var sb = StyleBoxFlat.new(); sb.bg_color = FIELD_COLOR
	gb.add_theme_stylebox_override("panel", sb); gb.z_index = 0; add_child(gb)

	# Border
	var bnode = Node2D.new()
	bnode.z_index = 3
	add_child(bnode)
	bnode.draw.connect(Callable(self, "_draw_shaped_border").bind(bnode))
	bnode.queue_redraw()

func _is_goal_col(col: int) -> bool:
	return col >= GOAL_COL_START and col <= GOAL_COL_START + GOAL_COLS - 1

func _draw_shaped_border(bnode: Node2D):
	if not is_instance_valid(bnode): return
	var bw  = float(BORDER) - 2.0  # rysuj nieco cieniej żeby nie wystawało poza pad
	var pad = 4.0
	var rc  = CORNER_RADIUS

	var row_cy = func(row: int) -> float:
		return float(goal_h + inner + row * (QUAD_SIZE + GAP))

	var active_set: Dictionary = {}
	for row in range(ROWS):
		for col in range(COLS):
			if not _is_obstacle(row, col):
				active_set[Vector2i(col, row)] = true
	for i in range(GOAL_COLS):
		active_set[Vector2i(GOAL_COL_START + i, -1)]  = true
		active_set[Vector2i(GOAL_COL_START + i, ROWS)] = true

	var h_edges: Array = []
	var v_edges: Array = []

	for cell_key in active_set:
		var col: int = cell_key.x
		var row: int = cell_key.y
		var cx = inner + col * (QUAD_SIZE + GAP)
		var cy = row_cy.call(row)
		var x0 = cx - pad;             var y0 = cy - pad
		var x1 = cx + QUAD_SIZE + pad;  var y1 = cy + QUAD_SIZE + pad

		var ht = active_set.has(Vector2i(col, row - 1))
		var hb = active_set.has(Vector2i(col, row + 1))
		var hl = active_set.has(Vector2i(col - 1, row))
		var hr = active_set.has(Vector2i(col + 1, row))

		if not ht: h_edges.append({"y":y0,"x1":x0,"x2":x1,"lft_corner":not hl,"rgt_corner":not hr,"inner":1})
		if not hb: h_edges.append({"y":y1,"x1":x0,"x2":x1,"lft_corner":not hl,"rgt_corner":not hr,"inner":-1})
		if not hl: v_edges.append({"x":x0,"y1":y0,"y2":y1,"top_corner":not ht,"bot_corner":not hb,"inner":1})
		if not hr: v_edges.append({"x":x1,"y1":y0,"y2":y1,"top_corner":not ht,"bot_corner":not hb,"inner":-1})

	var merged_h = _merge_edges_h(h_edges)
	var merged_v = _merge_edges_v(v_edges)

	# ── Wykryj narożniki geometrycznie (nie przez flagi) ──────────────────────
	# Narożnik istnieje gdy koniec v_seg pokrywa się z końcem h_seg (w tolerancji tol).
	# To jest jedyne wiarygodne źródło informacji — flagi corner mogą być złe po scaleniu.
	var tol = pad * 2.0 + 2.0
	# Zbuduj słowniki: punkt → lista segmentów kończących/zaczynających się tam
	# corner_map: Vector2i(round_x, round_y) -> {"TL","TR","BL","BR"}
	var corners: Array = []  # [{vx, hy, type}]
	for hs in merged_h:
		for vs in merged_v:
			var lx_match = abs(hs.x1 - vs.x) < tol
			var rx_match = abs(hs.x2 - vs.x) < tol
			var ty_match = abs(hs.y - vs.y1) < tol
			var by_match = abs(hs.y - vs.y2) < tol
			if lx_match and ty_match: corners.append({"vx":vs.x,"hy":hs.y,"t":"TL","ih":hs.inner,"iv":vs.inner})
			if rx_match and ty_match: corners.append({"vx":vs.x,"hy":hs.y,"t":"TR","ih":hs.inner,"iv":vs.inner})
			if lx_match and by_match: corners.append({"vx":vs.x,"hy":hs.y,"t":"BL","ih":hs.inner,"iv":vs.inner})
			if rx_match and by_match: corners.append({"vx":vs.x,"hy":hs.y,"t":"BR","ih":hs.inner,"iv":vs.inner})

	# Sprawdź czy koniec segmentu ma narożnik — szukamy bezpośrednio w corners[]
	# zamiast w corner_set (który ma 1-2px rozbieżność między vx/hy a x1/y2 segmentów)
	var ctol = tol  # ta sama tolerancja co przy wykrywaniu
	var h_has_lft_corner = func(e) -> bool:
		for c in corners:
			if (c.t == "TL" or c.t == "BL") and abs(e.x1 - c.vx) < ctol and abs(e.y - c.hy) < ctol:
				return true
		return false
	var h_has_rgt_corner = func(e) -> bool:
		for c in corners:
			if (c.t == "TR" or c.t == "BR") and abs(e.x2 - c.vx) < ctol and abs(e.y - c.hy) < ctol:
				return true
		return false
	var v_has_top_corner = func(e) -> bool:
		for c in corners:
			if (c.t == "TL" or c.t == "TR") and abs(e.x - c.vx) < ctol and abs(e.y1 - c.hy) < ctol:
				return true
		return false
	var v_has_bot_corner = func(e) -> bool:
		for c in corners:
			if (c.t == "BL" or c.t == "BR") and abs(e.x - c.vx) < ctol and abs(e.y2 - c.hy) < ctol:
				return true
		return false

	# ── Rysuj linie skrócone o rc+bw/2 przy narożnikach ─────────────────────
	# Skracamy o rc + bw/2 żeby kwadratowy koniec linii był schowany pod łukiem
	var extra = bw * 0.5
	for e in merged_h:
		var rl = rc + extra if h_has_lft_corner.call(e) else 0.0
		var rr = rc + extra if h_has_rgt_corner.call(e) else 0.0
		if e.x1 + rl < e.x2 - rr:
			bnode.draw_line(Vector2(e.x1 + rl, e.y), Vector2(e.x2 - rr, e.y), BORDER_COLOR, bw, false)

	for e in merged_v:
		var rt = rc + extra if v_has_top_corner.call(e) else 0.0
		var rb = rc + extra if v_has_bot_corner.call(e) else 0.0
		if e.y1 + rt < e.y2 - rb:
			bnode.draw_line(Vector2(e.x, e.y1 + rt), Vector2(e.x, e.y2 - rb), BORDER_COLOR, bw, false)

	# ── Rysuj łuki ────────────────────────────────────────────────────────────
	for c in corners:
		# Narożnik jest "wklęsły" (trójkąt do środka) gdy:
		# TL: wnętrze jest w dół (ih=+1) ORAZ w prawo (iv=+1)
		# TR: wnętrze jest w dół (ih=+1) ORAZ w lewo (iv=-1)
		# BL: wnętrze jest w górę (ih=-1) ORAZ w prawo (iv=+1)
		# BR: wnętrze jest w górę (ih=-1) ORAZ w lewo (iv=-1)
		var concave: bool
		match c.t:
			"TL": concave = (c.ih ==  1 and c.iv ==  1)
			"TR": concave = (c.ih ==  1 and c.iv == -1)
			"BL": concave = (c.ih == -1 and c.iv ==  1)
			"BR": concave = (c.ih == -1 and c.iv == -1)
			_:    concave = true
		var corner_type = c.t if concave else c.t + "_wall"
		_draw_corner(bnode, c.vx, c.hy, rc, bw, corner_type)

func _draw_corner(node: Node2D, vx: float, hy: float, rc: float, bw: float, corner: String):
	var s = rc  # rozmiar trójkąta = radius łuku
	match corner:
		# ── Wklęsłe rogi wewnątrz pola (zielony trójkąt przed łukiem) ──
		"TL":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx+s-5, hy-5),
				Vector2(vx+s-5, hy+s-5),
				Vector2(vx-5,   hy+s-5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx+rc, hy+rc), rc, PI,     PI*1.5, BORDER_COLOR, bw)
		"TR":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx-s+5, hy-5),
				Vector2(vx-s+5, hy+s-5),
				Vector2(vx+5,   hy+s-5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx-rc, hy+rc), rc, PI*1.5, PI*2.0, BORDER_COLOR, bw)
		"BL":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx+5,   hy-5),
				Vector2(vx+s, hy),
				Vector2(vx,   hy-s)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx+rc, hy-rc), rc, PI*0.5, PI,     BORDER_COLOR, bw)
		"BR":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx-5,   hy-5),
				Vector2(vx-s, hy),
				Vector2(vx,   hy-s)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx-rc, hy-rc), rc, 0.0,    PI*0.5, BORDER_COLOR, bw)
		# ── Zewnętrzne rogi ścian (zakryj trójkątną lukę za łukiem) ──
		"TL_wall":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx-5,    hy-5),
				Vector2(vx+s-5,  hy-5),
				Vector2(vx-5,    hy+s-5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx+rc, hy+rc), rc, PI,     PI*1.5, BORDER_COLOR, bw)
		"TR_wall":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx+5,    hy-5),
				Vector2(vx-s+5,  hy-5),
				Vector2(vx+5,    hy+s-5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx-rc, hy+rc), rc, PI*1.5, PI*2.0, BORDER_COLOR, bw)
		"BL_wall":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx-5,    hy+5),
				Vector2(vx+s-5,  hy+5),
				Vector2(vx-5,    hy-s+5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx+rc, hy-rc), rc, PI*0.5, PI,     BORDER_COLOR, bw)
		"BR_wall":
			node.draw_colored_polygon(PackedVector2Array([
				Vector2(vx+5,    hy+5),
				Vector2(vx-s+5,  hy+5),
				Vector2(vx+5,    hy-s+5)
			]), FIELD_COLOR)
			_draw_arc(node, Vector2(vx-rc, hy-rc), rc, 0.0,    PI*0.5, BORDER_COLOR, bw)

func _merge_edges_h(edges: Array) -> Array:
	# Scal segmenty na tej samej linii y, stykające się końce x
	# Tolerancja scalania = GAP + 2*pad (odstęp między sąsiednimi kafelkami w tej samej linii)
	var merge_tol = GAP + 2.0 * 4.0 + 1.0  # GAP + 2*pad + 1
	var by_y: Dictionary = {}
	for e in edges:
		var key = roundi(e.y * 2.0)
		if not by_y.has(key): by_y[key] = []
		by_y[key].append(e)
	var result: Array = []
	for key in by_y:
		var grp: Array = by_y[key]
		grp.sort_custom(func(a, b): return a.x1 < b.x1)
		var cur = grp[0].duplicate()
		for i in range(1, grp.size()):
			var s = grp[i]
			if s.x1 <= cur.x2 + merge_tol:
				cur.x2 = maxf(cur.x2, s.x2)
				cur["rgt_corner"] = s.rgt_corner
			else:
				result.append(cur)
				cur = s.duplicate()
		result.append(cur)
	return result

func _merge_edges_v(edges: Array) -> Array:
	# Scalanie wzdłuż y — tolerancja uwzględnia odstęp między bramką a boiskiem
	# Bramka (row=-1) kończy się na cy + QUAD_SIZE + pad
	# Boisko row=0 zaczyna na cy - pad = goal_h + inner - pad
	# Odstęp = (goal_h+inner-pad) - (goal_h+inner+(-1)*(QUAD_SIZE+GAP)+QUAD_SIZE+pad)
	#        = GAP - 2*pad  (może być małe lub ujemne)
	# Używamy tej samej tolerancji co dla h
	var merge_tol = GAP + 2.0 * 4.0 + 1.0
	var by_x: Dictionary = {}
	for e in edges:
		var key = roundi(e.x * 2.0)
		if not by_x.has(key): by_x[key] = []
		by_x[key].append(e)
	var result: Array = []
	for key in by_x:
		var grp: Array = by_x[key]
		grp.sort_custom(func(a, b): return a.y1 < b.y1)
		var cur = grp[0].duplicate()
		for i in range(1, grp.size()):
			var s = grp[i]
			if s.y1 <= cur.y2 + merge_tol:
				cur.y2 = maxf(cur.y2, s.y2)
				cur["bot_corner"] = s.bot_corner
			else:
				result.append(cur)
				cur = s.duplicate()
		result.append(cur)
	return result

func _draw_arc(node: Node2D, center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color, width: float):
	var points = PackedVector2Array()
	var steps = 12
	for i in range(steps + 1):
		var angle = angle_from + (angle_to - angle_from) * float(i) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	node.draw_polyline(points, color, width, true)
