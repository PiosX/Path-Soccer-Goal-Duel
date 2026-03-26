extends CanvasLayer

# ————— ISTNIEJĄCE —————
@onready var sound_click = $MarginContainer/Control/SoundClick
@onready var btn_privacy = $MarginContainer/Control/ScrollContainer/VBoxContainer/TextureButton_Privacy
@onready var btn_terms = $MarginContainer/Control/ScrollContainer/VBoxContainer/TextureButton_Terms

# ————— FORMULARZE —————
@onready var register   = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register
@onready var registered = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered

# ————— REGISTER (gość) —————
@onready var reg_login_input    = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register/VBoxContainer_Login/Login_Input
@onready var reg_email_input    = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register/VBoxContainer_Email/Email_Input
@onready var reg_password_input = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register/VBoxContainer_Password/Password_Input
@onready var reg_label_error    = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register/VBoxContainer_Password/Label_Error
@onready var btn_register       = $MarginContainer/Control/ScrollContainer/VBoxContainer/Register/TextureButton_Register

# ————— REGISTERED (ma konto) —————
@onready var regd_login_input = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/VBoxContainer_Login/Login_Input
@onready var regd_email_input = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/VBoxContainer_Email/Email_Input
@onready var btn_logout       = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/HBoxContainer/TextureButton_Logout
@onready var btn_delete       = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/HBoxContainer/TextureButton_Delete
@onready var vbox_confirm     = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/HBoxContainer/VBoxContainer_Confirm
@onready var confirm_input    = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/HBoxContainer/VBoxContainer_Confirm/Confirmation_Input
@onready var confirm_error    = $MarginContainer/Control/ScrollContainer/VBoxContainer/Registered/HBoxContainer/VBoxContainer_Confirm/Label_Error

# ————— PLAYFAB —————
const PLAYFAB_TITLE_ID = "139617"
const PLAYFAB_URL      = "https://139617.playfabapi.com"

var _busy := false

# ═══════════════════════════════════════════
func _ready():
	await get_tree().process_frame

	for btn in [btn_privacy, btn_terms, btn_register, btn_logout, btn_delete]:
		if btn:
			btn.pivot_offset = btn.size / 2

	# Inputy tylko do odczytu
	reg_login_input.editable    = false
	reg_login_input.modulate.a  = 0.6
	regd_login_input.editable   = false
	regd_login_input.modulate.a = 0.6
	regd_email_input.editable   = false
	regd_email_input.modulate.a = 0.6

	reg_label_error.visible = false
	confirm_error.visible   = false
	vbox_confirm.visible    = false

	_load_session()

func _load_session():
	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		register.visible   = false
		registered.visible = false
		return

	var nick        = cfg.get_value("session", "nick", "")
	var has_account = cfg.get_value("session", "has_account", false)
	var email       = cfg.get_value("session", "email", "")

	if has_account:
		register.visible      = false
		registered.visible    = true
		regd_login_input.text = nick
		regd_email_input.text = email
	else:
		register.visible     = true
		registered.visible   = false
		reg_login_input.text = nick

# ═══════════════════════════════════════════
#  REGISTER
# ═══════════════════════════════════════════

func _on_texture_button_register_pressed():
	sound_click.play()
	var email = reg_email_input.text.strip_edges()
	var passw = reg_password_input.text.strip_edges()

	if email.length() < 5 or not "@" in email:
		_show_error(reg_label_error, "Enter a valid email address.")
		return
	if passw.length() < 6:
		_show_error(reg_label_error, "Password must be at least 6 characters.")
		return

	_set_busy(true)
	reg_label_error.visible = false

	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		_show_error(reg_label_error, "Session error. Please restart the game.")
		_set_busy(false)
		return

	var ticket = cfg.get_value("session", "ticket", "")
	var nick   = cfg.get_value("session", "nick", "")

	var body = {
		"Email":    email,
		"Password": passw,
		"Username": nick
	}

	var result = await _playfab_post_auth("/Client/AddUsernamePassword", body, ticket)
	if result == null:
		_show_error(reg_label_error, "Email already in use or connection error.")
		_set_busy(false)
		return

	cfg.set_value("session", "has_account", true)
	cfg.set_value("session", "email", email)
	cfg.save("user://session.cfg")

	_set_busy(false)

	register.visible      = false
	registered.visible    = true
	regd_login_input.text = nick
	regd_email_input.text = email
	vbox_confirm.visible  = false

# ═══════════════════════════════════════════
#  LOGOUT
# ═══════════════════════════════════════════

func _on_texture_button_logout_pressed():
	sound_click.play()
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("session.cfg")
	get_tree().change_scene_to_file("res://scenes/login.tscn")

# ═══════════════════════════════════════════
#  DELETE ACCOUNT
# ═══════════════════════════════════════════

func _on_texture_button_delete_pressed():
	sound_click.play()

	if not vbox_confirm.visible:
		vbox_confirm.visible  = true
		confirm_input.text    = ""
		confirm_error.visible = false
		return

	var typed = confirm_input.text.strip_edges().to_lower()

	if typed.length() == 0:
		vbox_confirm.visible = false
		return

	if typed != "yes":
		_show_error(confirm_error, "Type \"yes\" to confirm deletion.")
		return

	_set_busy(true)
	confirm_error.visible = false

	var cfg = ConfigFile.new()
	if cfg.load("user://session.cfg") != OK:
		_show_error(confirm_error, "Session error.")
		_set_busy(false)
		return

	var ticket = cfg.get_value("session", "ticket", "")
	await _playfab_post_auth("/Client/DeletePlayer", {}, ticket)

	var dir = DirAccess.open("user://")
	if dir:
		dir.remove("session.cfg")

	_set_busy(false)
	get_tree().change_scene_to_file("res://scenes/login.tscn")

# ═══════════════════════════════════════════
#  PLAYFAB HELPER
# ═══════════════════════════════════════════

func _playfab_post_auth(endpoint: String, body: Dictionary, ticket: String):
	var url = PLAYFAB_URL + endpoint
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + ticket
	]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()

	var status_code = response[1]
	var body_raw    = response[3]
	if status_code != 200:
		return null

	var json = JSON.new()
	if json.parse(body_raw.get_string_from_utf8()) != OK:
		return null

	var parsed = json.get_data()
	if parsed.get("code", 0) != 200:
		return null

	return parsed.get("data", null)

# ═══════════════════════════════════════════
#  UI HELPERS
# ═══════════════════════════════════════════

func _set_busy(busy: bool):
	_busy = busy
	if btn_register:
		btn_register.disabled   = busy
		btn_register.modulate.a = 0.5 if busy else 1.0
	if btn_delete:
		btn_delete.disabled   = busy
		btn_delete.modulate.a = 0.5 if busy else 1.0
	if btn_logout:
		btn_logout.disabled = busy

func _show_error(label: Label, msg: String):
	label.text       = msg
	label.visible    = true
	label.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.2)

# ═══════════════════════════════════════════
#  ISTNIEJĄCE
# ═══════════════════════════════════════════

func _on_privacy_pressed():
	sound_click.play()
	OS.shell_open("https://redmoongames-path-pp.carrd.co/")

func _on_privacy_mouse_entered():
	_scale_button(btn_privacy, 0.9)
func _on_privacy_mouse_exited():
	_scale_button(btn_privacy, 1.0)
	
func _on_terms_pressed():
	sound_click.play()
	OS.shell_open("https://redmoongames-path-tos.carrd.co/")
	
func _on_terms_mouse_entered():
	_scale_button(btn_terms, 0.9)
func _on_terms_mouse_exited():
	_scale_button(btn_terms, 1.0)

func _on_texture_button_register_mouse_entered():
	_scale_button(btn_register, 0.9)
func _on_texture_button_register_mouse_exited():
	_scale_button(btn_register, 1.0)

func _on_texture_button_logout_mouse_entered():
	_scale_button(btn_logout, 0.9)
func _on_texture_button_logout_mouse_exited():
	_scale_button(btn_logout, 1.0)

func _on_texture_button_delete_mouse_entered():
	_scale_button(btn_delete, 0.9)
func _on_texture_button_delete_mouse_exited():
	_scale_button(btn_delete, 1.0)

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
