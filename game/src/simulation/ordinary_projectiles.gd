extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
## Native timing and flight for verified ordinary primary projectiles. The owner
## supplies a world muzzle or authored fixed mount, aim and firing permission;
## capacity comes from bindings or an explicit fixture input. No collision,
## targeting, spread, ownership, effects or mission consequences are inferred.
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Bounds = preload("res://src/content/weapon_collision_bounds.gd")
const Hits = preload("res://src/content/ordinary_hit_definitions.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Library = preload("res://src/content/library.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const TrainingWeapons = preload("res://src/content/combat_training_weapon_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
const MAX_CAPACITY := 4096
const HIT_LIFETIME_SENTINEL := -1000000
var error := ""
var _weapon := {}
var _slots: Array = []
var _elapsed_ms := 0
# Do not reuse a live object's handles after clear, failure or content replacement.
var _next_id := 1

func clear() -> void:
	error = ""
	_weapon = {}
	_slots = []
	_elapsed_ms = 0

func configure(weapon: Dictionary, capacity: Variant = null) -> bool:
	clear()
	if capacity!=null and not Vitals.integer(capacity): return reject("Explicit projectile capacity must be an integer")
	if weapon.has("projectile_capacity"):
		if capacity!=null and capacity!=weapon.projectile_capacity: return reject("Explicit capacity disagrees with the source weapon")
		capacity=weapon.projectile_capacity
	if not Vitals.integer(capacity) or capacity<1 or capacity>MAX_CAPACITY:
		return reject("Projectile capacity must be explicitly supplied within supported bounds")
	for field in ["base_content_id", "binding_id"]:
		if not Library.valid_hash(weapon.get(field)): return reject("Projectile weapon requires content and binding identities")
	for field in ["item_id", "category", "kind", "damage", "interval_ms", "lifetime_ms"]:
		if not Vitals.integer(weapon.get(field)): return reject("Invalid projectile weapon field: "+field)
	if weapon.category!=0 or weapon.kind not in [0,1,2] or weapon.get("launch_mode")!="ordinary":
		return reject("This projectile owner requires a source-declared ordinary primary launch path")
	if weapon.kind==2 and not TrainingWeapons.dispersed_primary(weapon) and not Fitting.dispersed(weapon):return reject("This ordinary kind requires its verified dispersion and capacity")
	if weapon.kind!=2 and weapon.has("dispersion"):return reject("This ordinary kind has no supported dispersion declaration")
	if weapon.has("campaign_cursor") and not Vitals.integer(weapon.campaign_cursor):return reject("Invalid projectile campaign context")
	if weapon.has("nonplayer_source") and not weapon.nonplayer_source is bool:return reject("Invalid projectile damage attribution")
	if weapon.has("ordinary_hit_policy") and not Hits.resolved(weapon.ordinary_hit_policy,weapon.damage):
		return reject("Invalid resolved ordinary hit policy")
	if weapon.has("collision_bounds") and not Bounds.resolved(weapon.collision_bounds):
		return reject("Invalid resolved weapon collision bounds")
	var speed: Variant = weapon.get("speed_units_per_millisecond")
	if not (speed is int or speed is float) or not is_finite(float(speed)) or speed<=0 or not is_finite(Vitals.single(float(speed))) or weapon.interval_ms<1 or weapon.lifetime_ms<1:
		return reject("Projectile speed, interval and lifetime must be positive and finite")
	for field in ["base_content_id", "binding_id", "item_id", "category", "kind", "damage", "interval_ms", "lifetime_ms"]:
		_weapon[field]=weapon[field]
	_weapon.speed_units_per_millisecond=Vitals.single(float(speed))
	_weapon.launch_mode=weapon.launch_mode
	if weapon.has("campaign_cursor"):_weapon.campaign_cursor=weapon.campaign_cursor
	if weapon.has("nonplayer_source"):_weapon.nonplayer_source=weapon.nonplayer_source
	if weapon.has("dispersion"):_weapon.dispersion=weapon.dispersion.duplicate(true)
	if weapon.has("fitting_primary"):_weapon.fitting_primary=weapon.fitting_primary
	if weapon.has("ordinary_hit_policy"): _weapon.ordinary_hit_policy=weapon.ordinary_hit_policy.duplicate(true)
	if weapon.has("collision_bounds"): _weapon.collision_bounds=weapon.collision_bounds.duplicate(true)
	_weapon.projectile_capacity=capacity
	_slots.resize(capacity)
	_elapsed_ms=weapon.interval_ms
	return true

func snapshot() -> Dictionary:
	if _weapon.is_empty(): return {}
	var available := 0
	for slot in _slots:
		if slot==null or slot.remaining_ms<=0: available+=1
	return {"weapon":_weapon.duplicate(true),"elapsed_ms":_elapsed_ms,
		"time_ready":_elapsed_ms>int(_weapon.interval_ms),"available_slots":available,
		"slots":_slots.duplicate(true)}

func reset_fire_interval() -> bool:
	error=""
	if _weapon.is_empty():return reject("Configure a weapon before resetting its firing interval")
	_elapsed_ms=0
	return true

func discard_flying() -> void:
	_slots.fill(null)

func fork_state() -> RefCounted:
	# Native owners stage a multi-weapon operation on private copies before commit.
	# These copies represent the same logical weapon; their handles are not new
	# globally identified projectiles. The owner must keep its weapon handle too.
	var staged: RefCounted = get_script().new()
	staged._weapon = _weapon.duplicate(true)
	staged._slots = _slots.duplicate(true)
	staged._elapsed_ms = _elapsed_ms
	staged._next_id = _next_id
	return staged

func fire_forward_from_mount(mount: Dictionary, firing_transform: Variant, firing_allowed: Variant, random_state: Variant=null) -> Dictionary:
	if not firing_transform is Transform3D or not firing_transform.is_finite():
		return fail("Forward launch requires a finite firing transform")
	# These fixed mounts have zero local aim offset. fire() applies any
	# explicitly declared dispersion to the resulting world direction.
	# Forward in source coordinates is positive Z, not Godot camera negative Z.
	# Final normalization remains inside fire(), after direction preparation.
	return fire_from_mount(mount, firing_transform, firing_transform.basis.z, firing_allowed,random_state)

func fire(muzzle: Variant, world_direction: Variant, firing_allowed: Variant, random_state: Variant=null) -> Dictionary:
	error=""
	if _weapon.is_empty(): return fail("Configure ordinary projectiles before firing")
	if not finite_vector(muzzle) or not finite_vector(world_direction) or not firing_allowed is bool:
		return fail("Firing requires finite world vectors and explicit permission")
	if not firing_allowed: return {"fired":false,"reason":"permission"}
	if _elapsed_ms<=int(_weapon.interval_ms): return {"fired":false,"reason":"interval"}
	var index := -1
	for i in _slots.size():
		if _slots[i]==null or _slots[i].remaining_ms<=0:
			index=i
			break
	if index<0: return {"fired":false,"reason":"capacity"}
	var aim:=scaled(world_direction,1.0)
	var random: RefCounted
	if _weapon.has("dispersion"):
		# This ordinary kind emits one projectile. The three bounded draws
		# perturb its world direction before normalization, only after a slot
		# is found. Failed permission, interval and capacity consume no draws.
		random=Random.new()
		if not random.restore(random_state):return fail("Dispersed launch requires an explicit valid shared random state")
		var spread: Dictionary=_weapon.dispersion
		var center:=Vitals.single(float(spread.steps)*Vitals.single(float(spread.center_scale)))
		for axis in 3:
			var offset:=Vitals.single(Vitals.single(float(random.next_int(int(spread.steps)))*Vitals.single(float(spread.draw_scale)))-center)
			aim[axis]=Vitals.single(aim[axis]+offset)
	var direction := normalized_launch(aim)
	var velocity := scaled(direction,float(_weapon.speed_units_per_millisecond))
	var position := scaled(muzzle,1.0)
	if not position.is_finite() or not velocity.is_finite() or _next_id==9223372036854775807:
		return fail("Projectile velocity or handle exceeds supported bounds")
	# Normalize the fully prepared direction before applying projectile speed.
	var projectile := {"id":_next_id,"slot":index,"position":position,
		"previous_position":position,"velocity":velocity,"remaining_ms":int(_weapon.lifetime_ms)}
	_next_id+=1
	_slots[index]=projectile
	_elapsed_ms=0
	var result:={"fired":true,"reason":"","projectile":projectile.duplicate(true)}
	if random!=null:result.random_state=random.snapshot()
	return result

func fire_from_mount(mount: Dictionary, ship_transform: Variant, world_direction: Variant, firing_allowed: Variant, random_state: Variant=null) -> Dictionary:
	error = ""
	if _weapon.is_empty(): return fail("Configure ordinary projectiles before firing")
	if mount.get("base_content_id") != _weapon.base_content_id or mount.get("category") != 0:
		return fail("Ordinary launch requires a primary mount from the weapon's base content")
	for field in ["ship_id", "slot"]:
		if not Vitals.integer(mount.get(field)): return fail("Invalid weapon mount field: " + field)
	if not finite_vector(mount.get("position")) or not ship_transform is Transform3D or not ship_transform.is_finite():
		return fail("Mount launch requires a finite ship transform and local position")
	# Fixed player mounts: the verified setup shifts local Z by 100 source units.
	# Mount assignment uses the equipment instance's category slot, not item ID.
	# Alternating mount flags and other source launch kinds are not enabled here.
	var offset := scaled(mount.position, 1.0)
	offset.z = Vitals.single(offset.z + 100.0)
	var basis: Basis = ship_transform.basis
	var rotated := Vector3(
		mount_dot(Vector3(basis.x.x, basis.y.x, basis.z.x), offset),
		mount_dot(Vector3(basis.x.y, basis.y.y, basis.z.y), offset),
		mount_dot(Vector3(basis.x.z, basis.y.z, basis.z.z), offset))
	var muzzle := added(scaled(ship_transform.origin, 1.0), rotated)
	if not muzzle.is_finite(): return fail("Weapon mount exceeds finite world coordinates")
	var up:=scaled(basis.y,1.0)
	if not up.is_finite():return fail("Weapon up axis exceeds finite world coordinates")
	var result:=fire(muzzle, world_direction, firing_allowed,random_state)
	if result.get("fired",false) and _weapon.get("campaign_cursor") in FlightStages.EQUIPPED and not _weapon.get("nonplayer_source",false):
		# The original ordinary launch stores the firing matrix's Y column in
		# each slot. It survives ship rotation and is reused by the draw root.
		_slots[result.projectile.slot].up=up
		result.projectile.up=up
	return result

static func mount_dot(row: Vector3, offset: Vector3) -> float:
	var x := Vitals.single(Vitals.single(row.x) * offset.x)
	var y := Vitals.single(Vitals.single(row.y) * offset.y)
	var z := Vitals.single(Vitals.single(row.z) * offset.z)
	return Vitals.single(Vitals.single(x + y) + z)

func advance(delta_ms: Variant) -> Dictionary:
	error=""
	if _weapon.is_empty(): return fail("Configure ordinary projectiles before advancing")
	if not Vitals.integer(delta_ms) or _elapsed_ms>Vitals.MAX_INTEGER-delta_ms:
		return fail("Projectile time exceeds supported integer milliseconds")
	var result := {"moved":[],"expired":[],"cleared":[]}
	# Zero elapsed time still runs source cleanup and refreshes live geometry.
	# A caller requiring frozen state must suppress this update.
	var staged := _slots.duplicate(true)
	for i in staged.size():
		var slot: Variant = staged[i]
		if slot==null: continue
		if slot.remaining_ms<=0:
			result.cleared.append(slot.id)
			staged[i]=null
			continue
		var displacement := scaled(slot.velocity,Vitals.single(float(delta_ms)))
		var next := added(slot.position,displacement)
		if not displacement.is_finite() or not next.is_finite(): return fail("Projectile motion exceeds finite world coordinates")
		slot.previous_position=slot.position
		slot.position=next
		slot.remaining_ms-=delta_ms
		result.moved.append(slot.duplicate(true))
		if slot.remaining_ms<=0: result.expired.append(slot.id)
	# Commit only after every projectile's motion has been validated. A final
	# full step is retained for presentation; its slot can already be reused.
	_slots=staged
	_elapsed_ms+=delta_ms
	return result

func retire(projectile_id: Variant) -> bool:
	error=""
	if _weapon.is_empty() or not projectile_id is int or projectile_id<1:
		return reject("Retirement requires a configured owner and projectile handle")
	for i in _slots.size():
		if _slots[i]!=null and _slots[i].id==projectile_id:
			_slots[i]=null
			return true
	return reject("Projectile handle is stale or belongs to another owner")

func mark_impact(projectile_id: Variant) -> bool:
	error = ""
	if _weapon.is_empty() or not projectile_id is int or projectile_id < 1:
		return reject("Impact requires a configured projectile owner and handle")
	for slot in _slots:
		if slot != null and slot.id == projectile_id:
			# Source hit processing keeps geometry through the remaining target
			# checks. The next movement update clears it rather than moving it.
			# Do not use immediate retirement for an ordinary collision impact.
			slot.remaining_ms = HIT_LIFETIME_SENTINEL
			return true
	return reject("Impact projectile handle is stale or belongs to another owner")

static func finite_vector(value: Variant) -> bool:
	return value is Vector3 and value.is_finite()

static func scaled(value: Vector3, factor: float) -> Vector3:
	return Vectors.scaled(value,factor)

static func normalized_launch(value: Vector3) -> Vector3:
	return Vectors.normalized(value)

static func scaled_components_squared(value: Vector3) -> Vector3:
	return Vectors.squares(value)

static func added(left: Vector3, right: Vector3) -> Vector3:
	return Vectors.added(left,right)

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
