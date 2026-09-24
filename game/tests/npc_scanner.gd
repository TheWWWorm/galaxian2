extends SceneTree
const Scanner=preload("res://src/simulation/opening_npc_scanner.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Definitions=preload("res://src/content/npc_scanner_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Markers=preload("res://src/presentation/flight_npc_markers.gd")
const Frame=preload("res://src/presentation/flight_target_frame.gd")
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1],args[i+2])
	print("NPC scanner checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String, pixels: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var scanner:=Scanner.new()
	if bindings.opening_staging.get("npc_scanner",{}).is_empty():
		check(not scanner.configure(bindings,catalogues,Vector2(76,57),25) and scanner.snapshot().is_empty(),"Legacy pack invented scanner support")
		return
	var definition: Dictionary=bindings.opening_staging.npc_scanner
	var architecture: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(definition,10000000,architecture,bindings.opening_staging).is_empty(),"Source scanner rejected")
	for key in definition.provenance:
		var bad:=definition.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,10000000,architecture,bindings.opening_staging).is_empty(),"Disconnected scanner span accepted")
	var geometry:=Frame.source_geometry(library,bindings);var animation:=Markers.source_geometry(library,bindings)
	check(not geometry.has("error") and not animation.has("error"),"Original marker geometry unavailable")
	if geometry.has("error") or animation.has("error"):return
	check(animation.frames==25 and animation.frame_size==40,"Original scanner strip lost 25 square frames")
	check(scanner.configure(bindings,catalogues,Frame.logical_radii(geometry.quarter_size,false),animation.frames),scanner.error)
	check(scanner.snapshot().equipment_id==82 and scanner.snapshot().duration_ms==3000,"Scanner did not read opening equipment properties")
	var combat: Dictionary={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actors":[]}
	for id in 3:
		var actor:=Actor.new()
		check(actor.configure(bindings,catalogues,id,0.5),actor.error)
		var row:=actor.snapshot();row.active=true;row.actor_mode=1;row.hostile=true;row.pose=Transform3D(Basis.IDENTITY,Vector3(0,0,-1000))
		combat.actors.append(row)
	var aim: Dictionary={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"point":Vector3(400,300,-1000),"viewport_size":Vector2i(800,600)}
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,0,true),scanner.error)
	check(scanner.snapshot().candidate_actor_id==0 and scanner.snapshot().elapsed_ms==0 and scanner.snapshot().animation_frame==-1,"First population candidate / zero-time behavior differs")
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,3000,true),scanner.error)
	check(scanner.snapshot().selected_actor_id==-1 and scanner.snapshot().elapsed_ms==3000 and scanner.snapshot().animation_frame==24,"Scanner completed at equality or lost final animation frame")
	var saved:=scanner.snapshot();var fork: RefCounted=scanner.fork_for_frame()
	check(fork.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,1,true),fork.error)
	var locked: Dictionary=fork.snapshot()
	check(locked.selected_actor_id==0 and locked.elapsed_ms==0 and locked.events.size()==2 and locked.events[0].source_id==26 and locked.events[1].source_id==22,"New acquisition lost source events or timer reset")
	check(not locked.markers[0].selected and locked.animation_frame==-1,"Markers used post-acquisition selection")
	check(scanner.snapshot()==saved,"Detached scanner changed original state")
	# A normal offscreen ship must not reject the whole scanner update when its
	# projected pixels overflow. Retain the lock without acquiring it offscreen.
	var crossing: RefCounted=fork.fork_for_frame()
	var beside:=combat.duplicate(true)
	for actor in beside.actors:actor.pose.origin=Vector3(1000,0,-0.0001)
	check(crossing.advance(beside,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true),crossing.error)
	var crossed: Dictionary=crossing.snapshot()
	check(crossed.selected_actor_id==0 and crossed.elapsed_ms==0 and crossed.events.is_empty() and crossed.markers.size()==3,"Offscreen camera-plane targets changed acquisition or stopped the scanner")
	for marker in crossed.markers:
		check(not marker.in_view and not marker.in_scan_window and marker.pixels.x>400 and marker.pixels.x<500 and marker.pixels.y==300,"Camera-plane NPC lost its bounded marker or became selectable")
	scanner=fork
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,3001,true),scanner.error)
	check(scanner.snapshot().markers[0].selected and scanner.snapshot().events.is_empty(),"Same selected NPC repeated acquisition effects")
	combat.actors[0].pose.origin.x=100000
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,1000,true),scanner.error)
	check(scanner.snapshot().candidate_actor_id==1 and scanner.snapshot().elapsed_ms==1000 and not scanner.snapshot().markers[0].near,"Candidate switch failed or far marker stayed near")
	for row in combat.actors:row.pose.origin.x=100000
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,10,true),scanner.error)
	check(scanner.snapshot().selected_actor_id==0 and scanner.snapshot().candidate_actor_id==1 and scanner.snapshot().elapsed_ms==0,"No-candidate draw did not retain prior candidate with a selection")
	combat.actors[0].actor_mode=3
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,10,true),scanner.error)
	check(scanner.snapshot().selected_actor_id==-1 and scanner.snapshot().candidate_actor_id==-1 and scanner.snapshot().markers.size()==2,"Destroyed selection was not cleared before markers")
	combat.actors[1].pose.origin=Vector3(0,0,-1000)
	var radius:=800/int(definition.window_divisor)
	aim.point.x=400+radius
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true),scanner.error)
	check(scanner.snapshot().candidate_actor_id==-1,"Strict scanner edge accepted equality")
	aim.point.x-=0.5
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true),scanner.error)
	check(scanner.snapshot().candidate_actor_id==1 and scanner.snapshot().elapsed_ms==100,"Inside scanner boundary was rejected")
	saved=scanner.snapshot()
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,4000,false),scanner.error)
	check(scanner.snapshot().elapsed_ms==100 and scanner.snapshot().candidate_actor_id==1 and not scanner.snapshot().visible,"Hidden HUD advanced or discarded retained scanning")
	saved=scanner.snapshot()
	check(not scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,2147483647,true) and scanner.snapshot()==saved,"Overflowing scanner frame changed state")
	var bad_aim:=aim.duplicate(true);bad_aim.viewport_size=Vector2i.ZERO
	check(not scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,bad_aim,10,true) and scanner.snapshot()==saved,"Rejected viewport changed scanner state")
	combat.actors[1].pose.origin=Vector3(0,0,-24000);aim.point.x=400
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,0,true),scanner.error)
	check(scanner.snapshot().markers[0].near,"Inclusive near-box boundary was lost")
	combat.actors[1].pose.origin.z=-24001
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,3001,true),scanner.error)
	check(not scanner.snapshot().markers[0].near and scanner.snapshot().selected_actor_id==1,"Far NPC could not be acquired")
	# Negative fractional lower bound: int(20.5-radius) has a different
	# upper edge from int(20.5)-radius. Project safely inside pixel radius+20.
	var half_fov: float=bindings.flight_projection.vertical_fov_radians/2.0
	var target_x: float=(float(radius)+20.5-400.0)*1000.0*tan(half_fov)*(800.0/600.0)/400.0
	combat.actors[1].pose.origin=Vector3(target_x,0,-1000);aim.point.x=20.5
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true),scanner.error)
	check(scanner.snapshot().markers[0].pixels.x==radius+20 and scanner.snapshot().markers[0].in_scan_window,"Scanner truncated aim before subtracting its radius")
	combat.actors[1].pose.origin=Vector3(0,0,-70000);aim.point.x=400
	check(scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,1,true),scanner.error)
	check(scanner.snapshot().markers[0].in_scan_window and scanner.snapshot().elapsed_ms==101,"Scanner incorrectly applied the weapon's 60000-unit cutoff")
	saved=scanner.snapshot();combat.actors[1].hull_catalogue_id=44
	check(not scanner.advance(combat,Transform3D.IDENTITY,Transform3D.IDENTITY,aim,100,true) and scanner.snapshot()==saved,"Scanner accepted an unsupported target population")
	combat.actors[1].hull_catalogue_id=23
	if not visuals.open(pixels,library.manifest):check(false,visuals.error);return
	var hud:=Markers.new()
	check(hud.prepare(library,bindings,visuals),hud.error)
	check(hud.present(scanner.snapshot()),hud.error)
	check(hud.source().regions.size()==15 and hud.source().animation.frames==25,"Original marker aliases or filmstrip missing")
	hud.set_mobile_layout(true);hud.free()
	print(library.manifest.profile.edition,": scanner timing, source ordering, boundaries, death, detached failure and original art verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
