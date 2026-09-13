extends RefCounted
## Target choice is independent of weapon collision membership and firing gates.
## The caller supplies the verified ordinary, unattached training population.
const Vectors=preload("res://src/simulation/source_vectors.gd")

static func select(state: Dictionary, actor: Dictionary, targets: Array, random: RefCounted, tuning: Dictionary, rules: Dictionary) -> Dictionary:
	var next:=state.duplicate(true)
	var selected:=int(next.target_index)
	if selected>=targets.size() or selected<0 or not next.fire_desired:selected=-1
	if selected>=0 and not targets[selected].active:next.fire_desired=false
	if next.selection_elapsed_ms>int(tuning.selection_period_ms):
		next.straight=false if next.straight else random.next_int(int(tuning.straight_roll_bound))<int(tuning.straight_chance)
		next.selection_elapsed_ms=0
		var choose_other: bool=random.next_int(int(tuning.selection_roll_bound))<int(rules.random_selection_chance) and targets.size()>=2
		selected=0
		if choose_other:
			next.fire_desired=false
			for attempt in int(rules.random_selection_attempts):
				var candidate: int=random.next_int(targets.size())
				if targets[candidate].active and in_range(actor,targets[candidate]):
					selected=candidate;next.fire_desired=true;break
		if not alive(targets[selected]):
			selected=-1;next.fire_desired=false
		elif not in_range(actor,targets[selected]):
			# A range refresh leaves firing desire retained; it is not acquisition.
			selected=-1
	elif not next.fire_desired:
		for index in targets.size():
			if alive(targets[index]) and in_range(actor,targets[index]):
				selected=index;next.fire_desired=true;break
	if not actor.hostile and selected==0:
		selected=1;next.fire_desired=false
	if selected>0:
		selected=-1
		# The ordinary nonplayer pass starts at one in membership order. These
		# two opposed actor kinds need no reputation or attached-companion rules.
		for index in range(1,targets.size()):
			if alive(targets[index]) and (int(targets[index].actor_kind)==8)!=(int(actor.actor_kind)==8):
				selected=index;next.fire_desired=true;break
	next.target_index=selected
	next.target_selected=selected>=0
	return next

static func alive(target: Dictionary) -> bool:
	return target.active and target.hull>0

static func in_range(actor: Dictionary, target: Dictionary) -> bool:
	var distance:=Vectors.added(target.pose.origin,-actor.pose.origin).abs()
	var extent:=float(actor.spatial_half_extent)
	return distance.x<extent and distance.y<extent and distance.z<extent
