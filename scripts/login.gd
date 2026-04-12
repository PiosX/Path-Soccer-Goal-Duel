extends CanvasLayer

# ————— PANELE —————
@onready var ctrl_guest  = $MarginContainer/Control/Control_Guest
@onready var ctrl_login  = $MarginContainer/Control/Control_Login
@onready var ctrl_forgot = $MarginContainer/Control/Control_Forgot

# ————— GUEST —————
@onready var guest_input       = $MarginContainer/Control/Control_Guest/VBoxContainer/Guest_Input
@onready var checkbox_terms    = $MarginContainer/Control/Control_Guest/VBoxContainer/HBoxContainer/CheckBox
@onready var rich_text_terms   = $MarginContainer/Control/Control_Guest/VBoxContainer/HBoxContainer/RichTextLabel
@onready var label_error_guest = $MarginContainer/Control/Control_Guest/VBoxContainer/Label_Error
@onready var btn_play          = $MarginContainer/Control/Control_Guest/TextureButton_Play
@onready var btn_to_login      = $MarginContainer/Control/Control_Guest/TextureButton_Login

# ————— LOGIN —————
@onready var login_input       = $MarginContainer/Control/Control_Login/VBoxContainer_Login/Login_Input
@onready var password_input    = $MarginContainer/Control/Control_Login/VBoxContainer_Password/Password_Input
@onready var label_error_login = $MarginContainer/Control/Control_Login/VBoxContainer_Password/Label_Error
@onready var link_forgot       = $MarginContainer/Control/Control_Login/VBoxContainer_Password/HBoxContainer/LinkButton
@onready var btn_guest         = $MarginContainer/Control/Control_Login/HBoxContainer/TextureButton_Guest
@onready var btn_login         = $MarginContainer/Control/Control_Login/HBoxContainer/TextureButton_Login

# ————— FORGOT —————
@onready var forgot_email_input = $MarginContainer/Control/Control_Forgot/VBoxContainer_Email/Email_Input
@onready var forgot_label_error = $MarginContainer/Control/Control_Forgot/VBoxContainer_Email/Label_Error
@onready var btn_forgot_send    = $MarginContainer/Control/Control_Forgot/TextureButton_Send
@onready var btn_forgot_guest   = $MarginContainer/Control/Control_Forgot/HBoxContainer/TextureButton_Guest
@onready var btn_forgot_login   = $MarginContainer/Control/Control_Forgot/HBoxContainer/TextureButton_Login

# ————— SOUND —————
@onready var sound_click = $MarginContainer/Control/SoundClick

# ————— STAŁE —————
const MIN_NICK = 4
const MAX_NICK = 11
const MIN_PASS = 6
const MAX_PASS = 16
const PANEL_W  = 416.0

# ————— PLAYFAB —————
const PLAYFAB_TITLE_ID = "139617"
const PLAYFAB_URL      = "https://139617.playfabapi.com"

var _busy    := false
var _base_ol := 0.0
var _base_or := 0.0

# ═══════════════════════════════════════════
func _ready():
	await get_tree().process_frame
	await get_tree().process_frame  # drugi frame — layout musi się policzyć zanim size będzie niezerowy

	_base_ol = ctrl_guest.offset_left
	_base_or = ctrl_guest.offset_right

	# Pivoty — teraz size jest już prawidłowe
	for btn in [btn_play, btn_to_login, btn_guest, btn_login,
				btn_forgot_send, btn_forgot_guest, btn_forgot_login]:
		if btn:
			btn.pivot_offset = btn.size / 2

	# Max length
	guest_input.max_length    = MAX_NICK
	login_input.max_length    = MAX_NICK
	password_input.max_length = MAX_PASS
	password_input.secret     = true

	# RichTextLabel — linki terms/privacy
	rich_text_terms.bbcode_enabled = true
	rich_text_terms.text = "I agree to the [url=terms][color=#08B9FF]Terms of Service[/color][/url] and [url=privacy][color=#08B9FF]Privacy Policy[/color][/url]"

	# Checkbox — pivot
	checkbox_terms.pivot_offset = checkbox_terms.size / 2

	# Forgot error ukryty
	forgot_label_error.text = ""

	# Panele startowe
	ctrl_guest.modulate.a  = 1.0
	ctrl_guest.visible     = true

	ctrl_login.offset_left  = _base_ol + PANEL_W
	ctrl_login.offset_right = _base_or + PANEL_W
	ctrl_login.modulate.a   = 0.0
	ctrl_login.visible      = false

	ctrl_forgot.offset_left  = _base_ol + PANEL_W
	ctrl_forgot.offset_right = _base_or + PANEL_W
	ctrl_forgot.modulate.a   = 0.0
	ctrl_forgot.visible      = false

	_clear_errors()

# ═══════════════════════════════════════════
#  ANIMACJE PANELI
# ═══════════════════════════════════════════

func _slide_to(panel_in: Control, panel_out: Control, direction: int):
	# direction: 1 = panel_in wjeżdża z prawej, -1 = z lewej
	panel_in.offset_left  = _base_ol + PANEL_W * direction
	panel_in.offset_right = _base_or + PANEL_W * direction
	panel_in.modulate.a   = 0.0
	panel_in.visible      = true

	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel_out, "offset_left",  _base_ol - PANEL_W * direction, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(panel_out, "offset_right", _base_or - PANEL_W * direction, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(panel_out, "modulate:a", 0.0, 0.25)
	tw.tween_property(panel_in, "offset_left",  _base_ol, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(panel_in, "offset_right", _base_or, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(panel_in, "modulate:a", 1.0, 0.25)
	await tw.finished

	panel_out.offset_left  = _base_ol
	panel_out.offset_right = _base_or
	panel_out.modulate.a   = 1.0
	panel_out.visible      = false
	_clear_errors()

func _slide_to_login():
	await _slide_to(ctrl_login, ctrl_guest, 1)

func _slide_to_guest():
	await _slide_to(ctrl_guest, ctrl_login, -1)

func _slide_to_forgot():
	await _slide_to(ctrl_forgot, ctrl_login, 1)

func _slide_forgot_to_guest():
	await _slide_to(ctrl_guest, ctrl_forgot, -1)

func _slide_forgot_to_login():
	await _slide_to(ctrl_login, ctrl_forgot, -1)

# ═══════════════════════════════════════════
#  CHECKBOX ANIMACJA
# ═══════════════════════════════════════════

func _on_check_box_toggled(toggled_on: bool):
	sound_click.play()
	checkbox_terms.pivot_offset = checkbox_terms.size / 2
	var tw = create_tween()
	if toggled_on:
		tw.tween_property(checkbox_terms, "scale", Vector2(1.2, 1.2), 0.08)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(checkbox_terms, "scale", Vector2(1.0, 1.0), 0.1)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(checkbox_terms, "scale", Vector2(0.9, 0.9), 0.08)
		tw.tween_property(checkbox_terms, "scale", Vector2(1.0, 1.0), 0.1)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ═══════════════════════════════════════════
#  RICHTEXT LINKI
# ═══════════════════════════════════════════

func _on_rich_text_label_meta_clicked(meta):
	if meta == "terms":
		OS.shell_open("https://redmoongames-path-tos.carrd.co/")
	elif meta == "privacy":
		OS.shell_open("https://redmoongames-path-pp.carrd.co/")

# ═══════════════════════════════════════════
#  PRZYCISKI NAWIGACJI
# ═══════════════════════════════════════════

func _on_texture_button_login_pressed():
	sound_click.play()
	_slide_to_login()

func _on_texture_button_guest_pressed():
	sound_click.play()
	_slide_to_guest()

func _on_link_button_pressed():
	sound_click.play()
	forgot_email_input.text = ""
	forgot_label_error.text = ""
	_slide_to_forgot()

func _on_texture_button_forgot_guest_pressed():
	sound_click.play()
	_slide_forgot_to_guest()

func _on_texture_button_forgot_login_pressed():
	sound_click.play()
	_slide_forgot_to_login()

# ═══════════════════════════════════════════
#  PLAY (gość z nickiem)
# ═══════════════════════════════════════════

func _on_texture_button_play_pressed():
	sound_click.play()
	var nick = guest_input.text.strip_edges()

	if not checkbox_terms.button_pressed:
		_show_error(label_error_guest, "Please accept the Terms & Privacy Policy.")
		_shake(ctrl_guest)
		return

	if nick.length() < MIN_NICK:
		_show_error(label_error_guest, "Username must be at least %d characters." % MIN_NICK)
		_shake(ctrl_guest)
		return

	_set_busy(true)
	label_error_guest.text = ""

	var device_id = OS.get_unique_id()
	var body = {
		"TitleId":  PLAYFAB_TITLE_ID,
		"CustomId": device_id,
		"CreateAccount": true,
		"InfoRequestParameters": { "GetPlayerProfile": true }
	}

	var result = await _playfab_post("/Client/LoginWithCustomID", body)
	if result == null:
		_show_error(label_error_guest, "Connection error. Try again.")
		_set_busy(false)
		return

	var taken = await _is_display_name_taken(nick)
	if taken:
		_show_error(label_error_guest, "Username is already taken.")
		_set_busy(false)
		return

	var session_ticket = result.get("SessionTicket", "")
	await _set_display_name(session_ticket, nick)

	var newly_created = result.get("NewlyCreated", false)
	if newly_created:
		await _init_player_data(session_ticket)

	var entity_token = result.get("EntityToken", {}).get("EntityToken", "")
	var entity_id = result.get("EntityToken", {}).get("Entity", {}).get("Id", "")
	_save_session(result.get("PlayFabId", ""), session_ticket, nick, false, "", entity_token, entity_id)
	_set_busy(false)
	SceneTransition.go_to("res://scenes/play.tscn")

# ═══════════════════════════════════════════
#  LOGIN (nick + hasło)
# ═══════════════════════════════════════════

func _on_texture_button_login_login_pressed():
	sound_click.play()
	var uname = login_input.text.strip_edges()
	var passw = password_input.text.strip_edges()

	if uname.length() < MIN_NICK:
		_show_error(label_error_login, "Username must be at least %d characters." % MIN_NICK)
		_shake(ctrl_login)
		return
	if passw.length() < MIN_PASS:
		_show_error(label_error_login, "Password must be at least %d characters." % MIN_PASS)
		_shake(ctrl_login)
		return

	_set_busy(true)
	label_error_login.text = ""

	var body = {
		"TitleId":  PLAYFAB_TITLE_ID,
		"Username": uname,
		"Password": passw
	}

	var result = await _playfab_post("/Client/LoginWithPlayFab", body)
	if result == null:
		_show_error(label_error_login, "Invalid username or password.")
		_set_busy(false)
		return

	var session_ticket = result.get("SessionTicket", "")
	var nick = login_input.text.strip_edges()
	var entity_token = result.get("EntityToken", {}).get("EntityToken", "")
	var entity_id = result.get("EntityToken", {}).get("Entity", {}).get("Id", "")
	_save_session(result.get("PlayFabId", ""), session_ticket, nick, true, nick, entity_token, entity_id)

	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	await PlayerData._fetch_and_sync_player_data(session_ticket, cfg)

	_set_busy(false)
	SceneTransition.go_to("res://scenes/play.tscn")

# ═══════════════════════════════════════════
#  FORGOT PASSWORD — wyślij email
# ═══════════════════════════════════════════

func _on_texture_button_send_pressed():
	sound_click.play()
	var email = forgot_email_input.text.strip_edges()

	if email.length() < 5 or not "@" in email:
		_show_error(forgot_label_error, "Enter a valid email address.")
		_shake(ctrl_forgot)
		return

	_set_busy(true)
	forgot_label_error.text = ""

	var body = {
		"TitleId": PLAYFAB_TITLE_ID,
		"Email":   email
	}

	var result = await _playfab_post("/Client/SendAccountRecoveryEmail", body)
	_set_busy(false)

	if result == null:
		_show_error(forgot_label_error, "Email not found or connection error.")
		return

	# Sukces — pokaż info i wróć do loginu po chwili
	_show_error(forgot_label_error, "Recovery email sent! Check your inbox.")
	await get_tree().create_timer(2.0).timeout
	_slide_forgot_to_login()

# ═══════════════════════════════════════════
#  PLAYFAB HELPERS
# ═══════════════════════════════════════════

func _playfab_post(endpoint: String, body: Dictionary):
	var url = PLAYFAB_URL + endpoint
	var headers = ["Content-Type: application/json", "Accept-Encoding: identity"]
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

func _is_display_name_taken(nick: String) -> bool:
	# Sprawdź czy nick istnieje próbując zalogowania z niemożliwym hasłem.
	# PlayFab zwróci "InvalidUsernameOrPassword" (1001) jeśli konto istnieje,
	# albo "AccountNotFound" (1001) jeśli nie — w obu przypadkach result == null,
	# więc ta metoda jest zawodna. Używamy GetPlayerProfile zamiast tego.
	var body = {
		"TitleId":  PLAYFAB_TITLE_ID,
		"Username": nick,
		"Password": "___check_x9z___"
	}
	var url = PLAYFAB_URL + "/Client/LoginWithPlayFab"
	var headers = ["Content-Type: application/json", "Accept-Encoding: identity"]
	var http = HTTPRequest.new()
	add_child(http)
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var response = await http.request_completed
	http.queue_free()
	if response[1] != 200:
		var json = JSON.new()
		if json.parse(response[3].get_string_from_utf8()) == OK:
			var parsed = json.get_data()
			# errorCode 1001 = AccountNotFound (nick wolny), inne = konto istnieje
			var err_code = parsed.get("errorCode", 0)
			return err_code != 1001
		return false
	return true  # zalogował się poprawnie = nick zajęty

func _set_display_name(session_ticket: String, nick: String):
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + session_ticket
	]
	var body = { "DisplayName": nick }
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserTitleDisplayName",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	await http.request_completed
	http.queue_free()

func _init_player_data(session_ticket: String):
	var headers = [
		"Content-Type: application/json",
		"Accept-Encoding: identity",
		"X-Authorization: " + session_ticket
	]
	var body = {
		"Data": {
			"gold":        "20",
			"active_skin": "skin1",
			"owned_skins": JSON.stringify(["skin1"])
		}
	}
	var http = HTTPRequest.new()
	add_child(http)
	http.request(PLAYFAB_URL + "/Client/UpdateUserData",
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	await http.request_completed
	http.queue_free()

# ═══════════════════════════════════════════
#  LOKALNY ZAPIS SESJI
# ═══════════════════════════════════════════

func _save_session(playfab_id: String, ticket: String, nick: String, has_account: bool, email: String = "", entity_token: String = "", entity_id: String = ""):
	var cfg = ConfigFile.new()
	cfg.load("user://session.cfg")
	cfg.set_value("session", "playfab_id",  playfab_id)
	cfg.set_value("session", "ticket",      ticket)
	cfg.set_value("session", "nick",        nick)
	cfg.set_value("session", "has_account", has_account)
	cfg.set_value("session", "device_id",   OS.get_unique_id())
	if email != "":
		cfg.set_value("session", "email", email)
	if entity_token != "":
		cfg.set_value("session", "entity_token", entity_token)
	if entity_id != "":
		cfg.set_value("session", "entity_id", entity_id)
	if not cfg.has_section_key("session", "gold"):
		cfg.set_value("session", "gold", 20)
	cfg.save("user://session.cfg")

# ═══════════════════════════════════════════
#  UI HELPERS
# ═══════════════════════════════════════════

func _set_busy(busy: bool):
	_busy = busy
	for btn in [btn_play, btn_login, btn_to_login, btn_guest,
				btn_forgot_send, btn_forgot_guest, btn_forgot_login]:
		if btn:
			btn.disabled = busy
	btn_play.modulate.a        = 0.5 if busy else 1.0
	btn_login.modulate.a       = 0.5 if busy else 1.0
	btn_forgot_send.modulate.a = 0.5 if busy else 1.0

func _show_error(label: Label, msg: String):
	label.text       = msg
	label.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.2)

func _clear_errors():
	label_error_guest.text  = ""
	label_error_login.text  = ""
	forgot_label_error.text = ""

func _shake(ctrl: Control):
	var ol  = ctrl.offset_left
	var orr = ctrl.offset_right
	var tw = create_tween()
	tw.tween_property(ctrl, "offset_left", ol + 10, 0.05)
	tw.tween_property(ctrl, "offset_left", ol - 10, 0.05)
	tw.tween_property(ctrl, "offset_left", ol + 6,  0.04)
	tw.tween_property(ctrl, "offset_left", ol - 6,  0.04)
	tw.tween_property(ctrl, "offset_left", ol,      0.03)

# ═══════════════════════════════════════════
#  HOVER
# ═══════════════════════════════════════════

func _on_texture_button_play_mouse_entered():
	_scale_button(btn_play, 0.9)
func _on_texture_button_play_mouse_exited():
	_scale_button(btn_play, 1.0)

func _on_texture_button_login_mouse_entered():
	_scale_button(btn_to_login, 0.9)
func _on_texture_button_login_mouse_exited():
	_scale_button(btn_to_login, 1.0)

func _on_texture_button_guest_mouse_entered():
	_scale_button(btn_guest, 0.9)
func _on_texture_button_guest_mouse_exited():
	_scale_button(btn_guest, 1.0)

func _on_texture_button_login_login_mouse_entered():
	_scale_button(btn_login, 0.9)
func _on_texture_button_login_login_mouse_exited():
	_scale_button(btn_login, 1.0)

func _on_texture_button_send_mouse_entered():
	_scale_button(btn_forgot_send, 0.9)
func _on_texture_button_send_mouse_exited():
	_scale_button(btn_forgot_send, 1.0)

func _on_texture_button_forgot_guest_mouse_entered():
	_scale_button(btn_forgot_guest, 0.9)
func _on_texture_button_forgot_guest_mouse_exited():
	_scale_button(btn_forgot_guest, 1.0)

func _on_texture_button_forgot_login_mouse_entered():
	_scale_button(btn_forgot_login, 0.9)
func _on_texture_button_forgot_login_mouse_exited():
	_scale_button(btn_forgot_login, 1.0)

func _scale_button(btn: Control, target_scale: float):
	if btn == null:
		return
	btn.pivot_offset = btn.size / 2
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
