extends SceneTree
## Source-selected Dima28 component. This does not create campaign progress or
## authorize navigation to Thynome from an earned career.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const Dima=preload("res://src/content/dima_encounter_definitions.gd")
const Sahi=preload("res://src/content/sahi_encounter_definitions.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Route=preload("res://src/simulation/npc_route.gd")
const World=preload("res://src/simulation/opening_world_initialization.gd")
const Story=preload("res://src/content/story_encounter_definitions.gd")
const CombatActor=preload("res://src/simulation/opening_combat_actor.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected explicit content, bindings and visuals");quit(1);return
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):
		check(false,library.error+bindings.error+cat.error);quit(1);return
	var anchor:=Vector3(112345,-45678,12345)
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":28,"system_id":18,"station_id":91,"mission_kind":4,
		"mission_story":true,"mission_completed":false,"mission_failed":false,
		"rank":8,"difficulty":0.5,"portal_position":anchor}
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":91,"system_id":18,"ship_id":0,"equipment_ids":[2,86,81,68]}
	if not Thynome.available(bindings):
		check(not Dima.selected(bindings.mido_travel,context) and Dima.population(bindings.mido_travel,context).is_empty(),"Earlier binding enabled Dima without its original declarations")
		check(not Construction.new().configure_sahi(bindings,cat,seed,context),"Earlier binding constructed Dima without its original declarations")
		print("Dima population (earlier binding): %d checks; %d failures"%[checks,failures])
		quit(1 if failures else 0);return
	verify(bindings,cat,context,seed)
	print("Dima population: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(bindings: RefCounted,cat: RefCounted,context: Dictionary,seed: Dictionary) -> void:
	check(Dima.selected(bindings.mido_travel,context) and Story.selected(bindings,context),"Dima declarations did not select the native story cast")
	for key in ["campaign_cursor","system_id","station_id","mission_kind","mission_story","mission_completed","mission_failed"]:
		var wrong:=context.duplicate(true)
		wrong[key]={"campaign_cursor":27,"system_id":9,"station_id":48,"mission_kind":11,
			"mission_story":false,"mission_completed":true,"mission_failed":true}[key]
		check(not Dima.selected(bindings.mido_travel,wrong) and Dima.population(bindings.mido_travel,wrong).is_empty(),"Dima accepted wrong "+key)
	for missing in [null,Vector3(INF,0,0)]:
		var wrong:=context.duplicate(true);wrong.portal_position=missing
		check(Dima.selected(bindings.mido_travel,wrong) and Dima.population(bindings.mido_travel,wrong).is_empty(),"Dima selected declaration or constructed with an invalid portal anchor")
		check(not Construction.new().configure_sahi(bindings,cat,seed,wrong) and not Route.new().configure_sahi_generated(bindings,0,wrong),"Dima factory or route accepted an invalid portal anchor")
	var no_anchor:=context.duplicate(true);no_anchor.erase("portal_position")
	check(Dima.selected(bindings.mido_travel,no_anchor) and not Story.flight(bindings,no_anchor).is_empty(),"Dima flight could not select before environment placement")
	check(Dima.population(bindings.mido_travel,no_anchor).is_empty() and not Construction.new().configure_sahi(bindings,cat,seed,no_anchor),"Dima constructed its cast before environment placement")
	check(not Story.combat_population(bindings,{"campaign_cursor":28,"context":no_anchor,"actors":[]}),"Dima accepted live combat before environment placement")
	var altered: Dictionary=bindings.mido_travel.duplicate(true)
	altered.thynome_expedition.world28.cast.groups[1].hull_scaling.divisor=3
	check(not Dima.selected(altered,context),"Dima accepted an unguarded source hull divisor")
	var source: Dictionary=bindings.mido_travel.thynome_expedition.world28.cast
	var data: Dictionary=Dima.population(bindings.mido_travel,context)
	if data.is_empty():check(false,"Dima population rejected guarded declarations");return
	check(data.actor_count==8 and data.construction_order==range(8) and data.waypoints==[[context.portal_position.x,context.portal_position.y,context.portal_position.z]],"Dima population lost its ordered cast or relocated portal anchor")
	check(data.actor_route_ids.is_empty() and data.freighter_hull_divisor==4 and not data.freighter_cruise_enabled and data.freighter_cargo_cleared,"Dima population applied a Sahi patrol or wrong freighter rules")
	check(data.dima.hull_scaling==source.groups[1].hull_scaling and data.dima.player_target_id==-1 and data.dima.target_memberships==source.target_memberships,"Dima cast lost its source hull or target rules")
	for id in 8:
		var row: Dictionary=data.actors[id]
		check(row.actor_id==id and row.actor_kind==(9 if id<5 else 0) and row.subtype==(0 if id<5 else 1) and row.hull_catalogue_id==(8 if id<5 else 15),"Dima population reordered a factory actor")
	for id in 9:
		var route:=Route.new()
		check(route.configure_sahi_generated(bindings,id,context)==(id<8),"Dima route admission changed for actor "+str(id))
	var wrong_seed:=seed.duplicate(true);wrong_seed.binding_id="foreign"
	check(not Construction.new().configure_sahi(bindings,cat,wrong_seed,context),"Dima construction accepted a foreign binding identity")
	wrong_seed=seed.duplicate(true);wrong_seed.station_id=48
	check(not Construction.new().configure_sahi(bindings,cat,wrong_seed,context),"Dima construction accepted equipment at another station")
	var owner:=Construction.new()
	if not owner.configure_sahi(bindings,cat,seed,context):check(false,owner.error);return
	var before:=owner.snapshot()
	check(owner.generate({"state":-1}).is_empty() and owner.snapshot()==before,"Invalid Dima RNG partly committed the cast")
	var state:=owner.generate({"state":42})
	if state.is_empty():check(false,owner.error);return
	check(state.campaign_cursor==28 and state.station_id==91 and state.sahi_context==context and state.actors.size()==8,"Dima factory lost its selected identity or cast")
	for id in 8:
		var actor: Dictionary=state.actors[id]
		check(actor.actor_id==id and actor.actor_kind==(9 if id<5 else 0) and actor.subtype==(0 if id<5 else 1) and actor.hull_catalogue_id==(8 if id<5 else 15),"Dima factory changed source cast order")
		check(actor.body_pose.origin==actor.factory_position and actor.statistics_pose==actor.body_pose and actor.body_pose.basis==Basis.IDENTITY,"Dima factory changed the source body pose")
		var offset: Vector3=actor.factory_position-context.portal_position
		check(offset.x>=-20000 and offset.x<20000 and offset.y>=-20000 and offset.y<20000 and offset.z>=-20000 and offset.z<20000,"Dima factory jitter left source bounds")
		if id<5:
			var route:=owner.route(id)
			check(route!=null and route.snapshot()==actor.route and not actor.route.has("completed") and actor.route.waypoints.size()>=2 and actor.route.waypoints.size()<=4,"Dima fighter lost its generated factory route")
			check(actor.cargo is Array and actor.discarded_cargo.is_empty() and not actor.fragments.is_empty(),"Dima fighter lost retained factory cargo or fragments")
		else:
			check(owner.route(id)==null and actor.route.is_empty() and actor.fragments.is_empty(),"Dima freighter acquired a small-ship route or debris")
			check(actor.assembly==data.freighter_assembly and actor.model_assembly_required and not actor.cruise_enabled,"Dima freighter lost generic assembly or cruise rule")
			check(actor.hull_divisors==[4] and actor.cargo.is_empty(),"Dima freighter lost hull divisor or retained generated cargo")
	check(owner.generate({"state":42}).is_empty() and owner.snapshot()==state,"Committed Dima factory generated twice")
	var world:=World.new()
	if not world.configure_sahi(bindings,cat,seed,context,Story.entry_conditions(28)):check(false,world.error);return
	var initialized:=world.generate({"state":42})
	if initialized.is_empty():check(false,world.error);return
	check(initialized.npc_construction==state and initialized.weapon_effects.size()==8,"Dima world lost its generated cast or Void weapon effects")
	var again:=Construction.new()
	if not again.configure_sahi(bindings,cat,seed,context):check(false,again.error);return
	check(again.generate({"state":42})==state,"Dima factory RNG is not repeatable")
	var shifted:=context.duplicate(true);shifted.portal_position+=Vector3(3000,-2000,1000)
	var moved:=Construction.new()
	if not moved.configure_sahi(bindings,cat,seed,shifted):check(false,moved.error);return
	var moved_state:=moved.generate({"state":42})
	if moved_state.is_empty():check(false,moved.error);return
	check(moved_state.random_state==state.random_state,"Changing an accepted portal point consumed a cast RNG draw")
	for id in 8:
		check(moved_state.actors[id].factory_position-state.actors[id].factory_position==shifted.portal_position-context.portal_position,"Dima factory did not translate exactly with the supplied portal")
	var composed:=Story.compose(bindings,cat,state)
	if composed.is_empty():check(false,"Dima construction failed shared story combat composition");return
	var counterfeit:=state.duplicate(true);counterfeit.actors[5].actor_kind=2
	check(Story.compose(bindings,cat,counterfeit).is_empty(),"Dima story accepted a Sahi Nivelian freighter")
	var expected_memberships: Array=source.target_memberships.map(func(ids):return ids.map(func(id):return int(id)))
	check(composed.actor_count==8 and composed.player_weapon_targets==range(8) and composed.target_memberships==expected_memberships,"Dima combat lost its exact source targets")
	check(composed.target_memberships.all(func(ids):return ids.all(func(id):return id is int)),"Dima combat kept imported floating-point target IDs")
	check(not composed.initial_hostile and not composed.initial_actor_targeting_blocked and not composed.initial_statistics_targeting_blocked,"Dima combat forced hostility or target gates at spawn")
	check(composed.freighter_death.actor_kind==0 and composed.freighter_death.model_id==18302 and composed.freighter_death.cargo_model_id==16992,"Dima freighter inherited the Nivelian death path")
	for id in 8:
		var weapon: Dictionary=composed.npc_weapons[id]
		if id<5:check(weapon.item_id==5 and weapon.actor_kind==9 and not weapon.get("unarmed",false),"Dima Void fighter lost its original weapon")
		else:check(weapon=={"unarmed":true,"actor_id":id,"actor_kind":0,"hull_catalogue_id":15},"Dima freighter acquired a fighter weapon")
	var live_actors:=[]
	for id in 8:
		var body:=CombatActor.new()
		if not body._configure_story(bindings,composed,state.actors[id]):check(false,body.error);continue
		var vital: Dictionary=body.snapshot()
		live_actors.append(vital)
		var divisor:=4 if id>=5 else 1
		@warning_ignore("integer_division")
		check(vital.vitals.hull==vital.factory_hull/divisor and vital.max_hull==vital.vitals.hull and not vital.hostile and not vital.forced_hostile,"Dima story hull pools or initial opposition changed")
	check(live_actors.size()==8 and Story.combat_population(bindings,{"campaign_cursor":28,"context":context,"actors":live_actors}),"Dima native combat actors were not admitted as the source cast")
	for cursor in [24,25,26]:
		var old:=context.duplicate(true);old.campaign_cursor=cursor
		check(not Dima.selected(bindings.mido_travel,old) and Dima.population(bindings.mido_travel,old).is_empty(),"Dima replaced an existing Sahi/Void population")
	check(Sahi.selected(bindings.mido_travel,{"campaign_cursor":24,"system_id":9,"station_id":48,"mission_kind":4,"mission_story":true,"mission_completed":false,"mission_failed":false}),"Dima changed Sahi24 selection")
	check(Post.available(bindings),"Dima changed the existing Void/return capability")
