extends SceneTree
## Detached weapon/target inputs test timing and damage boundaries. They do not
## grant inventory, produce campaign fixtures or claim flight integration.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/emp_bombs_definitions.gd")
const Bombs=preload("res://src/simulation/emp_bombs.gd")
const Systems=preload("res://src/simulation/ship_systems.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("EMP bomb components: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var bomb:=Bombs.new();var systems:=Systems.new()
	if not Definitions.available(bindings):
		check(not bomb.configure(bindings,cat,41,[]),"Older content inferred EMP flight")
		check(not systems.configure(bindings,100,15000),"Older content inferred systems damage")
		return
	var catalogue: Dictionary=cat.tables.duplicate(true)
	for id in [41,42,43]:
		check(bomb.configure(bindings,cat,id,[]),bomb.error)
		var weapon: Dictionary=bomb.snapshot().weapon
		check(weapon.category==1 and weapon.kind==6 and weapon.model_id==14684,"An EMP bomb resolved as an ordinary primary or wrong model")
		check(weapon.system_damage==cat.tables.items[id].properties[10] and weapon.radius==cat.tables.items[id].properties[14],"The bomb lost its source systems damage or radius")
	check(bomb.configure(bindings,cat,41,[]),bomb.error)
	var before:=bomb.snapshot()
	check(not bomb.configure(bindings,cat,2,[]) and bomb.snapshot()==before,"A primary weapon replaced the EMP owner")
	check(bomb.trigger(Transform3D.IDENTITY,10,[]).action=="none","The initial interval equality launched a bomb")
	check(bomb.advance(1,[]).action=="none",bomb.error)
	var launch:=bomb.trigger(Transform3D.IDENTITY,10,[])
	check(launch.action=="launched" and launch.ammunition_consumed==1,"Successful launch did not consume exactly one round")
	check(launch.shot.position==Vector3(0,0,400) and launch.shot.velocity==Vector3(0,0,7),"EMP muzzle offset or speed changed")
	var shot_id: int=launch.shot.id
	var targets:=[target(0,Vector3(0,0,400)),target(1,Vector3(11000,0,400)),target(2,Vector3(22000,0,400)),target(3,Vector3(21999.5,0,400)),target(4,Vector3(0,0,400),true,true),target(5,Vector3(0,0,400),false)]
	before=bomb.snapshot()
	check(bomb.trigger(Transform3D.IDENTITY,9,targets,false).action=="none" and bomb.snapshot()==before,"Blocked controls detonated a bomb")
	check(bomb.detonate(shot_id+1,targets).is_empty() and bomb.snapshot()==before,"A stale projectile handle detonated a live bomb")
	var invalid: Array=targets.duplicate(true);invalid.append(targets[0])
	check(bomb.trigger(Transform3D.IDENTITY,9,invalid).is_empty() and bomb.snapshot()==before,"Duplicate targets partly committed a blast")
	var branch: RefCounted=bomb.fork()
	var pulse: Dictionary=branch.trigger(Transform3D.IDENTITY,0,targets)
	check(pulse.action=="detonated" and pulse.ammunition_consumed==0 and bomb.snapshot()==before,"Speculative last-round detonation changed the parent or consumed ammo")
	check(pulse.blast.hits==[{"actor_id":0,"system_damage":80,"distance":0},{"actor_id":1,"system_damage":40,"distance":11000},{"actor_id":3,"system_damage":0,"distance":21999}],"EMP radius, falloff, integer distance or target exclusions changed")
	check(branch.detonate(shot_id,targets).is_empty(),"A bomb delivered the same contact pulse twice")
	check(branch.advance(0,targets).action=="none" and branch.snapshot().shot.is_empty(),"The next update retained detonated geometry")
	check(branch.trigger(Transform3D.IDENTITY,10,[]).action=="none","Detonation bypassed the launch cooldown")
	var endpoint:=Vector3(0,0,42400)
	var expiry:=bomb.advance(6000,[target(1,endpoint)])
	check(expiry.action=="detonated" and expiry.blast.position==endpoint and expiry.blast.hits[0].system_damage==80,"Lifetime expiry omitted full-step movement or the EMP pulse")
	check(bomb.trigger(Transform3D.IDENTITY,1,[]).action=="none","Exact6000ms permitted another launch")
	check(bomb.advance(1,[]).action=="none",bomb.error)
	check(bomb.trigger(Transform3D.IDENTITY,0,[]).action=="none","Empty ammunition launched a bomb")
	var rotated:=Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(10,20,30))
	launch=bomb.trigger(rotated,1,[])
	check(launch.action=="launched" and launch.shot.id>shot_id and launch.shot.position.is_equal_approx(Vector3(410,20,30)),"Rotated launch lost its source-local muzzle or reused a handle")
	check(launch.shot.velocity.is_equal_approx(Vector3(7,0,0)),"Bomb direction did not follow the player transform")
	before=bomb.snapshot()
	for invalid_delta in [-1,1.5,NAN,INF]:check(bomb.advance(invalid_delta,[]).is_empty() and bomb.snapshot()==before,"Invalid timing moved a bomb")
	var corrupt:=target(0,Vector3(INF,0,0))
	check(bomb.detonate(launch.shot.id,[corrupt]).is_empty() and bomb.snapshot()==before,"Malformed targets partially consumed the bomb")
	check(bomb.detonate(launch.shot.id,[]).action=="detonated","A confirmed contact could not detonate the bomb")
	check(cat.tables==catalogue,"Weapon configuration or firing changed catalogue prototypes")
	verify_systems(bindings)

func verify_systems(bindings: RefCounted) -> void:
	var systems:=Systems.new()
	check(systems.configure(bindings,100,15000),systems.error)
	var initial:=systems.snapshot()
	for context in [[50,0,true,true],[50,100,false,true],[50,100,true,false]]:
		check(not systems.hit(context[0],context[1],context[2],context[3]).accepted and systems.snapshot()==initial,"Inactive, dead or protected systems took damage")
	var hit:=systems.hit(50,100,true,true)
	check(hit.accepted and not hit.disabled_now and hit.after.integrity==50,"Partial systems damage disabled the ship")
	check(systems.advance(20000) and systems.snapshot().integrity==50,"Undepleted systems regenerated without a source rule")
	hit=systems.hit(50,100,true,true)
	check(hit.disabled_now and hit.after.integrity==0 and hit.after.elapsed_ms==0,"Exact depletion did not begin systems recovery")
	check(not systems.hit(80,100,true,true).accepted,"Zero integrity accepted another hit")
	check(systems.advance(7500) and systems.snapshot().integrity==50 and systems.snapshot().disabled,"Half-duration recovery changed its integer system pool")
	var branch: RefCounted=systems.fork();var before:=systems.snapshot()
	hit=branch.hit(80,100,true,true)
	check(hit.accepted and hit.after.integrity==0 and hit.after.elapsed_ms==0 and not hit.disabled_now and systems.snapshot()==before,"Repeat depletion did not reset the speculative recovery timer")
	check(systems.advance(7500) and systems.snapshot().integrity==100 and systems.snapshot().disabled,"Exact recovery duration cleared the strict source boundary")
	check(systems.advance(149) and systems.snapshot().disabled,"Truncated full integrity ended recovery too early")
	check(systems.advance(1) and not systems.snapshot().disabled and systems.snapshot().elapsed_ms==0,"Recovery did not end after the truncated result exceeded capacity")
	before=systems.snapshot()
	check(systems.hit(0,100,true,true).accepted and systems.snapshot()==before,"A zero-damage pulse changed full integrity")
	check(not systems.advance(-1) and systems.snapshot()==before,"Negative systems time changed state")
	check(systems.hit(-1,100,true,true).is_empty() and systems.snapshot()==before,"Negative systems damage changed state")
	check(not systems.configure(bindings,100,0) and systems.snapshot()==before,"Rejected reconfiguration replaced systems state")

static func target(id: int,position: Vector3,active:=true,immune:=false) -> Dictionary:
	return {"actor_id":id,"position":position,"active":active,"emp_immune":immune}

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
