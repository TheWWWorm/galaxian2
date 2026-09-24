extends "res://tests/tractor_recovery.gd"
## Focused, detached recovery vectors using real source declarations and item
## rows. The paid fitted-flight application test separately earns player cargo.

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected identified Mac content, bindings and visuals")
	else:
		var library:=Library.new();var source:=Bindings.new();cat=Catalogues.new()
		if not library.open(args[0]) or not source.open(args[1],library.manifest) or not cat.open(library):
			check(false,library.error+source.error+cat.error)
		elif not Definitions.available(source):
			var unavailable:=Recovery.new()
			check(not unavailable.configure(source,cat,{"base_content_id":source.base_content_id,
				"binding_id":source.binding_id,"ship_id":0,"equipment_ids":[68,81]}),
				"An earlier binding pack silently gained an unverified tractor")
		else:
			rules=source
			verify_missing_device()
			verify_repeat_pickup()
	print("Container pickup: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_missing_device() -> void:
	var absent:=owner([90,81])
	var wreck:=scenery_actor(0,Vector3(0,0,1300))
	check(absent.snapshot().equipment_id==-1 and not absent.queue_acquired_wreck(wreck),
		"A scanner and drill without a fitted tractor acquired scenery cargo")
	check(absent.acquire(1,[marker()],gates()) and absent.snapshot().request_actor_id==-1
		and absent.snapshot().frame.events==[{"kind":"notification","source_id":9,"actor_id":0}],
		"A missing tractor lost its original device notice")

func verify_repeat_pickup() -> void:
	var tractor:=owner([68,81])
	var first:=scenery_actor(0,Vector3(0,0,1300))
	var second:=scenery_actor(1,Vector3(0,0,1100))
	var inventory:=hold(20,0,[])
	check(tractor.acquire(100,[marker(7)],gates())
		and tractor.snapshot().candidate_actor_id==7 and tractor.snapshot().elapsed_ms==100,
		"The preceding NPC scan did not retain its independent candidate")
	if failures:return
	var npc_before: Dictionary=tractor.snapshot()
	inventory=collect(tractor,first,inventory)
	if inventory.is_empty():return
	check(tractor.snapshot().request_actor_id==-1 and tractor.snapshot().current_actor_id==-1
		and tractor.snapshot().transfer_serial==1 and tractor.snapshot().candidate_actor_id==npc_before.candidate_actor_id
		and tractor.snapshot().elapsed_ms==npc_before.elapsed_ms,
		"Scenery pickup left a request behind or discarded the unrelated NPC clock")
	check(not tractor.queue_acquired_wreck(first),"A consumed container could be queued again")
	check(tractor.acquire(0,[],gates()) and tractor.snapshot().candidate_actor_id==-1,
		"Looking away failed to clear the previous NPC candidate")
	if failures:return
	inventory=collect(tractor,second,inventory)
	if inventory.is_empty():return
	check(tractor.snapshot().transfer_serial==2 and tractor.snapshot().request_actor_id==-1
		and tractor.snapshot().current_actor_id==-1 and inventory.used==4
		and inventory.entries==[{"item_id":118,"quantity":4}],
		"A second container could not be targeted and collected after the first")
	check(not tractor.queue_acquired_wreck(first) and not tractor.queue_acquired_wreck(second),
		"A consumed container remained recoverable after retargeting")

func collect(tractor: RefCounted,wreck: Dictionary,inventory: Dictionary) -> Dictionary:
	if not tractor.queue_acquired_wreck(wreck) or not tractor.advance(0,player(),wreck,inventory):
		check(false,tractor.error);return {}
	check(tractor.snapshot().frame.phase=="started" and tractor.snapshot().request_group=="scenery",
		"Acquired scenery skipped the next-player-phase tractor start")
	if failures:return {}
	if not tractor.advance(100,player(),wreck,inventory):check(false,tractor.error);return {}
	var pull: Dictionary=tractor.snapshot().frame
	check(pull.phase=="pulling" and pull.actor_changes.has("cargo_pose"),
		"A distant container jumped into the hold without its original pull")
	if failures:return {}
	wreck.merge(pull.actor_changes,true)
	if not tractor.advance(0,player(),wreck,inventory):check(false,tractor.error);return {}
	var pickup: Dictionary=tractor.snapshot().frame
	check(pickup.phase=="pickup" and pickup.transfer.accepted_quantity==2
		and pickup.transfer.serial==tractor.snapshot().transfer_serial,
		"The pulled container was not accepted exactly once")
	if failures:return {}
	wreck.merge(pickup.actor_changes,true)
	var next:=inventory.duplicate(true)
	next.entries=pickup.transfer.inventory_entries.duplicate(true)
	next.used=int(pickup.transfer.used)
	return next

func scenery_actor(id: int,position: Vector3) -> Dictionary:
	var value:=actor(id,position)
	value.target_group="scenery"
	value.actor_kind=-1
	value.active=false
	value.statistics_exempt=true
	value.retire_on_transfer=true
	value.cargo_entries=[{"item_id":118,"quantity":2}]
	return value
