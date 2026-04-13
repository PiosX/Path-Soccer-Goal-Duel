extends Control

# ————— ZASOBY —————
var quad_f1 = preload("res://scenes/quad_f1.tscn")
var quad_f2 = preload("res://scenes/quad_f2.tscn")
var quad_f3 = preload("res://scenes/quad_f3.tscn")  # niebieskie — bramka gracza (dół)
var quad_f4 = preload("res://scenes/quad_f4.tscn")  # czerwone — bramka AI (góra)
var tex_skin: Texture2D = null  # wczytywany dynamicznie z equipped_skin
var scene_complete = preload("res://scenes/level_complete.tscn")
var scene_failed  = preload("res://scenes/level_failed.tscn")

# ————— WYMIARY —————
const QUAD_SIZE = 90.0
var COLS: int = 6
var ROWS: int = 8
var GOAL_COL_START: int = 2
var GOAL_COLS: int = 2
var GOAL_COL_START_RED: int = 2
var GOAL_COLS_RED: int = 2
var GOAL_COL_START_BLUE: int = 2
var GOAL_COLS_BLUE: int = 2
var GOAL_ROW_START_LEFT: int = 0
var GOAL_ROWS_LEFT: int = 0
var GOAL_ROW_START_RIGHT: int = 0
var GOAL_ROWS_RIGHT: int = 0

# ————— DANE POZIOMU —————
var level_data: Dictionary = {}
var obstacle_cells: Array = []   # [{row,col}] w układzie board (bez bramek)
var goal_cells_data: Array = []  # [{row,col,type}] type=3=red, type=2=blue — dla orientacji poziomej
var GOAL_ROW_START: int = 0      # dla orientacji poziomej — który wiersz zaczyna bramkę
var GOAL_ROWS: int = 0           # dla orientacji poziomej — ile wierszy ma bramka

const BORDER = 8.0
const PADDING = 9.0
const RADIUS = 30.0
const CORNER_RADIUS = 22.0  # zaokrąglenie bordera boiska (takie jak w bramkach)
const FIELD_COLOR = Color("#448B47")
const BORDER_COLOR = Color.WHITE
const GAP = 9.0

# ————— TELEPORTY —————
const TELEPORT_A_COLOR = Color("#aa44ff")  # fioletowy (para A)
const TELEPORT_B_COLOR = Color("#ff8800")  # pomarańczowy (para B)
const TELEPORT_C_COLOR = Color("#00ffaa")

var teleport_a_cells: Array = []  # nieużywane (legacy)
var teleport_b_cells: Array = []  # nieużywane (legacy)
var teleport_c_cells: Array = []  # nieużywane (legacy)
var _tp_wave_active: bool = true  # flaga do zatrzymania fal przy reload

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
var _applying_opponent_move: bool = false

# ————— TRYB GRY —————
var VS_AI: bool = true
const AI_PLAYER: int = 2
var _ai_is_player1: bool = false   # true = bot jest Player1 (gracz jest P2)
const AI_DEPTH: int = 3
var ai_thinking: bool = false
var _game_ended: bool = false
var _popup_open: bool = false

# ————— ZMIANA POŁÓW —————
var _goal_switch_interval: int = 0  # 0 = wyłączone
var _goal_switch_counter: int = 0   # licznik ruchów od ostatniej zmiany
var _goals_swapped: bool = false    # czy bramki są aktualnie zamienione

func _is_my_turn() -> bool:
	# W trybie VS AI lub kampanii — zawsze tura gracza (AI jest blokowane przez ai_thinking)
	if not PlayerData.online_mode:
		return true
	# W online — moja tura gdy current_player odpowiada mojemu numerowi gracza
	var my_player_num = 1 if PlayerData.player1_is_me else 2
	return current_player == my_player_num

func _get_ai_player() -> int:
	return 1 if _ai_is_player1 else 2

# ————— TIMER (tryb 2 graczy) —————
const TURN_TIME: float = 15.0
var turn_timer: float = TURN_TIME
var timer_running: bool = false
var timer_node: Timer = null       # Godot Timer do tickowania

# ————— WĘZŁY UI —————
var ball_node: Sprite2D

# ————— DŹWIĘKI (pobierane z drzewa sceny po _ready) —————
var snd_bounce: AudioStreamPlayer = null
var snd_teleport: AudioStreamPlayer = null
var snd_kick: AudioStreamPlayer = null
var _bounce_stop_timer: SceneTreeTimer = null

# ————— DRAG BOISKA —————
var _drag_active: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_scroll: Vector2 = Vector2.ZERO
var _scroll_container: ScrollContainer = null
var dot_nodes: Array = []   # [{node, gx, gy}]
var active_moves: Array = []
var _drag_base_x: float = 0.0  # pozycja X planszy gdy jest wyśrodkowana — baza dla clampa
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
	var step = QUAD_SIZE + GAP
	if level_data.get("orientation", "vertical") == "horizontal":
		# X: boisko od step+inner, gx=0..COLS. Bramki: gx=-1 (lewa) i gx=COLS+1 (prawa)
		var px = step + inner + gx * step - GAP / 2.0
		var py = inner + gy * step - GAP / 2.0
		return Vector2(px, py)
	var px = inner + gx * step - GAP / 2.0
	var py = goal_h + inner + gy * step - GAP / 2.0
	return Vector2(px, py)

# Pozycja piksela węzła bramki bocznej — używa grid_to_pixel (spójna z resztą)
func _goal_side_pixel(gx: int, gy: int) -> Vector2:
	return grid_to_pixel(gx, gy)

# Klucz krawędzi (nieskierowany)
func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]

# Czy węzeł jest w bounds (pole + bramki), z uwzględnieniem przeszkód
func is_valid_node(gx: int, gy: int) -> bool:
	if gx >= 0 and gx <= COLS and gy >= 0 and gy <= ROWS:
		return _node_accessible(gx, gy)
	if level_data.get("orientation", "vertical") == "horizontal":
		# Bramki boczne: gx==-1 (lewa) i gx==COLS+1 (prawa)
		if gx == -1 and gy >= GOAL_ROW_START_LEFT and gy <= GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT:
			return true
		if gx == COLS + 1 and gy >= GOAL_ROW_START_RIGHT and gy <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT:
			return true
	else:
		if gy == -1 and gx >= GOAL_COL_START_RED and gx <= GOAL_COL_START_RED + GOAL_COLS_RED:
			return true
		if gy == ROWS + 1 and gx >= GOAL_COL_START_BLUE and gx <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
			return true
	return false

# Czy komórka (row,col) jest przeszkodą lub poza boiskiem
func _cell_is_wall(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return true  # poza boiskiem = ściana
	return _is_obstacle(row, col)

# Czy krawędź jest niedozwolona (leży wzdłuż ściany lub przez nią)
func is_wall_edge(a: Vector2i, b: Vector2i) -> bool:
	if level_data.get("orientation", "vertical") == "horizontal":
		# Górna/dolna ściana (zamknięte)
		if a.y == 0 and b.y == 0: return true
		if a.y == ROWS and b.y == ROWS: return true
		# Lewa/prawa linia boiska — otwarta tylko przy bramce
		if a.x == 0 and b.x == 0:
			var mn = mini(a.y, b.y); var mx = maxi(a.y, b.y)
			if not (mn >= GOAL_ROW_START_LEFT and mx <= GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT):
				return true
		if a.x == COLS and b.x == COLS:
			var mn = mini(a.y, b.y); var mx = maxi(a.y, b.y)
			if not (mn >= GOAL_ROW_START_RIGHT and mx <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT):
				return true
		# Słupek bramki (między polem a wnętrzem bramki)
		if a.y == b.y and abs(a.x - b.x) == 1:
			var by2 = a.y
			if by2 == GOAL_ROW_START_LEFT or by2 == GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT:
				var minx = mini(a.x, b.x); var maxx = maxi(a.x, b.x)
				if (minx == -1 and maxx == 0):
					return true
			if by2 == GOAL_ROW_START_RIGHT or by2 == GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT:
				var minx = mini(a.x, b.x); var maxx = maxi(a.x, b.x)
				if (minx == COLS and maxx == COLS + 1):
					return true
		# Przekątna i obstacle — ta sama logika co pionowa
		if abs(a.x - b.x) == 1 and abs(a.y - b.y) == 1:
			var side_a = Vector2i(b.x, a.y)
			var side_b = Vector2i(a.x, b.y)
			
			# Sprawdź czy KTÓRYKOLWIEK z węzłów bocznych jest niedostępny
			var a_invalid = not is_valid_node(side_a.x, side_a.y)
			var b_invalid = not is_valid_node(side_b.x, side_b.y)
			
			# Jeśli któryś jest niedostępny - zablokuj przekątną
			if a_invalid or b_invalid:
				return true
			
			return false
		var a_is_goal2 = (a.x < 0 or a.x > COLS)
		var b_is_goal2 = (b.x < 0 or b.x > COLS)
		if not a_is_goal2 and not b_is_goal2:
			if abs(a.x - b.x) == 1 and a.y == b.y:
				# Słupek bramki poziomej: węzeł na linii GOAL_ROW_START lub GOAL_ROW_START+GOAL_ROWS
				# Komórki po "zewnętrznej" stronie słupka są poza boiskiem — nie blokuj ruchu wzdłuż pola
				var on_top_goalpost = (a.y == GOAL_ROW_START)
				var on_bot_goalpost = (a.y == GOAL_ROW_START + GOAL_ROWS)
				if not on_top_goalpost:
					var top_l = _cell_is_wall(a.y - 1, mini(a.x, b.x)) if a.y > 0 else true
					var top_r = _cell_is_wall(a.y - 1, maxi(a.x, b.x) - 1) if a.y > 0 else true
					if top_l and top_r: return true
				if not on_bot_goalpost:
					var bot_l = _cell_is_wall(a.y, mini(a.x, b.x)) if a.y < ROWS else true
					var bot_r = _cell_is_wall(a.y, maxi(a.x, b.x) - 1) if a.y < ROWS else true
					if bot_l and bot_r: return true
				if on_top_goalpost:
					var bot_l = _cell_is_wall(a.y, mini(a.x, b.x)) if a.y < ROWS else true
					var bot_r = _cell_is_wall(a.y, maxi(a.x, b.x) - 1) if a.y < ROWS else true
					if bot_l and bot_r: return true
				if on_bot_goalpost:
					var top_l = _cell_is_wall(a.y - 1, mini(a.x, b.x)) if a.y > 0 else true
					var top_r = _cell_is_wall(a.y - 1, maxi(a.x, b.x) - 1) if a.y > 0 else true
					if top_l and top_r: return true
			elif a.x == b.x and abs(a.y - b.y) == 1:
				# Ruch pionowy wzdłuż ściany bramki — nie sprawdzaj strony zewnętrznej (col=-1 lub col=COLS)
				if a.x > 0:
					var lft_t = _cell_is_wall(mini(a.y, b.y), a.x - 1)
					var lft_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x - 1)
					if lft_t and lft_b: return true
				if a.x < COLS:
					var rgt_t = _cell_is_wall(mini(a.y, b.y), a.x)
					var rgt_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x)
					if rgt_t and rgt_b: return true
		return false

	# ——— Orientacja pionowa (oryginalna) ———
	# Lewa ściana — blokuj ruch wzdłuż niej, chyba że bramka jest przy tej ścianie
	if a.x == 0 and b.x == 0:
		var in_blue_slot = (GOAL_COL_START_BLUE == 0)
		var in_red_slot  = (GOAL_COL_START_RED  == 0)
		if not in_blue_slot and not in_red_slot:
			return true
		var min_y = mini(a.y, b.y); var max_y = maxi(a.y, b.y)
		var in_blue = in_blue_slot and (min_y >= GOAL_COL_START_BLUE and max_y <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE + 1)
		var in_red  = in_red_slot  and (min_y >= GOAL_COL_START_RED  and max_y <= GOAL_COL_START_RED  + GOAL_COLS_RED  + 1)
		if not in_blue and not in_red: return true
	# Prawa ściana — blokuj ruch wzdłuż niej, chyba że bramka jest przy tej ścianie
	if a.x == COLS and b.x == COLS:
		var in_blue_slot = (GOAL_COL_START_BLUE + GOAL_COLS_BLUE == COLS)
		var in_red_slot  = (GOAL_COL_START_RED  + GOAL_COLS_RED  == COLS)
		if not in_blue_slot and not in_red_slot:
			return true
		var min_y = mini(a.y, b.y); var max_y = maxi(a.y, b.y)
		var in_blue = in_blue_slot and (min_y >= GOAL_COL_START_BLUE and max_y <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE + 1)
		var in_red  = in_red_slot  and (min_y >= GOAL_COL_START_RED  and max_y <= GOAL_COL_START_RED  + GOAL_COLS_RED  + 1)
		if not in_blue and not in_red: return true

	# Górna/dolna linia boiska — ruch poziomy wzdłuż niej poza zakresem bramki
	if a.y == 0 and b.y == 0:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		# Sprawdź czy ruch jest w CAŁEJ bramce (łącznie ze słupkami)
		if mn >= GOAL_COL_START_RED and mx <= GOAL_COL_START_RED + GOAL_COLS_RED:
			return false  # dozwolone - jesteśmy w bramce lub na słupkach
		return true  # zabronione - poza bramką
	if a.y == ROWS and b.y == ROWS:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START_BLUE and mx <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE):
			return true
		if mn == GOAL_COL_START_BLUE or mx == GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
			return true

	# Ruch pionowy wzdłuż słupka bramki (między polem a wnętrzem bramki)
	if a.x == b.x and abs(a.y - b.y) == 1:
		var bx = a.x
		var miny = mini(a.y, b.y); var maxy = maxi(a.y, b.y)
		if miny == -1 and maxy == 0:
			if bx == GOAL_COL_START_RED or bx == GOAL_COL_START_RED + GOAL_COLS_RED:
				return true
		if miny == ROWS and maxy == ROWS + 1:
			if bx == GOAL_COL_START_BLUE or bx == GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
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
				pass
			else:
				var top_l = _cell_is_wall(a.y - 1, mini(a.x, b.x))
				var top_r = _cell_is_wall(a.y - 1, maxi(a.x, b.x) - 1)
				var bot_l = _cell_is_wall(a.y, mini(a.x, b.x))
				var bot_r = _cell_is_wall(a.y, maxi(a.x, b.x) - 1)
				if top_l and top_r and bot_l and bot_r: return true
		elif a.x == b.x and abs(a.y - b.y) == 1:
			# Ruch wzdłuż lewej ściany boiska
			if a.x == 0:
				var mn = mini(a.y, b.y); var mx = maxi(a.y, b.y)
				# Bramka przy lewej ścianie pionowej nie istnieje — zawsze blokuj
				# (bramki są tylko na y=0 i y=ROWS w orientacji pionowej)
				return true
			# Ruch wzdłuż prawej ściany boiska
			elif a.x == COLS:
				return true
			# Ruch wzdłuż granicy obstacle (nie na ścianie)
			else:
				var lft_t = _cell_is_wall(mini(a.y, b.y),     a.x - 1)
				var lft_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x - 1)
				var rgt_t = _cell_is_wall(mini(a.y, b.y),     a.x)
				var rgt_b = _cell_is_wall(maxi(a.y, b.y) - 1, a.x)
				if lft_t and lft_b and rgt_t and rgt_b: return true

	return false

# Czy węzeł (gx,gy) leży na ścianie boiska lub na granicy obstacle
func _node_on_wall_or_obstacle(n: Vector2i) -> bool:
	if level_data.get("orientation", "vertical") == "horizontal":
		# Włączamy słupki (>= i <=) — są węzłami gry, nie ścianą
		var in_goal_left  = (n.x == 0    and n.y >= GOAL_ROW_START_LEFT  and n.y <= GOAL_ROW_START_LEFT  + GOAL_ROWS_LEFT)
		var in_goal_right = (n.x == COLS and n.y >= GOAL_ROW_START_RIGHT and n.y <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT)
		if n.y == 0 or n.y == ROWS: return true
		if n.x == 0    and not in_goal_left:  return true
		if n.x == COLS and not in_goal_right: return true
	else:
		var in_goal_top = (n.x > GOAL_COL_START_RED  and n.x < GOAL_COL_START_RED  + GOAL_COLS_RED)
		var in_goal_bot = (n.x > GOAL_COL_START_BLUE and n.x < GOAL_COL_START_BLUE + GOAL_COLS_BLUE)
		if n.x == 0 or n.x == COLS: return true
		if n.y == 0    and not in_goal_top: return true
		if n.y == ROWS and not in_goal_bot: return true

	return false

# Możliwe ruchy z danej pozycji
func get_valid_moves(pos: Vector2i) -> Array:
	var moves = []
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	var near_goal_blue = (pos.y == ROWS and pos.x >= GOAL_COL_START_BLUE - 1 and pos.x <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE + 1)
	var near_goal_red  = (pos.y == 0    and pos.x >= GOAL_COL_START_RED  - 1 and pos.x <= GOAL_COL_START_RED  + GOAL_COLS_RED  + 1)
	var debug = near_goal_blue or near_goal_red
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			if not is_valid_node(nb.x, nb.y):
				if debug: print("[MOVES] ", nb, " INVALID_NODE")
				continue
			if used_edges.has(edge_key(pos, nb)):
				if debug: print("[MOVES] ", nb, " USED_EDGE")
				continue
			if is_wall_edge(pos, nb):
				if debug: print("[MOVES] ", nb, " WALL_EDGE")
				continue
			if debug: print("[MOVES] ", nb, " OK")
			moves.append(nb)
	if debug: print("[MOVES] z ", pos, " GCSR=", GOAL_COL_START_RED, " GCSR_COLS=", GOAL_COLS_RED, " GCSB=", GOAL_COL_START_BLUE, " GCSB_COLS=", GOAL_COLS_BLUE, " ROWS=", ROWS, " COLS=", COLS, " wynik=", moves)
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
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var nb = Vector2i(pos.x + dx, pos.y + dy)
			var ek = edge_key(pos, nb)
			if used_edges.has(ek):
				count += 1
				if is_h: print("[BOUNCE] krawedz: ", pos, "->", nb, " count=", count)
	if is_h:
		if pos.y == 0: count += 1; print("[BOUNCE] gorna sciana count=", count)
		if pos.y == ROWS: count += 1; print("[BOUNCE] dolna sciana count=", count)
		var in_goal_interior = (pos.y > GOAL_ROW_START and pos.y < GOAL_ROW_START + GOAL_ROWS)
		print("[BOUNCE] pos=", pos, " GRS=", GOAL_ROW_START, " GR=", GOAL_ROWS, " interior=", in_goal_interior)
		if pos.x == 0 and not in_goal_interior: count += 1; print("[BOUNCE] lewa sciana count=", count)
		if pos.x == COLS and not in_goal_interior: count += 1; print("[BOUNCE] prawa sciana count=", count)
		for dr in [-1, 0]:
			for dc in [-1, 0]:
				var cr = pos.y + dr; var cc = pos.x + dc
				if cr >= 0 and cr < ROWS and cc >= 0 and cc < COLS:
					if _is_obstacle(cr, cc):
						count += 1
		print("[BOUNCE] WYNIK pos=", pos, " count=", count, " bounce=", count >= 2)
		return count >= 2
	else:
		if pos.x == 0: count += 1
		if pos.x == COLS: count += 1
		var in_red_interior  = (pos.x > GOAL_COL_START_RED  and pos.x < GOAL_COL_START_RED  + GOAL_COLS_RED)
		var in_blue_interior = (pos.x > GOAL_COL_START_BLUE and pos.x < GOAL_COL_START_BLUE + GOAL_COLS_BLUE)
		if pos.y == 0    and not in_red_interior:  count += 1
		if pos.y == ROWS and not in_blue_interior: count += 1
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
	if PlayerData.online_mode:
		level_data = {}
		VS_AI = (PlayerData.online_opponent_name == "")
		# Ustal role deterministycznie (mniejszy playfab_id = P1) zanim zapiszemy klucze
		if not PlayerData.player1_decided or PlayerData.online_opponent_name != "":
			var _cfg = ConfigFile.new()
			_cfg.load("user://session.cfg")
			var _my_id  = _cfg.get_value("session", "playfab_id", "")
			var _opp_id = _cfg.get_value("session", "opponent_playfab_id", "")
			if _my_id != "" and _opp_id != "":
				PlayerData.player1_is_me = (_my_id < _opp_id)
				PlayerData.player1_decided = true
		_ai_is_player1 = VS_AI and not PlayerData.player1_is_me
		await PlayerData.reset_online_game(PlayerData.online_match_id)
		_start_opponent_polling()
	elif level_data.is_empty() and not PlayerData.current_level_data.is_empty():
		level_data = PlayerData.current_level_data
		VS_AI = PlayerData.vs_ai
	if not level_data.is_empty():
		_apply_level_data()
	_scroll_container = _find_scroll_parent()
	_build_board()
	if _scroll_container:
		_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll_container.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_setup_game()
	if not PlayerData.online_mode:
		call_deferred("_update_level_label")

	# ————— DŹWIĘKI — szukaj węzłów po załadowaniu sceny —————
	_start_sound_init()

	# ————— ONLINE READY HANDSHAKE —————
	# Timer zatrzymany do czasu aż obaj gracze załadują planszę
	if PlayerData.online_mode and PlayerData.online_opponent_name != "":
		call_deferred("_online_ready_handshake")

func _update_level_label():
	var p = get_parent()
	while p:
		var lbl = p.get_node_or_null("MarginContainer/Control/HBoxContainer/Control_Level/Label")
		if lbl:
			lbl.text = "LEVEL " + str(PlayerData.current_level_index)
			return
		p = p.get_parent()


# Przetłumacz dane JSON na wymiary board.gd
# WAŻNE: w edytorze grid[0] i grid[rows-1] to bramki wliczone w rozmiar.
# W board.gd ROWS = liczba wierszy POLA (bez bramek), bramki są na gy=-1 i gy=ROWS+1.
# Więc: ROWS = editor_rows - 2, COLS = editor_cols
func _apply_level_data():
	var ed_cols = int(level_data.get("cols", 6))
	var ed_rows = int(level_data.get("rows", 10))
	var grid = level_data.get("grid", [])
	var ed_orientation = level_data.get("orientation", "vertical")

	COLS = ed_cols
	ROWS = ed_rows - 2

	if ed_orientation == "horizontal":
		# W edytorze poziomym WSZYSTKIE ed_rows to pole gry (brak wierszy-bramek góra/dół).
		# col=0 = lewa bramka (RED/AI), col=ed_cols-1 = prawa (BLUE/gracz)
		# Pole gry = col 1..ed_cols-2  →  board col 0..COLS-1
		COLS = ed_cols - 2
		ROWS = ed_rows          # brak odjęcia 2 — nie ma wierszy-bramek!
		GOAL_COL_START = 0
		GOAL_COLS = 0

		obstacle_cells = []
		goal_cells_data = []
		teleport_a_cells = []
		teleport_b_cells = []
		
		# Wiersze lewej bramki (col=0)
		var left_rows = []
		for er in range(ed_rows):
			if er >= grid.size(): continue
			var cell_val = int(grid[er][0])
			if cell_val == 2 or cell_val == 3:
				left_rows.append(er)
		if left_rows.size() > 0:
			left_rows.sort()
			GOAL_ROW_START_LEFT = left_rows[0]
			GOAL_ROWS_LEFT = left_rows[-1] - left_rows[0] + 1
		else:
			GOAL_ROW_START_LEFT = ROWS / 2 - 1
			GOAL_ROWS_LEFT = 2

		# Wiersze prawej bramki (col=ed_cols-1)
		var right_rows = []
		for er in range(ed_rows):
			if er >= grid.size(): continue
			var cell_val = int(grid[er][ed_cols - 1])
			if cell_val == 2 or cell_val == 3:
				right_rows.append(er)
		if right_rows.size() > 0:
			right_rows.sort()
			GOAL_ROW_START_RIGHT = right_rows[0]
			GOAL_ROWS_RIGHT = right_rows[-1] - right_rows[0] + 1
		else:
			GOAL_ROW_START_RIGHT = ROWS / 2 - 1
			GOAL_ROWS_RIGHT = 2

		# Stare zmienne wspólne — zostaw dla kompatybilności
		GOAL_ROW_START = GOAL_ROW_START_LEFT
		GOAL_ROWS = GOAL_ROWS_LEFT

		# Wiersze bramki z col=0 edytora (er = board row, bezpośrednio)
		var goal_rows = []
		for er in range(ed_rows):
			if er >= grid.size(): continue
			var cell_val = int(grid[er][0])
			if (cell_val == 2 or cell_val == 3) and not (er in goal_rows):
				goal_rows.append(er)

		if goal_rows.size() > 0:
			goal_rows.sort()
			GOAL_ROW_START = goal_rows[0]
			GOAL_ROWS = goal_rows[-1] - goal_rows[0] + 1
		else:
			GOAL_ROW_START = ROWS / 2 - 1
			GOAL_ROWS = 2

		# Przeszkody z pola gry (col 1..ed_cols-2 → board col 0..COLS-1)
		for er in range(ed_rows):
			if er >= grid.size(): continue
			for c in range(1, ed_cols - 1):
				var cell_val = int(grid[er][c])
				if cell_val == 0 or cell_val == 4:
					obstacle_cells.append({"row": er, "col": c - 1})

		# goal_cells_data — col=-1 lewa, col=COLS prawa (dla rysowania)
		for er in range(ed_rows):
			if er >= grid.size(): continue
			var lv = int(grid[er][0])
			var rv = int(grid[er][ed_cols - 1])
			if lv == 2 or lv == 3:
				goal_cells_data.append({"row": er, "col": -1, "type": lv})
			if rv == 2 or rv == 3:
				goal_cells_data.append({"row": er, "col": COLS, "type": rv})

		teleport_a_nodes = []
		teleport_b_nodes = []
		teleport_c_nodes = []
		for t in level_data.get("teleport_a", []):
			teleport_a_nodes.append(Vector2i(int(t.get("gx", 0)) - 1, int(t.get("gy", 0))))
		for t in level_data.get("teleport_b", []):
			teleport_b_nodes.append(Vector2i(int(t.get("gx", 0)) - 1, int(t.get("gy", 0))))
		for t in level_data.get("teleport_c", []):
			teleport_c_nodes.append(Vector2i(int(t.get("gx", 0)) - 1, int(t.get("gy", 0))))

	else:
		# Orientacja pionowa (oryginalna)
		goal_cells_data = []
		# Czerwona — wiersz 0
		var red_cols = []
		if grid.size() > 0:
			for c in range((grid[0] as Array).size()):
				if int(grid[0][c]) == 3:
					red_cols.append(c)
		if red_cols.size() > 0:
			red_cols.sort()
			GOAL_COL_START_RED = red_cols[0]
			GOAL_COLS_RED = red_cols[-1] - red_cols[0] + 1
		else:
			GOAL_COL_START_RED = COLS / 2 - 1
			GOAL_COLS_RED = 2

		# Niebieska — ostatni wiersz
		var blue_cols = []
		if ed_rows - 1 < grid.size():
			for c in range((grid[ed_rows - 1] as Array).size()):
				if int(grid[ed_rows - 1][c]) == 2:
					blue_cols.append(c)
		if blue_cols.size() > 0:
			blue_cols.sort()
			GOAL_COL_START_BLUE = blue_cols[0]
			GOAL_COLS_BLUE = blue_cols[-1] - blue_cols[0] + 1
		else:
			GOAL_COL_START_BLUE = COLS / 2 - 1
			GOAL_COLS_BLUE = 2

		# Zostaw stare dla kompatybilności (używane przez is_valid_node itp.)
		GOAL_COL_START = GOAL_COL_START_RED
		GOAL_COLS = GOAL_COLS_RED

		obstacle_cells = []
		teleport_a_cells = []
		teleport_b_cells = []
		teleport_c_cells = []
		for er in range(1, ed_rows - 1):
			if er >= grid.size(): continue
			for c in range(ed_cols):
				var cell_val = int(grid[er][c])
				if cell_val == 4 or cell_val == 0:
					obstacle_cells.append({"row": er - 1, "col": c})

		teleport_a_nodes = []
		teleport_b_nodes = []
		teleport_c_nodes = []
		for t in level_data.get("teleport_a", []):
			teleport_a_nodes.append(Vector2i(int(t.get("gx", 0)), int(t.get("gy", 0)) - 1))
		for t in level_data.get("teleport_b", []):
			teleport_b_nodes.append(Vector2i(int(t.get("gx", 0)), int(t.get("gy", 0)) - 1))
		for t in level_data.get("teleport_c", []):
			teleport_c_nodes.append(Vector2i(int(t.get("gx", 0)), int(t.get("gy", 0)) - 1))

func _setup_game():
	_kill_all_tweens()
	# Wczytaj parametr zmiany połów
	_goal_switch_interval = int(level_data.get("goal_switch_interval", 0))
	_goal_switch_counter = 0
	_goals_swapped = false
	# ScrollContainer już znaleziony w _ready / _reload_board
	if not _scroll_container:
		_scroll_container = _find_scroll_parent()

	ball_grid_pos = Vector2i(COLS / 2, ROWS / 2)
	current_player = 1
	used_edges.clear()
	_preload_obstacle_edges()
	bounce_active = false
	active_moves.clear()
	move_history.clear()
	_game_ended = false
	_tp_wave_active = true
	_spawn_teleport_dots()

	_draw_grid_dots()

	# Piłka — wczytaj aktywny skin gracza
	var _equipped_idx = PlayerData.get_equipped_skin()
	var _skin_path = "res://ui/skins/skin%d.png" % (_equipped_idx + 1)
	tex_skin = load(_skin_path)
	if tex_skin == null:
		tex_skin = load("res://ui/skins/skin1.png")
	ball_node = Sprite2D.new()
	ball_node.texture = tex_skin
	ball_node.z_index = 10
	# Skaluj wg rzeczywistego rozmiaru tekstury — wszystkie skiny wyglądają jak 88x88
	var tex_w = tex_skin.get_width() if tex_skin else 88
	ball_node.scale = Vector2(36.0 / tex_w, 36.0 / tex_w)
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
	call_deferred("_center_scroll")

	if VS_AI and not PlayerData.online_mode:
		current_player = 2  # bot (Player2) zaczyna
		ai_thinking = true
		_hide_active_dots()
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(self):
				_ai_take_turn()
			)
	elif VS_AI and _ai_is_player1:
		ai_thinking = true
		_hide_active_dots()
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(self):
				_ai_take_turn()
			)

func _center_scroll():
	if not _scroll_container: return
	await get_tree().process_frame
	await get_tree().process_frame
	position.x = 0.0
	_drag_base_x = 0.0
	print("START: position=", position, " global_pos=", global_position, " size=", size, " custom_min=", custom_minimum_size, " parent=", get_parent_control().name, " parent.size=", get_parent_control().size, " parent.global=", get_parent_control().global_position, " sc.size=", _scroll_container.size, " sc.global=", _scroll_container.global_position)

func _find_scroll_parent() -> ScrollContainer:
	var node = get_parent()
	while node:
		if node is ScrollContainer:
			var sc = node as ScrollContainer
			sc.follow_focus = false
			return sc
		node = node.get_parent()
	return null

func _on_scroll_gui_input(_event: InputEvent):
	pass  # nieużywane

# ——————————————————————————————————————————
#  DRAG BOISKA — przesuwanie pozycji jak w hex_grid
# ——————————————————————————————————————————

func _unhandled_input(event: InputEvent):
	if _popup_open: return
	# Środkowy lub prawy przycisk myszy — drag planszy (tylko oś X)
	var is_rmb = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT
	var is_mmb = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE
	var is_drag = event is InputEventMouseMotion and (
		(event.button_mask & MOUSE_BUTTON_MASK_RIGHT) or
		(event.button_mask & MOUSE_BUTTON_MASK_MIDDLE)
	)

	if (is_rmb or is_mmb) and event.pressed:
		_drag_active = true
		_drag_start_mouse = event.global_position
		_drag_start_scroll = position
		get_viewport().set_input_as_handled()
		return

	if (is_rmb or is_mmb) and not event.pressed:
		_drag_active = false
		get_viewport().set_input_as_handled()
		return

	if _drag_active and is_drag:
		var delta_x = event.global_position.x - _drag_start_mouse.x
		var new_x = _drag_start_scroll.x + delta_x
		var board_w = size.x  # rzeczywisty rozmiar, nie custom_minimum_size
		var viewport_w = get_viewport_rect().size.x
		# lewa krawędź planszy w pikselach ekranu przy new_x:
		# global.x = parent.global.x + position.x (bo anchor=0, offset=-board_w/2... sprawdź)
		# Z logu: global=(-48.5) gdy position=(-78.5) i parent.global=(30)
		# więc global.x = parent.global.x + position.x + board_w/2 ? 
		# -48.5 = 30 + (-78.5) + 0 → nie... 
		# -48.5 = 30 + (-78.5) = -48.5 ✓  (anchor 0.5 nie dodaje nic do global gdy offset=-board_w/2)
		# lewa krawędź = global.x = parent_global_x + new_x
		var parent_global_x = global_position.x - position.x  # = 30
		var left_edge = parent_global_x + new_x
		var right_edge = left_edge + board_w
		var pad = 30.0
		if left_edge > pad:
			new_x -= left_edge - pad
		if right_edge < viewport_w - pad:
			new_x += (viewport_w - pad) - right_edge
		position.x = new_x
		get_viewport().set_input_as_handled()
		return

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
	if level_data.get("orientation", "vertical") == "horizontal":
		for gy in range(GOAL_ROW_START, GOAL_ROW_START + GOAL_ROWS + 1):
			var dot_l = _make_dot(_goal_side_pixel(-1, gy), false)
			dot_l.set_meta("goal_node", true)
			dot_nodes.append({"node": dot_l, "gx": -1, "gy": gy})
			var dot_r = _make_dot(_goal_side_pixel(COLS + 1, gy), false)
			dot_r.set_meta("goal_node", true)
			dot_nodes.append({"node": dot_r, "gx": COLS + 1, "gy": gy})
	else:
		for gx in range(GOAL_COL_START_RED, GOAL_COL_START_RED + GOAL_COLS_RED + 1):
			var dot = _make_dot(grid_to_pixel(gx, -1), false)
			dot.set_meta("goal_node", true)
			dot_nodes.append({"node": dot, "gx": gx, "gy": -1})
		for gx in range(GOAL_COL_START_BLUE, GOAL_COL_START_BLUE + GOAL_COLS_BLUE + 1):
			var dot = _make_dot(grid_to_pixel(gx, ROWS + 1), false)
			dot.set_meta("goal_node", true)
			dot_nodes.append({"node": dot, "gx": gx, "gy": ROWS + 1})

# Czy węzeł (gx,gy) powinien mieć widoczną kropkę.
# Pokaż jeśli co najmniej 2 z 4 przylegających komórek są aktywne.
# Zewnętrzny róg kształtu ma dokładnie 1 aktywną komórkę — ukryty.
# Wewnętrzny róg obstacle ma 2+ aktywne komórki — widoczny.
func _dot_inside_field(gx: int, gy: int) -> bool:
	var count = 0
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	
	# Liczymy aktywne komórki wokół węzła
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var r = gy + dr
			var c = gx + dc
			
			if c < 0 or c >= COLS:
				if is_h:
					if r >= GOAL_ROW_START_LEFT and r < GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT:
						count += 1
					elif r >= GOAL_ROW_START_RIGHT and r < GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT:
						count += 1
			elif r < 0:
				if c >= GOAL_COL_START_RED and c < GOAL_COL_START_RED + GOAL_COLS_RED:
					count += 1
			elif r >= ROWS:
				if c >= GOAL_COL_START_BLUE and c < GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
					count += 1
			elif not _is_obstacle(r, c):
				count += 1
	
	# Standardowo: pokaż jeśli >= 2 aktywne komórki
	if count >= 2:
		return true
	
	# Dodatkowo: pokaż kropkę w wklęsłych narożnikach przy przeszkodach
	# Sprawdzamy czy węzeł dotyka jakiejś przeszkody
	var touches_obstacle = false
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var r = gy + dr
			var c = gx + dc
			if r >= 0 and r < ROWS and c >= 0 and c < COLS:
				if _is_obstacle(r, c):
					touches_obstacle = true
					break
	
	# Jeśli dotyka przeszkody i ma co najmniej 1 aktywną komórkę — pokaż kropkę
	if touches_obstacle and count >= 1:
		return true
	
	return false

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

	# W trybie online ukryj kropki gdy to tura przeciwnika
	if PlayerData.online_mode and not _is_my_turn():
		_hide_active_dots()
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
	_tp_wave_active = false
	for t in _active_tweens:
		if t and is_instance_valid(t): t.kill()
	_active_tweens.clear()

# ——————————————————————————————————————————
#  INPUT
# ——————————————————————————————————————————

# ——————————————————————————————————————————
#  INPUT
# ——————————————————————————————————————————

func _input(event: InputEvent):
	if _popup_open: return
	# ── Touch drag boiska ──────────────────────────────────────────────────
	if _scroll_container:
		var is_touch      = event is InputEventScreenTouch
		var is_drag_touch = event is InputEventScreenDrag

		if is_touch and event.pressed:
			_drag_active = true
			_touch_moved = false
			_drag_start_mouse = event.position
			_drag_start_scroll = Vector2(_scroll_container.scroll_horizontal, _scroll_container.scroll_vertical)
			get_viewport().set_input_as_handled()
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
			if not _touch_moved and not ai_thinking and _is_my_turn():
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
	if not _is_my_turn(): return
	_try_move(get_global_transform().affine_inverse() * click_pos)

func _try_move(local_pos: Vector2):
	var tap_radius = (QUAD_SIZE + GAP) * 0.55
	var best_dist = tap_radius
	var best_move: Variant = null

	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	for move in active_moves:
		var mpx: Vector2
		if is_h and (move.x < 0 or move.x > COLS):
			mpx = _goal_side_pixel(move.x, move.y)
		else:
			mpx = grid_to_pixel(move.x, move.y)
		var d = local_pos.distance_to(mpx)
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
	if PlayerData.online_mode and not _applying_opponent_move:
		PlayerData.push_online_move(from, target)
	# Zablokuj krawędź
	used_edges[ek] = true

	# Ślad — zapamiętaj referencję na wypadek cofnięcia
	var trail_line = _draw_trail(from, target)

	# Zapisz historię
	move_history.append({"from": from, "to": target, "ek": ek, "player": current_player, "line": trail_line})

	# Licznik ruchów dla zmiany połów (każdy ruch, nie tylko zmiana tury)
	_check_goal_switch()

	# Sprawdź gol przed animacją
	var scored = _check_goal(target)

	# Animuj do celu
	_animate_ball(target, false)
	ball_grid_pos = target

	# ————— DŹWIĘK KOPNIĘCIA —————
	if snd_kick:
		snd_kick.stop()
		snd_kick.play()

	if scored:
		_game_ended = true
		ai_thinking = true
		_hide_combo()
		score += 500
		var player_scored: bool
		if PlayerData.online_mode:
			if level_data.get("orientation", "vertical") == "horizontal":
				# x<0 = lewa bramka (RED/AI) — P1 strzela tam = wygrana P1
				player_scored = (PlayerData.player1_is_me and ball_grid_pos.x < 0) or (not PlayerData.player1_is_me and ball_grid_pos.x > COLS)
			else:
				# y<0 = bramka RED (góra) — P1 strzela tam = wygrana P1
				player_scored = (PlayerData.player1_is_me and ball_grid_pos.y < 0) or (not PlayerData.player1_is_me and ball_grid_pos.y > ROWS)
		else:
			if level_data.get("orientation", "vertical") == "horizontal":
				player_scored = (ball_grid_pos.x < 0)
			else:
				player_scored = (ball_grid_pos.y < 0)
		await get_tree().create_timer(0.25).timeout
		if player_scored:
			_show_popup_win()
		else:
			_show_popup_fail()
		return

	# Teleport — jeśli piłka wchodzi na teleport
	if _check_and_do_teleport(target):
		return  # teleportacja przejęła kontrolę

	# Odbicie jeśli węzeł ma już ślady
	bounce_active = node_has_any_trail(target)
	if bounce_active:
		combo_count += 1
		score += combo_count * 10
		_show_combo(target, false)
		# ————— DŹWIĘK ODBICIA OD ŚCIANKI —————
		_play_bounce_sound()
		# Odbicie — ten sam gracz gra dalej, przedłuż timer o 3s (max do TURN_TIME)
		if not VS_AI or PlayerData.online_mode:
			turn_timer = minf(turn_timer + 3.0, TURN_TIME)
	else:
		combo_count = 0
		_hide_combo()
		current_player = 2 if current_player == 1 else 1
		# Zmiana tury — restart timera
		if not VS_AI or PlayerData.online_mode:
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
	if VS_AI and current_player == _get_ai_player():
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
			if VS_AI and current_player == _get_ai_player():
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
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	var target_px: Vector2
	if is_h and (target.x < 0 or target.x > COLS):
		target_px = _goal_side_pixel(target.x, target.y)
	else:
		target_px = grid_to_pixel(target.x, target.y)
	var tex_w = ball_node.texture.get_width() if ball_node.texture else 88
	var base_scale = 36.0 / tex_w
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
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	var from_px = _goal_side_pixel(from.x, from.y) if (is_h and (from.x < 0 or from.x > COLS)) else grid_to_pixel(from.x, from.y)
	var to_px   = _goal_side_pixel(to.x, to.y)     if (is_h and (to.x < 0   or to.x > COLS))   else grid_to_pixel(to.x, to.y)
	line.add_point(from_px)
	line.add_point(to_px)
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
	if level_data.get("orientation", "vertical") == "horizontal":
		# Lewa bramka (x<0) = bramka AI (RED), prawa (x>COLS) = bramka gracza (BLUE)
		if pos.x < 0 and pos.y >= GOAL_ROW_START_LEFT and pos.y <= GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT:
			return true
		if pos.x > COLS and pos.y >= GOAL_ROW_START_RIGHT and pos.y <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT:
			return true
	else:
		if pos.y < 0 and pos.x >= GOAL_COL_START_RED and pos.x <= GOAL_COL_START_RED + GOAL_COLS_RED:
			return true
		if pos.y > ROWS and pos.x >= GOAL_COL_START_BLUE and pos.x <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
			return true
	return false

func _on_goal_anim():
	var scorer = current_player
	print("GOL! Gracz %d strzelił!" % scorer)
	_hide_combo()
	var player_scored: bool
	if PlayerData.online_mode:
		if level_data.get("orientation", "vertical") == "horizontal":
			# x<0 = lewa bramka (RED/AI) — P1 strzela tam = wygrana P1
			player_scored = (PlayerData.player1_is_me and ball_grid_pos.x < 0) or (not PlayerData.player1_is_me and ball_grid_pos.x > COLS)
		else:
			# y<0 = bramka RED (góra) — P1 strzela tam = wygrana P1
			player_scored = (PlayerData.player1_is_me and ball_grid_pos.y < 0) or (not PlayerData.player1_is_me and ball_grid_pos.y > ROWS)
	else:
		if level_data.get("orientation", "vertical") == "horizontal":
			player_scored = (ball_grid_pos.x < 0)
		else:
			player_scored = (ball_grid_pos.y < 0)  # górna bramka = bramka AI = gracz strzelił
	if player_scored:
		score += 500
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

func _check_goal_switch():
	if _goal_switch_interval <= 0 or _game_ended: return
	_goal_switch_counter += 1
	if _goal_switch_counter >= _goal_switch_interval:
		_goal_switch_counter = 0
		_swap_goals()

func _swap_goals():
	_goals_swapped = not _goals_swapped
	# Zbierz pozycje i typy wszystkich kafelków bramek
	var to_swap: Array = []
	for child in get_children():
		if child.has_meta("goal_type"):
			to_swap.append({"pos": child.position, "type": child.get_meta("goal_type")})
			child.queue_free()
	# Postaw nowe kafelki z zamienionymi kolorami
	for entry in to_swap:
		var new_type = "blue" if entry["type"] == "red" else "red"
		var new_scene = quad_f3 if new_type == "blue" else quad_f4
		_place_quad_type(entry["pos"], new_scene, new_type)
	# Przelicz logiczne parametry bramek (zamień RED<->BLUE)
	var tmp_col  = GOAL_COL_START_RED;  GOAL_COL_START_RED  = GOAL_COL_START_BLUE;  GOAL_COL_START_BLUE  = tmp_col
	var tmp_cols = GOAL_COLS_RED;       GOAL_COLS_RED       = GOAL_COLS_BLUE;       GOAL_COLS_BLUE       = tmp_cols
	_flash_goal_switch()

func _flash_goal_switch():
	# Błysk białego overlay na chwilę — sygnalizuje zmianę połów
	var overlay = ColorRect.new()
	overlay.color = Color(1, 1, 1, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var tw = create_tween()
	tw.tween_property(overlay, "color:a", 0.35, 0.12)
	tw.tween_property(overlay, "color:a", 0.0,  0.25)
	tw.tween_callback(overlay.queue_free)

func _show_popup_win():
	ai_thinking = true
	_game_ended = true
	if PlayerData.online_mode:
		PlayerData.save_game_result(true, score / 100, score, false)
		var popup = scene_complete.instantiate()
		var ctrl = popup.get_node("Control")
		ctrl.score = score
		ctrl.reward = score / 100
		ctrl.completed_level_index = 0
		ctrl.level_name = "VICTORY!"
		ctrl.is_online_mode = true
		get_tree().root.add_child(popup)
	else:
		if VS_AI:
			PlayerData.on_level_win(PlayerData.current_level_index)
		PlayerData.save_game_result(true, score / 100, score, VS_AI)
		var popup = scene_complete.instantiate()
		var ctrl = popup.get_node("Control")
		ctrl.score = score
		ctrl.reward = score / 100
		ctrl.completed_level_index = PlayerData.current_level_index
		ctrl.level_name = "LEVEL " + str(PlayerData.current_level_index)
		ctrl.is_online_mode = false
		get_tree().root.add_child(popup)

func _show_popup_fail():
	ai_thinking = true
	_game_ended = true
	PlayerData.save_game_result(false, 0, score, not PlayerData.online_mode and VS_AI)
	var popup = scene_failed.instantiate()
	var ctrl = popup.get_node("Control")
	ctrl.score = score
	ctrl.level_name = "DEFEAT!" if PlayerData.online_mode else ("LEVEL " + str(PlayerData.current_level_index))
	ctrl.is_online_mode = PlayerData.online_mode
	get_tree().root.add_child(popup)

# ——————————————————————————————————————————
#  AI — MINIMAX
# ——————————————————————————————————————————

func _ai_take_turn():
	if _game_ended: return
	# Minimax bez wątku — używamy call_deferred żeby nie blokować animacji
	var best = _minimax_root(ball_grid_pos, used_edges.duplicate(), _get_ai_player(), AI_DEPTH)
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
	_animate_ball(target, false)
	ball_grid_pos = target

	# ————— DŹWIĘK KOPNIĘCIA (AI) —————
	if snd_kick:
		snd_kick.stop()
		snd_kick.play()

	if scored:
		_game_ended = true
		ai_thinking = false
		_hide_combo()
		score += 500
		var player_scored: bool
		if PlayerData.online_mode:
			if level_data.get("orientation", "vertical") == "horizontal":
				# x<0 = lewa bramka (RED/AI) — P1 strzela tam = wygrana P1
				player_scored = (PlayerData.player1_is_me and ball_grid_pos.x < 0) or (not PlayerData.player1_is_me and ball_grid_pos.x > COLS)
			else:
				# y<0 = bramka RED (góra) — P1 strzela tam = wygrana P1
				player_scored = (PlayerData.player1_is_me and ball_grid_pos.y < 0) or (not PlayerData.player1_is_me and ball_grid_pos.y > ROWS)
		else:
			if level_data.get("orientation", "vertical") == "horizontal":
				player_scored = (ball_grid_pos.x < 0)
			else:
				player_scored = (ball_grid_pos.y < 0)
		await get_tree().create_timer(0.25).timeout
		if player_scored:
			_show_popup_win()
		else:
			_show_popup_fail()
		return

	# Teleport — jeśli piłka wchodzi na teleport
	if _check_and_do_teleport(target):
		return  # teleportacja przejęła kontrolę

	bounce_active = node_has_any_trail(target)
	if bounce_active:
		combo_count += 1
		score += combo_count * 10
		_show_combo(target, false)
		# ————— DŹWIĘK ODBICIA OD ŚCIANKI (AI) —————
		_play_bounce_sound()
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

	if current_player == _get_ai_player():
		await get_tree().create_timer(0.12).timeout
		_ai_take_turn()
	else:
		ai_thinking = false
		_refresh_active_dots()
		# Tura gracza — wystartuj timer
		_start_turn_timer()

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

		# Bonus za teleport jeśli prowadzi bliżej bramki przeciwnika
		var tp_dest = _teleport_destination_pure(move)
		if tp_dest != null:
			var dist_before: float
			var dist_after: float
			if level_data.get("orientation", "vertical") == "horizontal":
				var goal_center_y = float(GOAL_ROW_START) + float(GOAL_ROWS) / 2.0
				dist_before = abs(move.y - goal_center_y) * 0.5 + float(COLS - move.x)
				dist_after  = abs(tp_dest.y - goal_center_y) * 0.5 + float(COLS - tp_dest.x)
			else:
				var goal_center_x = float(GOAL_COL_START) + float(GOAL_COLS) / 2.0
				dist_before = abs(move.x - goal_center_x) * 0.5 + float(ROWS - move.y)
				dist_after  = abs(tp_dest.x - goal_center_x) * 0.5 + float(ROWS - tp_dest.y)
			if dist_after < dist_before:
				score += 80.0  # teleport przybliża do bramki — dobry ruch

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
	if level_data.get("orientation", "vertical") == "horizontal":
		# Lewa bramka (x<0) = bramka AI (RED) = GOL GRACZA = źle dla AI
		if pos.x < 0 and pos.y >= GOAL_ROW_START and pos.y <= GOAL_ROW_START + GOAL_ROWS:
			return -10000.0 - depth
		# Prawa bramka (x>COLS) = bramka gracza (BLUE) = GOL AI = świetnie dla AI
		if pos.x > COLS and pos.y >= GOAL_ROW_START and pos.y <= GOAL_ROW_START + GOAL_ROWS:
			return 10000.0 + depth
	else:
		if pos.y < 0 and pos.x >= GOAL_COL_START_RED and pos.x <= GOAL_COL_START_RED + GOAL_COLS_RED:
			return -10000.0 - depth
		if pos.y > ROWS and pos.x >= GOAL_COL_START_BLUE and pos.x <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
			return 10000.0 + depth

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
	var position_score: float
	if level_data.get("orientation", "vertical") == "horizontal":
		# AI atakuje prawą bramkę (duże x), broni lewej
		var goal_center_y = float(GOAL_ROW_START) + float(GOAL_ROWS) / 2.0
		var dist_to_attack = abs(pos.y - goal_center_y) * 0.5 + float(COLS - pos.x)
		var dist_to_defend = abs(pos.y - goal_center_y) * 0.5 + float(pos.x)
		position_score = (dist_to_defend - dist_to_attack) * 12.0
	else:
		var goal_center_attack = float(GOAL_COL_START_BLUE) + float(GOAL_COLS_BLUE) / 2.0
		var goal_center_defend = float(GOAL_COL_START_RED)  + float(GOAL_COLS_RED)  / 2.0
		var dist_to_attack = abs(pos.x - goal_center_attack) * 0.5 + float(ROWS - pos.y)
		var dist_to_defend = abs(pos.x - goal_center_defend) * 0.5 + float(pos.y)
		position_score = (dist_to_defend - dist_to_attack) * 12.0

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

# Sprawdź czy węzeł (pos) jest teleportem i gdzie prowadzi
func _teleport_destination_pure(pos: Vector2i) -> Variant:
	for n in teleport_a_nodes:
		if n == pos:
			return _find_teleport_node_partner(pos, teleport_a_nodes)
	for n in teleport_b_nodes:
		if n == pos:
			return _find_teleport_node_partner(pos, teleport_b_nodes)
	for n in teleport_c_nodes:
		if n == pos:
			return _find_teleport_node_partner(pos, teleport_c_nodes)
	return null

func _find_nearest_valid_node(cell: Vector2i) -> Vector2i:
	var candidates = [
		Vector2i(cell.x, cell.y),
		Vector2i(cell.x + 1, cell.y),
		Vector2i(cell.x, cell.y + 1),
		Vector2i(cell.x + 1, cell.y + 1),
	]
	for cn in candidates:
		if is_valid_node(cn.x, cn.y):
			return cn
	return cell

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
	if level_data.get("orientation", "vertical") == "horizontal":
		if pos.y == 0: count += 1
		if pos.y == ROWS: count += 1
		var in_goal_interior_h = (pos.y > GOAL_ROW_START and pos.y < GOAL_ROW_START + GOAL_ROWS)
		if pos.x == 0 and not in_goal_interior_h: count += 1
		if pos.x == COLS and not in_goal_interior_h: count += 1
	else:
		if pos.x == 0: count += 1
		if pos.x == COLS: count += 1
		var in_goal_top = (pos.x > GOAL_COL_START_RED  and pos.x < GOAL_COL_START_RED  + GOAL_COLS_RED)
		var in_goal_bot = (pos.x > GOAL_COL_START_BLUE and pos.x < GOAL_COL_START_BLUE + GOAL_COLS_BLUE)
		if pos.y == 0    and not in_goal_top: count += 1
		if pos.y == ROWS and not in_goal_bot: count += 1
	for dr in [-1, 0]:
		for dc in [-1, 0]:
			var cr = pos.y + dr; var cc = pos.x + dc
			if cr >= 0 and cr < ROWS and cc >= 0 and cc < COLS:
				if _is_obstacle(cr, cc):
					count += 1
	return count >= 2

func _is_goal_pure(pos: Vector2i) -> bool:
	if level_data.get("orientation", "vertical") == "horizontal":
		if pos.x < 0 and pos.y >= GOAL_ROW_START and pos.y <= GOAL_ROW_START + GOAL_ROWS:
			return true
		if pos.x > COLS and pos.y >= GOAL_ROW_START and pos.y <= GOAL_ROW_START + GOAL_ROWS:
			return true
	else:
		if pos.y < 0 and pos.x >= GOAL_COL_START_RED and pos.x <= GOAL_COL_START_RED + GOAL_COLS_RED:
			return true
		if pos.y > ROWS and pos.x >= GOAL_COL_START_BLUE and pos.x <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE:
			return true
	return false

# ——————————————————————————————————————————
#  DETEKCJA ODCIĘCIA
# ——————————————————————————————————————————

# BFS od pozycji piłki — czy można dotrzeć do bramki
# target_is_top: dla pionowej = górna (AI), dla poziomej = lewa (AI)
func _can_reach_goal(target_is_top: bool) -> bool:
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	var visited: Dictionary = {}
	var queue: Array = [ball_grid_pos]
	visited[ball_grid_pos] = true
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		# Sprawdź czy to bramka
		if is_h:
			if target_is_top and pos.x < 0: return true
			if not target_is_top and pos.x > COLS: return true
		else:
			if target_is_top and pos.y < 0: return true
			if not target_is_top and pos.y > ROWS: return true
		# Wirtualny skok przez teleport (nawet gdy krawędzie zużyte — teleport to punkt docelowy)
		var tp_dest = _teleport_destination_pure(pos)
		if tp_dest != null and not visited.has(tp_dest):
			visited[tp_dest] = true
			queue.append(tp_dest)
		# Normalne sąsiedztwo
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(pos.x + dx, pos.y + dy)
				if visited.has(nb): continue
				if not is_valid_node(nb.x, nb.y): continue
				if used_edges.has(edge_key(pos, nb)): continue
				if _is_physical_wall(pos, nb): continue
				visited[nb] = true
				queue.append(nb)
	return false

# Tylko twarde fizyczne bariery dla BFS (ściany boiska + przekątne przez nieaktywne węzły)
# NIE blokuje ruchów wzdłuż granicy obstacle — to zakaz gry, nie fizyczna ściana
func _is_physical_wall(a: Vector2i, b: Vector2i) -> bool:
	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	if is_h:
		# Górna/dolna ściana
		if a.y == 0 and b.y == 0: return true
		if a.y == ROWS and b.y == ROWS: return true
		# Lewa ściana — otwarta przy bramce
		if a.x == 0 and b.x == 0:
			var mn = mini(a.y, b.y); var mx = maxi(a.y, b.y)
			if not (mn >= GOAL_ROW_START_LEFT and mx <= GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT):
				return true
		# Prawa ściana — otwarta przy bramce
		if a.x == COLS and b.x == COLS:
			var mn = mini(a.y, b.y); var mx = maxi(a.y, b.y)
			if not (mn >= GOAL_ROW_START_RIGHT and mx <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT):
				return true
		# Przekątna przez nieaktywny węzeł
		if abs(a.x - b.x) == 1 and abs(a.y - b.y) == 1:
			var sa = Vector2i(b.x, a.y); var sb = Vector2i(a.x, b.y)
			if not is_valid_node(sa.x, sa.y) or not is_valid_node(sb.x, sb.y): return true
		return false
	# Orientacja pionowa (oryginalna)
	if a.x == 0 and b.x == 0: return true
	if a.x == COLS and b.x == COLS: return true
	if a.y == 0 and b.y == 0:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS): return true
	if a.y == ROWS and b.y == ROWS:
		var mn = mini(a.x, b.x); var mx = maxi(a.x, b.x)
		if not (mn >= GOAL_COL_START and mx <= GOAL_COL_START + GOAL_COLS): return true
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
	# Nie sprawdzaj tuż po rollbacku
	if _just_rolled_back:
		_just_rolled_back = false
		return
	var can_top = _can_reach_goal(true)    # górna/lewa bramka (AI)
	var can_bot = _can_reach_goal(false)   # dolna/prawa bramka (gracz)
	if can_top and can_bot:
		return  # obie osiągalne — gra trwa
	if not can_top and not can_bot:
		# Totalnie uwięziona — przegrywa ten kto ostatnio ruszał
		if current_player == 1:
			_show_popup_fail()
		else:
			_show_popup_win()
		return
	if not can_top:
		# Nie można dotrzeć do bramki AI — gracz przegrywa
		_show_popup_fail()
	else:
		# Nie można dotrzeć do bramki gracza — gracz wygrywa
		_show_popup_win()

# ——————————————————————————————————————————
#  TIMER (tryb gracz vs gracz)
# ——————————————————————————————————————————

func _init_timer_ui():
	var root = get_tree().root
	ui_turn_label     = _find_node_by_name(root, "Turn")
	ui_panel_timer    = _find_node_by_name(root, "Panel_Timer")
	ui_panel_color    = _find_node_by_name(root, "Panel_Color")
	ui_timer_container = ui_panel_timer

	var use_timer = (not VS_AI) or PlayerData.online_mode
	if use_timer:
		if ui_panel_timer: ui_panel_timer.get_parent().visible = true
		if ui_turn_label: ui_turn_label.visible = true
		# W online z graczem — timer startuje dopiero po ready handshake
		if PlayerData.online_mode and PlayerData.online_opponent_name != "":
			pass  # _online_ready_handshake odpali timer
		elif not (VS_AI and _ai_is_player1):
			_start_turn_timer()
	else:
		if ui_panel_timer: ui_panel_timer.get_parent().visible = false
		if ui_turn_label: ui_turn_label.visible = false
		timer_running = false

func _online_ready_handshake():
	# Wyślij "gotowy" i czekaj na przeciwnika — timer startuje po synchronizacji
	await PlayerData.push_board_ready()
	await PlayerData.wait_for_opponent_board_ready()
	# Obaj gotowi — startuj timer
	if not _game_ended:
		_start_turn_timer()

func _start_sound_init():
	await get_tree().create_timer(0.1).timeout
	var control_node = get_parent().get_parent()
	snd_bounce   = control_node.get_node_or_null("AudioStreamPlayer_Bounce")
	snd_teleport = control_node.get_node_or_null("AudioStreamPlayer_Teleport")
	snd_kick     = control_node.get_node_or_null("AudioStreamPlayer_Kick")
	if not snd_bounce:
		push_warning("board.gd: NIE ZNALEZIONO AudioStreamPlayer_Bounce")
	if not snd_teleport:
		push_warning("board.gd: NIE ZNALEZIONO AudioStreamPlayer_Teleport")
	if not snd_kick:
		push_warning("board.gd: NIE ZNALEZIONO AudioStreamPlayer_Kick")

func _init_sound_nodes():
	pass  # nieużywane — zastąpione przez _start_sound_init

func _deep_find_audio(node: Node, target_name: String) -> AudioStreamPlayer:
	if node.name == target_name and node is AudioStreamPlayer:
		return node as AudioStreamPlayer
	for child in node.get_children():
		var result = _deep_find_audio(child, target_name)
		if result:
			return result
	return null

func _find_node_by_name_safe(node: Node, target_name: String) -> AudioStreamPlayer:
	var found = _find_node_by_name(node, target_name)
	if found is AudioStreamPlayer:
		return found
	return null

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

func _start_turn_timer():
	if VS_AI and not PlayerData.online_mode:
		return
	turn_timer = TURN_TIME
	timer_running = true
	_update_timer_ui(TURN_TIME)
	_set_timer_color()

func _stop_turn_timer():
	timer_running = false

func _process(delta: float):
	_process_timer(delta)

func _process_timer(delta: float):
	if not timer_running or (VS_AI and not PlayerData.online_mode):
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
		# "YOUR TURN" gdy to moja tura — mój gracz to Player1 jeśli player1_is_me, inaczej Player2
		var my_player_num = 1 if (not PlayerData.online_mode or PlayerData.player1_is_me) else 2
		if current_player == my_player_num:
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
	_start_turn_timer()
	# Jeśli teraz tura AI — niech ruszy i zablokuj gracza
	if VS_AI and current_player == _get_ai_player():
		ai_thinking = true
		_hide_active_dots()
		await get_tree().create_timer(0.3).timeout
		_ai_take_turn()
	else:
		_refresh_active_dots()

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

# Dla każdej komórki przeszkody (wartość 0 lub 4 w edytorze) wstępnie wypełnia
# used_edges tak, jakby piłka już odwiedziła wszystkie 4 narożniki tej komórki.
# Dzięki temu wszystkie 4 boki + 2 przekątne każdej przeszkody są już "zajęte"
# i zachowują się jak ściany przy obliczaniu odbić i blokowania ruchu.
func _preload_obstacle_edges():
	for obs in obstacle_cells:
		var row: int = obs.row
		var col: int = obs.col
		# Cztery narożniki komórki (row,col) w siatce węzłów
		# Węzeł (gx, gy) = (col, row) — x=kolumna, y=wiersz
		var tl = Vector2i(col,     row)
		var tr = Vector2i(col + 1, row)
		var bl = Vector2i(col,     row + 1)
		var br = Vector2i(col + 1, row + 1)
		# 4 boki + 2 przekątne
		var pairs = [
			[tl, tr],  # górny bok
			[bl, br],  # dolny bok
			[tl, bl],  # lewy bok
			[tr, br],  # prawy bok
			[tl, br],  # przekątna TL→BR
			[tr, bl],  # przekątna TR→BL
		]
		for pair in pairs:
			var ek = edge_key(pair[0], pair[1])
			used_edges[ek] = true

func _is_obstacle(row: int, col: int) -> bool:
	for obs in obstacle_cells:
		if obs.row == row and obs.col == col:
			return true
	return false

# ——————————————————————————————————————————
#  TELEPORTY (węzły siatki, nie komórki)
# ——————————————————————————————————————————

# teleport_a_nodes / teleport_b_nodes: Array of Vector2i (gx, gy) w siatce board
var teleport_a_nodes: Array = []
var teleport_b_nodes: Array = []
var teleport_c_nodes: Array = []

func _is_teleport_node_a(gx: int, gy: int) -> bool:
	for n in teleport_a_nodes:
		if n.x == gx and n.y == gy: return true
	return false

func _is_teleport_node_b(gx: int, gy: int) -> bool:
	for n in teleport_b_nodes:
		if n.x == gx and n.y == gy: return true
	return false

# Tworzy animację "fali" teleportu na węźle siatki — szybkie kółka rozchodzące się i zanikające
func _spawn_teleport_dot(gx: int, gy: int, color: Color):
	var pos = grid_to_pixel(gx, gy)
	# Pętla nieskończona przez rekurencyjny callback
	_spawn_teleport_wave(pos, color)

func _spawn_teleport_wave(pos: Vector2, color: Color):
	var dot = Node2D.new()
	dot.position = pos
	dot.z_index = 9
	dot.set_meta("tp_radius", 0.0)
	dot.set_meta("tp_alpha", 1.0)
	dot.set_meta("tp_color", color)
	dot.draw.connect(func():
		if not is_instance_valid(dot): return
		var r: float = dot.get_meta("tp_radius")
		var a: float = dot.get_meta("tp_alpha")
		var c: Color = dot.get_meta("tp_color")
		# Fala rozchodząca się i zanikająca
		dot.draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(c.r, c.g, c.b, a * 0.7), 3.0, true)
		# Stała środkowa kropka — w pełni kolorze teleportu, bez białego
		dot.draw_circle(Vector2.ZERO, 8.0, Color(c.r, c.g, c.b, 1.0))
	)
	add_child(dot)

	var tween = create_tween().set_parallel(true)
	_active_tweens.append(tween)
	tween.tween_method(func(v: float):
		if is_instance_valid(dot): dot.set_meta("tp_radius", v); dot.queue_redraw()
	, 0.0, 26.0, 0.9)
	tween.tween_method(func(v: float):
		if is_instance_valid(dot): dot.set_meta("tp_alpha", v); dot.queue_redraw()
	, 1.0, 0.0, 0.9)
	tween.chain().tween_callback(func():
		if is_instance_valid(dot): dot.queue_free()
		if _tp_wave_active and is_instance_valid(self):
			_spawn_teleport_wave(pos, color)
	)

func _spawn_teleport_dots():
	for n in teleport_a_nodes:
		_spawn_teleport_dot(n.x, n.y, TELEPORT_A_COLOR)
	for n in teleport_b_nodes:
		_spawn_teleport_dot(n.x, n.y, TELEPORT_B_COLOR)
	for n in teleport_c_nodes:
		_spawn_teleport_dot(n.x, n.y, TELEPORT_C_COLOR)

# Sprawdź czy piłka stanęła na węźle teleportu i teleportuj
func _check_and_do_teleport(pos: Vector2i) -> bool:
	if _is_teleport_node_a(pos.x, pos.y):
		var partner = _find_teleport_node_partner(pos, teleport_a_nodes)
		if partner != null:
			_do_teleport(pos, partner)
			return true
	if _is_teleport_node_b(pos.x, pos.y):
		var partner = _find_teleport_node_partner(pos, teleport_b_nodes)
		if partner != null:
			_do_teleport(pos, partner)
			return true
	if _is_teleport_node_c(pos.x, pos.y):
		var partner = _find_teleport_node_partner(pos, teleport_c_nodes)
		if partner != null:
			_do_teleport(pos, partner)
			return true
	return false

func _find_teleport_node_partner(current: Vector2i, nodes: Array) -> Variant:
	for n in nodes:
		if n != current:
			return n
	return null

# Animacja teleportacji: skurczenie → teleport → pojawienie → koniec tury
func _do_teleport(from_node: Vector2i, target_node: Vector2i):
	if snd_teleport:
		snd_teleport.stop()
		snd_teleport.play()
	var tex_w = ball_node.texture.get_width() if ball_node.texture else 88
	var base_scale = 36.0 / tex_w
	var target_px = grid_to_pixel(target_node.x, target_node.y)
	var tween = create_tween().set_parallel(false)
	tween.tween_property(ball_node, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		ball_grid_pos = target_node
		ball_node.position = target_px
	)
	tween.tween_property(ball_node, "scale", Vector2(base_scale * 1.4, base_scale * 1.4), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ball_node, "scale", Vector2(base_scale, base_scale), 0.1)
	tween.tween_callback(func():
		# Teleport zawsze kończy turę — zmiana gracza
		combo_count = 0
		_hide_combo()
		bounce_active = false
		current_player = 2 if current_player == 1 else 1
		if not VS_AI or PlayerData.online_mode:
			_start_turn_timer()
		_refresh_active_dots()
		_check_cutoff()
		if VS_AI and current_player == _get_ai_player():
			ai_thinking = true
			_hide_active_dots()
			await get_tree().create_timer(0.28).timeout
			_ai_take_turn()
		else:
			# Tura gracza — odblokuj input
			ai_thinking = false
			_refresh_active_dots()
	)

func _build_board():
	inner   = BORDER + PADDING
	field_w = COLS      * QUAD_SIZE + (COLS      - 1) * GAP
	field_h = ROWS      * QUAD_SIZE + (ROWS      - 1) * GAP
	goal_w  = GOAL_COLS * QUAD_SIZE + (GOAL_COLS - 1) * GAP

	var is_h = level_data.get("orientation", "vertical") == "horizontal"
	var step = QUAD_SIZE + GAP

	if is_h:
		# Orientacja pozioma: bramki po bokach, goal_h=0 (brak bramek góra/dół)
		goal_h = 0
		# board_w = lewa_bramka + inner + pole + inner + prawa_bramka
		var board_w = step * 2 + inner * 2 + field_w  # step*2 = lewa + prawa bramka
		var board_h = inner * 2 + field_h
		custom_minimum_size = Vector2(board_w, board_h)
		anchor_left = 0.5; anchor_right  = 0.5
		anchor_top  = 0.5; anchor_bottom = 0.5
		offset_left   = -board_w / 2.0; offset_right  = board_w / 2.0
		offset_top    = -board_h / 2.0; offset_bottom = board_h / 2.0

		_add_field_bg(board_w)

		# Kafelki boiska (przesunięte o step w prawo bo lewa bramka zajmuje krok)
		for row in range(ROWS):
			for col in range(COLS):
				if _is_obstacle(row, col): continue
				var use_f2 = (row + col) % 2 == 1
				_place_quad(Vector2(
					step + inner + col * step,
					inner + row * step
				), use_f2)

		# Kafelki bramek bocznych
		for gc in goal_cells_data:
			var px: float
			if gc["col"] < 0:
				px = inner  # lewa bramka
			else:
				px = step + inner + COLS * step  # prawa bramka
			var py = inner + gc["row"] * step
			var quad_scene = quad_f4 if gc["type"] == 3 else quad_f3
			var gt = "red" if gc["type"] == 3 else "blue"
			_place_quad_type(Vector2(px, py), quad_scene, gt)
	else:
		# Orientacja pionowa (oryginalna)
		goal_h = step

		var board_w = field_w + inner * 2
		var board_h = goal_h * 2 + inner * 2 + field_h

		custom_minimum_size = Vector2(board_w, board_h)
		anchor_left = 0.5; anchor_right  = 0.5
		anchor_top  = 0.5; anchor_bottom = 0.5
		offset_left   = -board_w / 2.0; offset_right  = board_w / 2.0
		offset_top    = -board_h / 2.0; offset_bottom = board_h / 2.0

		var goal_quad_x_red  = inner + GOAL_COL_START_RED  * step
		var goal_quad_x_blue = inner + GOAL_COL_START_BLUE * step

		_add_field_bg(board_w)

		for i in range(GOAL_COLS_RED):
			_place_quad_type(Vector2(goal_quad_x_red + i * step, inner), quad_f4, "red")

		for row in range(ROWS):
			for col in range(COLS):
				if _is_obstacle(row, col): continue
				var use_f2 = (row + col) % 2 == 1
				_place_quad(Vector2(
					inner + col * step,
					goal_h + inner + row * step
				), use_f2)

		var bot_quad_y = goal_h + inner + ROWS * step
		for i in range(GOAL_COLS_BLUE):
			_place_quad_type(Vector2(goal_quad_x_blue + i * step, bot_quad_y), quad_f3, "blue")

func _place_quad(pos: Vector2, use_f2: bool):
	var quad = quad_f2.instantiate() if use_f2 else quad_f1.instantiate()
	quad.position = pos
	add_child(quad)

func _place_quad_type(pos: Vector2, quad_scene, goal_type: String = "") -> void:
	var quad = quad_scene.instantiate()
	quad.position = pos
	if goal_type != "":
		quad.set_meta("goal_type", goal_type)
	add_child(quad)

func _add_field_bg(_board_w: float):
	_add_shaped_field_bg()

func _add_shaped_field_bg():
	var ovr = GAP / 2.0 + 1.0
	var step = QUAD_SIZE + GAP
	var is_h = level_data.get("orientation", "vertical") == "horizontal"

	if is_h:
		# ── Poziome boisko ──────────────────────────────────────────────
		# cx boiska = step + inner + col*step (przesunięcie o lewą bramkę)
		for row in range(ROWS):
			for col in range(COLS):
				if _is_obstacle(row, col): continue
				var cx = step + inner + col * step
				var cy = inner + row * step
				var has_l = col > 0      and not _is_obstacle(row, col-1)
				var has_r = col < COLS-1 and not _is_obstacle(row, col+1)
				var has_t = row > 0      and not _is_obstacle(row-1, col)
				var has_b = row < ROWS-1 and not _is_obstacle(row+1, col)
				var goal_l = col == 0      and (row >= GOAL_ROW_START_LEFT  and row <= GOAL_ROW_START_LEFT  + GOAL_ROWS_LEFT  - 1)
				var goal_r = col == COLS-1 and (row >= GOAL_ROW_START_RIGHT and row <= GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT - 1)
				var el = ovr if (has_l or goal_l) else 1.0
				var er2 = ovr if (has_r or goal_r) else 1.0
				var et = ovr if has_t else 1.0
				var eb = ovr if has_b else 1.0
				var cell = Panel.new()
				cell.position = Vector2(cx - el, cy - et)
				cell.size     = Vector2(QUAD_SIZE + el + er2, QUAD_SIZE + et + eb)
				var sty = StyleBoxFlat.new(); sty.bg_color = FIELD_COLOR
				cell.add_theme_stylebox_override("panel", sty)
				cell.z_index = 0
				add_child(cell)

		# Bramki boczne — jeden wysoki panel po lewej i po prawej
		var goal_ry_start = inner + GOAL_ROW_START * step
		var goal_ry_end   = inner + (GOAL_ROW_START + GOAL_ROWS - 1) * step + QUAD_SIZE
		var goal_bg_h = goal_ry_end - goal_ry_start

		# Lewa bramka
		var goal_ry_start_l = inner + GOAL_ROW_START_LEFT * step
		var goal_ry_end_l   = inner + (GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT - 1) * step + QUAD_SIZE
		var goal_bg_h_l = goal_ry_end_l - goal_ry_start_l
		var cx_field_left = step + inner
		var gl = Panel.new()
		gl.position = Vector2(inner - 1.0, goal_ry_start_l - 1.0)
		gl.size     = Vector2((cx_field_left + ovr) - (inner - 1.0) + 1.0, goal_bg_h_l + 2.0)
		var sl = StyleBoxFlat.new(); sl.bg_color = FIELD_COLOR
		gl.add_theme_stylebox_override("panel", sl); gl.z_index = 0; add_child(gl)

		# Prawa bramka
		var goal_ry_start_r = inner + GOAL_ROW_START_RIGHT * step
		var goal_ry_end_r   = inner + (GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT - 1) * step + QUAD_SIZE
		var goal_bg_h_r = goal_ry_end_r - goal_ry_start_r
		var cx_field_right = step + inner + COLS * step
		var gr = Panel.new()
		gr.position = Vector2(cx_field_right - ovr, goal_ry_start_r - 1.0)
		gr.size     = Vector2((inner + step + COLS * step + QUAD_SIZE + 1.0) - (cx_field_right - ovr), goal_bg_h_r + 2.0)
		var sr = StyleBoxFlat.new(); sr.bg_color = FIELD_COLOR
		gr.add_theme_stylebox_override("panel", sr); gr.z_index = 0; add_child(gr)

	else:
		# ── Pionowe boisko (oryginał) ────────────────────────────────────
		var row_cy = func(row: int) -> float:
			return float(goal_h + inner + row * step)

		for row in range(ROWS):
			for col in range(COLS):
				if _is_obstacle(row, col): continue
				var cx = inner + col * step
				var cy = row_cy.call(row)
				var has_l = col > 0      and not _is_obstacle(row, col-1)
				var has_r = col < COLS-1 and not _is_obstacle(row, col+1)
				var has_t = row > 0      and not _is_obstacle(row-1, col)
				var has_b = row < ROWS-1 and not _is_obstacle(row+1, col)
				var goal_t = row == 0      and _is_goal_col(col)
				var goal_b = row == ROWS-1 and _is_goal_col(col)
				var el = ovr if has_l          else 1.0
				var er2 = ovr if has_r          else 1.0
				var et = ovr if (has_t or goal_t) else 1.0
				var eb = ovr if (has_b or goal_b) else 1.0
				var cell = Panel.new()
				cell.position = Vector2(cx - el, cy - et)
				cell.size     = Vector2(QUAD_SIZE + el + er2, QUAD_SIZE + et + eb)
				var sty = StyleBoxFlat.new(); sty.bg_color = FIELD_COLOR
				cell.add_theme_stylebox_override("panel", sty)
				cell.z_index = 0
				add_child(cell)

		var goal_cx_start_red = inner + GOAL_COL_START_RED * step
		var goal_cx_end_red   = inner + (GOAL_COL_START_RED + GOAL_COLS_RED - 1) * step + QUAD_SIZE
		var goal_bg_w_red     = goal_cx_end_red - goal_cx_start_red
		var cy_top = row_cy.call(-1)
		var cy_0   = row_cy.call(0)
		var gt = Panel.new()
		gt.position = Vector2(goal_cx_start_red - 1.0, cy_top - 1.0)
		gt.size     = Vector2(goal_bg_w_red + 2.0, (cy_0 + QUAD_SIZE + ovr) - (cy_top - 1.0) + 1.0)
		var st = StyleBoxFlat.new(); st.bg_color = FIELD_COLOR
		gt.add_theme_stylebox_override("panel", st); gt.z_index = 0; add_child(gt)

		# Dolna bramka (BLUE)
		var goal_cx_start_blue = inner + GOAL_COL_START_BLUE * step
		var goal_cx_end_blue   = inner + (GOAL_COL_START_BLUE + GOAL_COLS_BLUE - 1) * step + QUAD_SIZE
		var goal_bg_w_blue     = goal_cx_end_blue - goal_cx_start_blue
		var cy_bot  = row_cy.call(ROWS)
		var cy_last = row_cy.call(ROWS - 1)
		var gb = Panel.new()
		gb.position = Vector2(goal_cx_start_blue - 1.0, cy_last + QUAD_SIZE - ovr - 1.0)
		gb.size     = Vector2(goal_bg_w_blue + 2.0, (cy_bot + QUAD_SIZE + 1.0) - (cy_last + QUAD_SIZE - ovr - 1.0))
		var sb = StyleBoxFlat.new(); sb.bg_color = FIELD_COLOR
		gb.add_theme_stylebox_override("panel", sb); gb.z_index = 0; add_child(gb)

	# Border (wspólny)
	var bnode = Node2D.new()
	bnode.z_index = 3
	add_child(bnode)
	bnode.draw.connect(Callable(self, "_draw_shaped_border").bind(bnode))
	bnode.queue_redraw()

func _is_goal_col(col: int) -> bool:
	if col >= GOAL_COL_START_RED and col <= GOAL_COL_START_RED + GOAL_COLS_RED - 1:
		return true
	if col >= GOAL_COL_START_BLUE and col <= GOAL_COL_START_BLUE + GOAL_COLS_BLUE - 1:
		return true
	return false

func _is_goal_row(row: int) -> bool:
	return row >= GOAL_ROW_START and row <= GOAL_ROW_START + GOAL_ROWS - 1

func _draw_shaped_border(bnode: Node2D):
	if not is_instance_valid(bnode): return
	var bw  = float(BORDER) - 2.0  # rysuj nieco cieniej żeby nie wystawało poza pad
	var pad = 4.0
	var rc  = CORNER_RADIUS
	var step = QUAD_SIZE + GAP

	var row_cy = func(row: int) -> float:
		return float(goal_h + inner + row * (QUAD_SIZE + GAP))

	var active_set: Dictionary = {}
	var is_h2 = level_data.get("orientation", "vertical") == "horizontal"
	for row in range(ROWS):
		for col in range(COLS):
			if not _is_obstacle(row, col):
				active_set[Vector2i(col, row)] = true
	if is_h2:
		for r in range(GOAL_ROW_START_LEFT, GOAL_ROW_START_LEFT + GOAL_ROWS_LEFT):
			active_set[Vector2i(-1, r)] = true
		for r in range(GOAL_ROW_START_RIGHT, GOAL_ROW_START_RIGHT + GOAL_ROWS_RIGHT):
			active_set[Vector2i(COLS, r)] = true
	else:
		for i in range(GOAL_COLS_RED):
			active_set[Vector2i(GOAL_COL_START_RED + i, -1)]  = true
		for i in range(GOAL_COLS_BLUE):
			active_set[Vector2i(GOAL_COL_START_BLUE + i, ROWS)] = true

	var h_edges: Array = []
	var v_edges: Array = []

	for cell_key in active_set:
		var col: int = cell_key.x
		var row: int = cell_key.y
		var cx: float
		var cy: float
		if is_h2:
			cx = step + inner + col * step
			cy = inner + row * step
		else:
			cx = inner + col * (QUAD_SIZE + GAP)
			cy = row_cy.call(row)
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

func _play_bounce_sound():
	if not snd_bounce:
		return
	snd_bounce.stop()
	snd_bounce.play()
	
func _is_teleport_node_c(gx: int, gy: int) -> bool:
	for n in teleport_c_nodes:
		if n.x == gx and n.y == gy: return true
	return false

func _start_opponent_polling():
	var forfeit_check_counter = 0
	while PlayerData.online_mode and not _game_ended:
		await get_tree().create_timer(0.8).timeout
		if _game_ended or not PlayerData.online_mode: return
		
		# Sprawdź forfeit co 5 iteracji (co ~4 sekundy)
		forfeit_check_counter += 1
		if forfeit_check_counter >= 5:
			forfeit_check_counter = 0
			var forfeited = await PlayerData.poll_opponent_forfeit()
			if forfeited and not _game_ended:
				print("=== przeciwnik wyszedł — wygrana!")
				_show_popup_win()
				return
		
		if _is_my_turn(): continue
		var new_moves = await PlayerData.poll_opponent_moves()
		for move_data in new_moves:
			if _game_ended: return
			var from = Vector2i(int(move_data["fx"]), int(move_data["fy"]))
			var to   = Vector2i(int(move_data["tx"]), int(move_data["ty"]))
			print("=== aplikuję ruch przeciwnika: ", from, "->", to, " piłka na: ", ball_grid_pos)
			if ball_grid_pos == from:
				_apply_opponent_move(from, to)
				await get_tree().create_timer(0.3).timeout
			else:
				print("=== desync! ignoruję")

func _apply_opponent_move(from: Vector2i, to: Vector2i):
	if ball_grid_pos != from: return
	_applying_opponent_move = true
	_do_move(to)
	_applying_opponent_move = false
