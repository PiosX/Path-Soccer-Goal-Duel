extends Node
# IAP Manager — Path Game
# Autoload: Project → Project Settings → Autoload → "IAPManager"

var billing_client = null
var is_ready = false
var owned_products: Array = []

signal purchase_completed(product_id: String)
signal purchase_failed(error_message: String)
signal purchase_cancelled
signal restore_completed(restored_count: int)

# ===== PRODUKTY — uzupełnij ID gdy utworzysz w Google Play Console =====
const PRODUCTS = {
	"no_ads": {
		"type": "non_consumable",
		"title": "Remove Ads Forever",
		"description": "Removes all advertisements permanently",
		"price_display": "$0.99"
	}
	# Tutaj dodasz więcej produktów (gold packi itp.) gdy będziesz gotowy
	# "gold_small": {
	#     "type": "consumable",
	#     "title": "100 Gold",
	#     "amount": 100,
	#     "price_display": "$0.99"
	# },
}

func _ready():
	if OS.get_name() == "Android":
		billing_client = BillingClient.new()
		billing_client.connected.connect(_on_billing_connected)
		billing_client.disconnected.connect(_on_billing_disconnected)
		billing_client.connect_error.connect(_on_billing_connect_error)
		if billing_client.has_signal("on_purchases_updated"):
			billing_client.on_purchases_updated.connect(_on_purchases_updated)
		if billing_client.has_signal("query_purchases_response"):
			billing_client.query_purchases_response.connect(_on_query_purchases)
		if billing_client.has_signal("product_details_query_completed"):
			billing_client.product_details_query_completed.connect(_on_product_details_completed)
		if billing_client.has_signal("purchase_acknowledged"):
			billing_client.purchase_acknowledged.connect(_on_purchase_acknowledged)
		if billing_client.has_signal("purchase_consumed"):
			billing_client.purchase_consumed.connect(_on_purchase_consumed)
		billing_client.start_connection()
	else:
		print("IAP skipped - not on Android")

func _on_billing_connected():
	is_ready = true
	query_product_details()
	query_purchases()

func _on_billing_disconnected():
	is_ready = false

func _on_billing_connect_error(error_code: int, error_message: String):
	print("Billing error [%d]: %s" % [error_code, error_message])
	is_ready = false

func query_purchases():
	if not is_ready or not billing_client: return
	billing_client.query_purchases(BillingClient.ProductType.INAPP)

func query_product_details():
	if not is_ready or not billing_client: return
	billing_client.query_product_details(PRODUCTS.keys(), BillingClient.ProductType.INAPP)

func _on_query_purchases(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK: return
	var purchases = result.get("purchases", [])
	owned_products.clear()
	for purchase in purchases:
		var product_id = purchase.get("product_ids", [""])[0]
		var purchase_token = purchase.get("purchase_token", "")
		var is_acknowledged = purchase.get("is_acknowledged", false)
		owned_products.append(product_id)
		handle_owned_product(product_id)
		if not is_acknowledged:
			billing_client.acknowledge_purchase(purchase_token)
	restore_completed.emit(purchases.size())

func _on_purchases_updated(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK:
		if result.get("response_code", -1) == 1:
			purchase_cancelled.emit()
		else:
			purchase_failed.emit(result.get("debug_message", "Unknown error"))
		return
	for purchase in result.get("purchases", []):
		handle_new_purchase(purchase)

func _on_product_details_completed(result: Dictionary):
	if result.get("response_code", -1) != BillingClient.BillingResponseCode.OK: return
	for detail in result.get("product_details", []):
		var sku = detail.get("product_id", "")
		if PRODUCTS.has(sku):
			PRODUCTS[sku]["price"] = detail.get("price", "")

func purchase_product(product_id: String):
	if not is_ready or not billing_client:
		purchase_failed.emit("Billing system not ready")
		return
	if not PRODUCTS.has(product_id):
		purchase_failed.emit("Unknown product")
		return
	if PRODUCTS[product_id].type == "non_consumable" and owns_product(product_id):
		purchase_failed.emit("Already owned")
		return
	billing_client.purchase(product_id)

func _on_purchase_acknowledged(purchase_token: String):
	pass

func _on_purchase_consumed(purchase_token: String):
	pass

func handle_new_purchase(purchase: Dictionary):
	var product_id = purchase.get("product_ids", [""])[0]
	var purchase_token = purchase.get("purchase_token", "")
	if purchase.get("purchase_state", 0) != 1: return
	if not PRODUCTS.has(product_id): return

	var product = PRODUCTS[product_id]

	if product.type == "non_consumable":
		if product_id == "no_ads":
			var admob = get_node_or_null("/root/AdMobManager")
			if admob:
				admob.disable_ads()
		billing_client.acknowledge_purchase(purchase_token)

	elif product.type == "consumable":
		var amount = product.get("amount", 0)
		# Dodaj gold do PlayerData
		PlayerData.add_gold(amount)
		billing_client.consume_purchase(purchase_token)

	purchase_completed.emit(product_id)

func handle_owned_product(product_id: String):
	if product_id == "no_ads":
		var admob = get_node_or_null("/root/AdMobManager")
		if admob:
			admob.disable_ads()

func restore_purchases():
	query_purchases()

func owns_product(product_id: String) -> bool:
	return product_id in owned_products

func get_product_price(product_id: String) -> String:
	var product = PRODUCTS.get(product_id, {})
	return product.get("price", product.get("price_display", ""))

func is_available() -> bool:
	return is_ready
