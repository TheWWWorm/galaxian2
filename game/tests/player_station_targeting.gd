extends "res://tests/player_station_departure.gd"
## Earned Var Hastra departure, with only a detached target observation placed
## at the actual exterior. The source save and live flight remain untouched.
const Target=preload("res://src/simulation/station_targeting.gd")
const Catalogues=preload("res://src/content/catalogues.gd")

func verify_departure(app: Control) -> void:
	await super.verify_departure(app)
	if failures:return
	var host: Control=app.game
	var session: Node=host.session
	var state: Dictionary=session.snapshot()
	check(state.has("station_targeting") and state.has("station_exterior") and state.has("mining_targeting") and state.scenery.objects.size()>0,"Earned Var Hastra field has no ordinary station and asteroid targets")
	if failures:return
	var scene: Node=session.scene
	check(scene.station_target_overlay!=null and scene.scan_animation!=null,"Station departure lacks marker or shared scanner art")
	if failures:return
	var cat:=Catalogues.new();check(cat.open(host.library),cat.error)
	if failures:return
	var station: Dictionary=state.station_exterior
	var mining: Dictionary=state.mining_targeting
	var target:=Target.new()
	check(target.configure_ordinary(host.bindings,station,mining,scene.target_frame.marker_radii(),int(state.campaign_cursor)),target.error)
	if failures:return
	var initial: Dictionary=target.snapshot()
	check(initial.station_id==station.station_id and initial.duration_ms==mining.duration_ms and initial.scanner_id==mining.scanner_id and initial.found_index==-1,"Ordinary lock did not reuse the installed source scanner")
	var camera:=Transform3D(Basis.IDENTITY,station.pose.origin+Vector3.BACK*10000.0)
	var sample:=observation(state,station,camera,100)
	var elapsed:=0
	while elapsed<int(mining.duration_ms):
		var step: int=mini(100,int(mining.duration_ms)-elapsed)
		sample.delta_ms=step
		check(target.advance(sample),target.error)
		if failures:return
		elapsed+=step
	var boundary: Dictionary=target.snapshot()
	check(boundary.station_pixels==Vector2i(640,360) and boundary.found_index==0 and boundary.aimed_index==0 and boundary.locked_index==-1 and boundary.elapsed_ms==mining.duration_ms,"Var Hastra station missed the strict source acquisition boundary")
	check(target.advance(observation(state,station,camera,1)) and target.snapshot().locked_index==0,"Var Hastra station did not lock after the source duration")
	var overlay: Control=scene.station_target_overlay
	check(overlay.present(target.snapshot(),camera,true),overlay.error)
	var marker: Dictionary=overlay.snapshot()
	check(marker.visible and marker.label_visible and marker.name.contains(station.name) and marker.tech=="%s: %d"%[host.library.strings[132],cat.tables.stations[station.station_id].fields[2]] and marker.distance_meters>0,"Station marker lost its original ring or localized identity")
	var scan_state: Dictionary=state.duplicate(true);scan_state.station_targeting=boundary
	var scan: Dictionary=scene._scan_sample(scan_state)
	check(not scan.has("error") and scan.sample.visible and scan.sample.animation_frame>=0,"Station aim did not use the shared source scanner filmstrip")
	# Mission objectives can advance within a retained departure. The scene
	# must keep reading the departure-bound target when the public cursor moves.
	scan_state.campaign_cursor=int(state.campaign_cursor)+1
	scan=scene._scan_sample(scan_state)
	check(not scan.has("error") and scan.sample.visible,"An in-flight objective cursor invalidated the departure station lock")
	scan_state.campaign_cursor=state.campaign_cursor
	scan_state.station_targeting=target.snapshot();scan=scene._scan_sample(scan_state)
	check(not scan.has("error") and not scan.sample.visible,"Completed ordinary station lock retained acquisition animation")
	var locked: Dictionary=target.snapshot()
	var disabled:=observation(state,station,camera,100);disabled.controller_enabled=false;disabled.station.active=false
	check(target.advance(disabled) and target.snapshot()==locked,"Disabled ordinary controller changed its retained target")
	for gate in ["other_selected_target","held_primary","mining_approach_active","alternate_operation_active","selected_target_active"]:
		var blocked:=observation(state,station,camera,100);blocked[gate]=true
		check(target.advance(blocked) and target.snapshot().found_index==0 and target.snapshot().aimed_index==-1 and target.snapshot().locked_index==-1 and target.snapshot().elapsed_ms==0,"Station lock survived asteroid/combat/operation preemption: "+gate)
		var selection: Dictionary=state.duplicate(true);selection.station_targeting=target.snapshot()
		check(scene._scan_sample(selection).sample==selection.mining_targeting,"Preempted station suppressed the asteroid scanner sample")
		check(target.advance(observation(state,station,camera,100)) and target.snapshot().elapsed_ms==100,"Station did not reacquire after preemption: "+gate)
	var moved:=observation(state,station,camera,100);moved.aim_point=Vector3(840,360,0)
	check(target.advance(moved) and target.snapshot().found_index==0 and target.snapshot().aimed_index==-1 and target.snapshot().elapsed_ms==0,"Station kept an aim lock after moving onto scenery")
	check(target.advance(observation(state,station,camera,100)) and target.snapshot().elapsed_ms==100,"Station did not reacquire after aim left its window")
	var foreign:=observation(state,station,camera,100);foreign.binding_id="0".repeat(64)
	var retained: Dictionary=target.snapshot()
	check(not target.advance(foreign) and target.snapshot()==retained,"Foreign station observation changed the earned flight target")
	var fork: RefCounted=target.fork_for_frame()
	check(fork.advance(observation(state,station,camera,100)) and fork.snapshot().elapsed_ms==200 and target.snapshot()==retained,"Station target fork changed its parent")

func observation(state: Dictionary,station: Dictionary,camera: Transform3D,delta: int) -> Dictionary:
	return {"base_content_id":state.base_content_id,"binding_id":state.binding_id,"campaign_cursor":int(state.campaign_cursor),
		"delta_ms":delta,"viewport_size":Vector2i(1280,720),"camera_pose":camera,"aim_point":Vector3(640,360,0),
		"station":{"environment_slot":0,"pose":station.pose,"active":true},
		"controller_enabled":true,"held_primary":false,"other_selected_target":false,
		"mining_approach_active":false,"alternate_operation_active":false,"selected_target_active":false}
