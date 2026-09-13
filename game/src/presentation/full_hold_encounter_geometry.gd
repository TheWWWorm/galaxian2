extends Node3D
## Original NPC hulls, lights, engines, cargo and effects. Each complete cast is
## prepared before drawing; lifetime and gameplay stay in the encounter owner.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Ship=preload("res://src/presentation/ship_geometry.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const DeathEffect=preload("res://src/presentation/npc_death_effect_geometry.gd")
const Projectiles=preload("res://src/presentation/projectile_geometry.gd")
const Impacts=preload("res://src/presentation/ordinary_impact_geometry.gd")
const Pose=preload("res://src/presentation/opening_geometry.gd")
const ENGINES={2:{"id":18002,"path":"resources/data/assets/main/3d/meshes/ships/ship_002_pirates_engine_add.aem"},
	30:{"id":18030,"path":"resources/data/assets/main/3d/meshes/ships/ship_030_midorian_engine_add.aem"}}
var error:=""
# The first assembly remains directly accessible to the existing single-NPC
# scene inspections. All gameplay/presentation traversals use the complete list.
var hull: Node3D
var engine: Node3D
var cargo: Node3D
var explosion: Node3D
var projectiles: Node3D
var impacts: Node3D
var actors: Array=[]
var _identity:={}

func build(owner: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not owner is Encounter or owner.snapshot().is_empty():return fail("Prepare the ordinary encounter before its geometry")
	var state: Dictionary=owner.snapshot()
	if bindings==null or state.base_content_id!=bindings.base_content_id or state.binding_id!=bindings.binding_id:return fail("NPC geometry belongs to another content identity")
	if state.campaign_cursor not in [4,7] or state.combat.actors.size()!=(4 if state.campaign_cursor==7 else 1):return fail("Unsupported ordinary encounter population")
	for id in state.combat.actors.size():
		var actor: Dictionary=state.combat.actors[id]
		var ship_id:=30 if id==3 else 2
		if actor.actor_id!=id or actor.hull_catalogue_id!=ship_id or actor.actor_kind!=(3 if id==3 else 8):return fail("Unsupported ordinary NPC model construction")
		var exhaust: Dictionary=ENGINES[ship_id]
		if bindings.resolve(exhaust.id,"mesh")!=exhaust.path or bindings.material_for_mesh(exhaust.path,"high").get("render_type")!=2:return fail("Unsupported NPC engine model/material mapping")
		var death: RefCounted=owner.npc_destruction_owner(id)
		if death==null:return fail("NPC model lacks its retained destruction owner")
		var held: Dictionary=death.snapshot().cargo
		if bindings.resolve(held.model_id,"mesh")!=held.resource or bindings.material_for_mesh(held.resource,"high").get("render_type")!=28:return fail("Unsupported NPC cargo model/material mapping")
		var body:=Ship.new();add_child(body)
		if not body.build(ship_id,library,visuals,bindings):return fail(body.error)
		var resources:=Models.new()
		if not resources.prepare([exhaust.path,held.resource],library,visuals,bindings,"high",true,true):return fail(resources.error)
		var motor: Node3D=resources.instantiate(exhaust.path);var container: Node3D=resources.instantiate(held.resource)
		resources.clear();add_child(motor);add_child(container);motor.hide();container.hide()
		motor.set_meta("source_resource_id",exhaust.id);container.set_meta("source_resource_id",held.model_id)
		var effect:=DeathEffect.new();add_child(effect)
		if not effect.build(library,visuals,bindings,death):return fail(effect.error)
		actors.append({"hull":body,"engine":motor,"cargo":container,"explosion":effect,
			"ship_id":ship_id,"hull_resource":actor.hull_resource,"cargo_resource":held.resource})
	hull=actors[0].hull;engine=actors[0].engine;cargo=actors[0].cargo;explosion=actors[0].explosion
	projectiles=Projectiles.new();add_child(projectiles)
	if not projectiles.build(owner.projectile_visual_owner(),library,visuals,bindings):return fail(projectiles.error)
	impacts=Impacts.new();add_child(impacts)
	if not impacts.build(owner.impact_visual_owner(),library,visuals,bindings):return fail(impacts.error)
	_identity={"base_content_id":state.base_content_id,"binding_id":state.binding_id,"campaign_cursor":state.campaign_cursor}
	return true

func prepare_world(owner: RefCounted, camera: Transform3D, detail: Dictionary) -> Dictionary:
	error=""
	if actors.is_empty() or not owner is Encounter:return failed("Build the NPC assemblies before presenting them")
	var state: Dictionary=owner.snapshot()
	for key in _identity:
		if state.get(key)!=_identity[key]:return failed("NPC frame belongs to another encounter")
	if state.combat.actors.size()!=actors.size():return failed("NPC population changed")
	if detail.get("base_content_id")!=_identity.base_content_id or detail.get("binding_id")!=_identity.binding_id:return failed("NPC detail selections belong to another geometry manager")
	var prepared:=[]
	for id in actors.size():
		var nodes: Dictionary=actors[id];var actor: Dictionary=state.combat.actors[id]
		if actor.actor_id!=id or actor.hull_catalogue_id!=nodes.ship_id or actor.hull_resource!=nodes.hull_resource or not Pose.valid_pose(actor.pose):return failed("NPC hull or statistics pose changed")
		for key in ["active","node_draw_requested","model_draw_enabled","engine_draw_enabled"]:
			if not actor.get(key) is bool:return failed("NPC visibility flag is missing")
		if not nodes.hull.valid_selection(detail.get("selections",{}).get(id)):return failed("NPC detail selection is unavailable")
		var death: RefCounted=owner.npc_destruction_owner(id)
		if death==null:return failed("NPC lost its destruction owner")
		var held: Dictionary=death.snapshot().cargo
		if held.get("resource")!=nodes.cargo_resource or not held.get("model_exists") is bool or not Pose.valid_pose(held.get("pose")):return failed("NPC cargo presentation lost its retained model")
		var effect: Dictionary=nodes.explosion.prepare_effect(death,camera,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0)
		if effect.is_empty():return failed(nodes.explosion.error)
		var body_visible: bool=actor.active and actor.node_draw_requested and actor.model_draw_enabled and effect.body_visible
		prepared.append({"pose":actor.pose,"body_visible":body_visible,"engine_visible":body_visible and actor.engine_draw_enabled,
			"cargo_visible":held.model_exists,"cargo_pose":held.pose,"selection":detail.selections[id].duplicate(true),"effect":effect})
	var shots: Dictionary=projectiles.prepare_world(owner.projectile_visual_owner(),state,camera)
	if shots.is_empty():return failed(projectiles.error)
	var hits: Dictionary=impacts.prepare_world(owner.impact_visual_owner(),state,camera)
	if hits.is_empty():return failed(impacts.error)
	var result: Dictionary=prepared[0].duplicate(true)
	result.merge({"actors":prepared,"shots":shots,"hits":hits})
	return result

func commit_world(frame: Dictionary) -> void:
	for id in actors.size():
		var nodes: Dictionary=actors[id];var current: Dictionary=frame.actors[id]
		nodes.hull.transform=current.pose;nodes.hull.visible=current.body_visible;nodes.hull.apply_selection(current.selection)
		nodes.engine.transform=current.pose;nodes.engine.visible=current.engine_visible
		# Source draws a retained cargo model before testing the NPC's activity.
		nodes.cargo.transform=current.cargo_pose;nodes.cargo.visible=current.cargo_visible
		nodes.explosion.commit_effect(current.effect)
	projectiles.commit_world(frame.shots);impacts.commit_world(frame.hits)

func clear() -> void:
	for child in get_children():child.free()
	hull=null;engine=null;cargo=null;explosion=null;projectiles=null;impacts=null
	actors=[];_identity={};error=""
func fail(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
