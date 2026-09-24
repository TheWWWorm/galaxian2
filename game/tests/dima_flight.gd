extends "res://tests/dima_construction.gd"
## Detached selected28 fixture. The earned station27 route has its own producer.
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const ProjectileModels=preload("res://src/simulation/projectile_visual_state.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Pilot=preload("res://tests/fixtures/expedition_flight_pilot.gd")
var _pilot_scene: Node3D

func test_label() -> String:return "Dima selected flight"

func after_prepared(library: RefCounted,bindings: RefCounted,cat: RefCounted,prepared: RefCounted) -> void:
	verify_projectile_models(bindings)
	if not library.select_language("gb"):check(false,library.error);return
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var seed: Dictionary=prepared.snapshot()
	var complete:=FlightConstruction.new()
	if not complete.prepare_dima_selected(bindings,cat,prepared.equipment_owner(),seed.sahi_context,seed.departure.progress,{},4096,123,true,bodies,effects):check(false,complete.error);return
	check(complete.snapshot().environment_object==seed.environment_object and complete.snapshot().scenery.world_initialization.npc_construction.actors==seed.scenery.world_initialization.npc_construction.actors,"Dima resource completion redrew the portal or cast")
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,library.manifest):check(false,visuals.error);return
	root.size=Vector2i(1280,720)
	var frame:=Frame.new()
	if not frame.configure(bindings,cat,library,complete,"E",0.5):check(false,"Dima frame: "+frame.error);return
	var scene:=Scene.new();root.add_child(scene);_pilot_scene=scene
	if not scene.build(library,bindings,visuals,cat,frame):check(false,"Dima scene: "+scene.error);scene.free();return
	var initial: Dictionary=frame.snapshot()
	check(initial.campaign_cursor==28 and initial.location.station_id==91 and initial.location.system_id==18 and initial.actors.size()==8,"Dima frame lost selected location or original eight actors")
	check(initial.actors.slice(0,5).all(func(actor):return actor.actor_kind==9) and initial.actors.slice(5).all(func(actor):return actor.actor_kind==0),"Dima frame changed the original five fighters/three freighters")
	check(initial.void_portal.model_id==16994 and initial.void_portal.position==seed.environment_object.position and initial.void_portal.visible,"Dima frame lost its translated original portal")
	check(initial.radio.started==[false,false,false] and not initial.dialogue.visible and initial.dialogue.count==0,"Dima flight invented an arrival briefing or early radio")
	check(initial.progress==seed.departure.progress and initial.equipment==complete.equipment_owner().snapshot() and initial.cargo.used==0,"Dima frame changed selected component progress or inventory")
	check(scene.portal!=null and scene.station!=null and scene.sky!=null and scene.planets!=null,"Dima scene lost its portal, station, sky or planet")
	await capture_frame(scene,frame,"dima-departure")
	await fly_to_portal(frame,scene,initial)
	scene.free();_pilot_scene=null

func verify_projectile_models(bindings: RefCounted) -> void:
	var original: Dictionary=bindings.mido_travel.sahi_encounter.weapons["void"]
	var weapon:={"campaign_cursor":28,"item_id":int(original.item_id),"category":0,
		"kind":int(original.kind),"nonplayer_source":true}
	var dima_count: int=int(bindings.mido_travel.thynome_expedition.world28.cast.groups[0].count)
	var void_count: int=int(bindings.mido_travel.post_sahi["void"].population.count)
	var pursuit_count: int=int(bindings.mido_travel.post_sahi.pursuers.count)
	check(dima_count==5 and void_count==3 and pursuit_count==2,"Selected fighter counts changed from the guarded source cast")
	for cursor in [25,26,28,29]:
		weapon.campaign_cursor=cursor
		var count: int=dima_count if cursor==28 else pursuit_count if cursor==26 else void_count
		for impact in [false,true]:
			var model_id: int=int(original.impact_model_id if impact else original.model_resource_id)
			var expected:={"id":model_id,"resource":bindings.resolve(model_id,"mesh"),"captured_up":false}
			for actor_id in [0,count-1]:
				check(ProjectileModels.model_mapping(bindings,weapon,"npc:%d"%actor_id,impact)==expected,"Expedition fighter lost its source projectile/impact model")
			check(ProjectileModels.model_mapping(bindings,weapon,"npc:%d"%count,impact).is_empty(),"Expedition unarmed/absent actor gained a Void weapon model")
			var wrong:=weapon.duplicate();wrong.item_id=0
			check(ProjectileModels.model_mapping(bindings,wrong,"npc:0",impact).is_empty(),"Expedition actor accepted another projectile/impact item")

func fly_to_portal(frame: RefCounted,_scene: Node3D,initial: Dictionary) -> void:
	var contact: RefCounted=await Pilot.enter_portal(frame,Callable(self,"advance_pilot"),Callable(self,"capture_pilot"),Callable(self,"check"),process_frame)
	if contact!=null:
		var state: Dictionary=contact.snapshot()
		check(contact.void_return_required() and state.progress==initial.progress and state.cargo==initial.cargo and state.equipment==initial.equipment,"Dima contact changed the selected component's progression or inventory")

func advance_pilot(frame: RefCounted,ms: int,commands: Vector2,throttle: float,fire: bool) -> RefCounted:
	return frame.evaluate(ms,commands,throttle,false,Vector2i.ZERO,Vector2.ZERO,fire)

func capture_pilot(_unused_scene: Node3D,frame: RefCounted,label: String) -> void:
	await capture_frame(_pilot_scene,frame,label)

func capture_frame(scene: Node3D,frame: RefCounted,label: String) -> void:
	if not scene.present(frame):check(false,scene.error);return
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(captures)
	await process_frame
	RenderingServer.force_draw(false);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(captures.path_join(label+".png"))==OK,"Cannot capture "+label)
