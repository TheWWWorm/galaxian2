extends "res://tests/free_application.gd"
## Paid purchases use the actual application and survive local travel/docking.
## The optional earned fixture has the same producer checks as the full route.
const ShoppingChecks=preload("res://tests/ordinary_shopping.gd")

class RefusedPanel extends Control:
	var error:="Deliberate presentation refusal"
	func present(_state: Dictionary) -> bool:return false

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	app.show();app.present_session();await process_frame;resume_application_focus()
	check(app._hangar_button.visible and app._launch_button.visible,"The earned ordinary station did not expose its hangar")
	if not app.request_departure():check(false,app.status.text);return
	check(not app.equipment_action("open") and app.session.station_owner().snapshot()==original,"The hangar opened through a pending departure confirmation")
	app.cancel_departure();resume_application_focus()
	var key:=InputEventKey.new();key.physical_keycode=KEY_H;key.pressed=true
	app._unhandled_input(key)
	if not app.session.snapshot().get("hangar_open",false):check(false,app.status.text);return
	var quote: Dictionary=app.session.station_owner().snapshot()
	check(app.equipment_panel.visible and not app._launch_button.visible and not app._hangar_button.visible,"An open shop retained station launch controls")
	check(app.equipment_panel._credits==quote.contracts.credits and app.equipment_panel._cargo.text.contains(str(quote.contracts.credits)),"The shop omitted its retained wallet")
	var affordable:=ShoppingChecks.cheapest(quote)
	if affordable.is_empty():check(false,"The current station has no affordable generated offer");return
	var id: int=affordable.item_id;var price: int=affordable.unit_price
	check(app.equipment_panel._rows[id].detail.text.contains(str(price)),"The shop displayed a tutorial price")
	check(not app.equipment_panel._rows[id].actions.buy.disabled,"An affordable paid item was disabled")
	await capture_free_application("shopping-desktop")
	await verify_shop_layout(false)
	if failures:return
	app._focused=false
	check(not app.equipment_action("buy",id) and app.session.station_owner().snapshot()==quote,"Unfocused controls bought an item")
	resume_application_focus()
	app.hide()
	check(not app.equipment_action("buy",id) and app.session.station_owner().snapshot()==quote,"Hidden controls bought an item")
	app.show();resume_application_focus()
	app.set_user_paused(true)
	check(not app.equipment_action("buy",id) and app.session.station_owner().snapshot()==quote,"Paused controls bought an item")
	app.set_user_paused(false);app.session.rebase_time(now_us);resume_application_focus()
	var refused:=RefusedPanel.new();root.add_child(refused)
	check(not app.session.equipment_action("buy",id,source,definitions,app.station_panel,refused) and app.session.station_owner().snapshot()==quote,"Failed presentation committed cargo, stock or credits")
	refused.free()
	check(not app.contract_action("open",-1) and app.session.station_owner().snapshot()==quote,"An open hangar allowed a competing lounge transaction")
	key=InputEventKey.new();key.physical_keycode=KEY_ENTER;key.pressed=true;app._unhandled_input(key)
	check(app._launch_packet.is_empty() and app.session.station_owner().snapshot()==quote,"Hangar confirmation input leaked into departure")
	app.equipment_panel._rows[id].actions.buy.pressed.emit()
	var bought: Dictionary=app.session.station_owner().snapshot()
	check(bought.contracts.credits==quote.contracts.credits-price and bought.cargo.used==quote.cargo.used+1,"The actual Buy button did not commit its paid unit")
	check(app.equipment_panel._credits==bought.contracts.credits,"The accepted purchase left a stale wallet display")
	app.equipment_panel.select_tab("cargo")
	check(app.equipment_panel._rows[id].actions.sell.visible and app.equipment_panel._rows[id].actions.mount.visible==bought.equipment.has("fitting_support"),"Paid cargo controls disagree with the supported fitting capability")
	await capture_free_application("shopping-cargo-desktop")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame;resume_application_focus();app.present_session()
	await verify_shop_layout(true)
	await capture_free_application("shopping-cargo-mobile-landscape")
	app.equipment_panel.select_tab("shop")
	await capture_free_application("shopping-mobile-landscape")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	await process_frame;resume_application_focus();app.present_session()
	if not await verify_overfilled_shop():return
	bought=app.session.station_owner().snapshot()
	if not app.equipment_action("close"):check(false,app.session.error);return
	var departure: Dictionary=app.session.station_owner().snapshot()
	var retained_stock: Array=app.current_locations().item_stock(98)
	var retained_location: Dictionary=app.current_locations().location(98)
	check(departure.phase==original.phase and departure.mission==original.mission and app._launch_button.visible,"Closing the shop changed the pending story or disabled departure")
	if OS.get_environment("GOF2_SHOPPING_PANELS_ONLY")=="1":return
	for destination in [95,98]:
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight() or not await travel_application(destination) or not await dock_application():return
		var landed: Dictionary=app.session.snapshot()
		check(landed.loadout.station_id==destination and landed.contracts.credits==bought.contracts.credits and landed.cargo==bought.cargo,"Local flight or docking lost the paid cargo or wallet")
		check(landed.mission==original.mission and landed.contracts.completed_side_missions==4 and landed.contracts.travel_statistics==original.contracts.travel_statistics,"Trading travel advanced the story, a job or the gate count")
		check(app.current_locations().item_stock(98)==retained_stock and app.current_locations().location(98)==retained_location,"Local travel regenerated or lost the traded station stock")
		print("Paid cargo retained after actual local arrival/docking at ",destination,"; ",landed.contracts.credits,"cr")
		if destination==95:
			if not app.equipment_action("open"):check(false,app.session.error);return
			var shop: Dictionary=app.session.snapshot()
			check(shop.equipment.stock_station_id==95 and app.current_locations().item_stock(95)==shop.equipment.stock,"The destination shop reused Alioth's offers")
			var offer:=ShoppingChecks.cheapest(shop)
			if offer.is_empty():check(false,"Gome C has no affordable generated offer");return
			if not app.equipment_action("buy",offer.item_id) or not app.equipment_action("sell",offer.item_id):check(false,app.session.error);return
			check(app.session.snapshot().cargo==bought.cargo and app.session.snapshot().contracts.credits==bought.contracts.credits,"Destination purchase/resale lost retained quantities or wallet")
			check(app.current_locations().location(98)==retained_location,"Trading at Gome C changed Alioth's cached stock")
			await capture_free_application("shopping-gome-c-desktop")
			if not app.equipment_action("close"):check(false,app.session.error);return
	check(app.equipment_action("open"),app.session.error)
	check(app.session.snapshot().cargo==bought.cargo and app.session.snapshot().contracts.credits==bought.contracts.credits,"Reopening after travel restored the pre-purchase inventory")
	await capture_free_application("shopping-return-desktop")
	check(app.equipment_action("close"),app.session.error)
	check(app.session.snapshot().mission==original.mission,"The shop return completed the unsupported next mission")

func verify_overfilled_shop() -> bool:
	for unit in 1024:
		var current: Dictionary=app.session.station_owner().snapshot()
		if current.cargo.used>current.cargo.capacity:break
		var offer:=ShoppingChecks.cheapest(current)
		if offer.is_empty() or not app.equipment_action("buy",offer.item_id):check(false,"Actual shop could not exercise its overfilled-hold boundary: "+app.session.error);return false
	var full: Dictionary=app.session.station_owner().snapshot()
	check(full.cargo.used==full.cargo.capacity+1 and app.equipment_panel._cargo.text.contains(source.strings[193]),"The actual shop lost its overfilled warning or accepted quantity")
	root.size=Vector2i(960,540);app.set_mobile_layout(true);app.set_touch_controls(true)
	await process_frame;resume_application_focus();app.present_session()
	await verify_shop_layout(true)
	await capture_free_application("shopping-overfilled-mobile-landscape")
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	await process_frame;resume_application_focus();app.present_session()
	if not app.equipment_action("close"):check(false,app.session.error);return false
	var closed: Dictionary=app.session.station_owner().snapshot()
	check(not app.request_departure() and app._launch_packet.is_empty() and app.status.text==source.strings[193] and app.session.station_owner().snapshot()==closed,"Overfilled departure lost the source warning or changed inventory")
	if not app.equipment_action("open"):check(false,app.session.error);return false
	var sale: Dictionary={}
	for row in app.session.snapshot().equipment.market_rows:
		if row.owned>0 and not row.mission:sale=row;break
	if sale.is_empty():check(false,"Overfilled shop has no saleable owned item");return false
	app.equipment_panel.select_tab("cargo")
	app.equipment_panel._rows[sale.item_id].actions.sell.pressed.emit()
	check(app.session.snapshot().cargo.used==full.cargo.capacity,"Actual Sell button failed to make the overfilled hold fit")
	return failures==0

func verify_shop_layout(mobile: bool) -> void:
	for frame in 3:await process_frame
	resume_application_focus()
	var panel: Control=app.equipment_panel._panel
	var bounds:=Rect2(Vector2.ZERO,Vector2(root.size))
	check(bounds.encloses(panel.get_global_rect()),"The shop panel overflows its landscape viewport")
	check(panel.get_global_rect().encloses(app.equipment_panel._close.get_global_rect()),"The shop Close control is clipped")
	check(app.equipment_panel._close.custom_minimum_size.y==(44 if mobile else 28),"The shop ignored desktop/mobile control sizing")
	check(app.equipment_panel._title.get_theme_font_size("font_size")== (20 if mobile else 15),"The shop ignored desktop/mobile text sizing")
