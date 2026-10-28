extends SceneTree
## Past story step 13 the career check must use the imported release's own job count
## (4 on Mac, 1 on Android), not a literal. GOF2_CAREER_SAVE (optional): a saved station
## past step 13 on this import, checked through the full restore.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:check(false,"Expected content and bindings")
	else:verify(args)
	print("Career boundary: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL %d: %s"%[checks,text])

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library) or not bindings.bind_catalogues(cat):check(false,library.error+bindings.error+cat.error);return
	var android: bool=str(library.manifest.get("profile",{}).get("edition","")).begins_with("android")
	var needed:=1 if android else 4
	for completed in range(0,8):
		check(Archive.career_boundary_met(bindings,14,completed)==(completed>=needed),"Step 14 with %d jobs: expected %s on this edition"%[completed,completed>=needed])
		check(Archive.career_boundary_met(bindings,13,completed),"Step 13 is never gated by the job count")
	var path:=OS.get_environment("GOF2_CAREER_SAVE")
	if path.is_empty():return
	var doc:=SaveFile.new().read_document(path)
	check(not doc.is_empty() and int(doc.station.campaign_cursor)>13,"GOF2_CAREER_SAVE must be a station past step 13")
	if failures:return
	for completed in [0,needed-1,needed,needed+1]:
		var d: Dictionary=doc.duplicate(true)
		d.career.completed_side_missions=completed;d.station.completed_side_missions=completed
		var archive:=Archive.new();var restored: RefCounted=archive.restore(bindings,cat,library,d)
		check((restored!=null)==(completed>=needed),"Restore with %d jobs: expected %s (%s)"%[completed,completed>=needed,archive.error])
		if restored==null:check(archive.error=="The save has an unresolved result or unsupported career boundary","Wrong rejection: "+archive.error)
