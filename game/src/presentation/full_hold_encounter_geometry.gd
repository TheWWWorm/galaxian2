extends Node3D
## Original pirate hull/lights, engine, cargo and effects. Each frame is fully
## prepared before drawing; lifetime and gameplay stay in the encounter owner.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Ship=preload("res://src/presentation/ship_geometry.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const DeathEffect=preload("res://src/presentation/npc_death_effect_geometry.gd")
const Projectiles=preload("res://src/presentation/projectile_geometry.gd")
const Impacts=preload("res://src/presentation/ordinary_impact_geometry.gd")
const Pose=preload("res://src/presentation/opening_geometry.gd")
const ENGINE_ID=18002
const ENGINE_PATH="resources/data/assets/main/3d/meshes/ships/ship_002_pirates_engine_add.aem"
var error:=""
var hull: Node3D
var engine: Node3D
var cargo: Node3D
var explosion: Node3D
var projectiles: Node3D
var impacts: Node3D
var _identity:={}
var _hull_resource:=""
var _cargo_resource:=""

func build(owner: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not owner is Encounter or owner.snapshot().is_empty():return fail("Prepare the second-trip encounter before its geometry")
	var state: Dictionary=owner.snapshot()
	if bindings==null or state.base_content_id!=bindings.base_content_id or state.binding_id!=bindings.binding_id:return fail("Pirate geometry belongs to another content identity")
	var actor: Dictionary=state.combat.actors[0]
	if actor.actor_id!=0 or actor.hull_catalogue_id!=2 or actor.actor_kind!=8:return fail("Unsupported pirate model construction")
	if bindings.resolve(ENGINE_ID,"mesh")!=ENGINE_PATH or bindings.material_for_mesh(ENGINE_PATH,"high").get("render_type")!=2:return fail("Unsupported pirate engine model/material mapping")
	var death: RefCounted=owner.npc_destruction_owner(0)
	var held: Dictionary=death.snapshot().cargo
	if bindings.resolve(held.model_id,"mesh")!=held.resource or bindings.material_for_mesh(held.resource,"high").get("render_type")!=28:return fail("Unsupported pirate cargo model/material mapping")
	hull=Ship.new();add_child(hull)
	if not hull.build(2,library,visuals,bindings):return fail(hull.error)
	var resources:=Models.new()
	if not resources.prepare([ENGINE_PATH,held.resource],library,visuals,bindings,"high",true,true):return fail(resources.error)
	engine=resources.instantiate(ENGINE_PATH);cargo=resources.instantiate(held.resource)
	resources.clear();add_child(engine);add_child(cargo);engine.hide();cargo.hide()
	engine.set_meta("source_resource_id",ENGINE_ID);cargo.set_meta("source_resource_id",held.model_id)
	explosion=DeathEffect.new();add_child(explosion)
	if not explosion.build(library,visuals,bindings,death):return fail(explosion.error)
	projectiles=Projectiles.new();add_child(projectiles)
	if not projectiles.build(owner.projectile_visual_owner(),library,visuals,bindings):return fail(projectiles.error)
	impacts=Impacts.new();add_child(impacts)
	if not impacts.build(owner.impact_visual_owner(),library,visuals,bindings):return fail(impacts.error)
	_identity={"base_content_id":state.base_content_id,"binding_id":state.binding_id,"campaign_cursor":4}
	_hull_resource=actor.hull_resource;_cargo_resource=held.resource
	return true

func prepare_world(owner: RefCounted, camera: Transform3D, detail: Dictionary) -> Dictionary:
	error=""
	if hull==null or not owner is Encounter:return failed("Build the pirate assembly before presenting it")
	var state: Dictionary=owner.snapshot()
	for key in _identity:
		if state.get(key)!=_identity[key]:return failed("Pirate frame belongs to another encounter")
	if state.combat.actors.size()!=1:return failed("Pirate population changed")
	var actor: Dictionary=state.combat.actors[0]
	if actor.actor_id!=0 or actor.hull_catalogue_id!=2 or actor.hull_resource!=_hull_resource or not Pose.valid_pose(actor.pose):return failed("Pirate hull or statistics pose changed")
	for key in ["active","node_draw_requested","model_draw_enabled","engine_draw_enabled"]:
		if not actor.get(key) is bool:return failed("Pirate visibility flag is missing")
	if detail.get("base_content_id")!=_identity.base_content_id or detail.get("binding_id")!=_identity.binding_id or not hull.valid_selection(detail.get("selections",{}).get(0)):return failed("Pirate detail selection belongs to another geometry manager")
	var death: RefCounted=owner.npc_destruction_owner(0)
	var held: Dictionary=death.snapshot().cargo
	if held.get("resource")!=_cargo_resource or not held.get("model_exists") is bool or not Pose.valid_pose(held.get("pose")):return failed("Pirate cargo presentation lost its retained model")
	var effect: Dictionary=explosion.prepare_effect(death,camera,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0)
	if effect.is_empty():return failed(explosion.error)
	var shots: Dictionary=projectiles.prepare_world(owner.projectile_visual_owner(),state,camera)
	if shots.is_empty():return failed(projectiles.error)
	var hits: Dictionary=impacts.prepare_world(owner.impact_visual_owner(),state,camera)
	if hits.is_empty():return failed(impacts.error)
	var body_visible: bool=actor.active and actor.node_draw_requested and actor.model_draw_enabled and effect.body_visible
	return {"pose":actor.pose,"body_visible":body_visible,"engine_visible":body_visible and actor.engine_draw_enabled,
		"cargo_visible":held.model_exists,"cargo_pose":held.pose,"selection":detail.selections[0].duplicate(true),
		"effect":effect,"shots":shots,"hits":hits}

func commit_world(frame: Dictionary) -> void:
	hull.transform=frame.pose;hull.visible=frame.body_visible;hull.apply_selection(frame.selection)
	engine.transform=frame.pose;engine.visible=frame.engine_visible
	# Source draws a retained cargo model before testing the NPC's activity.
	cargo.transform=frame.cargo_pose;cargo.visible=frame.cargo_visible
	explosion.commit_effect(frame.effect);projectiles.commit_world(frame.shots);impacts.commit_world(frame.hits)

func clear() -> void:
	for child in get_children():child.free()
	hull=null;engine=null;cargo=null;explosion=null;projectiles=null;impacts=null
	_identity={};_hull_resource="";_cargo_resource="";error=""
func fail(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
