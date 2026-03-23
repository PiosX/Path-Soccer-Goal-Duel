extends CanvasLayer

# ══════════════════════════════════════════════════════════════════
#  LEVEL EDITOR  —  F12 toggle
# ══════════════════════════════════════════════════════════════════

const CELL  = 48
const MAX_COLS = 22
const MAX_ROWS = 10
const MIN_COLS = 4
const MIN_ROWS = 4

const C_BG         = Color(0.08, 0.08, 0.12, 0.97)
const C_FIELD      = Color("#448B47")
const C_FIELD_DARK = Color("#2d5e30")
const C_GOAL_BLUE  = Color("#06c3f6")
const C_GOAL_RED   = Color("#fe4b60")
const C_OBSTACLE   = Color("#3d1a1a")
const C_OBSTACLE_BORDER = Color.WHITE
const C_GRID       = Color(1,1,1,0.10)
const C_BORDER     = Color.WHITE
const C_TELEPORT_A = Color("#aa44ff")    # teleport fioletowy (para A)
const C_TELEPORT_B = Color("#ff8800")    # teleport pomarańczowy (para B)
const C_PANEL      = Color(0.12, 0.12, 0.18, 1.0)
const C_BTN        = Color(0.22, 0.22, 0.30, 1.0)
const C_BTN_HOV    = Color(0.32, 0.32, 0.42, 1.0)
const C_BTN_ACT    = Color("#1a6faa")
const C_ACCENT     = Color("#06c3f6")

enum Cell { EMPTY=0, FIELD=1, GOAL_BLUE=2, GOAL_RED=3, OBSTACLE=4, TELEPORT_A=5, TELEPORT_B=6 }

var cols: int = 8
var rows: int = 10
var grid: Array = []
# Teleporty jako węzły siatki [{gx,gy}] — oddzielnie od gridu
var teleport_nodes_a: Array = []  # para fioletowych (max 2)
var teleport_nodes_b: Array = []  # para pomarańczowych (max 2)

var draw_mode: int = 1
var is_lmb: bool = false
var is_rmb: bool = false
var last_cell: Vector2i = Vector2i(-1,-1)

var orientation: String = "vertical"
var gen_obstacles: bool = false
var current_level_id: int = 1

var root_control: Control
var canvas_node: Node2D
var sidebar: Control
var level_id_edit: LineEdit
var cols_spin: SpinBox
var rows_spin: SpinBox
var status_label: Label
var btn_modes: Array = []
var btn_orient_v: Button
var btn_orient_h: Button

# ══════════════════════════════════════════════════════════════════
func _ready():
	layer = 100
	_build_ui()
	_reset_grid()
	visible = false

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			visible = not visible
			if visible:
				_redraw()
			return

	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _set_mode(1)
			KEY_2: _set_mode(2)
			KEY_3: _set_mode(3)
			KEY_4: _set_mode(5)
			KEY_5: _set_mode(6)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_lmb = event.pressed
			if not event.pressed: last_cell = Vector2i(-1,-1)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_rmb = event.pressed
			if not event.pressed: last_cell = Vector2i(-1,-1)

	if event is InputEventMouseMotion and (is_lmb or is_rmb):
		var ctrl = canvas_node.get_meta("ctrl_ref") as Control
		if not is_instance_valid(ctrl): return
		var lpos = ctrl.get_local_mouse_position()
		if draw_mode == 5 or draw_mode == 6:
			pass  # węzły tylko na klik, nie na drag
		else:
			var cell = _pixel_to_cell(lpos)
			if cell != last_cell:
				last_cell = cell
				_paint_cell(cell, is_lmb)

	if event is InputEventMouseButton and event.pressed:
		var ctrl = canvas_node.get_meta("ctrl_ref") as Control
		if not is_instance_valid(ctrl): return
		var lpos = ctrl.get_local_mouse_position()
		if draw_mode == 5:
			_handle_teleport_click(lpos, event.button_index == MOUSE_BUTTON_LEFT, true)
		elif draw_mode == 6:
			_handle_teleport_click(lpos, event.button_index == MOUSE_BUTTON_LEFT, false)
		else:
			var cell = _pixel_to_cell(lpos)
			if cell.x >= 0:
				_paint_cell(cell, event.button_index == MOUSE_BUTTON_LEFT)

# ══════════════════════════════════════════════════════════════════
func _reset_grid():
	grid = []
	for r in range(rows):
		var row = []
		for c in range(cols):
			row.append(Cell.FIELD)
		grid.append(row)
	teleport_nodes_a = []
	teleport_nodes_b = []
	_place_default_goals()
	_redraw()

func _place_default_goals():
	if orientation == "vertical":
		# Wiersz 0 = bramka AI (czerwona), wiersz rows-1 = bramka gracza (niebieska)
		# Środkowe kolumny (2 szerokie)
		var mid = cols / 2
		var gl = mid - 1
		var gr = mid
		for c in range(cols):
			grid[0][c] = Cell.GOAL_RED if (c >= gl and c <= gr) else Cell.EMPTY
			grid[rows-1][c] = Cell.GOAL_BLUE if (c >= gl and c <= gr) else Cell.EMPTY
	else:
		# Kolumna 0 = bramka AI (czerwona), kolumna cols-1 = bramka gracza (niebieska)
		var mid = rows / 2
		var gt = mid - 1
		var gb = mid
		for r in range(rows):
			grid[r][0] = Cell.GOAL_RED if (r >= gt and r <= gb) else Cell.EMPTY
			grid[r][cols-1] = Cell.GOAL_BLUE if (r >= gt and r <= gb) else Cell.EMPTY

func _set_grid_size(new_cols: int, new_rows: int):
	cols = clampi(new_cols, MIN_COLS, MAX_COLS)
	rows = clampi(new_rows, MIN_ROWS, MAX_ROWS)
	_reset_grid()

func _get_canvas_size() -> Vector2:
	if canvas_node and canvas_node.has_meta("ctrl_ref"):
		var ctrl = canvas_node.get_meta("ctrl_ref") as Control
		if ctrl and is_instance_valid(ctrl): return ctrl.size
	return Vector2(800, 600)

func _grid_offset_x() -> float:
	return (_get_canvas_size().x - cols * CELL) / 2.0

func _grid_offset_y() -> float:
	return (_get_canvas_size().y - rows * CELL) / 2.0

func _pixel_to_cell(local_pos: Vector2) -> Vector2i:
	var ox = _grid_offset_x(); var oy = _grid_offset_y()
	var c = int((local_pos.x - ox) / CELL)
	var r = int((local_pos.y - oy) / CELL)
	if c < 0 or c >= cols or r < 0 or r >= rows:
		return Vector2i(-1, -1)
	return Vector2i(c, r)

# Konwersja pixel → węzeł siatki (punkt między kafelkami)
func _pixel_to_node(local_pos: Vector2) -> Vector2i:
	var ox = _grid_offset_x(); var oy = _grid_offset_y()
	var nx = clampi(roundi((local_pos.x - ox) / CELL), 0, cols)
	var ny = clampi(roundi((local_pos.y - oy) / CELL), 0, rows)
	return Vector2i(nx, ny)

func _node_to_pixel(nx: int, ny: int) -> Vector2:
	return Vector2(_grid_offset_x() + nx * CELL, _grid_offset_y() + ny * CELL)

func _paint_cell(cell: Vector2i, lmb: bool):
	if cell.x < 0: return
	var r = cell.y; var c = cell.x
	var new_val: int
	if lmb:
		match draw_mode:
			1: new_val = Cell.FIELD
			2: new_val = Cell.GOAL_BLUE
			3: new_val = Cell.GOAL_RED
			_: new_val = Cell.FIELD
	else:
		new_val = Cell.EMPTY
	grid[r][c] = new_val
	_redraw()

# Tryb 5/6: klikanie węzłów ustawia teleporty (max 2 na parę)
func _handle_teleport_click(lpos: Vector2, lmb: bool, is_a: bool):
	var node = _pixel_to_node(lpos)
	var arr = teleport_nodes_a if is_a else teleport_nodes_b
	if not lmb:
		# PPM — usuń teleport na tym węźle
		var new_arr = []
		for t in arr:
			if t != node: new_arr.append(t)
		if is_a: teleport_nodes_a = new_arr
		else: teleport_nodes_b = new_arr
		_redraw()
		return
	# LPM — dodaj węzeł (max 2 na parę; jeśli już 2 — zamień najstarszy)
	var exists = false
	for t in arr:
		if t == node: exists = true; break
	if not exists:
		arr.append(node)
		if arr.size() > 2:
			arr.pop_front()
		if is_a: teleport_nodes_a = arr
		else: teleport_nodes_b = arr
	_redraw()

func _apply_symmetry(r: int, c: int, val: int):
	var mr = rows - 1 - r
	var mc = cols - 1 - c
	var val_v = val
	if val == Cell.GOAL_BLUE: val_v = Cell.GOAL_RED
	elif val == Cell.GOAL_RED: val_v = Cell.GOAL_BLUE
	# Teleporty zachowują swój typ przy symetrii
	if mr != r: grid[mr][c] = val_v
	if mc != c: grid[r][mc] = val
	if mr != r and mc != c: grid[mr][mc] = val_v

# ══════════════════════════════════════════════════════════════════
func _generate_random():
	_reset_grid()
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	if gen_obstacles:
		var max_obs = int(cols * rows * 0.12)
		var placed = 0; var attempts = 0
		while placed < max_obs and attempts < 200:
			attempts += 1
			var r = rng.randi_range(1, rows/2 - 1)
			var c = rng.randi_range(0, cols/2 - 1)
			if grid[r][c] == Cell.FIELD:
				grid[r][c] = Cell.EMPTY
				_apply_symmetry(r, c, Cell.EMPTY)
				placed += 1

	_set_status("Wygenerowano losowy poziom")
	_redraw()

# ══════════════════════════════════════════════════════════════════
func _redraw():
	if is_instance_valid(canvas_node):
		canvas_node.queue_redraw()

func _draw_editor(cn: Node2D):
	var ox = _grid_offset_x()
	var oy = _grid_offset_y()

	for r in range(rows):
		for c in range(cols):
			var x = ox + c * CELL
			var y = oy + r * CELL
			var rect = Rect2(x, y, CELL, CELL)
			match grid[r][c]:
				Cell.EMPTY:
					cn.draw_rect(rect, Color(0.05, 0.05, 0.08), true)
				Cell.FIELD:
					var dark = (r + c) % 2 == 1
					cn.draw_rect(rect, C_FIELD_DARK if dark else C_FIELD, true)
				Cell.GOAL_BLUE:
					cn.draw_rect(rect, C_GOAL_BLUE * Color(1,1,1,0.7), true)
				Cell.GOAL_RED:
					cn.draw_rect(rect, C_GOAL_RED * Color(1,1,1,0.7), true)
				Cell.OBSTACLE:
					# Stonowana czerwień — jak quad_f4 ale ciemniejsza
					cn.draw_rect(rect, C_OBSTACLE, true)

	# Bordery przeszkód — zaokrąglone białe linie
	for r in range(rows):
		for c in range(cols):
			if grid[r][c] != Cell.OBSTACLE: continue
			var x = ox + c * CELL; var y = oy + r * CELL
			var bw = 3.5
			if r == 0 or grid[r-1][c] != Cell.OBSTACLE:
				cn.draw_line(Vector2(x+4,y+1), Vector2(x+CELL-4,y+1), C_OBSTACLE_BORDER, bw)
			if r == rows-1 or grid[r+1][c] != Cell.OBSTACLE:
				cn.draw_line(Vector2(x+4,y+CELL-1), Vector2(x+CELL-4,y+CELL-1), C_OBSTACLE_BORDER, bw)
			if c == 0 or grid[r][c-1] != Cell.OBSTACLE:
				cn.draw_line(Vector2(x+1,y+4), Vector2(x+1,y+CELL-4), C_OBSTACLE_BORDER, bw)
			if c == cols-1 or grid[r][c+1] != Cell.OBSTACLE:
				cn.draw_line(Vector2(x+CELL-1,y+4), Vector2(x+CELL-1,y+CELL-4), C_OBSTACLE_BORDER, bw)

	# Linie siatki
	for r in range(rows + 1):
		cn.draw_line(Vector2(ox, oy+r*CELL), Vector2(ox+cols*CELL, oy+r*CELL), C_GRID, 1.0)
	for c in range(cols + 1):
		cn.draw_line(Vector2(ox+c*CELL, oy), Vector2(ox+c*CELL, oy+rows*CELL), C_GRID, 1.0)

	# Obramowanie boiska
	_draw_outline(cn, ox, oy)

	# Węzły siatki widoczne w trybach 4, 5, 6
	if draw_mode == 5 or draw_mode == 6:
		for nx in range(cols + 1):
			for ny in range(rows + 1):
				var pp = _node_to_pixel(nx, ny)
				cn.draw_circle(pp, 3.5, Color(1,1,1,0.5))

	# Teleporty — kropki na węzłach siatki
	for t in teleport_nodes_a:
		var pp = _node_to_pixel(t.x, t.y)
		cn.draw_circle(pp, 11.0, Color(C_TELEPORT_A.r, C_TELEPORT_A.g, C_TELEPORT_A.b, 0.3))
		cn.draw_circle(pp, 7.0, C_TELEPORT_A)
		cn.draw_circle(pp, 3.5, Color.WHITE)
	for t in teleport_nodes_b:
		var pp = _node_to_pixel(t.x, t.y)
		cn.draw_circle(pp, 11.0, Color(C_TELEPORT_B.r, C_TELEPORT_B.g, C_TELEPORT_B.b, 0.3))
		cn.draw_circle(pp, 7.0, C_TELEPORT_B)
		cn.draw_circle(pp, 3.5, Color.WHITE)
	# Linia łącząca parę teleportów (podgląd)
	if teleport_nodes_a.size() == 2:
		var p1 = _node_to_pixel(teleport_nodes_a[0].x, teleport_nodes_a[0].y)
		var p2 = _node_to_pixel(teleport_nodes_a[1].x, teleport_nodes_a[1].y)
		cn.draw_dashed_line(p1, p2, Color(C_TELEPORT_A.r, C_TELEPORT_A.g, C_TELEPORT_A.b, 0.5), 1.5, 6.0)
	if teleport_nodes_b.size() == 2:
		var p1 = _node_to_pixel(teleport_nodes_b[0].x, teleport_nodes_b[0].y)
		var p2 = _node_to_pixel(teleport_nodes_b[1].x, teleport_nodes_b[1].y)
		cn.draw_dashed_line(p1, p2, Color(C_TELEPORT_B.r, C_TELEPORT_B.g, C_TELEPORT_B.b, 0.5), 1.5, 6.0)

	# Etykiety bramek
	for r in range(rows):
		for c in range(cols):
			var x = ox + c * CELL + 4
			var y = oy + r * CELL + 4
			if grid[r][c] == Cell.GOAL_BLUE or grid[r][c] == Cell.GOAL_RED:
				var label = "B" if grid[r][c] == Cell.GOAL_BLUE else "R"
				var col2 = C_GOAL_BLUE if grid[r][c] == Cell.GOAL_BLUE else C_GOAL_RED
				cn.draw_string(ThemeDB.fallback_font, Vector2(x, y+14), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col2)

func _draw_outline(cn: Node2D, ox: float, oy: float):
	var bw = 3.0
	for c in range(cols):
		if grid[0][c] != Cell.EMPTY:
			cn.draw_line(Vector2(ox+c*CELL,oy), Vector2(ox+(c+1)*CELL,oy), C_BORDER, bw)
		if grid[rows-1][c] != Cell.EMPTY:
			cn.draw_line(Vector2(ox+c*CELL,oy+rows*CELL), Vector2(ox+(c+1)*CELL,oy+rows*CELL), C_BORDER, bw)
	for r in range(rows):
		if grid[r][0] != Cell.EMPTY:
			cn.draw_line(Vector2(ox,oy+r*CELL), Vector2(ox,oy+(r+1)*CELL), C_BORDER, bw)
		if grid[r][cols-1] != Cell.EMPTY:
			cn.draw_line(Vector2(ox+cols*CELL,oy+r*CELL), Vector2(ox+cols*CELL,oy+(r+1)*CELL), C_BORDER, bw)
	for r in range(rows):
		for c in range(cols):
			if grid[r][c] == Cell.EMPTY: continue
			var x = ox+c*CELL; var y = oy+r*CELL
			if c > 0 and grid[r][c-1] == Cell.EMPTY:
				cn.draw_line(Vector2(x,y), Vector2(x,y+CELL), C_BORDER, bw)
			if c < cols-1 and grid[r][c+1] == Cell.EMPTY:
				cn.draw_line(Vector2(x+CELL,y), Vector2(x+CELL,y+CELL), C_BORDER, bw)
			if r > 0 and grid[r-1][c] == Cell.EMPTY:
				cn.draw_line(Vector2(x,y), Vector2(x+CELL,y), C_BORDER, bw)
			if r < rows-1 and grid[r+1][c] == Cell.EMPTY:
				cn.draw_line(Vector2(x,y+CELL), Vector2(x+CELL,y+CELL), C_BORDER, bw)

# ══════════════════════════════════════════════════════════════════
func _save_level():
	var id = int(level_id_edit.text) if level_id_edit.text.is_valid_int() else current_level_id
	current_level_id = id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://levels"))
	var tp_a_data = []
	for t in teleport_nodes_a:
		tp_a_data.append({"gx": t.x, "gy": t.y})
	var tp_b_data = []
	for t in teleport_nodes_b:
		tp_b_data.append({"gx": t.x, "gy": t.y})
	var data = {
		"id": id, "cols": cols, "rows": rows,
		"orientation": orientation, "grid": [],
		"teleport_a": tp_a_data, "teleport_b": tp_b_data
	}
	for row in grid:
		data["grid"].append(row.duplicate())
	var json_str = JSON.stringify(data, "\t")
	var abs_path = ProjectSettings.globalize_path("res://levels/level_%03d.json" % id)
	var file = FileAccess.open(abs_path, FileAccess.WRITE)
	if not file:
		file = FileAccess.open("res://levels/level_%03d.json" % id, FileAccess.WRITE)
	if file:
		file.store_string(json_str); file.close()
		_set_status("Zapisano:\nlevel_%03d.json" % id)
	else:
		_set_status("BLAD zapisu!\nSprawdz res://levels/")

func _load_level():
	var id = int(level_id_edit.text) if level_id_edit.text.is_valid_int() else current_level_id
	var path_res = "res://levels/level_%03d.json" % id
	var path_abs = ProjectSettings.globalize_path(path_res)
	var json_str = ""
	if FileAccess.file_exists(path_abs):
		var f = FileAccess.open(path_abs, FileAccess.READ)
		json_str = f.get_as_text(); f.close()
	elif FileAccess.file_exists(path_res):
		var f = FileAccess.open(path_res, FileAccess.READ)
		json_str = f.get_as_text(); f.close()
	else:
		_set_status("Nie znaleziono:\nlevel_%03d.json" % id); return
	var parsed = JSON.parse_string(json_str)
	if not parsed or not parsed is Dictionary:
		_set_status("Blad JSON"); return
	cols = int(parsed.get("cols", 8))
	rows = int(parsed.get("rows", 10))
	orientation = parsed.get("orientation", "vertical")
	current_level_id = id
	grid = []
	for row_data in parsed.get("grid", []):
		var ra: Array = []
		for cell in (row_data as Array): ra.append(int(cell))
		grid.append(ra)
	# Wczytaj teleporty
	teleport_nodes_a = []
	for t in parsed.get("teleport_a", []):
		teleport_nodes_a.append(Vector2i(int(t.get("gx",0)), int(t.get("gy",0))))
	teleport_nodes_b = []
	for t in parsed.get("teleport_b", []):
		teleport_nodes_b.append(Vector2i(int(t.get("gx",0)), int(t.get("gy",0))))
	cols_spin.set_value_no_signal(cols)
	rows_spin.set_value_no_signal(rows)
	_update_orient_buttons()
	_set_status("Wczytano poziom %d\n(%d x %d)" % [id, cols, rows])
	_redraw()
	_reload_board(parsed)

func _reload_board(data: Dictionary):
	var board = _find_node_by_name_editor(get_tree().root, "BoardContainer")
	if not board:
		_set_status("Wczytano poziom %d\nNie znaleziono BoardContainer" % current_level_id)
		return
	for child in board.get_children():
		child.queue_free()
	board.used_edges.clear()
	board.move_history.clear()
	board.dot_nodes.clear()
	board.active_moves.clear()
	board.score = 0
	board.combo_count = 0
	board.bounce_active = false
	if "_just_rolled_back" in board: board._just_rolled_back = false
	if "combo_label" in board: board.combo_label = null
	board.level_data = data
	board.obstacle_cells = []
	board.teleport_a_nodes = []
	board.teleport_b_nodes = []
	board._apply_level_data()
	# Upewnij się że scroll container jest znaleziony przed build
	if not board._scroll_container:
		board._scroll_container = board._find_scroll_parent()
	board._build_board()
	board._setup_game()
	_set_status("Zaladowano poziom %d (%d x %d)" % [current_level_id, cols, rows])

func _find_node_by_name_editor(node: Node, target_name: String) -> Node:
	if node.name == target_name: return node
	for child in node.get_children():
		var found = _find_node_by_name_editor(child, target_name)
		if found: return found
	return null

# ══════════════════════════════════════════════════════════════════
#  UI — identyczne jak oryginał
# ══════════════════════════════════════════════════════════════════
func _build_ui():
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = C_BG
	root_control.add_child(bg)

	sidebar = _make_panel(Vector2(260, 0))
	sidebar.set_anchor_and_offset(SIDE_RIGHT, 1.0, -260)
	sidebar.set_anchor_and_offset(SIDE_LEFT, 1.0, -260)
	sidebar.set_anchor_and_offset(SIDE_TOP, 0.0, 0)
	sidebar.set_anchor_and_offset(SIDE_BOTTOM, 1.0, 0)
	root_control.add_child(sidebar)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	var mg = MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		mg.add_theme_constant_override("margin_"+side, 12)
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sidebar.add_child(mg)
	mg.add_child(vbox)

	_add_label(vbox, "LEVEL EDITOR", 18, C_ACCENT)
	_add_separator(vbox)

	_add_label(vbox, "Numer poziomu:", 13)
	level_id_edit = LineEdit.new()
	level_id_edit.text = "1"
	level_id_edit.custom_minimum_size = Vector2(0, 34)
	_style_lineedit(level_id_edit)
	vbox.add_child(level_id_edit)

	_add_label(vbox, "Kolumny (z bramkami):", 13)
	cols_spin = _make_spinbox(MIN_COLS, MAX_COLS, cols)
	cols_spin.value_changed.connect(func(v): _set_grid_size(int(v), rows))
	vbox.add_child(cols_spin)

	_add_label(vbox, "Wiersze (z bramkami):", 13)
	rows_spin = _make_spinbox(MIN_ROWS, MAX_ROWS, rows)
	rows_spin.value_changed.connect(func(v): _set_grid_size(cols, int(v)))
	vbox.add_child(rows_spin)

	_add_separator(vbox)
	_add_label(vbox, "Orientacja:", 13)
	var orient_hbox = HBoxContainer.new()
	orient_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(orient_hbox)
	btn_orient_v = _make_button("Pionowa", func(): _set_orientation("vertical"))
	btn_orient_h = _make_button("Pozioma", func(): _set_orientation("horizontal"))
	orient_hbox.add_child(btn_orient_v)
	orient_hbox.add_child(btn_orient_h)
	_update_orient_buttons()

	_add_separator(vbox)
	_add_label(vbox, "Tryb (1-5):", 13)
	var modes_data = [
		[1, "1 - Kafelek",           C_FIELD],
		[2, "2 - Bramka niebieska",  C_GOAL_BLUE],
		[3, "3 - Bramka czerwona",   C_GOAL_RED],
		[5, "4 - Teleport (fiol.)",  C_TELEPORT_A],
		[6, "5 - Teleport (pom.)",   C_TELEPORT_B],
	]
	btn_modes.clear()
	for md in modes_data:
		var btn = _make_button(md[1], func(m=md[0]): _set_mode(m))
		btn.set_meta("mode_id", md[0])
		btn.set_meta("mode_color", md[2])
		vbox.add_child(btn)
		btn_modes.append(btn)
	_update_mode_buttons()

	_add_separator(vbox)
	_add_label(vbox, "Generator losowy:", 13)
	var cb_obs = _make_checkbox("Przeszkody (dziury)", gen_obstacles, func(v): gen_obstacles = v)
	vbox.add_child(cb_obs)
	var btn_gen = _make_button("Generuj losowo", func(): _generate_random())
	btn_gen.custom_minimum_size.y = 40
	vbox.add_child(btn_gen)

	_add_separator(vbox)
	vbox.add_child(_make_button("Wyczysc siatke", func(): _reset_grid()))
	_add_separator(vbox)

	var btn_save = _make_button("Zapisz poziom", func(): _save_level())
	btn_save.add_theme_color_override("font_color", Color("#80ffaa"))
	vbox.add_child(btn_save)
	vbox.add_child(_make_button("Wczytaj poziom", func(): _load_level()))
	_add_separator(vbox)

	status_label = Label.new()
	status_label.text = "Gotowy"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(status_label)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	_add_label(vbox, "F12 - zamknij edytor", 11, Color(0.5,0.5,0.5))

	canvas_node = Node2D.new()
	canvas_node.set_script(null)
	root_control.add_child(canvas_node)

	var canvas_ctrl = Control.new()
	canvas_ctrl.set_anchor_and_offset(SIDE_LEFT, 0, 0)
	canvas_ctrl.set_anchor_and_offset(SIDE_TOP, 0, 0)
	canvas_ctrl.set_anchor_and_offset(SIDE_RIGHT, 1, -260)
	canvas_ctrl.set_anchor_and_offset(SIDE_BOTTOM, 1, 0)
	root_control.add_child(canvas_ctrl)

	canvas_node.draw.connect(_on_canvas_draw)
	canvas_node.set_meta("ctrl_ref", canvas_ctrl)
	root_control.resized.connect(_on_resize)
	_on_resize()

func _on_canvas_draw():
	if is_instance_valid(canvas_node):
		_draw_editor(canvas_node)

func _on_resize():
	if not canvas_node: return
	var ctrl = canvas_node.get_meta("ctrl_ref") as Control
	if ctrl and is_instance_valid(ctrl):
		canvas_node.position = Vector2.ZERO
		canvas_node.set_meta("size", ctrl.size)

# ── Helpers UI — identyczne jak oryginał ──────────────────────────
func _make_panel(min_size: Vector2) -> Panel:
	var p = Panel.new()
	p.custom_minimum_size = min_size
	var s = StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.border_color = Color(1,1,1,0.1)
	s.border_width_left = 1
	p.add_theme_stylebox_override("panel", s)
	return p

func _make_button(text: String, callable: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(b, false)
	b.pressed.connect(callable)
	b.mouse_entered.connect(func(): if is_instance_valid(b): _style_button(b, true))
	b.mouse_exited.connect(func(): if is_instance_valid(b): _style_button(b, false))
	return b

func _style_button(b: Button, hovered: bool):
	var s = StyleBoxFlat.new()
	s.bg_color = C_BTN_HOV if hovered else C_BTN
	s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left = 8; s.content_margin_right = 8
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 13)

func _make_spinbox(min_v: int, max_v: int, val: int) -> SpinBox:
	var s = SpinBox.new()
	s.min_value = min_v; s.max_value = max_v; s.value = val
	s.custom_minimum_size = Vector2(0, 34)
	return s

func _make_checkbox(text: String, init: bool, callable: Callable) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = text; cb.button_pressed = init
	cb.add_theme_font_size_override("font_size", 13)
	cb.add_theme_color_override("font_color", Color.WHITE)
	cb.toggled.connect(callable)
	return cb

func _add_label(parent: Control, text: String, size: int = 13, color: Color = Color.WHITE):
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)

func _add_separator(parent: Control):
	var s = HSeparator.new()
	s.add_theme_color_override("color", Color(1,1,1,0.1))
	parent.add_child(s)

func _style_lineedit(le: LineEdit):
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.18, 0.18, 0.25)
	s.border_color = C_ACCENT; s.border_width_bottom = 2
	s.content_margin_left = 8
	le.add_theme_stylebox_override("normal", s)
	le.add_theme_color_override("font_color", Color.WHITE)
	le.add_theme_font_size_override("font_size", 14)

func _set_mode(m: int):
	draw_mode = m
	_update_mode_buttons()
	_set_status("Tryb: %d" % m)
	_redraw()

func _update_mode_buttons():
	for btn in btn_modes:
		if not is_instance_valid(btn): continue
		var mid = btn.get_meta("mode_id")
		var mcol = btn.get_meta("mode_color") as Color
		var active = mid == draw_mode
		var s = StyleBoxFlat.new()
		s.bg_color = Color(mcol.r*0.4, mcol.g*0.4, mcol.b*0.4, 1.0) if active else C_BTN
		if active:
			s.border_color = mcol
			s.border_width_bottom = 2; s.border_width_top = 2
			s.border_width_left = 2; s.border_width_right = 2
		s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
		s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
		s.content_margin_left = 8; s.content_margin_right = 8
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)

func _set_orientation(o: String):
	orientation = o
	_update_orient_buttons()
	_place_default_goals()
	_redraw()

func _update_orient_buttons():
	var sv = StyleBoxFlat.new(); sv.bg_color = C_BTN_ACT if orientation == "vertical" else C_BTN
	sv.corner_radius_top_left=4;sv.corner_radius_top_right=4
	sv.corner_radius_bottom_left=4;sv.corner_radius_bottom_right=4
	sv.content_margin_left=8;sv.content_margin_right=8
	btn_orient_v.add_theme_stylebox_override("normal", sv)
	btn_orient_v.add_theme_stylebox_override("hover", sv)
	var sh = StyleBoxFlat.new(); sh.bg_color = C_BTN_ACT if orientation == "horizontal" else C_BTN
	sh.corner_radius_top_left=4;sh.corner_radius_top_right=4
	sh.corner_radius_bottom_left=4;sh.corner_radius_bottom_right=4
	sh.content_margin_left=8;sh.content_margin_right=8
	btn_orient_h.add_theme_stylebox_override("normal", sh)
	btn_orient_h.add_theme_stylebox_override("hover", sh)

func _set_status(msg: String):
	if status_label and is_instance_valid(status_label):
		status_label.text = msg
