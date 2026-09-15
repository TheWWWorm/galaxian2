extends "res://tests/mido_ambient_combat.gd"
## Isolated lifecycle checks from the earned prerequisite and generated population.
## Damage/pose and random inputs are explicit fixtures, not a live departure.
const FResources=preload("res://src/content/freighter_destruction_resources.gd")
const FreighterLife=preload("res://src/simulation/freighter_destruction.gd")
const DeathCounters=preload("res://src/simulation/npc_death_accounting.gd")
const AEM=preload("res://src/content/aem.gd")
const SourceAnimation=preload("res://src/presentation/scenery_animation.gd")
const CollisionVolumes=preload("res://src/content/station_collision_volumes.gd")
var death_resources: RefCounted
var cargo_cases:={}
var life_cases:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	if death_resources!=null:check(cargo_cases.has(true) and cargo_cases.has(false),"Generated vectors did not exercise both laden and empty freighters")
	print("Freighter destruction: %d checks; %d failures; %d generated cases"%[checks,failures,life_cases])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	super.verify_population(bindings,catalogues,equipment,construction)
	if failures:return
	if bindings.freighter_destruction.is_empty():
		check(not FreighterLife.new().configure(bindings,null,construction,0),"Earlier pack invented freighter destruction");return
	if death_resources==null:
		var library:=Library.new()
		if not library.open(OS.get_cmdline_user_args()[0]):check(false,library.error);return
		death_resources=FResources.new()
		if not death_resources.configure(library,bindings):check(false,death_resources.error);return
		verify_resources(library,bindings)
	for row in construction.snapshot().actors:
		if row.population_group!="freighter":
			check(not FreighterLife.new().configure(bindings,death_resources,construction,row.actor_id),"A fighter acquired freighter destruction");continue
		for nonplayer in [false,true]:verify_life(bindings,catalogues,equipment,construction,row.actor_id,nonplayer)

func verify_resources(library: RefCounted,bindings: RefCounted) -> void:
	var pack: Dictionary=death_resources.snapshot()
	check(pack.model.model_id==18300 and pack.model.start_ms==50 and pack.model.end_ms==10000,"Original freighter animation mapping/range changed")
	check(pack.cargo_model.model_id==16990 and pack.wreck_shapes.size()==19 and pack.wreck_source_offset==508 and pack.wreck_source_bytes==496,"Original cargo or wreck record changed")
	check(pack.initial_material.id==34700 and pack.wreck_material.id==33352,"Wreck lost its original material change")
	var shape: Dictionary=pack.wreck_shapes[0]
	check(shape.kind==1 and shape.center==Vector3(-513,63,-1248) and shape.half_extents==Vector3(1104.4000244140625,721.6000366210938,3542),"Wreck box lost its source coordinate mapping/scale")
	var sphere: Dictionary=pack.wreck_shapes[5]
	check(sphere.kind==0 and sphere.center==Vector3(1998,-126,3807) and sphere.radius==786.0000610351562,"Wreck sphere lost its independent source mapping/scale")
	var decoder:=AEM.new();var mesh:=decoder.decode(library.read_resource(pack.model.resource,AEM.MAX_BYTES))
	var animation:=SourceAnimation.new()
	if not animation.configure(mesh.get("surfaces",[])):check(false,animation.error);return
	check(mesh.surfaces.size()==15,"Freighter animated surface population changed")
	var initial:=animation.sample(50,Transform3D.IDENTITY)
	var final:=animation.sample(10000,Transform3D.IDENTITY)
	check(not initial.is_empty() and not final.is_empty() and initial!=final,"Freighter breakup did not animate its original surfaces")
	for surface in final.surfaces:check(surface.pose.is_finite(),"Freighter final animated pose is not finite")
	var bytes: PackedByteArray=library.read_resource(bindings.freighter_destruction.wreck_resource,CollisionVolumes.MAX_BYTES)
	var volumes:=CollisionVolumes.new()
	for scale in [0.0,-1.0,NAN,INF,2.01]:check(volumes.decode(bytes,1,6,0.6,scale).is_empty(),"Invalid wreck box scale was accepted")
	check(volumes.decode(bytes.slice(0,bytes.size()-1),1,6,0.6,1.1).is_empty(),"Truncated trailing collision record was ignored")

func verify_life(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,id: int,nonplayer: bool) -> void:
	var equipment_before: Dictionary=equipment.snapshot();var built: Dictionary=construction.snapshot()
	var row: Dictionary=built.actors[id];cargo_cases[not row.cargo.is_empty()]=true
	var death:=FreighterLife.new()
	if not death.configure(bindings,death_resources,construction,id):check(false,death.error);return
	life_cases+=1
	var group:=fresh(bindings,catalogues,equipment,construction)
	if group==null:return
	var pose:=Transform3D(Basis(Vector3.UP,0.7),Vector3(12345,-6789,45678))
	check(group.set_pose(id,pose,pose),group.error)
	var before:=death.snapshot()
	check(before.phase=="ready" and before.fragments.is_empty() and not before.cargo.model_exists and before.cargo.entries==row.cargo,"Preparing death changed retained cargo or consumed fragments")
	var random_input:={"state":98765}
	check(death.advance(16,random_input,group.snapshot().actors[id]).is_empty() and death.snapshot()==before,"Live freighter began destruction")
	damage(group,id,320,nonplayer);group.refresh_hostility(id)
	var lethal: Dictionary=group.snapshot().actors[id]
	for invalid in [-1,true,0.1,int(bindings.frame_clock.max_frame_milliseconds)+1]:
		check(death.advance(invalid,random_input,lethal).is_empty() and death.snapshot()==before,"Invalid death duration mutated the retained state")
	check(death.advance(16,{"state":-1},lethal).is_empty() and death.snapshot()==before,"Invalid death stream mutated cargo or model state")
	var wrong:=lethal.duplicate(true);wrong.binding_id="bad"
	check(death.advance(16,random_input,wrong).is_empty() and death.snapshot()==before,"Foreign lethal state started freighter destruction")
	wrong=lethal.duplicate(true);wrong.vitals=null
	check(death.advance(16,random_input,wrong).is_empty() and death.snapshot()==before,"Malformed vitals partly started freighter destruction")
	var counters:=DeathCounters.new()
	if not counters.configure_ambient(bindings,construction):check(false,counters.error);return
	var credit:=counters.record(lethal)
	check(not credit.is_empty(),counters.error)
	if credit.is_empty():return
	check(credit.counter_deltas.pirate_kills==0 and credit.counter_deltas.player_kills==(0 if nonplayer else 1) and credit.counter_deltas.nonhostile_remaining==(-1 if nonplayer else 0),"Freighter death invented pirate credit or changed source hostility counters")
	var totals:=counters.snapshot()
	check(counters.record(lethal).is_empty() and counters.snapshot()==totals,"Repeated freighter death repeated counters")
	var step:=death.advance(0,random_input,lethal)
	if step.is_empty():check(false,death.error);return
	var state:=death.snapshot();var random_after: Dictionary=step.random_state
	check(step.started and not step.breakup and state.mode==3 and state.animation.time_ms==50 and state.pose==pose and state.statistics_pose==pose and not state.world_movement_enabled,"Lethal entry changed the native pose/animation phase")
	check(state.cargo.model_exists==state.cargo.eligible and state.cargo.entries==row.cargo and (not state.cargo.eligible or state.cargo.pose==Transform3D(Basis.IDENTITY,pose.origin)),"Freighter salvage lost its identity basis or cargo at death entry")
	check(not state.interaction_blocked and state.effect.active and step.audio_events.size()==2 and step.audio_events[0].source_id==20,"Freighter initial explosion/audio was omitted")
	check(state.fragments.size()==7 and random_after.state==261116350266043,"Death did not consume the independent debris/sound RNG vector")
	check(group.apply_freighter_destruction(id,death),group.error)
	observe_lifecycle(death,"entry")
	before=death.snapshot()
	check(death.advance(1,random_after,lethal).is_empty() and death.snapshot()==before,"Death was started twice")
	var original:=death;death=death.fork_for_frame()
	var remaining:=9950
	var middle:=false
	while remaining>0:
		var duration:=mini(remaining,int(bindings.frame_clock.max_frame_milliseconds));remaining-=duration
		step=death.advance(duration,random_after)
		if step.is_empty():check(false,death.error);return
		random_after=step.random_state
		if not middle and death.snapshot().animation.time_ms>=5000:
			middle=true;observe_lifecycle(death,"middle")
	check(original.snapshot()==before,"Prospective death frames mutated committed state")
	state=death.snapshot()
	check(state.mode==3 and state.animation.time_ms==10000 and state.animation.playing and not state.effect.active,"Exact animation end incorrectly entered the wreck phase")
	check(state.cleanup_elapsed_ms==0 and state.cargo.pose==before.cargo.pose,"Animation consumed the later cleanup timer or moved cargo")
	observe_lifecycle(death,"animation-end")
	step=death.advance(1,random_after)
	if step.is_empty():check(false,death.error);return
	random_after=step.random_state;state=death.snapshot()
	check(step.breakup and state.mode==4 and state.effect.active and state.effect.elapsed_ms==0 and state.effect_scale==6 and state.wreck_elapsed_ms==0 and state.cleanup_elapsed_ms==0,"Animation completion did not reset the final explosion and wreck clocks")
	check(state.fragments==before.fragments and step.audio_events.size()==1 and random_after.state==155553827734442,"Final explosion regenerated debris or changed independent RNG order")
	check(group.apply_freighter_destruction(id,death),group.error)
	observe_lifecycle(death,"final-flash")
	check(state.wreck_shape_origin==Vector3.ZERO and state.material_id==34700,"Wreck moved its volumes/material before the source delay")
	advance_for(death,140,random_after,bindings)
	check(death.snapshot().material_id==34700 and death.snapshot().wreck_shape_origin==Vector3.ZERO,"Wreck delay lost its strict boundary")
	step=death.advance(1,random_after)
	check(not step.is_empty() and step.random_state==random_after,"Wreck material transition consumed randomness")
	state=death.snapshot()
	check(state.material_id==33352 and state.wreck_shape_origin==pose.origin,"Wreck did not adopt original material and translated world-axis volumes at 141 ms")
	observe_lifecycle(death,"wreck-material")
	var first: Dictionary=state.wreck_shapes[0];var point: Vector3=pose.origin+first.center
	check(death.wreck_point(point)=={"hit":true,"shape_index":0},"Wreck point collision lost source shape order")
	check(death.wreck_point(point+Vector3(1000000,0,0))=={"hit":false},"Wreck collision invented a broad bound")
	check(death.wreck_point(Vector3(NAN,0,0)).is_empty(),"Wreck collision accepted a nonfinite sample")
	advance_for(death,60000-141,random_after,bindings)
	state=death.snapshot()
	check(state.cleanup_elapsed_ms==60000 and state.active and not state.effect.active and state.interaction_blocked==(not state.cargo.eligible),"Freighter was deactivated before 60001 ms")
	check(state.cargo.pose==before.cargo.pose and state.cargo.entries==row.cargo,"Freighter cargo drifted or disappeared without pickup")
	step=death.advance(1,random_after);state=death.snapshot()
	check(step.cleaned_now and not state.active and state.interaction_blocked and state.phase=="wreck" and state.material_id==33352,"Freighter cleanup deleted its retained wreck or missed deactivation")
	check(group.apply_freighter_destruction(id,death) and not group.snapshot().actors[id].active,group.error)
	observe_lifecycle(death,"cleanup")
	var held: Dictionary=group.snapshot()
	check(not group.apply_freighter_destruction(id,original) and group.snapshot()==held,"Freighter lifecycle regressed after cleanup")
	step=death.advance(1,random_after)
	check(not step.cleaned_now and step.random_state==random_after and step.audio_events.is_empty(),"Cleanup repeated effects or consumed randomness")
	check(equipment.snapshot()==equipment_before and construction.snapshot()==built,"Freighter destruction changed player equipment or construction")

func advance_for(death: RefCounted,milliseconds: int,random_state: Dictionary,bindings: RefCounted) -> void:
	while milliseconds>0:
		var duration:=mini(milliseconds,int(bindings.frame_clock.max_frame_milliseconds));milliseconds-=duration
		var result: Dictionary=death.advance(duration,random_state)
		if result.is_empty():check(false,death.error);return
		if result.random_state!=random_state:check(false,"Wreck timer consumed unexpected randomness");return

func observe_lifecycle(_death: RefCounted,_label: String) -> void:
	pass
