extends SceneTree
## Mac integration of the second mining field, retained pirate and cargo cue.
## Departure packets and close mining/encounter placements are explicit fixtures;
## ore is earned by the native drill. This is not an application playthrough.
const Fixtures=preload("res://tests/full_hold_control.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
var failures:=0
var checks:=0
var world: RefCounted
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold world: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not lib.select_language("gb") or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","Mac content is required")
	var fixture:=Fixtures.new();var construction:=Construction.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,bodies.error+effects.error);fixture.free();return
	var prepared:=construction.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000,true,bodies,effects)
	fixture.free()
	if not prepared:check(false,construction.error);return
	var saved: Dictionary=construction.snapshot()
	world=Frame.new()
	if not world.configure(bindings,cat,lib,construction,"E",.5):check(false,world.error);return
	var initial: Dictionary=world.snapshot()
	check(initial.actors.size()==1 and initial.actors[0].actor_mode==5 and not initial.actors[0].active,"Fresh flight did not retain its dormant pirate")
	check(initial.encounter.weapons.actors.size()==1 and initial.encounter.weapons.actors[0].projectiles.weapon.item_id==19,"Fresh encounter installed the wrong weapon population")
	check(initial.encounter.projectile_visuals.models.size()==1 and initial.encounter.projectile_visuals.models[0].key=="npc:0","Unarmed starter fabricated projectile visuals")
	check(initial.random_state==saved.random_state and initial.cargo.used==0,"Live world repeated construction draws or granted cargo")
	for i in 160:
		if world.dialogue_visible():break
		if not step(100):return
	var modal: Dictionary=world.snapshot()
	check(modal.dialogue.get("text_id")==int(bindings.full_hold_story.briefing_events[0].text_id) and modal.encounter.elapsed_ms==modal.world_elapsed_ms,"Second trip lost its original entry line or weapon clock")
	check(modal.world_phase_elapsed_ms==modal.world_elapsed_ms-100 and modal.encounter.world_elapsed_ms==modal.world_phase_elapsed_ms,"Modal creation did not zero only the later world pass")
	check(modal.encounter.controller.actors[0].guidance.selection_elapsed_ms<5001 and modal.random_state!=saved.random_state,"Dormant pirate selection did not share the retained world stream")
	for i in 3:
		if not step(100):return
	check(world.snapshot().player_pose==modal.player_pose and world.snapshot().encounter.elapsed_ms==modal.encounter.elapsed_ms and world.snapshot().world_phase_elapsed_ms==modal.world_phase_elapsed_ms and world.snapshot().dialogue==modal.dialogue,"Modal wait advanced player/weapons/time or acknowledged itself")
	var paused: Dictionary=world.snapshot()
	var frozen: RefCounted=world.evaluate(150,Vector2.ONE,0,true)
	check(frozen!=null and frozen.snapshot()==paused,"Explicit pause visited world owners")
	verify_modal_activation()
	if not navigate():return
	check(world.snapshot().phase=="flight" and not world.dialogue_visible(),"Original entry acknowledgement did not release flight")
	if not mine():return
	for i in 70:
		if world.dialogue_visible():break
		if not step(100):return
	var completion: Dictionary=world.snapshot()
	check(completion.cargo.used==25 and completion.dialogue.get("text_id")==int(bindings.full_hold_story.completion_events[0].text_id) and completion.campaign_cursor==4,"Full hold did not open its original warning before advancement")
	check(not completion.encounter.controller.appearance.applied and completion.mining_objective.reward_credits==0,"Completion opened the pirate early or paid a reward")
	if not navigate():return
	check(world.snapshot().dialogue.get("text_id")==int(bindings.full_hold_story.completion_events[1].text_id),"Second full-hold warning was lost")
	if not navigate():return
	var accepted: Dictionary=world.snapshot()
	check(accepted.campaign_cursor==5 and accepted.mission.kind==11 and accepted.cargo.used==25 and not accepted.encounter.controller.appearance.applied,"Acknowledgement moved the pirate before the following logic pass")
	if not step(0):return
	var cued: Dictionary=world.snapshot()
	check(cued.actors[0].body_pose.origin==accepted.player_pose.origin+Vector3(5000,0,30000) and cued.actors[0].body_pose.basis.z.is_equal_approx(Vector3(0,0,-1)),"World cue lost source position/yaw or ran after motion")
	check(cued.encounter.controller.appearance.applied and not cued.encounter.controller.appearance.pending and cued.actors[0].active,"Cue did not reach the same frame's NPC pass")
	check(cued.encounter.elapsed_ms==accepted.encounter.elapsed_ms and cued.encounter.world_elapsed_ms==accepted.encounter.world_elapsed_ms and cued.cargo==accepted.cargo,"Zero-time cue advanced weapon clocks or changed owned cargo")
	verify_atomicity()
	verify_player_hit_order()
	verify_world_order()
	check(construction.snapshot()==saved,"Live frames modified prepared construction")
	check(world.prepare_station().is_empty(),"Unconnected second return fabricated a station entry")

func verify_modal_activation():
	var retained: RefCounted=world
	world=world.fork_for_frame()
	# Source zero-time world passes are observable. Move only this branch's
	# physical player close to the authored dormant actor during its modal.
	world._pose=Transform3D(Basis.IDENTITY,Fixtures.ORIGIN+Vector3(0,0,20000))
	var before: Dictionary=world.snapshot()
	if step(150):
		var after: Dictionary=world.snapshot()
		check(after.actors[0].active and after.actors[0].actor_mode==1 and after.actors[0].body_pose.origin==Fixtures.ORIGIN,"Modal NPC pass was skipped or moved with real time")
		check(after.encounter.elapsed_ms==before.encounter.elapsed_ms and after.player_pose==before.player_pose and after.camera_view==before.camera_view,"Modal activation advanced earlier logic owners")
	world=retained

func mine() -> bool:
	var asteroid:={}
	for body in world.snapshot().scenery.bodies.objects:
		if body.source_size_value==7:asteroid=body;break
	if asteroid.is_empty():check(false,"Source field has no core asteroid for the drill fixture");return false
	var stand_off:=float(int(asteroid.scale*2500))
	world=world.fork_for_frame()
	world._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,stand_off-.5))
	world._pilot.angular_units=Vector2.ZERO;world._targeting._selected=int(asteroid.index)
	world._autopilot.observe_manual(world._pose,Vector2.ZERO)
	var selected: RefCounted=world.start_mining()
	if selected==null:check(false,world.error);return false
	world=selected
	for i in 200:
		if world.drill_owner()!=null:break
		if not step(100):return false
	if world.drill_owner()==null:check(false,"Second field approach never reached its native drill");return false
	for i in 500:
		var state: Dictionary=world.snapshot().mining_session.drill
		var desired: Vector2=-(state.point+(state.input+state.drift)*5.0)*.2-state.drift
		var command:=Vector2.ZERO
		for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
		if not step(100,command):return false
		if world.drill_owner()==null:break
	check(world.snapshot().cargo.used==25 and world.snapshot().scenery.mined_count==1,"Native drilling did not earn exactly one full cargo hold")
	return world.snapshot().cargo.used==25

func verify_atomicity():
	var before: Dictionary=world.snapshot()
	for dt in [-1,151,1.5,true]:check(world.evaluate(dt)==null and world.snapshot()==before,"Rejected frame changed the retained world")
	var corrupt: RefCounted=world.fork_for_frame();corrupt._random={"state":-1}
	var invalid: Dictionary=corrupt.snapshot()
	check(corrupt.evaluate(100)==null and corrupt.snapshot()==invalid,"Late NPC failure committed player or weapon advancement")
	check(world.snapshot()==before,"Failed fork corrupted its accepted parent")

func verify_player_hit_order():
	var retained: RefCounted=world
	var accepted: Dictionary=retained.snapshot()
	world=Fixtures.fork_world_fixture(world)
	# Explicit slot fixture at the NEXT player position. Contacts must use the
	# moved player and the old projectile slot, before projectile advancement.
	var muzzle: Vector3=world._pose.origin+world._pose.basis.z*200.0
	var gun: RefCounted=world._encounter._weapons._guns[0]
	gun._elapsed_ms=593
	var shot: Dictionary=gun.fire(muzzle,Vector3.RIGHT,true)
	check(shot.get("fired",false),"Contact fixture could not create an ordinary pirate shot")
	var before: Dictionary=world.snapshot()
	var broken: RefCounted=world.fork_for_frame();broken._random={"state":-1}
	var invalid: Dictionary=broken.snapshot()
	check(broken.evaluate(100)==null and broken.snapshot()==invalid,"Late failure committed a player hit or impact effect")
	if step(100):
		var after: Dictionary=world.snapshot()
		check(after.player.vitals.hull==before.player.vitals.hull-1 and after.encounter.impact_visuals.hits.size()==1,"World contacts did not use the moved player before shot advancement")
		if after.encounter.impact_visuals.hits.size()==1:check(after.encounter.impact_visuals.hits[0].position==muzzle,"Impact lost the original contact-slot position")
	# Exhaust the remaining hull through the same verified weapon policy, then
	# let a final positioned shot reach the supported destruction owner, or the
	# explicit boundary retained by older packs without that capability.
	var weapon: Dictionary=gun.snapshot().weapon
	while world._player.snapshot().vitals.hull>1:world._player.weapon_hit(weapon,true,true,false)
	gun=world._encounter._weapons._guns[0];gun._elapsed_ms=593
	gun.fire(world._pose.origin+world._pose.basis.z*200.0,Vector3.RIGHT,true)
	if step(100):
		var dead: Dictionary=world.snapshot()
		if dead.has("player_destruction"):
			check(dead.player.vitals.hull==0 and not dead.player.active and dead.player_destruction.phase=="tumble" and dead.player_destruction.elapsed_ms==0,"Lethal contact did not start the later death poll")
			var after: RefCounted=world.evaluate(100)
			check(after!=null and after.snapshot().player_destruction.elapsed_ms==100 and after.snapshot().world_phase_elapsed_ms==dead.world_phase_elapsed_ms+100 and after.prepare_station().is_empty(),"Death froze the world or fabricated station arrival")
			if after!=null:
				for i in 160:
					if after.game_over_waiting():break
					var next: RefCounted=after.evaluate(100)
					if next==null:check(false,after.error);break
					after=next
				var exit: RefCounted=after.request_game_over_exit()
				check(exit!=null and exit.prepare_game_over().campaign_cursor==5 and exit.prepare_game_over().source_state==1,"Returning player death lost its current story cursor")
				check(after.snapshot().cargo==dead.cargo and after.snapshot().progress==dead.progress and after.prepare_station().is_empty(),"Death delivered, disposed or rewarded the earned full hold")
		else:
			check(dead.player.vitals.hull==0 and dead.get("boundary")=="player_death_required","Lethal player contact continued an unsupported transition")
			check(world.evaluate(100).snapshot()==dead and world.start_mining()==null and world.start_station_autopilot()==null and world.navigate("next")==null,"Unsupported death continued flight or campaign acknowledgement")
	check(retained.snapshot()==accepted,"Positioned-shot fixture changed the accepted world")
	world=retained

func verify_world_order():
	var accepted: Dictionary=world.snapshot()
	var branch: RefCounted=Fixtures.fork_world_fixture(world)
	check(branch._encounter._combat.normal_hit(0,50).destroyed_now,"Ordered-death fixture failed to exhaust the pirate")
	check(branch._scenery._bodies.normal_hit(0,100000).destroyed_now,"Ordered-death fixture failed to exhaust its asteroid")
	# Existing independently verified owners provide the source NPC-before-rock
	# composition oracle. The reverse order must allocate different random data.
	var actors: Dictionary=branch._encounter.evaluate_world(branch._player,branch._pose,1,branch._random)
	if actors.is_empty():check(false,branch._encounter.error);return
	var expected: RefCounted=branch._scenery.fork_for_frame()
	if not expected.update(1,branch._reference,1.0,null,actors.random_state):check(false,expected.error);return
	var reverse: RefCounted=branch._scenery.fork_for_frame()
	if not reverse.update(1,branch._reference,1.0,null,branch._random):check(false,reverse.error);return
	var reversed: Dictionary=branch._encounter.evaluate_world(branch._player,branch._pose,1,reverse.snapshot().random_state)
	if reversed.is_empty():check(false,branch._encounter.error);return
	check(actors.encounter.snapshot().controller!=reversed.encounter.snapshot().controller,"Ordering fixture failed to distinguish reversed random allocation")
	var before: Dictionary=branch.snapshot();var next: RefCounted=branch.evaluate(1)
	if next==null:check(false,branch.error);return
	check(next.snapshot().encounter.controller==actors.encounter.snapshot().controller and next.snapshot().scenery==expected.snapshot(),"Live frame reversed NPC and scenery lifecycle/random work")
	check(branch.snapshot()==before,"Ordered world evaluation mutated its parent")
	check(world.snapshot()==accepted,"Direct scenery damage fixture changed the accepted world")

func step(milliseconds: int, drill:=Vector2.ZERO) -> bool:
	var next: RefCounted=world.evaluate(milliseconds,Vector2.ZERO,1.0,false,Vector2i.ZERO,drill)
	if next==null:check(false,world.error);return false
	world=next;return true
func navigate() -> bool:
	var next: RefCounted=world.navigate("next")
	if next==null:check(false,world.error);return false
	world=next;return true
func check(value: bool, message: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL ",checks,": ",message)
