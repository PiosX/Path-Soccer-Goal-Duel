extends Node
# ConsentManager - GDPR / UMP
# Autoload: Project Settings → Autoload → "ConsentManager"
# Kolejność autoloadów:
#   1. AdMobManager
#   2. ConsentManager  ← odpala reklamy po zgodzie

var _consent_form: ConsentForm

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame
	request_consent()

func request_consent():
	if OS.get_name() != "Android":
		print("ConsentManager: nie Android, pomijam UMP")
		_start_ads()
		return

	var request := ConsentRequestParameters.new()
	# Odkomentuj TYLKO do testów (symuluje użytkownika z EU):
	# var debug := ConsentDebugSettings.new()
	# debug.debug_geography = DebugGeography.Values.EEA
	# request.consent_debug_settings = debug

	UserMessagingPlatform.consent_information.update(
		request,
		_on_consent_info_updated,
		_on_consent_error
	)

func _on_consent_info_updated():
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	print("ConsentManager: status = ", status)

	if not UserMessagingPlatform.consent_information.get_is_consent_form_available():
		_start_ads()
		return

	if status == UserMessagingPlatform.consent_information.ConsentStatus.OBTAINED:
		_start_ads()
		return

	UserMessagingPlatform.load_consent_form(_on_form_loaded, _on_consent_error)

func _on_form_loaded(form: ConsentForm):
	_consent_form = form
	var status = UserMessagingPlatform.consent_information.get_consent_status()
	if status == UserMessagingPlatform.consent_information.ConsentStatus.REQUIRED:
		form.show(_on_form_dismissed)
	else:
		_start_ads()

func _on_form_dismissed(_error: FormError):
	_start_ads()

func _on_consent_error(error: FormError):
	print("ConsentManager: błąd UMP: ", error.get_message())
	_start_ads()  # błąd = nie blokuj reklam

func _start_ads():
	var admob = get_node_or_null("/root/AdMobManager")
	if not admob or admob.ads_disabled:
		return
	await get_tree().create_timer(1.0).timeout
	admob._load_interstitial()

func show_privacy_options():
	if _consent_form:
		_consent_form.show(_on_form_dismissed)
