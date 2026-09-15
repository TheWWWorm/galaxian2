extends "res://tests/local_station_save.gd"
## Earn the first lounge through the training and local-journey application.
## Its first save has no fabricated result, wallet, job count or previous client.
func after_lounge_application(args: PackedStringArray):
	if failures:return
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var original: Dictionary=host.session.station_owner().snapshot()
	check(original.campaign_cursor==13 and original.contracts.credits==0 and original.completed_side_missions==0 and not original.contracts.has("last_result"),"The first lounge contains unearned contract progress")
	var archive:=Archive.new();var file:=SaveFile.new()
	var document:=archive.capture(host.session.station_owner(),bindings)
	var restored:=archive.restore(bindings,cat,lib,document)
	if restored==null:check(false,archive.error);return
	check(restored.snapshot()==original,"The first lounge changed on restoration")
	check(file.load_document(host.station_save_path(),bindings,cat,lib)==document,"The lounge introduction did not autosave: "+file.error)
	var path:=SaveFile.path_for(save_directory.path_join("13"),bindings)
	check(file.save(path,restored,bindings,cat,lib),file.error)
	check(host.load_station(now_us),host._save_notice.text)
	check(host.session.station_owner().snapshot()==original,"The application lost the first lounge's earned inventory or contacts")
	check(host.request_departure(),host.session.error);host.cancel_departure()
	print("Saved actual lounge introduction: ",path)
	await super.after_lounge_application(args)
