extends "res://tests/ordinary_contract_application.gd"
## First process: save an actual accepted courier before ending the application.
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Archive=preload("res://src/simulation/station_archive.gd")

func verify_free_application() -> void:
	var directory:=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if directory.is_empty() or not FreePlayCheckpoint.private_path(directory+"/save.bin"):check(false,"Set a private application save directory");return
	app.show();app.enable_saves(directory);app.present_session();await process_frame;resume_application_focus()
	var original: Dictionary=app.session.station_owner().snapshot()
	var key:=InputEventKey.new();key.physical_keycode=KEY_F5;key.pressed=true
	app._unhandled_input(key)
	var file:=SaveFile.new();var before:=file.load_document(app.station_save_path(),definitions,catalogue,source)
	if before.is_empty():check(false,file.error+app._save_notice.text);return
	check(before==Archive.new().capture(app.session.station_owner(),definitions),"F5 changed the earned station record")
	if not app.contract_action("open",-1):check(false,app.session.error);return
	var chosen:=-1
	for id in original.contracts.offers:
		if original.contracts.offers[id].offer.mission.kind==0 and app.session.station_owner().contract_preview(id,definitions).get("can_accept",false):chosen=id;break
	if chosen<0:check(false,"The earned lounge has no affordable supported courier");return
	app.lounge_panel.select_contact(chosen);app.lounge_panel.confirm();app.lounge_panel.confirm()
	if not app.contract_action("close",-1):check(false,app.session.error);return
	var saved:=file.load_document(app.station_save_path(),definitions,catalogue,source)
	if saved.is_empty():check(false,file.error+app._save_notice.text);return
	check(saved.career.mission==original.contracts.offers[chosen].offer.mission and saved.career.accepted_contact.offer_id==chosen,"Closing the lounge did not save the accepted job")
	check(file.read_document(app.station_save_path()+".bak")==before,"Acceptance overwrote its previous viable save")
	check(app.session.station_owner().snapshot().mission==original.mission,"Saving advanced the pending campaign")
	await capture_free_application("save-accepted-desktop")
	print("Saved courier for a separate process: ",app.station_save_path())
