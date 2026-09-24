extends SceneTree
const Definitions=preload("res://src/content/physical_scenery_contact_definitions.gd")
const Contacts=preload("res://src/simulation/physical_scenery_contacts.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==1,"Expected private source-proof fixture")
	if args.size()==1:
		var profiles: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
		check(profiles is Array and profiles.size()==2,"Expected both Mac source layouts")
		if profiles is Array and profiles.size()==2:
			for profile in profiles:verify_profile(profile)
	print("Physical scenery contacts: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_profile(profile: Dictionary) -> void:
	var policy: Dictionary=profile.policy
	check(Definitions.validate(policy,int(profile.source_bytes),profile.architecture,profile.arrival,profile.scenery,profile.station,profile.opening)=="","Source physical-contact declarations were refused")
	for key in Definitions.VALUES:
		var changed:=policy.duplicate(true);changed[key]=null
		check(not Definitions.parameters(changed),"Changed source contact parameter accepted: "+key)
	for key in Definitions.APP_SPANS:
		var displaced:=policy.duplicate(true);displaced.provenance[key].offset+=1
		check(Definitions.validate(displaced,int(profile.source_bytes),profile.architecture,profile.arrival,profile.scenery,profile.station,profile.opening)!="","Detached source contact extent accepted: "+key)
	var displaced_opening: Dictionary=profile.opening.duplicate(true)
	displaced_opening.player_motion.provenance.release.offset+=1
	check(Definitions.validate(policy,int(profile.source_bytes),profile.architecture,profile.arrival,profile.scenery,profile.station,displaced_opening)!="","Physical contact accepted a detached opening release")
	var changed_order: Dictionary=profile.opening.duplicate(true)
	changed_order.player_motion.motion_before_controller=false
	check(Definitions.validate(policy,int(profile.source_bytes),profile.architecture,profile.arrival,profile.scenery,profile.station,changed_order)!="","Physical contact accepted controller-before-motion timing")
	check(policy.opening_collision_initial_enabled==false and policy.opening_collision_enabled_phase==4 and policy.opening_collision_escape_phase==5 and policy.opening_collision_earned_escape_enabled==false and policy.opening_collision_sample=="incoming_player_phase_before_controller","Opening collision gate declarations differ")
	var identity:={"base_content_id":profile.base_content_id,"binding_id":profile.binding_id}
	var player:=identity.merged({"center":Vector3.ZERO,"eligible":true})
	var station:=identity.merged({"pose":Transform3D.IDENTITY,"bounds_half_extent":100,"collision":{"boxes":[{"center":Vector3.ZERO,"half_extents":Vector3.ONE*10.0}]}})
	var empty:=identity.merged({"objects":[]})
	var body_a:=body(0,Vector3(11,0,0),4)
	var body_b:=body(1,Vector3(13,0,0),4)
	var bodies:=identity.merged({"objects":[body_a,body_b]})
	var operation:=configured(policy,identity,station,bodies)
	var station_only:=configured(policy,identity,station,empty)
	if operation==null or station_only==null:return
	var before_station:=station.duplicate(true);var before_bodies:=bodies.duplicate(true)
	var result: Dictionary=operation.plan(player,bodies,true)
	check(not result.is_empty(),operation.error)
	if result.is_empty():return
	check(result.center_before==Vector3.ZERO and result.center_after==Vector3(10,0,0),"Station tie did not project to the first nearest face")
	check(result.operations.size()==3,"Station and overlapping asteroids did not produce all contacts")
	if result.operations.size()==3:
		check(result.operations[0].kind=="station" and result.operations[0].station_slot==0 and result.operations[0].authored_volume_index==0 and result.operations[0].damage==0,"Station list slot, authored volume and damage differ")
		check(result.operations[1].kind=="asteroid" and result.operations[1].object_index==0 and result.operations[2].object_index==1,"Asteroid contact order differs")
		check(result.operations[1].impact_vector==Vector3.RIGHT and result.operations[1].body_damage==9999 and result.operations[1].player_damage==20,"Asteroid inward impact and source damage differ")
	check(station==before_station and bodies==before_bodies,"Pure contact planner changed observed owners")
	var exact:=player.duplicate();exact.center=Vector3(10,0,0)
	check(station_only.plan(exact,empty,true).operations.is_empty(),"Exact station box face counted as contact")
	var outside:=player.duplicate();outside.center=Vector3(10.001,0,0)
	check(station_only.plan(outside,empty,true).operations.is_empty(),"Point outside station box counted as contact")
	var near:=player.duplicate();near.center=Vector3(9.999,0,0)
	check(station_only.plan(near,empty,true).center_after==Vector3(10,0,0),"Interior station point was not projected to its face")
	var other_face:=player.duplicate();other_face.center=Vector3(0,9,0)
	check(station_only.plan(other_face,empty,true).center_after==Vector3(0,10,0),"Nearest station face was not selected")
	var broad:=player.duplicate();broad.center=Vector3(100,0,0)
	check(station_only.plan(broad,empty,true).operations.is_empty(),"Exact broad-phase station face counted as contact")
	var two_shapes:=station.duplicate(true)
	two_shapes.collision.boxes.push_front({"center":Vector3(50,0,0),"half_extents":Vector3.ONE*2.0})
	var indexed_station:=configured(policy,identity,two_shapes,empty)
	if indexed_station==null:return
	var indexed_result: Dictionary=indexed_station.plan(player,empty,true)
	check(indexed_result.operations.size()==1 and indexed_result.operations[0].station_slot==0 and indexed_result.operations[0].authored_volume_index==1,"Station list slot was confused with authored volume index")
	var sphere:=identity.merged({"pose":Transform3D.IDENTITY,"bounds_half_extent":100,"collision":{"shapes":[{"kind":0,"center":Vector3.ZERO,"radius":10.0}]}})
	var sphere_only:=configured(policy,identity,sphere,empty)
	if sphere_only==null:return
	var inside_sphere:=player.duplicate();inside_sphere.center=Vector3(3,4,0)
	check(sphere_only.plan(inside_sphere,empty,true).center_after==Vector3(6,8,0),"Station sphere did not project radially")
	check(sphere_only.plan(player,empty,true).center_after==Vector3(0,10,0),"Concentric station sphere produced a nonfinite projection")
	check(sphere_only.plan(exact,empty,true).operations.is_empty(),"Exact station sphere face counted as contact")
	var only_a:=identity.merged({"objects":[body_a]})
	var asteroid_only:=configured(policy,identity,{},only_a)
	if asteroid_only==null:return
	var asteroid_face:=player.duplicate();asteroid_face.center=Vector3(7,0,0)
	check(asteroid_only.plan(asteroid_face,only_a,true).operations.is_empty(),"Exact asteroid box face counted as contact")
	var asteroid_inside:=player.duplicate();asteroid_inside.center=Vector3(7.001,0,0)
	check(asteroid_only.plan(asteroid_inside,only_a,true).operations.size()==1,"Interior asteroid point missed contact")
	check(operation.plan(player,bodies,false).operations.is_empty(),"Disabled player collision still responded")
	var inactive_player:=player.duplicate();inactive_player.eligible=false
	check(operation.plan(inactive_player,bodies,true).operations.is_empty(),"Inactive player statistics still responded")
	check(operation.plan(player,bodies,true,0).operations.size()==2,"Selected mining target was not excluded")
	var dead:=body_a.duplicate(true);dead.vitals.hull=0
	check(asteroid_only.plan(asteroid_inside,identity.merged({"objects":[dead]}),true).operations.is_empty(),"Zero-hull asteroid still collided")
	var disabled:=body_a.duplicate(true);disabled.collision_enabled=false
	check(asteroid_only.plan(asteroid_inside,identity.merged({"objects":[disabled]}),true).operations.is_empty(),"Collision-disabled asteroid still collided")
	var retired:=body_a.duplicate(true);retired.active=false;retired.mined=true
	check(asteroid_only.plan(asteroid_inside,identity.merged({"objects":[retired]}),true).operations.is_empty(),"Mined retired asteroid still collided")
	var foreign:=bodies.duplicate(true);foreign.binding_id="f".repeat(64)
	check(operation.plan(player,foreign,true).is_empty() and not operation.error.is_empty(),"Cross-binding scenery was accepted")
	var invalid:=station.duplicate(true);invalid.collision.boxes[0].half_extents.x=0
	check(not Contacts.new().configure(policy,identity,invalid,empty),"Malformed authored station shape was accepted")
	check(operation.plan(player,bodies,true,2).is_empty(),"Unavailable mining index was accepted")
	var fork: RefCounted=operation.fork_for_frame()
	check(fork.plan(player,bodies,true)==result and operation.plan(player,bodies,true)==result,"Configured planner fork changed the contact operation")
	var changed_policy:=policy.duplicate(true);changed_policy.player_damage=99
	check(not Contacts.new().configure(changed_policy,identity,station,bodies),"Changed source policy was accepted at configuration")
	var changed_geometry:=bodies.duplicate(true);changed_geometry.objects[0].half_extent=0
	check(operation.plan(player,changed_geometry,true)==result,"Static body geometry was resampled during the flight")
	station.collision.boxes[0].half_extents=Vector3.ONE
	check(operation.plan(player,bodies,true)==result,"Configured station shape still aliases an external snapshot")
	var invalid_center:=player.duplicate();invalid_center.center=Vector3(INF,0,0)
	check(operation.plan(invalid_center,bodies,true).is_empty(),"Nonfinite live player center was accepted")

func configured(policy: Dictionary, identity: Dictionary, station: Dictionary, bodies: Dictionary) -> RefCounted:
	var contacts:=Contacts.new()
	check(contacts.configure(policy,identity,station,bodies),contacts.error)
	return contacts if contacts.error.is_empty() else null

func body(index: int, center: Vector3, half_extent: int) -> Dictionary:
	return {"index":index,"position":center,"half_extent":half_extent,"active":true,"collision_enabled":true,"vitals":{"hull":100}}

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:failures+=1;printerr(message)
