extends SceneTree
## Exercise the detached arrival selection transaction from an actually earned
## paid32 save. These proposals do not travel, change inventory or advance story.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const SETTINGS={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,
	"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=4:check(false,"Expected content/bindings/visuals and the earned paid32 v8 save")
	else:verify(args)
	print("Ordinary Void career selection: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var document: Dictionary=file.read_document(args[3])
	var station: RefCounted=archive.restore(bindings,cat,library,document)
	if station==null:check(false,archive.error);return
	check(document.version==8 and document.station.campaign_cursor==32 and document.inventory.loadout.station_id==98,"Use the actually earned paid Alioth32 source/blueprint fixture")
	var career: RefCounted=station.contract_owner()
	var before: Dictionary=career.snapshot()
	check(before.void_source.eligible_selection_count==0 and before.void_source.source_station_id==91 and before.blueprints.entries.size()==25,"The paid result changed source or blueprint history")
	var random: Dictionary=before.lounges.random
	var unchanged: RefCounted=career.fork()
	check(unchanged.select_location(bindings,cat,library,98,SETTINGS,random,1789100846),unchanged.error)
	check(unchanged.snapshot()==before,"Selecting the retained station counted or regenerated unchanged state")
	var selected: RefCounted=career.fork()
	if not selected.select_location(bindings,cat,library,95,SETTINGS,random,1789100846):check(false,selected.error);return
	var observed: Dictionary=selected.snapshot()
	check(observed.void_source.eligible_selection_count==1 and observed.void_source.source_station_id==91,"A changed ordinary location did not count exactly once")
	check(observed.lounges.current_station_id==95 and observed.lounges.random==random,"A retained location changed the stream without a reroll")
	check(observed.blueprints==before.blueprints and observed.progress==before.progress and observed.credits==before.credits and observed.mission==before.mission,"Location selection changed blueprints, earned progress, wallet or accepted job")
	check(selected.select_location(bindings,cat,library,95,SETTINGS,random,1789100846) and selected.snapshot()==observed,"A repeated arrival proposal counted the same location again")
	check(career.snapshot()==before and archive.capture(station,bindings)==document,"Detached selection changed the parent or saved station")
	for target in [-1,999]:
		check(not selected.select_location(bindings,cat,library,target,SETTINGS,random,1789100846) and selected.snapshot()==observed,"A failed destination committed its source or location")
	check(not selected.select_location(bindings,cat,library,98,SETTINGS,{"state":-1},1789100846) and selected.snapshot()==observed,"A failed random stream changed the source transaction")
	var bad_settings: Dictionary=SETTINGS.duplicate();bad_settings.difficulty=1.0
	check(not selected.select_location(bindings,cat,library,98,bad_settings,random,1789100846) and selected.snapshot()==observed,"A changed difficulty committed the arrival")
	for target in [10,91]:
		var skipped: RefCounted=career.fork()
		check(skipped.select_location(bindings,cat,library,target,SETTINGS,random,1789100846),skipped.error)
		check(skipped.void_source_state()==before.void_source,"Selecting the story target or existing source added an eligible call")
	check(file.read_document(args[3])==document,"The earned input file was rewritten")

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
