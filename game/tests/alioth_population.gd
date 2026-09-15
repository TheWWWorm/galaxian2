extends SceneTree
## Explicit construction fixtures. No earned departure, combat outcome or
## campaign advancement is supplied by these component checks.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const Rules=preload("res://src/content/alioth_attack_definitions.gd")
const Population=preload("res://src/content/alioth_population_definitions.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Attack=preload("res://src/simulation/alioth_attack.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Weapons=preload("res://src/simulation/opening_npc_weapons.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const CONDITIONS={"companions_empty":true,"location_match":false,"special_placement":false}
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Alioth population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":98,"system_id":19,"ship_id":0,"equipment_ids":[22,86,81,55]}
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"station_id":98,"system_id":19,"rank":0,"difficulty":0.5,"mission_kind":4,"mission_story":true,"mission_completed":false}
	if not Rules.available(bindings):
		check(not Construction.new().configure_alioth_attack(bindings,cat,seed,context,Vector3.ZERO),"Legacy content enabled Alioth construction")
		check(not Route.new().configure_alioth_generated(bindings,3),"Legacy content enabled Alioth patrols")
		return
	for field in ["campaign_cursor","station_id","system_id","rank","difficulty","mission_kind","mission_story","mission_completed","binding_id"]:
		var invalid:=context.duplicate();invalid[field]={"campaign_cursor":15,"station_id":79,"system_id":15,"rank":21,"difficulty":0.75,"mission_kind":11,"mission_story":false,"mission_completed":true,"binding_id":"foreign"}[field]
		check(not Construction.new().configure_alioth_attack(bindings,cat,seed,invalid,Vector3.ZERO),"Alioth accepted a mismatched context: "+field)
	var invalid_seed:=seed.duplicate(true);invalid_seed.station_id=79
	check(not Construction.new().configure_alioth_attack(bindings,cat,invalid_seed,context,Vector3.ZERO),"Alioth accepted a different retained location")
	invalid_seed=seed.duplicate(true);invalid_seed.equipment_ids=[-1]
	check(not Construction.new().configure_alioth_attack(bindings,cat,invalid_seed,context,Vector3.ZERO),"Alioth accepted an invalid installed item")
	check(not Construction.new().configure_alioth_attack(bindings,cat,seed,context,Vector3(NAN,0,0)),"Non-finite player pose entered escort placement")
	for id in [-1,0,1,2,10]:check(not Route.new().configure_alioth_generated(bindings,id),"Non-fighter received a generated patrol")
	var vectors: Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GOF2_ALIOTH_VECTORS")))
	if not vectors is Array or vectors.size()!=5:check(false,"Supply five independent vectors in GOF2_ALIOTH_VECTORS");return
	var retained:=seed.duplicate(true)
	for vector in vectors:
		var owner:=Construction.new()
		if not owner.configure_alioth_attack(bindings,cat,seed,context,point(vector.player_position)):check(false,owner.error);return
		var before: Dictionary=owner.snapshot()
		check(owner.generate({"state":-1}).is_empty() and owner.snapshot()==before,"Invalid RNG partially constructed Alioth")
		var state:=owner.generate({"state":int(vector.input_state)})
		if state.is_empty():check(false,owner.error);return
		check(state.actors.size()==10 and state.random_state.state==int(vector.random_state),"Alioth random stream differs for seed "+str(vector.seed))
		check(state.campaign_cursor==16 and state.alioth_context==context,"Construction lost its content/career context")
		for id in 10:
			var actor: Dictionary=state.actors[id];var expected: Dictionary=vector.actors[id]
			check(actor.actor_id==id and actor.actor_kind==(9 if id in range(3,7) else 0) and actor.hull_catalogue_id==(15 if id<3 else 8 if id<7 else 5),"Alioth changed its authored cast order")
			check(actor.factory_position==point(expected.factory_position) and actor.body_pose.origin==point(expected.position) and actor.body_pose==actor.statistics_pose and actor.body_pose.basis==Basis.IDENTITY,"Alioth changed factory or authored placement")
			check(actor.cargo==expected.cargo.map(item) and actor.discarded_cargo==expected.discarded_cargo.map(item),"Cargo differs from the independent original-factory vector")
			check(actor.fragments.size()==int(expected.fragment_count),"Alioth changed original breakup allocation")
			if id<3:
				check(owner.route(id)==null and actor.route.is_empty() and actor.fragments.is_empty(),"Freighter inherited a fighter patrol or breakup allocation")
				check(actor.model_assembly_required and actor.assembly==bindings.mido_travel.alioth_attack.population.freighter_assembly and actor.friendly and not actor.cruise_enabled,"Alioth freighter gained another faction's assembly or cruise")
				check(actor.hull_divisors==([3,6] if id==0 else [3]),"Alioth freighter lost the sequential source hull reductions")
			else:
				var route: RefCounted=owner.route(id)
				check(route!=null and route.snapshot()==actor.route and actor.route.loop and actor.route.waypoints==expected.route.map(point),"Spawn waypoint incorrectly replaced the generated patrol")
				if id<7:check(actor.hull_multiplier==10,"Void hull multiplier changed")
				else:check(actor.current_hull_override==600 and actor.friendly,"Terran escort lost its authored hull or friendliness")
		check(owner.generate({"state":0}).is_empty() and owner.snapshot()==state,"Committed population generated twice")
		var detached: Dictionary=owner.snapshot();detached.actors[3].cargo.clear()
		check(owner.snapshot()==state,"A snapshot consumer changed retained cargo")
		check(seed==retained,"Construction mutated the supplied inventory")
		var world:=World.new()
		if not world.configure_alioth_attack(bindings,cat,seed,context,point(vector.player_position),CONDITIONS):check(false,world.error);return
		var composed:=world.generate({"state":int(vector.input_state)})
		if composed.is_empty():check(false,world.error);return
		check(composed.npc_construction==state and composed.random_state.state==int(vector.world_random_state),"Weapon allocation changed original population or RNG order")
		for id in 10:
			var effect: Dictionary=composed.weapon_effects[id]
			if id<3:check(effect=={"actor_id":id,"unarmed":true},"Terran freighter allocated an armed effect pool")
			else:
				check(effect.discarded_default.flipped==vector.effects[id][0] and effect.primary.flipped==vector.effects[id][1],"Alioth weapon effects changed independent random draws")
				check(effect.primary.item_id==(5 if id<7 else 0) and effect.primary.resource_id==(14602 if id<7 else 14600),"Alioth weapon effect lost original faction art")
	verify_bodies(bindings,cat,library,seed,context)

func verify_bodies(bindings: RefCounted,cat: RefCounted,library: RefCounted,seed: Dictionary,context: Dictionary) -> void:
	var construction: RefCounted
	for sample in [[0,0.5,84,420,23,140],[0,1.0,126,630,35,210],[8,0.5,196,980,54,326],[8,1.0,294,1470,81,490],[20,0.5,364,1820,101,606],[20,1.0,546,2730,151,910]]:
		var selected:=context.duplicate();selected.rank=sample[0];selected.difficulty=sample[1]
		construction=Construction.new()
		if not construction.configure_alioth_attack(bindings,cat,seed,selected,Vector3(0,0,50000)) or construction.generate({"state":42}).is_empty():check(false,construction.error);return
		var weapons:=Weapons.new()
		if not weapons.configure_alioth_attack(bindings,cat,construction):check(false,weapons.error);return
		var targets:=Population.combat(bindings,construction.snapshot())
		check(targets.target_memberships[3]==[0,1,2,7,8,9,-1] and targets.target_memberships[7]==[-1,3,4,5,6] and targets.player_weapon_targets==[0,1,2,3,4,5,6,7,8,9],"Alioth changed player-last Void targets or ordinary Terran membership")
		var basic_damage: int=3 if sample[0]==0 else (7 if sample[1]==0.5 else 9) if sample[0]==8 else (18 if sample[1]==0.5 else 24)
		for id in 10:
			var actor:=Actor.new()
			if not actor.configure_alioth_attack(bindings,cat,construction,id):check(false,actor.error);return
			var state:=actor.snapshot()
			var expected: int=sample[4] if id==0 else sample[5] if id<3 else sample[2]*10 if id<7 else 600
			check(state.factory_hull==sample[3 if id<3 else 2] and state.max_hull==expected and state.vitals.hull==expected and state.hull_percent==100,"Alioth rank/difficulty or sequential hull setters changed")
			check(state.vitals.armor==0 and state.vitals.shield==0.0 and state.active and state.actor_mode==0 and not state.targeting_blocked,"Alioth inherited hidden training actors or an invented shield pool")
			check(state.friendly==(id<3 or id>=7) and not state.hostile,"Alioth body changed its constructor flags")
			var contact:=actor.collision_context()
			check(contact.eligible and contact.path==("point_geometry" if id<3 else "bounds") and (id>=3 or contact.boxes.size()==3),"Alioth body uses the wrong collision geometry")
			var gun: Dictionary=weapons.snapshot().actors[id]
			if id<3:check(gun.projectiles.is_empty() and gun.definition.unarmed,"Terran freighter acquired an ordinary gun")
			else:
				check(gun.definition.damage==basic_damage*(2 if id<7 else 1) and gun.definition.interval_ms==568 and gun.definition.projectile_capacity==4 and gun.definition.lifetime_ms==3000 and gun.definition.speed_units_per_millisecond==16.0,"Alioth source damage scaling, rate or speed changed")
				check(gun.definition.item_id==(5 if id<7 else 0) and gun.definition.model_resource_id==(6762 if id<7 else 6754) and not gun.audio.is_empty(),"Alioth lost original faction projectile or sound selection")
	var invalid: Dictionary=construction.snapshot();invalid.actors[0].assembly.body_resource_ids[0]=14311
	check(Population.population(bindings,invalid).is_empty(),"Alioth body accepted a capital ship assembly")
	invalid=construction.snapshot();invalid.actors[0].hull_divisors=[18]
	check(Population.population(bindings,invalid).is_empty(),"Alioth body replaced ordered source hull setters")
	verify_damage_sequence(bindings,cat,library,construction)

func verify_damage_sequence(bindings: RefCounted,cat: RefCounted,library: RefCounted,construction: RefCounted) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var resources:=RadioResources.new()
	if not resources.prepare(library,bindings,null,16):check(false,resources.error);return
	var radio:=Radio.new();var attack:=Attack.new()
	if not radio.configure(bindings,library,resources.line_counts,16) or not attack.configure(bindings):check(false,radio.error+attack.error);return
	var actors:=[]
	for id in 10:
		var actor:=Actor.new()
		if not actor.configure_alioth_attack(bindings,cat,construction,id):check(false,actor.error);return
		actors.append(actor)
	var initial: Array=actors.map(func(actor):return actor.snapshot())
	var old_attack: RefCounted=attack.fork_for_frame()
	var random_state: Dictionary=construction.snapshot().random_state
	var retained: Dictionary=construction.snapshot()
	var now:=0;var relocation_count:=0
	while now<180000 and attack.snapshot().phase!=Attack.Stage.RETURN_FLIGHT:
		now+=100
		# Explicit nonplayer hits exercise actual native hulls. This fixture
		# does not stand in for the pending AI/weapons/world integration.
		for id in 3:
			if now==[35000,43000,45000][id]:
				var hit: Dictionary=actors[id].normal_hit(actors[id].snapshot().vitals.hull,true)
				check(hit.get("destroyed_now",false),"Native nonplayer damage did not exhaust its freighter")
		var bodies:=body_context(bindings,actors)
		if not attack.advance(100,radio.snapshot(),bodies,Transform3D(Basis.IDENTITY,Vector3(0,0,50000)),Transform3D(Basis.IDENTITY,Vector3(0,0,210000)),random_state):check(false,attack.error);return
		var frame: Dictionary=attack.snapshot().frame
		random_state=frame.random_state
		for override in frame.actor_overrides:
			if not actors[override.actor_id].set_pose(override.body_pose,override.body_pose):check(false,actors[override.actor_id].error);return
			relocation_count+=1
		for id in 10:
			var before: Dictionary=actors[id].snapshot();var next: RefCounted=actors[id].fork_for_frame()
			if not next.apply_alioth_retirement(attack):check(false,next.error);return
			if actors[id].snapshot()!=before:check(false,"Prospective retirement mutated the retained body");return
			actors[id]=next
		radio.step_alioth_attack(now,body_context(bindings,actors))
		if not radio.error.is_empty():check(false,radio.error);return
	check(now==62100 and attack.snapshot().completion_ready and relocation_count==4,"Actual hulls failed to drive the radio, one-shot escape or completion condition")
	for id in 10:
		var state: Dictionary=actors[id].snapshot()
		if id<3:check(state.vitals.hull==0 and state.nonplayer_kill and not state.alioth_script_retired,"Freighter hit attribution was replaced by scripted escape")
		elif id<7:
			check(state.vitals==initial[id].vitals and not state.nonplayer_kill and state.alioth_script_retired and state.actor_mode==4 and not state.active and not state.model_draw_enabled and not state.node_draw_requested,"Escaped Void ship took fabricated damage or remained visible")
			check(not actors[id].collision_context().eligible and not actors[id].normal_hit(100,true).get("destroyed_now",true),"Retired Void ship remained a damage target")
		else:check(state.vitals==initial[id].vitals and state.active and not state.alioth_script_retired,"Escape damaged or retired a Terran escort")
	var before: Dictionary=actors[3].snapshot()
	check(not actors[3].apply_alioth_retirement(old_attack) and actors[3].snapshot()==before,"Older sequence state revived an escaped ship")
	check(construction.snapshot()==retained,"Combat changed retained factory cargo or poses")

func body_context(bindings: RefCounted,actors: Array) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,
		"actors":actors.map(func(actor):
			var state: Dictionary=actor.snapshot()
			state.current_hull=int(state.vitals.hull)
			return state)}

func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func item(value: Array) -> Dictionary:return {"item_id":int(value[0]),"quantity":int(value[1])}
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
