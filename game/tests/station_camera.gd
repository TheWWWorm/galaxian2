extends SceneTree
## Detached camera admission for each supported source hangar, without a journey.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Views=preload("res://src/content/station_presentation_definitions.gd")
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")
const FreeCampaign=preload("res://src/content/free_campaign_definitions.gd")
const Camera=preload("res://src/simulation/station_camera.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Station cameras: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var visited:=0
	for world in Worlds.SYSTEMS.values():
		for station in world.station_ids:
			if Worlds.catalogue_location(bindings,cat,station).is_empty():continue
			visited+=1
			var view:=Views.select(bindings,station,18)
			var selected:=bindings.resolve_hangar(station,cat)
			if view.is_empty() or selected.is_empty():check(false,"The supported station lacks its original hangar view: "+str(station));continue
			check(view.station_id==station and view.hangar_row==selected.row,"The camera differs from the imported hangar row: "+str(station))
			var camera:=Camera.new();var reference:=Camera.new()
			if not camera.configure(view,42) or not reference.configure(view,42):check(false,camera.error+reference.error+" at "+str(station));continue
			check(camera.snapshot()==reference.snapshot(),"Camera admission changed the seeded source drift")
			check(camera.advance(150) and reference.advance(150) and camera.snapshot()==reference.snapshot(),"Supported station camera lost its native drift")
			var before:=camera.snapshot()
			check(not camera.advance(151) and camera.snapshot()==before,"Invalid camera time changed the accepted pose")
			var changed:=view.duplicate(true);changed.camera.position[0]+=1
			check(not Views.view_parameters(changed),"The supported station admitted a fabricated camera")
			changed=view.duplicate(true);changed.station_id=999
			check(not Views.view_parameters(changed),"An unknown station borrowed the supported camera")
	check(visited>0,"No supported source locations were checked")
	if FreeCampaign.supported(bindings.mido_travel,27):
		# The earned return docks at Sahi48 after the Void pursuit. Every
		# system9 station shares source hangar row2, including this cursor27 path.
		for station in [45,46,47,48,49]:
			var world:=Worlds.catalogue_location(bindings,cat,station)
			var selected:=bindings.resolve_hangar(station,cat)
			var view:=Views.select(bindings,station,27)
			check(not world.is_empty() and not selected.is_empty() and not view.is_empty(),"Missing source system9 camera at cursor27: "+str(station))
			if world.is_empty() or selected.is_empty() or view.is_empty():continue
			check(world.system_id==9 and int(world.system_fields[int(bindings.hangars.system_field)])==2,"The source system9 field no longer selects row2: "+str(station))
			check(selected.row==2 and view.hangar_row==selected.row and view.station_id==station,"Cursor27 camera differs from the imported hangar: "+str(station))
			check(view.camera.position==Views.ROW_TWO.position and view.camera.angles==Views.ROW_TWO.angles and view.light.ambient==Views.ROW_TWO.ambient,"Cursor27 camera or light differs from the source row2 table: "+str(station))
			check(Views.view_parameters(view),"Cursor27 source camera failed declaration admission: "+str(station))
			var camera:=Camera.new()
			check(camera.configure(view,42),"Cursor27 source camera could not start: "+str(station)+" "+camera.error)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;printerr("FAIL: "+message)
