extends RefCounted
## One native side-mission slot, independent of the retained story objective.
## Generated contacts are supplied by the lounge owner. Acceptance stages cargo
## and fees together. Delivery results require the destination inventory and
## acknowledgement; ordinary contract travel and combat have separate owners.
const Difficulty=preload("res://src/content/difficulty_definitions.gd")
const Readonly=preload("res://src/simulation/readonly_state.gd")
const Definitions=preload("res://src/content/early_contract_definitions.gd")
const Offer=preload("res://src/simulation/contract_offer.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Contacts=preload("res://src/simulation/lounge_contacts.gd")
const Career=preload("res://src/simulation/opening_handoff.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Delivery=preload("res://src/content/delivery_result_definitions.gd")
const FlightResults=preload("res://src/content/contract_flight_result_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const LoungeCache=preload("res://src/simulation/lounge_cache.gd")
const LoungeLifecycle=preload("res://src/content/lounge_lifecycle_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Story=preload("res://src/content/lounge_story_definitions.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Bakka=preload("res://src/content/bakka_contest_definitions.gd")
const Dekato=preload("res://src/content/dekato_convoy_definitions.gd")
const OrdinaryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
const VoidSource=preload("res://src/simulation/ordinary_void_source.gd")
const VoidAccess=preload("res://src/content/void_access_definitions.gd")
const Blueprints=preload("res://src/simulation/blueprint_progress.gd")
const ContractProgress=preload("res://src/simulation/contract_progress.gd")
const Wingmen=preload("res://src/simulation/wingman_contract.gd")
const Recipe=preload("res://src/content/mission_recipe.gd")
const BaseMedals=preload("res://src/simulation/base_medal_progress.gd")
const EliteMedals=preload("res://src/simulation/elite_medal_progress.gd")
const StoryFlights=preload("res://src/content/valkyrie_flight_definitions.gd")
const Valkyrie=preload("res://src/content/valkyrie_campaign_definitions.gd")
const Wanted=preload("res://src/simulation/wanted_board.gd")
const FrameTransaction=preload("res://src/simulation/frame_transaction.gd")
var error:=""
var _txn:=0
var _state:={}
var _rules:={}
var _cabins:={}
var _progress_rules:={}
var _stations:=[]
var _result_inventory:={}
var _flight:={}
var _pending_flight:={}
var _flight_identity: RefCounted
var _lounges: RefCounted
var _catalogues: RefCounted
var _void_source: RefCounted
var _blueprints: RefCounted
var _selected40_entry: RefCounted
var _shopping_booze_quantity:=-1

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Definitions.acceptance_parameters(bindings.early_contracts)

func configure(bindings: RefCounted,catalogues: RefCounted,station: Dictionary,equipment: RefCounted,difficulty: float) -> bool:
	error=""
	if not _state.is_empty():return reject("Retain the current contract session instead of resetting it")
	if not available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:return reject("Contract acceptance is unavailable for this content")
	if not bindings.bind_catalogues(catalogues):return reject(bindings.error)
	if not Difficulty.valid(difficulty):return reject("The game difficulty is invalid")
	var terms: Dictionary=bindings.early_contracts
	var visit: Dictionary=bindings.mido_travel.get("return_visit",{})
	var gate: Dictionary=visit.get("contract_gate",{})
	if gate.is_empty() or station.get("phase")!="contracts_required" or station.get("campaign_cursor")!=int(terms.first_cursor) or not station.get("local_visit_acknowledged",false) or not station.get("acknowledged",false):return reject("Acknowledge the lounge introduction before opening contracts")
	if station.get("base_content_id")!=bindings.base_content_id or station.get("binding_id")!=bindings.binding_id or not equipment is Equipment:return reject("Contracts require the retained station inventory and content identity")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or not equipment.cargo_cache_valid() or owned.get("loadout")!=station.get("loadout") or owned.get("cargo")!=station.get("cargo"):return reject("Contracts lost the earned ship or cargo")
	if owned.loadout.station_id!=int(visit.station_id) or owned.loadout.system_id!=int(terms.system_id):return reject("The first lounge belongs to the Kernstal return")
	var progress: Dictionary=station.get("progress",{})
	if progress.get("campaign_cursor")!=int(terms.first_cursor) or not progress.get("rank") is int or not Reputation.valid_state(progress.get("reputation")):return reject("Contracts require the retained career")
	var mission: Dictionary=station.get("mission",{})
	if mission.get("kind")!=int(visit.next_kind) or station.get("completed_side_missions")!=int(gate.initial_completed_count) or mission.get("completed_contract_target")!=int(gate.initial_completed_count)+int(gate.additional_completions):return reject("The first lounge lost its pending story requirement")
	var cabins:=cabin_catalogue(catalogues,terms.acceptance)
	if cabins.is_empty():return reject("The catalogue has no supported passenger cabins")
	_rules=terms.duplicate(true);_cabins=cabins;_catalogues=catalogues
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"campaign_cursor":int(terms.first_cursor),"station_id":owned.loadout.station_id,
		"rank":progress.rank,"reputation":progress.reputation.duplicate(true),"difficulty":difficulty,
		"credits":int(terms.acceptance.initial_credits),"passengers":int(terms.acceptance.initial_passengers),
		"mission":{},"active_offer_id":-1,"offers":{},"conversations":0,"rejected_jobs":0}
	if Definitions.delivery_parameters(terms):
		_progress_rules=bindings.opening_handoff.duplicate(true)
		_stations=catalogues.tables.systems[int(terms.system_id)].station_ids.duplicate()
		_state.progress=progress.duplicate(true)
		_state.completed_side_missions=station.completed_side_missions
		_state.delivery_statistics={"cargo":0,"passengers":0}
		_state.pending_result={};_state.result_serial=0
		if Junk.available(bindings):_state.progress.debris_destroyed=int(terms.junk_lifecycle.initial_debris_destroyed)
	if terms.has("world_initialization"):_state.accepted_contact={}
	if GateArrival.available(bindings):_state.travel_statistics={"jumpgates_used":int(bindings.mido_travel.gate_arrival.career.initial_jumpgates_used)}
	if _state.has("travel_statistics") and not retain_location_visit(int(owned.loadout.station_id),int(owned.loadout.system_id)):return false
	if LoungeLifecycle.available(bindings):
		_lounges=LoungeCache.new()
		if not _lounges.configure(bindings):return reject(_lounges.error)
	return settle_base_medals()

func settle_base_medals() -> bool:
	if _state.is_empty() or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Medals require an acknowledged station career")
	if not _bank_medals(_state):return reject("The station lost its earned medal evidence")
	return true

## Each newly reached tier pays its original reward and queues a notice. The
## first observation of a career is its baseline, not a new award.
func _bank_medals(state: Dictionary) -> bool:
	var previous: Dictionary=state.get("base_medals",{})
	# Extreme (hardcore) careers earn medals without their credit rewards.
	var paid: bool=float(state.get("difficulty",Difficulty.NORMAL))!=Difficulty.EXTREME
	var retained:=LoungeCache.Medals.commit(previous,state,blueprint_state())
	if retained.is_empty():return false
	if not previous.is_empty():
		var notices: Array=state.get("medal_notices",[]).duplicate()
		for id in retained.levels.size():
			var level: int=retained.levels[id];var prior: int=previous.levels[id]
			if level>0 and (prior<=0 or level<prior):
				notices.append([id,level])
				if paid and state.has("credits"):state.credits=mini(int(state.credits)+LoungeCache.Medals.reward_credits(level),2147483647)
		if not notices.is_empty():state.medal_notices=notices
	state.base_medals=retained
	return EliteMedals.bank(state,[],LoungeCache.Medals.reward_credits(EliteMedals.GOLD) if paid else 0)

## Add-on medals reached in flight or at docking (see elite_medal_progress.gd).
func record_elite_medals(reached: Array) -> bool:
	error=""
	if _state.is_empty():return reject("Add-on medals require a station career")
	var reward: int=LoungeCache.Medals.reward_credits(EliteMedals.GOLD) if float(_state.get("difficulty",Difficulty.NORMAL))!=Difficulty.EXTREME else 0
	if not EliteMedals.bank(_state,reached,reward):return reject("Add-on medal evidence is invalid")
	return true

func acknowledge_medal_notice() -> bool:
	var notices: Array=_state.get("medal_notices",[])
	if notices.is_empty():return reject("No medal notice is waiting")
	notices=notices.slice(1)
	if notices.is_empty():_state.erase("medal_notices")
	else:_state.medal_notices=notices
	return true

## Station-observed medal stats. Counters add; hull keeps the lowest arrival
## percentage and the other maxima keep the highest value seen.
func record_stats(observed: Dictionary) -> bool:
	error=""
	if _state.is_empty():return reject("Career stats require a station career")
	var stats: Dictionary=_state.get("stats",{}).duplicate()
	for key in observed:
		var value: int=int(observed[key])
		if key in ["play_ms","cloak_ms","alien_remains","unarmed_departures","accepted_jobs"]:
			if value>0:stats[key]=mini(int(stats.get(key,0))+value,2147483647)
		elif key in ["max_primaries","max_free_cargo"]:
			if value>int(stats.get(key,0)):stats[key]=value
		elif key=="min_arrival_hull_percent":
			var current: int=int(stats.get(key,-1))
			if value>=0 and value<=100 and (current<0 or value<current):stats[key]=value
		else:return reject("Unknown career stat")
	if not LoungeCache.Medals.valid_stats(stats):return reject("Career stats are out of range")
	_state.stats=stats
	return settle_base_medals() if _flight.is_empty() and _pending_flight.is_empty() and _state.get("pending_result",{}).is_empty() else true

func retain_asteroid_destruction_total(total: int) -> bool:
	error=""
	if _state.is_empty() or _flight.is_empty():return reject("Asteroid destruction progress requires the retained living flight")
	var current:=int(_state.get("progress",{}).get("asteroids_destroyed",0))
	if not Numbers.integer(total,current,2147483647):return reject("Asteroid destruction progress regressed or exceeded the supported career range")
	if total>0 or _state.progress.has("asteroids_destroyed"):_state.progress.asteroids_destroyed=total
	return true

## The secondary owner reports its cumulative count within this flight. Retain
## only the new committed kind-7 blasts so repeated polling and docking remain
## idempotent while the career keeps the lifetime total.
func retain_nuclear_bomb_detonations(observed: int) -> bool:
	error=""
	if _state.is_empty() or _flight.is_empty():return reject("Nuclear Armament progress requires the retained living flight")
	var retained: Variant=_flight.get("nuclear_bomb_detonations",0)
	if not Numbers.integer(retained,0,2147483647) or not Numbers.integer(observed,int(retained),2147483647):return reject("Nuclear bomb detonation history regressed or exceeded the supported flight range")
	var current: Variant=_state.get("progress",{}).get("nuclear_bomb_detonations",0)
	var delta:=observed-int(retained)
	if not Numbers.integer(current,0,2147483647) or delta>2147483647-int(current):return reject("Nuclear Armament progress exceeds the supported career range")
	if delta>0 or _state.progress.has("nuclear_bomb_detonations"):_state.progress.nuclear_bomb_detonations=int(current)+delta
	_flight.nuclear_bomb_detonations=observed
	return true

func complete_story_wait(bindings: RefCounted,story_mission: Dictionary) -> bool:
	# Stage this on the station's fork. The caller publishes it only when the
	# final original story line is acknowledged. A side job can remain accepted.
	error=""
	if not Story.available(bindings) or not Travel.parameters(bindings.mido_travel):return reject("The contract story continuation is unavailable")
	var rules: Dictionary=bindings.mido_travel.contract_completion
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Resolve the current flight or result before the station conversation")
	if _state.get("base_content_id")!=bindings.base_content_id or _state.get("binding_id")!=bindings.binding_id or _state.get("campaign_cursor")!=int(rules.campaign_cursor):return reject("The story continuation belongs to another career")
	if not Travel.navigation_mission(bindings.mido_travel,int(rules.campaign_cursor),story_mission):return reject("The original contract requirement is missing")
	if not Numbers.integer(_state.get("completed_side_missions"),0,2147483647) or _state.completed_side_missions<int(story_mission.completed_contract_target):return reject("Complete the additional required contracts before continuing the story")
	var progress: Dictionary=_state.get("progress",{})
	if progress.get("campaign_cursor")!=_state.campaign_cursor:return reject("The story and retained career disagree")
	var earned:=Career.calculate_progress(_progress_rules,int(rules.next_cursor),progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty():return reject("The story continuation exceeds the supported career range")
	_state.campaign_cursor=int(rules.next_cursor);_state.progress.merge(earned,true);_state.rank=earned.rank
	return true

func retain_mining_hint(seen: bool) -> void:
	_state.progress.mining_failure_hint_seen=seen

## Adds hint windows the player has seen to the career (saved progress "hints_seen").
func record_hints(seen: Array) -> bool:
	error=""
	if _state.is_empty() or not _state.get("progress") is Dictionary:return reject("Hints require a station career")
	var merged: Array=preload("res://src/simulation/flight_hints.gd").merge_seen(_state.progress.get("hints_seen",[]),seen)
	if merged.is_empty() and seen.is_empty():return true
	if merged.is_empty():return reject("Hint history is invalid")
	_state.progress.hints_seen=merged
	return true

func register_offer(offer_id: int,offer: RefCounted) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before changing lounge offers")
	if _state.is_empty() or offer_id<0 or not offer is Offer:return reject("A generated lounge contact needs a verified offer")
	if not _state.get("pending_result",{}).is_empty():return reject("Acknowledge the current result before changing lounge offers")
	var quote: Dictionary=offer.snapshot()
	if quote.is_empty() or quote.base_content_id!=_state.base_content_id or quote.binding_id!=_state.binding_id:return reject("The offer belongs to another content identity")
	for key in ["campaign_cursor","station_id","rank","reputation"]:
		if quote.context[key]!=_state[key]:return reject("The offer no longer matches the station career")
	if _state.has("population") and not _state.offers.has(offer_id):return reject("This generated lounge has no such contract contact")
	if _state.offers.has(offer_id):
		if _state.offers[offer_id].offer!=quote:return reject("A retained contact cannot change its offer")
		return true
	_state.offers[offer_id]={"offer":quote,"consumed":false}
	return true

## Stage only on the enclosing flight transaction's detached career. Changing
## the selected world does not complete the story or settle the independent job.
func rebase_bakka_target(bindings: RefCounted,equipment: RefCounted,context: Dictionary,progress: Dictionary) -> bool:
	error=""
	if not Bakka.context_valid(bindings,context) or _state.is_empty():return reject("B'akka target career is unavailable")
	var mission: Dictionary=bindings.mido_travel.bakka_contest.mission
	var source: Dictionary=bindings.mido_travel.get("gakkrr_visit",{}).get("mission35",{})
	if source.is_empty():return reject("B'akka target requires its Ga'kkrr prerequisite")
	if progress!=_state.get("progress",{}) or context.rank!=_state.get("rank") or context.difficulty!=_state.get("difficulty"):return reject("B'akka target changed retained progress, rank or difficulty")
	if not equipment is Equipment or not equipment.cargo_cache_valid():return reject("B'akka target requires its relocated retained inventory")
	var loadout: Dictionary=equipment.snapshot().loadout
	for key in ["base_content_id","binding_id"]:
		if loadout.get(key)!=bindings.get(key):return reject("B'akka target inventory belongs to another content identity")
	if loadout.get("station_id")!=int(mission.station_id) or loadout.get("system_id")!=int(mission.system_id):return reject("B'akka target inventory is at another location")
	var cursor:=int(mission.campaign_cursor)
	return _retain_story_progress(bindings,progress,cursor,cursor,int(source.station_id),int(mission.station_id),true)

## The enclosing story result owns success and the final modal acknowledgement.
## This detached ledger step cannot pay a job or award a second completion.
func advance_bakka_story(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not Bakka.available(bindings) or _state.is_empty():return reject("B\'akka result continuation is unavailable")
	var mission: Dictionary=bindings.mido_travel.bakka_contest.mission
	var cursor:=int(mission.campaign_cursor)
	return _retain_story_progress(bindings,progress,cursor,cursor+1,int(mission.station_id),int(mission.station_id),false)

## Docking retains subsequent flight counters without another story advance,
## reward, side-job settlement or location regeneration.
func retain_bakka_return_progress(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not Bakka.available(bindings) or _state.is_empty():return reject("B'akka return career is unavailable")
	var mission: Dictionary=bindings.mido_travel.bakka_contest.mission
	var cursor:=int(mission.campaign_cursor)+1
	return _retain_story_progress(bindings,progress,cursor,cursor,int(mission.station_id),int(mission.station_id),false)

## Only the enclosing native result transaction publishes the final Next.
## The independent delivery, wallet, locations and Void owners remain retained.
func advance_dekato_story(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not Dekato.available(bindings) or _state.is_empty():return reject("Dekato result continuation is unavailable")
	var rules: Dictionary=Dekato.declarations(bindings)
	return _retain_story_progress(bindings,progress,int(rules.mission.campaign_cursor),int(rules.next_mission.campaign_cursor),int(rules.mission.station_id),int(rules.mission.station_id),false)

func advance_mission_story(bindings: RefCounted,context: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not is_instance_of(context,load("res://src/simulation/mission_context.gd")) or _state.is_empty():return reject("Mission acknowledgement requires its retained career and entry")
	var recipe: Dictionary=context.recipe()
	if recipe.is_empty():return reject("Mission acknowledgement lost its recipe")
	return _retain_story_progress(bindings,progress,recipe.cursor,recipe.next_cursor,recipe.station_id,recipe.station_id,false)

## Reading the living flight's career incorporates its native combat counters
## without another acknowledgement, payment, relocation or generated contact.
func retain_dekato_progress(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not Dekato.available(bindings) or _state.is_empty():return reject("Dekato retained career is unavailable")
	var rules: Dictionary=Dekato.declarations(bindings)
	var cursor: int=int(_state.get("campaign_cursor",-1))
	if cursor not in [int(rules.mission.campaign_cursor),int(rules.next_mission.campaign_cursor)]:return reject("Dekato cannot retain another chapter's progress")
	return _retain_story_progress(bindings,progress,cursor,cursor,int(rules.mission.station_id),int(rules.mission.station_id),false)

func advance_capture_story(bindings: RefCounted,progress: Dictionary,next_cursor: int) -> bool:
	# Only the station transaction calls this after live capture or final dialogue
	# acknowledgement. Retain the independent job, wallet and historical contacts.
	error=""
	var definitions=load("res://src/content/alioth_arrival_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth story continuation is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_arrival
	var previous:=int(rules.departing_cursor) if next_cursor==int(rules.campaign_cursor) else int(rules.campaign_cursor)
	if next_cursor not in [int(rules.campaign_cursor),int(rules.next_cursor)]:return reject("The capture story has no such continuation")
	var relocated:=previous==int(rules.departing_cursor)
	return _retain_story_progress(bindings,progress,previous,next_cursor,int(rules.from_station_id) if relocated else int(rules.station_id),int(rules.station_id),relocated)

func advance_alioth_story(bindings: RefCounted,progress: Dictionary,next_cursor: int) -> bool:
	error=""
	var definitions=load("res://src/content/alioth_return_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth return is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_return
	if next_cursor not in [int(rules.campaign_cursor),int(rules.next_cursor)]:return reject("The Alioth return has no such continuation")
	return _retain_story_progress(bindings,progress,next_cursor-1,next_cursor,int(rules.station_id),int(rules.station_id),false)

## Sahi's first portal advances24; subsequent flight results advance25/26.
## The return portal only relocates the already advanced26 career.
func advance_sahi_story(bindings: RefCounted,progress: Dictionary,next_cursor: int=25) -> bool:
	error=""
	var post=load("res://src/content/post_sahi_definitions.gd")
	if next_cursor not in [25,26,27,29,30] or not post.available(bindings) or _state.is_empty():return reject("The portal continuation is unavailable")
	if next_cursor in [29,30] and not post.portal_available(bindings.mido_travel,next_cursor):return reject("The expedition continuation is unavailable")
	var from_station:=-1 if next_cursor in [26,30] else 91 if next_cursor==29 else 48
	return _retain_story_progress(bindings,progress,next_cursor-1,next_cursor,from_station,48 if next_cursor==27 else -1,next_cursor in [25,29])

func return_from_void(bindings: RefCounted,progress: Dictionary,cursor:=26) -> bool:
	error=""
	if bindings==null or cursor not in [26,30] or not load("res://src/content/post_sahi_definitions.gd").portal_available(bindings.mido_travel,cursor) or _state.is_empty():return reject("The Void return is unavailable")
	return _retain_story_progress(bindings,progress,cursor,cursor,-1,91 if cursor==30 else 48,true)

## The flight owns living portal contact; this detached career transaction only
## carries its earned counters and existing job between the two retained places.
func transfer_ordinary_void(bindings: RefCounted,progress: Dictionary,source: RefCounted,entering: bool) -> bool:
	error=""
	var route: Dictionary=load("res://src/simulation/mission_context.gd").ordinary_void_route(bindings,source)
	if route.is_empty():return reject("Ordinary Void travel requires its admitted return route")
	if source is VoidSource and (_void_source==null or source.snapshot()!=_void_source.snapshot()):return reject("The portal changed the career's retained source")
	if _lounges==null or _lounges.selection_state().current_station_id!=route.source_station_id:return reject("The Void visit lost its retained ordinary location")
	return _retain_story_progress(bindings,progress,route.campaign_cursor,route.campaign_cursor,int(route.source_station_id) if entering else -1,-1 if entering else int(route.source_station_id),true)

## Leaving the alien world moves the story on and to its next station (79:
## the way out leads to Kothar at 80).
func leave_void_for_story(bindings: RefCounted,progress: Dictionary,source: RefCounted,cursor: int,station_id: int) -> bool:
	error=""
	var route: Dictionary=load("res://src/simulation/mission_context.gd").ordinary_void_route(bindings,source)
	if route.is_empty():return reject("Ordinary Void travel requires its admitted return route")
	if _lounges==null or _lounges.selection_state().current_station_id!=route.source_station_id:return reject("The Void visit lost its retained ordinary location")
	return _retain_story_progress(bindings,progress,route.campaign_cursor,cursor,-1,station_id,true)

## Keep the independent job and final combat counters while the world changes.
var _station_context: RefCounted

func station_context_owner() -> RefCounted:return _station_context

func enter_mission_station(bindings: RefCounted,cat: RefCounted,library: RefCounted,entry: RefCounted,equipment: RefCounted,settings: Dictionary,unix_seconds: Variant) -> bool:
	if not is_instance_of(entry,load("res://src/simulation/mission_station_return.gd")) or not entry.matches_source_career(self):return reject("Station continuation requires its actual retained career")
	var context: RefCounted=entry.context_owner();var destination: Dictionary=context.snapshot()
	if not context.permits(bindings,_state.campaign_cursor,destination.station_id,context) or equipment.snapshot().loadout.station_id!=destination.station_id:return reject("Station continuation lost its career or inventory location")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _result_inventory.is_empty() or not _state.pending_result.is_empty():return reject("Station continuation cannot discard an unresolved independent result")
	if not select_location(bindings,cat,library,destination.station_id,settings,entry.source_random(),unix_seconds,context):return false
	if not _adopt_station(destination.station_id):return false
	if _state.has("travel_statistics") and not retain_location_visit(int(destination.station_id),int(destination.system_id)):return false
	_state.erase("location_generation_pending");_station_context=context
	return settle_base_medals()

func transfer_mission_return(bindings: RefCounted,entry: RefCounted) -> bool:
	error=""
	if not is_instance_of(entry,load("res://src/simulation/mission_portal_return.gd")) or not entry.matches_source_career(self):return reject("The return lost its actual retained career")
	var source: Dictionary=entry.source_observation()
	if source.is_empty() or _lounges==null or _lounges.selection_state().current_station_id!=source.return_station_id:return reject("The return lost its retained normal-space location history")
	return _retain_story_progress(bindings,source.progress,source.campaign_cursor,source.campaign_cursor,-1,source.return_station_id,true)

func retain_sahi_return_progress(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	if not load("res://src/content/post_sahi_definitions.gd").available(bindings) or _state.is_empty():return reject("The Sahi return is unavailable")
	return _retain_story_progress(bindings,progress,27,27,48,48,false)

func retain_alioth_return_progress(bindings: RefCounted,progress: Dictionary) -> bool:
	error=""
	var definitions=load("res://src/content/alioth_return_definitions.gd")
	if not definitions.available(bindings) or _state.is_empty():return reject("The Alioth return is unavailable")
	var rules: Dictionary=bindings.mido_travel.alioth_return
	return _retain_story_progress(bindings,progress,int(rules.campaign_cursor),int(rules.campaign_cursor),int(rules.station_id),int(rules.station_id),false)

func _retain_story_progress(bindings: RefCounted,progress: Dictionary,previous: int,next_cursor: int,from_station: int,to_station: int,relocated: bool) -> bool:
	if _state.campaign_cursor!=previous or progress.get("campaign_cursor")!=previous:return reject("The story is stale or already acknowledged")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("The story cannot discard an unresolved contract result")
	if bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id:return reject("The story career belongs to another content identity")
	if _state.station_id!=from_station:return reject("The story career is at another station")
	var current:=Career.calculate_progress(_progress_rules,previous,progress.get("player_kills"),progress.get("pirate_kills"),progress.get("other_score"))
	if current.is_empty() or not Reputation.valid_state(progress.get("reputation")):return reject("The capture lost its earned career")
	for key in current:
		if progress.get(key)!=current[key]:return reject("The capture career counters disagree")
	for key in ["player_kills","pirate_kills","other_score","debris_destroyed","capital_ship_kills","cargo_recovered","asteroids_destroyed","mined_ore_tons","mined_cores","nuclear_bomb_detonations","purchased_booze_quantity"]:
		if not Numbers.integer(progress.get(key,0),int(_state.progress.get(key,0)),2147483647):return reject("The capture lost a retained career counter")
	for key in ["mined_ore_types_mask","mined_core_types_mask","booze_types_mask"]:
		var previous_mask:=int(_state.progress.get(key,0));var next_mask: Variant=progress.get(key,0)
		var maximum:=BaseMedals.BOOZE_TYPE_MASK if key=="booze_types_mask" else 2047
		if not Numbers.integer(next_mask,0,maximum) or (int(next_mask) & previous_mask)!=previous_mask:return reject("The capture lost retained type history")
	var earned:=Career.calculate_progress(_progress_rules,next_cursor,current.player_kills,current.pirate_kills,current.other_score)
	if earned.is_empty():return reject("The Alioth story exceeds the supported career range")
	var source: RefCounted=_void_source
	var blueprints: RefCounted=_blueprints
	if next_cursor==28 and previous==27 and VoidAccess.parameters(bindings.mido_travel.get("void_access")):
		if _lounges==null:return reject("The Void source requires retained locations")
		source=VoidSource.new()
		if not source.configure_fresh(bindings,_catalogues,_lounges.selection_state().system_availability):return reject(source.error)
		blueprints=Blueprints.new()
		if not blueprints.configure(_catalogues,bindings.binding_id):return reject(blueprints.error)
	var next:=progress.duplicate(true);next.merge(earned,true)
	_state.campaign_cursor=next_cursor;_state.progress=next;_state.rank=next.rank
	_state.reputation=next.reputation.duplicate(true);_state.station_id=to_station
	_void_source=source
	_blueprints=blueprints
	if relocated:
		_state.offers={};_state.erase("population");_state.location_generation_pending=true
	return true

func populate(bindings: RefCounted,cat: RefCounted,library: RefCounted,random_state: Variant,history: Variant) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before opening another lounge")
	if _state.is_empty() or not _state.offers.is_empty() or _state.has("population"):return reject("Retain the existing contacts instead of regenerating their offers")
	if bindings==null or bindings.base_content_id!=_state.base_content_id or bindings.binding_id!=_state.binding_id:return reject("The lounge population belongs to another content identity")
	var context:={}
	for key in ["campaign_cursor","station_id","rank","reputation"]:context[key]=_state[key]
	var contacts:=Contacts.new()
	if not contacts.prepare(bindings,cat,library,context,random_state,history):return reject(contacts.error)
	var population: Dictionary=contacts.snapshot()
	var next: RefCounted=fork()
	for contact in population.contacts:
		if contact.offer.is_empty():continue
		var offer:=Offer.new()
		if not offer.restore(bindings,cat,contact.offer) or not next.register_offer(int(contact.contact_id),offer):return reject(offer.error+next.error)
	if next._lounges!=null:
		next._lounges=next._lounges.fork()
		if not next._lounges.remember(contacts):return reject(next._lounges.error)
	next._state.population=Readonly.freeze(population.duplicate(true))
	_state=next._state;_lounges=next._lounges
	return true

func retain_locations(cache: RefCounted) -> bool:
	# Opening selections can precede access to the lounge. Keep the historical
	# quotation context; accepting a retained job uses its original terms.
	error=""
	if _state.is_empty() or not _state.offers.is_empty() or _state.has("population") or not _flight.is_empty() or not cache is LoungeCache:return reject("Supply the opening's retained locations before populating contracts")
	var retained: Dictionary=cache.snapshot()
	for key in ["base_content_id","binding_id"]:
		if retained.get(key)!=_state[key]:return reject("The retained locations belong to another content identity")
	if retained.get("current_station_id")!=_state.station_id:return reject("The retained locations do not select the current station")
	var local: Dictionary=cache.location(_state.station_id)
	if local.is_empty() or not local.has("stock") or local.population.context.campaign_cursor>_state.campaign_cursor:return reject("The current station lacks its earlier generated stock and contacts")
	_lounges=cache.fork();_state.population=Readonly.freeze(local.population.duplicate(true));_state.offers=local.offers
	_state.erase("location_generation_pending")
	return true

func rebase_station(equipment: RefCounted,bindings: RefCounted=null) -> bool:
	# The caller must first accept actual docking and detach the flight ledger.
	# Rebase never generates contacts, consumes RNG, pays or advances the story.
	error=""
	if _lounges==null or not _flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Station contracts require retained flight and result ownership")
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return false
	var station: int=owned.loadout.station_id
	if not _adopt_station(station):return false
	if _state.has("travel_statistics") and not retain_location_visit(station,int(owned.loadout.system_id)):return false
	# Docking outside Loma ends its toll (assumed: the source clears on leaving).
	if int(owned.loadout.get("system_id",-1))!=preload("res://src/content/loma_toll_definitions.gd").SYSTEM_ID:_state.progress.erase("loma_toll")
	return settle_base_medals()

## Only the real local-arrival transaction uses this authored-world adapter.
## Generic station inventory/cache admission remains closed at pending38/22.
func rebase_dekato_arrival(bindings: RefCounted,equipment: RefCounted,arrival: Dictionary,mission: Dictionary) -> bool:
	error=""
	if not Dekato.source_arrival_available(bindings) or not equipment is Equipment or not equipment.cargo_cache_valid():return reject("Dekato arrival requires its explicit source and retained inventory")
	if _lounges==null or _void_source==null or _blueprints==null or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Retain the full career before entering the convoy")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return reject("The convoy arrival requires the completed equipment exchange")
	var seed: Dictionary=owned.loadout
	for key in ["base_content_id","binding_id"]:
		if seed.get(key)!=bindings.get(key) or _state.get(key)!=bindings.get(key) or arrival.get(key)!=bindings.get(key):return reject("The convoy arrival changed its source identity")
	var cursor: Variant=_state.get("campaign_cursor")
	if not Dekato.selected(bindings,cursor,mission,seed.get("station_id")) or arrival.get("campaign_cursor")!=cursor or _state.get("progress",{}).get("campaign_cursor")!=cursor:return reject("The convoy arrival lost its pending story")
	var trip:=Travel.route(bindings,cursor,int(_state.station_id),int(seed.station_id))
	if trip.is_empty() or seed.get("system_id")!=int(Dekato.declarations(bindings).mission.system_id):return reject("The convoy arrival is not a local source-defined journey")
	var expected:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	expected.merge(trip)
	for key in ["source_state","world_type","audio_selector"]:expected[key]=int(bindings.mido_travel.travel[key])
	for key in expected:
		if typeof(arrival.get(key))!=typeof(expected[key]):return reject("The convoy transit fields require their exact native types")
	if arrival!=expected or _lounges.selection_state().current_station_id!=seed.station_id or _lounges.location(seed.station_id).is_empty():return reject("The convoy arrival lost its actual transit or destination location")
	if not _adopt_station(int(seed.station_id)):return false
	if _state.has("travel_statistics") and not retain_location_visit(int(seed.station_id),int(seed.system_id)):return false
	return settle_base_medals()

func _adopt_station(station: int) -> bool:
	if station==_state.station_id:return true
	_state.station_id=station
	_state.offers={};_state.erase("population")
	var cached: Dictionary=_lounges.location(station)
	if not cached.is_empty():
		# A station already in the cache needs no fresh location generation
		# (a story move elsewhere may have left that pending: 155 -> jump to 99).
		_state.offers=cached.offers;_state.population=Readonly.freeze(cached.population.duplicate(true));_state.erase("location_generation_pending")
	return true

## The story undoes a visit (90: the 89 scene's stop at Naneroh); the
## visited-stations count drops with it.
func forget_location_visit(station_id: int) -> bool:
	error=""
	var statistics: Variant=_state.get("travel_statistics")
	if not GateArrival.valid_statistics(statistics):return reject("Location history requires retained travel statistics")
	if statistics.size()==1 or station_id not in statistics.visited_station_ids:return true
	var next: Dictionary=statistics.duplicate(true)
	next.visited_station_ids.erase(station_id)
	if not GateArrival.valid_statistics(next):return reject("Location history produced an invalid travel ledger")
	_state.travel_statistics=next
	return true

func retain_location_visit(station_id: int,system_id: int) -> bool:
	error=""
	var statistics: Variant=_state.get("travel_statistics")
	if not GateArrival.valid_statistics(statistics):return reject("Location history requires retained travel statistics")
	if station_id<0 or system_id<0:return reject("Location history cannot retain a negative station or system")
	var next: Dictionary=statistics.duplicate(true)
	if next.size()==1:
		next.visited_station_ids=[];next.visited_system_ids=[]
	for pair in [["visited_station_ids",station_id],["visited_system_ids",system_id]]:
		var ids: Array=next[pair[0]]
		if pair[1] not in ids:
			ids.append(pair[1]);ids.sort()
			next[pair[0]]=ids
	if not GateArrival.valid_statistics(next):return reject("Location history produced an invalid travel ledger")
	_state.travel_statistics=next
	return true

## The physically docked post-convoy career already owns this exact location.
## Do not regenerate it, admit a generic39 flight or settle its independent job.
func retain_dekato_station(bindings: RefCounted,equipment: RefCounted,receipt: Dictionary) -> bool:
	if _dekato_station_inventory(bindings,equipment,receipt).is_empty():return false
	if not _result_inventory.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("The Dekato station has an unresolved result")
	return true

func _dekato_station_inventory(bindings: RefCounted,equipment: RefCounted,receipt: Dictionary) -> Dictionary:
	error=""
	if not Dekato.source_receipt_matches(bindings,receipt) or not Dekato.station_supported(bindings,_state.get("campaign_cursor"),_state.get("station_id")):return fail("The Dekato station requires its explicit retained source")
	if not equipment is Equipment or not equipment.cargo_cache_valid() or _lounges==null or _void_source==null or _blueprints==null:return fail("The Dekato station lost its inventory, locations or Void career")
	if not _flight.is_empty() or not _pending_flight.is_empty():return fail("The Dekato station has an unresolved flight")
	var owned: Dictionary=equipment.snapshot();var seed: Dictionary=owned.loadout
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or seed.get(key)!=bindings.get(key):return fail("The Dekato station changed its original identity")
	if seed.station_id!=_state.station_id or seed.system_id!=int(Dekato.declarations(bindings).mission.system_id) or _state.progress.campaign_cursor!=_state.campaign_cursor or not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false):return fail("The Dekato station changed its acknowledged location or equipment")
	var current: Dictionary=_lounges.location(_state.station_id)
	if _lounges.selection_state().current_station_id!=_state.station_id or current.is_empty() or current.population!=_state.get("population") or current.offers!=_state.get("offers"):return fail("The Dekato station lost its retained contacts or stock")
	return owned

func poll_dekato_station(bindings: RefCounted,equipment: RefCounted,receipt: Dictionary) -> bool:
	var owned:=_dekato_station_inventory(bindings,equipment,receipt)
	return false if owned.is_empty() else _poll_station_results(owned,equipment)

func acknowledge_dekato_delivery(bindings: RefCounted,equipment: RefCounted,receipt: Dictionary) -> RefCounted:
	var owned:=_dekato_station_inventory(bindings,equipment,receipt)
	return null if owned.is_empty() else _acknowledge_delivery_inventory(equipment,owned)

func location_owner() -> RefCounted:
	return null if _lounges==null else _lounges.fork()

func locations_snapshot() -> Dictionary:return {} if _lounges==null else _lounges.snapshot()

func open_shopping(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,unix_seconds: Array,library: RefCounted=null) -> RefCounted:
	error=""
	if _shopping_booze_quantity>=0:return _shopping_reject("Close the current Hangar quote before opening another")
	var owned:=_shopping_inventory(bindings,cat,equipment)
	if owned.is_empty():return null
	if unix_seconds.size()!=3:return _shopping_reject("Supply the three station price timestamps")
	for value in unix_seconds:
		if not value is int or value<0:return _shopping_reject("Station price timestamps must be nonnegative integers")
	var Kaamo=preload("res://src/content/kaamo_club_definitions.gd")
	var storage: bool=_state.station_id==Kaamo.STATION_ID and Kaamo.state(_state.progress)==Kaamo.OWNED
	if storage:
		# The owned club's hangar is the player's storage (kept in the career).
		var kept: Dictionary=_state.progress.get("kaamo_storage",{"items":[],"ships":[]})
		var restored: RefCounted=_lounges.fork()
		if not restored.replace_item_stock(bindings,cat,_state.station_id,_lounges.item_stock(_state.station_id),kept.items) or not restored.replace_ship_stock(bindings,cat,_state.station_id,_lounges.ship_stock(_state.station_id),kept.ships):return _shopping_reject(restored.error)
		_lounges=restored
	var stock: Array=_lounges.item_stock(_state.station_id)
	var times:=unix_seconds.duplicate()
	if owned.cargo.entries.is_empty():times[0]=null
	if stock.is_empty():times[2]=null
	var inventory: RefCounted=equipment.fork()
	var receipt: Dictionary=inventory.open_ordinary_shopping(bindings,cat,stock,_lounges.snapshot().random,times,0,library)
	if receipt.is_empty():return _shopping_reject(inventory.error)
	var ship_percent:=int(_lounges.location(_state.station_id).stock.context.get("ship_price_percent",0))
	if not inventory.open_ship_market(bindings,cat,_lounges.ship_stock(_state.station_id),ship_percent):return _shopping_reject(inventory.error)
	if storage and not inventory.open_free_transfers():return _shopping_reject(inventory.error)
	if not storage and Kaamo.state(_state.progress)==Kaamo.OWNED:inventory.offer_kaamo_keep(_state.progress.get("kaamo_storage",{}).get("ships",[]).map(func(row):return int(row.ship_id)))
	var locations: RefCounted=_lounges.fork()
	if not locations.replace_item_stock(bindings,cat,_state.station_id,stock,inventory.snapshot().stock,receipt.random):return _shopping_reject(locations.error)
	var booze_quantity:=_booze_quantity(owned.cargo.entries)
	if booze_quantity<0:return _shopping_reject("The retained booze quantity exceeds the supported career range")
	_lounges=locations;_shopping_booze_quantity=booze_quantity
	return inventory

func transact_shopping(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,action: String,item_id: int,slot_index: int=-1,quantity: int=1) -> RefCounted:
	error=""
	var owned:=_shopping_inventory(bindings,cat,equipment)
	if owned.is_empty():return null
	if not owned.get("ordinary_shopping_open",false) or owned.stock!=_lounges.item_stock(_state.station_id):return _shopping_reject("Open the current station's hangar quote before trading")
	if _story_protects(bindings,owned,action,item_id,slot_index):return _shopping_reject("This item cannot be sold or demounted at the moment.")
	if action=="supply_blueprint":
		if _blueprints==null:return _shopping_reject("No blueprint is available")
		var shipping: int=_blueprints.shipping_cost(item_id,_state.station_id,quantity)
		if shipping<0 or shipping>_state.credits:return _shopping_reject("Insufficient credits for shipping these materials")
		var project: RefCounted=_blueprints.fork_for_transaction()
		var supplied: RefCounted=project.contribute(item_id,slot_index,quantity,equipment)
		if supplied==null:return _shopping_reject(project.error)
		_blueprints=project;_state.credits-=shipping
		return supplied
	var inventory: RefCounted=equipment.fork()
	var Kaamo=preload("res://src/content/kaamo_club_definitions.gd")
	if action in ["buy_ship","keep_ship"]:
		if owned.get("market_ships")!=_lounges.ship_stock(_state.station_id):return _shopping_reject("The station's ship quote changed")
		if action=="keep_ship" and (not owned.get("kaamo_keep") is Array or _state.progress.get("kaamo_storage",{}).get("ships",[]).any(func(row):return int(row.ship_id)==int(owned.loadout.ship_id))):return _shopping_reject("There is already a ship of this type at your station. The sale was cancelled.")
		var passengers: Variant=_state.get("passengers")
		if not Numbers.integer(passengers,0,2147483647) or passengers!=ContractProgress.occupied_passengers(_state):return _shopping_reject("Ship exchange lost the retained contract's passengers")
		if not inventory.purchase_ship(bindings,cat,item_id,_state.credits,passengers,action=="keep_ship"):return _shopping_reject(inventory.error)
	elif action=="sell_ship":
		if owned.get("market_ships")!=_lounges.ship_stock(_state.station_id):return _shopping_reject("The station's ship quote changed")
		if not inventory.sell_parked_ship(item_id,_state.credits):return _shopping_reject(inventory.error)
	elif action in ["mount","unmount","replace"]:
		# A retained delivery does not lock unrelated equipment. Its actual
		# passengers must reach the shared occupied-berth guard; never assume
		# an empty ship or discard the accepted mission to permit fitting.
		if not _state.mission.is_empty() and not OrdinaryContracts.retained_mission(bindings,_state.mission,int(_state.campaign_cursor)):return _shopping_reject("Fitting for this active contract is not yet supported")
		var passengers: Variant=_state.get("passengers")
		var expected_passengers: Variant=ContractProgress.occupied_passengers(_state)
		if not Numbers.integer(passengers,0,2147483647) or not Numbers.integer(expected_passengers,0,2147483647) or passengers!=expected_passengers:return _shopping_reject("Fitting lost the retained contract's passengers")
		if not inventory.fit(bindings,cat,action,item_id,slot_index,passengers):return _shopping_reject(inventory.error)
	elif not inventory.transact(action,item_id,_state.credits):return _shopping_reject(inventory.error)
	var accepted: Dictionary=inventory.snapshot()
	var locations: RefCounted=_lounges.fork()
	if not locations.replace_item_stock(bindings,cat,_state.station_id,owned.stock,accepted.stock):return _shopping_reject(locations.error)
	if action in ["buy_ship","keep_ship","sell_ship"] and not locations.replace_ship_stock(bindings,cat,_state.station_id,owned.market_ships,accepted.market_ships):return _shopping_reject(locations.error)
	var credits:=credit_balance(_state.credits,accepted.credit_delta,_rules.delivery_results)
	_lounges=locations;_state.credits=credits
	if accepted.get("free_transfers",false):_state.progress.kaamo_storage={"items":accepted.stock.duplicate(true),"ships":accepted.market_ships.duplicate(true)}
	elif action=="keep_ship":
		var kept: Dictionary=_state.progress.get("kaamo_storage",{"items":[],"ships":[]}).duplicate(true)
		kept.ships.append(accepted.kept_ship.duplicate(true));_state.progress.kaamo_storage=kept
	if action=="buy" and not _retain_booze_type(item_id):return _shopping_reject(error)
	return inventory

## The story keeps an item on board while the career is at its cursor (77:
## the Khador Drive Alice is about to take): it cannot be sold or demounted.
func _story_protects(bindings: RefCounted,owned: Dictionary,action: String,item_id: int,slot_index: int) -> bool:
	var ids: Array=Valkyrie.protected_items(bindings,_state.get("campaign_cursor"))
	if ids.is_empty() or action not in ["sell","unmount","replace"]:return false
	if action!="replace":return item_id in ids
	var slots: Array=owned.loadout.slots
	return slot_index>=0 and slot_index<slots.size() and slots[slot_index]!=null and int(slots[slot_index].item_id) in ids

func close_shopping(equipment: RefCounted) -> RefCounted:
	error=""
	if _shopping_booze_quantity<0 or not equipment is Equipment:return _shopping_reject("No retained Hangar transaction awaits closing")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("ordinary_shopping_open",false) or not owned.get("cargo",{}).get("entries") is Array:return _shopping_reject("The retained Hangar transaction lost its cargo")
	var observed:=_booze_quantity(owned.cargo.entries)
	if observed<0:return _shopping_reject("The retained booze quantity exceeds the supported career range")
	var current: Variant=_state.get("progress",{}).get("purchased_booze_quantity",0)
	var gained:=maxi(0,observed-_shopping_booze_quantity)
	if not Numbers.integer(current,0,2147483647) or gained>2147483647-int(current):return _shopping_reject("Personal Need progress exceeds the supported career range")
	var inventory: RefCounted=equipment.fork()
	if not inventory.close_ordinary_shopping():return _shopping_reject(inventory.error)
	if gained>0 or _state.progress.has("purchased_booze_quantity"):_state.progress.purchased_booze_quantity=int(current)+gained
	_shopping_booze_quantity=-1
	if not settle_base_medals():return null
	return inventory

func _retain_booze_type(item_id: int) -> bool:
	var bit:=BaseMedals.booze_type_bit(item_id)
	if bit==0:return true
	var current: Variant=_state.get("progress",{}).get("booze_types_mask",0)
	if not Numbers.integer(current,0,BaseMedals.BOOZE_TYPE_MASK):return reject("Barkeeper type history exceeds the supported source domain")
	_state.progress.booze_types_mask=int(current) | bit
	return true

static func _booze_quantity(entries: Array) -> int:
	var total:=0
	for entry in entries:
		if not entry is Dictionary:continue
		if BaseMedals.booze_type_bit(int(entry.get("item_id",-1)))==0:continue
		var quantity: Variant=entry.get("quantity")
		if not quantity is int or quantity<0 or total>2147483647-int(quantity):return -1
		total+=int(quantity)
	return total

func collect_blueprint_products(equipment: RefCounted) -> RefCounted:
	error=""
	if _blueprints==null:return equipment.fork()
	if not equipment is Equipment or equipment.snapshot().loadout.station_id!=_state.station_id:return _shopping_reject("Blueprint collection lost its station")
	var project: RefCounted=_blueprints.fork_for_transaction()
	var inventory: RefCounted=project.collect(equipment)
	if inventory==null:return _shopping_reject(project.error)
	_blueprints=project
	return inventory

func _shopping_inventory(bindings: RefCounted,cat: RefCounted,equipment: RefCounted) -> Dictionary:
	if not equipment is Equipment or _lounges==null or not Campaign.supported(bindings,_state.get("campaign_cursor")) or _state.get("progress",{}).get("campaign_cursor")!=_state.get("campaign_cursor"):reject("Shopping requires the earned ordinary station career");return {}
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():reject("Resolve the current flight or result before shopping");return {}
	var place:=Shopping.location(bindings,cat,_state.station_id)
	if place.is_empty() or _state.get("mission",{}).get("kind",-1)==int(bindings.mido_travel.ordinary_shopping.pricing.special_mission_kind):reject("This station pricing context is not supported");return {}
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or not equipment.cargo_cache_valid():reject("Shopping lost the earned inventory");return {}
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or owned.loadout.get(key)!=bindings.get(key) or owned.cargo.get(key)!=bindings.get(key):reject("Shopping belongs to another content identity");return {}
	if owned.loadout.station_id!=place.station_id or owned.loadout.system_id!=place.system_id or _lounges.snapshot().current_station_id!=place.station_id or _lounges.location(place.station_id).is_empty():reject("Shopping lost the current cached station");return {}
	if not _state.get("credits") is int or _state.credits<0 or _state.credits>2147483647:reject("Shopping has an invalid retained wallet");return {}
	return owned

func _shopping_reject(message: String) -> RefCounted:
	reject(message);return null

func rebase_gate_arrival(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,arrival: Dictionary) -> bool:
	error=""
	if not GateArrival.packet_matches(bindings,catalogues,arrival) or _state.get("campaign_cursor")!=arrival.campaign_cursor or _state.get("station_id")!=arrival.from_station_id:return reject("Gate arrival must follow this retained career's location")
	if not equipment is Equipment or equipment.snapshot().get("loadout",{}).get("station_id")!=arrival.station_id or not _pending_flight.is_empty():return reject("Gate arrival requires its detached destination inventory and retired flight")
	var statistics: Variant=_state.get("travel_statistics")
	if not GateArrival.valid_statistics(statistics):return reject("Gate arrival lost its earned travel statistics")
	var count: int=statistics.jumpgates_used+int(bindings.mido_travel.gate_arrival.career.jump_increment)
	if not Numbers.integer(count,0,2147483647):return reject("The gate count exceeds its supported range")
	if not rebase_station(equipment,bindings):return false
	var retained: Dictionary=_state.travel_statistics.duplicate(true)
	retained.jumpgates_used=count;_state.travel_statistics=retained
	return settle_base_medals()

func select_location(bindings: RefCounted,cat: RefCounted,library: RefCounted,station_id: int,settings: Dictionary,random_state: Dictionary,unix_seconds: Variant,station_context: RefCounted=null) -> bool:
	# Called on the detached arrival career, after retiring its old flight
	# ledger and before constructing the destination world. Accepted jobs and
	# their original clients remain independent of the currently selected lounge.
	error=""
	if _lounges==null or not _flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Retain the completed flight before selecting its destination location")
	if settings.get("difficulty")!=_state.difficulty:return reject("Location generation changed the retained difficulty")
	var previous_station: int=_lounges.selection_state().current_station_id
	var candidate: RefCounted=_lounges.fork()
	var context:={"station_id":station_id,"campaign_cursor":_state.campaign_cursor,"rank":_state.rank,"reputation":_state.reputation.duplicate(true)}
	var medals:=LoungeCache.Medals.stock_progress(_state,blueprint_state())
	var all_medals: bool=LoungeCache.Medals.all_base_gold(int(_state.campaign_cursor),medals)==true and EliteMedals.earned(_state).size()==EliteMedals.TOTAL-EliteMedals.FIRST
	var wanted: Array=preload("res://src/content/valkyrie_world_definitions.gd").wanted_ships(_state.progress,cat.tables.get("wanted",[]))
	if not candidate.select_location(bindings,cat,library,context,settings,random_state,unix_seconds,station_context,medals,all_medals,wanted):return reject(candidate.error)
	var source: RefCounted=_void_source
	var selected_entry: RefCounted
	# The native arrival path represents the set-location wrapper. An unchanged
	# station does not call the source selection owner again.
	if source!=null and station_id!=previous_station and _state.campaign_cursor>=32:
		var selected: Dictionary=candidate.selection_state()
		var random: RefCounted=load("res://src/simulation/seeded_random.gd").new()
		if not random.restore(selected.random):return reject(random.error)
		var mission:=Campaign.mission(bindings,_state.campaign_cursor)
		if load("res://src/simulation/mission_station_context.gd").permits(bindings,_state.campaign_cursor,station_id,station_context):mission=station_context.snapshot().mission
		if mission.is_empty():return reject("The Void source requires the retained story destination")
		var plan: Dictionary
		if _state.campaign_cursor==40:
			# Observe the old source before this same location call may reroll
			# it. Arrival carries this native owner, never a second selection.
			selected_entry=load("res://src/simulation/selected40_world_entry.gd").new()
			var context40:=selected40_context(bindings,station_id,int(cat.tables.stations[station_id].system_id))
			if not selected_entry.prepare(bindings,cat,source,context40,station_id,"travel_arrival",random):return reject(selected_entry.error)
			var observation: Dictionary=selected_entry.snapshot()
			plan={"source":observation.source_after,"random_state":observation.random_state}
		else:
			plan=source.select(_state.campaign_cursor,station_id,int(mission.station_id),_state.campaign_cursor==32 and station_id==int(mission.station_id),random)
		if plan.is_empty():return reject(source.error)
		source=source.fork()
		if not source.restore(plan.source) or not candidate.adopt_selection_random(plan.random_state):return reject(source.error+candidate.error)
	_lounges=candidate;_void_source=source;_selected40_entry=selected_entry
	return true

func selected40_entry_owner() -> RefCounted:return null if _selected40_entry==null else _selected40_entry.fork()

func selected40_context(bindings: RefCounted,station_id: int,system_id: int) -> Dictionary:
	if _state.get("campaign_cursor")!=40 or not Campaign.onward_available(bindings):return {}
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"origin_station_id":station_id,"origin_system_id":system_id,"mission_kind":Campaign.mission(bindings,40).kind,
		"mission_story":true,"mission_completed":false,"mission_failed":false,"rank":_state.rank,"difficulty":_state.difficulty}

## Archive restoration supplies this optional owner separately from ordinary
## career fields. Older pre32 saves have observed no eligible native selections;
## older32 saves retain their existing scope without guessing a travel counter.
func restore_void_career(bindings: RefCounted,cat: RefCounted,retained: Variant=null,recipes: Variant=null) -> bool:
	_catalogues=cat
	if (retained==null)!=(recipes==null):return reject("The saved Void career lost its source or blueprint progress")
	if retained==null and (_state.campaign_cursor not in [28,31] or not VoidAccess.parameters(bindings.mido_travel.get("void_access"))):return true
	if _lounges==null:return reject("The Void source requires retained locations")
	var source:=VoidSource.new()
	var availability: Array=_lounges.selection_state().system_availability
	var accepted: bool=source.configure_fresh(bindings,cat,availability) if retained==null else source.configure(bindings,cat,availability,retained)
	if not accepted:return reject(source.error)
	if _state.campaign_cursor<32 and retained!=null:
		var rules: Dictionary=bindings.mido_travel.void_access.source
		if retained.eligible_selection_count!=0 or retained.source_station_id!=int(rules.initial_station_id) or retained.source_system_id!=int(rules.initial_system_id):return reject("The pre32 career has no eligible Void source selections")
	var blueprints:=Blueprints.new()
	if recipes!=null and not recipes is Dictionary:return reject("The saved blueprint progress is invalid")
	# No blueprint purchase or construction was implemented before this chapter;
	# older pre32 careers therefore start with the source's untouched recipe list.
	var blueprints_ready: bool=blueprints.configure(cat,bindings.binding_id) if recipes==null else blueprints.restore(cat,bindings.binding_id,recipes)
	if not blueprints_ready:return reject(blueprints.error)
	_void_source=source
	_blueprints=blueprints
	return true

func void_source_state() -> Dictionary:return {} if _void_source==null else _void_source.snapshot()
func void_source_owner() -> RefCounted:return null if _void_source==null else _void_source.fork()
func blueprint_state() -> Dictionary:return {} if _blueprints==null else _blueprints.snapshot()

func apply_station_entry(bindings: RefCounted,cat: RefCounted,equipment: RefCounted,story_mission: Dictionary) -> bool:
	# Called only on a detached, actually docked station candidate. Location
	# generation, opening the shop and restoring a save do not call this path.
	error=""
	if not _dock_wanted(bindings,cat):return false
	var delivery:=Recipe.station_delivery(_rules,_state.get("mission",{}))
	var item: Dictionary=delivery.get("entry_stock",{})
	if not item.is_empty() and _state.station_id==_state.mission.station_id:
		if _station_inventory(equipment,bindings).is_empty():return false
		var stock: Array=_lounges.item_stock(_state.station_id)
		if not stock.any(func(row):return row.item_id==item.item_id):
			var metadata: Dictionary=load("res://src/simulation/station_stock.gd").item_metadata(cat.tables.items[int(item.item_id)],_rules.station_generation)
			var supplied:=stock.duplicate(true)
			supplied.append({"item_id":int(item.item_id),"quantity":int(item.quantity),"unit_price":int(metadata.unit_price)})
			var locations: RefCounted=_lounges.fork()
			if not locations.replace_item_stock(bindings,cat,_state.station_id,stock,supplied):return reject(locations.error)
			_lounges=locations
	var definitions=load("res://src/content/kappa_preparation_definitions.gd")
	if not definitions.available(bindings) or _state.get("campaign_cursor")!=int(bindings.mido_travel.kappa_preparation.fitting.campaign_cursor):return true
	if _campaign_station_inventory(bindings,equipment,story_mission).is_empty():return false
	var preparation=load("res://src/simulation/campaign_preparation.gd").new()
	if not preparation.configure(bindings,cat,_state.campaign_cursor,story_mission):return reject(preparation.error)
	var before: Array=_lounges.item_stock(_state.station_id)
	var prepared: Dictionary=preparation.station_stock(_state.station_id,before)
	if prepared.is_empty():return reject(preparation.error)
	if not prepared.applied:return true
	var locations: RefCounted=_lounges.fork()
	if not locations.replace_item_stock(bindings,cat,_state.station_id,before,prepared.items):return reject(locations.error)
	_lounges=locations
	return true

## Most Wanted boards (expansion, from the story's cursor 128): each docking
## stands for the departure before it (every criminal moves one step), then
## the boards of this station's race unlock their due entries.
## Assumption: the original moves them as the player departs; the boards only
## show while docked, so moving them at the next docking looks the same.
func _dock_wanted(bindings: RefCounted,cat: RefCounted) -> bool:
	var table: Array=cat.tables.get("wanted",[])
	var cursor: int=int(_state.campaign_cursor)
	if _state.progress.get("wanted") is Dictionary and _state.progress.wanted.has("news"):
		_state.progress.wanted=_state.progress.wanted.duplicate(true);_state.progress.wanted.erase("news")
	if table.is_empty() or not Valkyrie.saved_story(bindings,cursor) or cursor<int(Valkyrie.WANTED.from_cursor):return true
	var state: Variant=_state.progress.get("wanted")
	if not Wanted.valid(state,table):state=Wanted.fresh(table)
	var known: Array=_lounges.snapshot().get("system_availability",[])
	var seed_value:=hash([cursor,int(_state.station_id),int(_state.get("travel_statistics",{}).get("jumpgates_used",0)),int(_state.completed_side_missions)])
	state=Wanted.travel(state,cat,int(_state.station_id),known,seed_value)
	var activated: Dictionary=Wanted.activate(state,table,cat,cursor,int(_state.station_id),known,seed_value+1)
	# How many criminals this docking added (the station announces them).
	activated.state.news=activated.activated.size()
	_state.progress.wanted=activated.state
	return true

func acknowledge_station_campaign(bindings: RefCounted,equipment: RefCounted,story_mission: Dictionary,visit: RefCounted) -> Dictionary:
	error=""
	var owned:=_campaign_station_inventory(bindings,equipment,story_mission)
	if owned.is_empty():return {}
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")):return fail("The station requires its native campaign conversation")
	if not visit.matches_station_inventory(owned.loadout,equipment):return fail("The station acknowledgement lost its retained inventory")
	var receipt: Dictionary=visit.transition()
	var rules:=Campaign.dialogue_rules(bindings,_state.campaign_cursor,story_mission,true)
	if receipt.is_empty() or rules.is_empty():return fail("Acknowledge the full station conversation before continuing")
	for key in ["base_content_id","binding_id"]:
		if receipt.get(key)!=_state[key]:return fail("The station acknowledgement belongs to another content identity")
	var equal=load("res://src/content/opening_escape_definitions.gd")
	if receipt.from_cursor!=_state.campaign_cursor or receipt.station_id!=_state.station_id or receipt.previous_mission!=story_mission or receipt.campaign_cursor!=int(rules.next_cursor) or not equal.equal_value(receipt.mission,rules.next_mission) or receipt.reward_credits!=int(rules.reward_credits):return fail("The station conversation changed its earned transition")
	if rules.has("unlock_system_ids") and (not equal.equal_value(receipt.get("unlock_system_ids"),rules.unlock_system_ids) or not equal.equal_value(receipt.get("next_course"),rules.get("next_course"))):return fail("The station conversation changed its next destination")
	var next: RefCounted=fork()
	var inventory: RefCounted=equipment.fork()
	# A completed career keeps its finished chapter only as lounge history once
	# the expansion story takes over.
	if _station_context!=null and _station_context.recipe().is_empty():pass
	elif _station_context!=null:
		next._station_context=_station_context.successor(bindings,receipt)
		if next._station_context==null:return fail(_station_context.error)
	if rules.has("cargo_requirement"):
		if next._blueprints==null:return fail("The crystal hand-in lost its retained blueprints")
		var required: Dictionary=rules.cargo_requirement
		if not inventory.debit_campaign_cargo(int(required.item_id),int(required.quantity)):return fail(inventory.error)
		var credit:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
			"from_cursor":receipt.from_cursor,"to_cursor":receipt.campaign_cursor,
			"item_id":int(required.item_id),"quantity":int(required.quantity),"expected_entry":next._blueprints.entry(85)}
		if not next._blueprints.precredit_story33(credit):return fail(next._blueprints.error)
	if rules.get("goods_requirement",{}).get("consume",false):
		if not inventory.debit_campaign_cargo(int(rules.goods_requirement.item_id),int(rules.goods_requirement.quantity)):return fail(inventory.error)
	if rules.has("story_blueprint"):
		if next._blueprints==null:return fail("The story blueprint lost its retained blueprints")
		var plan: Dictionary=rules.story_blueprint
		next._blueprints=next._blueprints.fork_for_transaction()
		var granted: bool
		if not plan.grant:granted=next._blueprints.story_lock(int(plan.item_id))
		elif plan.has("material_id"):granted=next._blueprints.story_grant(int(plan.item_id),int(plan.material_id),int(plan.quantity),int(plan.station_id))
		elif plan.has("materials"):
			# Several materials already supplied (141: the four plasmas).
			granted=true
			for pair in plan.materials:granted=granted and next._blueprints.story_grant(int(plan.item_id),int(pair[0]),int(pair[1]),int(plan.station_id))
		else:granted=next._blueprints.story_unlock(int(plan.item_id))
		if not granted:return fail(next._blueprints.error)
	if rules.has("story_ship"):
		var ship: Dictionary=rules.story_ship
		var changed: bool=inventory.return_story_ship(bindings,_catalogues) if ship.has("restore") else inventory.lend_story_ship(bindings,_catalogues,int(ship.ship_id),Valkyrie.ship_equipment(ship),bool(ship.store))
		if not changed:return fail(inventory.error)
	if not next._apply_story_station_rules(bindings,inventory,rules):return fail(next.error)
	if not next._retain_story_progress(bindings,next._state.progress,_state.campaign_cursor,receipt.campaign_cursor,_state.station_id,_state.station_id,false):return fail(next.error)
	if rules.has("unlock_system_ids"):
		next._lounges=next._lounges.fork()
		if not next._lounges.acknowledge_campaign_coordinates(bindings,visit):return fail(next._lounges.error)
	var reward: int=int(receipt.reward_credits)
	if rules.has("reward_per_story_counter"):
		var kills:=int(next._state.progress.get("story_counter",0))
		if kills>(2147483647-reward)/maxi(1,int(rules.reward_per_story_counter)):return fail("The story reward exceeds the supported credit range")
		reward+=kills*int(rules.reward_per_story_counter)
		next._state.progress.erase("story_counter");next._state.progress.erase("story_stations_mask")
	next._state.credits=credit_balance(_state.credits,reward,_rules.delivery_results)
	return {"career":next,"equipment":inventory}

## Station-side story changes as a talk enters its next cursor (tables in
## valkyrie_campaign_definitions): items taken away, a construction site
## reset, goods put in the hold and this station's shipyard changed.
## Call on the staged career with the staged inventory.
func _apply_story_station_rules(bindings: RefCounted,inventory: RefCounted,rules: Dictionary) -> bool:
	error=""
	for id in rules.get("story_removed_items",[]):
		if not inventory.remove_story_item(bindings,_catalogues,int(id)):return reject(inventory.error)
	if rules.has("story_blueprint_reset"):
		if _blueprints==null:return reject("The blueprint reset lost its retained blueprints")
		_blueprints=_blueprints.fork_for_transaction()
		if not _blueprints.story_reset_station(int(rules.story_blueprint_reset)):return reject(_blueprints.error)
	for row in rules.get("story_hold_grants",[]):
		if not inventory.receive_lounge_goods(int(row[0]),int(row[1])):return reject(inventory.error)
	for row in rules.get("story_removed_goods",[]):
		if not inventory.remove_story_goods(int(row[0]),int(row[1])):return reject(inventory.error)
	for station in rules.get("story_unvisit",[]):
		if not forget_location_visit(int(station)):return false
	if rules.has("story_station_ships"):
		var station:=int(_state.station_id);var plan: Dictionary=rules.story_station_ships
		var before: Array=_lounges.ship_stock(station)
		var ships: Array=[] if plan.get("clear",false) else before.duplicate(true)
		var affiliations: Array=bindings.early_contracts.base_station_stock.ships.affiliations
		var percent:=int(_lounges.location(station).get("stock",{}).get("context",{}).get("ship_price_percent",0))
		for row in plan.get("ships",[]):
			var id:=int(row[0]);var price:=int(row[1]);var at:=-1
			for i in ships.size():
				if int(ships[i].ship_id)==id:at=i
			if price<0:
				if at>=0:continue
				price=load("res://src/simulation/station_stock.gd").local_ship_price(bindings,_catalogues,id,station,percent)
			var offer:={"ship_id":id,"faction_id":int(affiliations[id]),"unit_price":price}
			if at>=0:ships[at]=offer
			else:ships.append(offer)
		_lounges=_lounges.fork()
		if not _lounges.replace_ship_stock(bindings,_catalogues,station,before,ships):return reject(_lounges.error)
	return true

func _campaign_station_inventory(bindings: RefCounted,equipment: RefCounted,story_mission: Dictionary) -> Dictionary:
	if bindings==null or not equipment is Equipment or _lounges==null or _state.is_empty():return fail("Campaign station progress requires its retained career and inventory")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or contract result before the campaign conversation")
	if Campaign.dialogue_rules(bindings,_state.get("campaign_cursor"),story_mission,true).is_empty():return fail("This career has no declared station conversation")
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or not equipment.cargo_cache_valid() or owned.get("ordinary_shopping_open",false):return fail("Close the retained equipment quote before campaign progress")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=_state[key] or owned.get("cargo",{}).get(key)!=_state[key]:return fail("The campaign station belongs to another content identity")
	if owned.loadout.station_id!=_state.get("station_id") or _lounges.selection_state().get("current_station_id")!=_state.station_id or _lounges.location(_state.station_id).is_empty():return fail("The campaign lost its actual docked location")
	if _state.get("progress",{}).get("campaign_cursor")!=_state.campaign_cursor or not _state.get("credits") is int or not Numbers.integer(_state.credits,0,2147483647):return fail("The campaign lost its retained progress or wallet")
	return owned

@warning_ignore("integer_division")
static func acceptance_fee(terms: Dictionary,mission: Dictionary,difficulty: float) -> int:
	if difficulty!=float(terms.acceptance.fee_difficulty):return 0
	return (int(mission.reward)+int(mission.bonus))/int(terms.acceptance.fee_divisor)

static func cabin_catalogue(catalogues: RefCounted,rules: Dictionary) -> Dictionary:
	var result:={}
	for index in catalogues.tables.items.size():
		var properties: Dictionary=catalogues.tables.items[index].properties
		if int(properties.get(2,-1))==int(rules.cabin_subtype):
			var places:=int(properties.get(int(rules.cabin_places_property),0))
			if places>0:result[index]=places
	return result

static func passenger_capacity(cabins: Dictionary,loadout: Dictionary) -> int:
	var places:=0
	for slot in loadout.slots:
		if slot!=null:places+=int(cabins.get(slot.item_id,0))
	return places

func preview(offer_id: int,equipment: RefCounted,bindings: RefCounted=null) -> Dictionary:
	error=""
	if not _flight.is_empty():reject("Contract acceptance requires the retained station arrival");return {}
	if not _state.get("pending_result",{}).is_empty():reject("Acknowledge the current contract result first");return {}
	if _state.is_empty() or not _state.offers.has(offer_id) or _state.offers[offer_id].consumed:reject("This contact has no available offer");return {}
	var quote: Dictionary=_state.offers[offer_id].offer
	if not acceptance_supported(_rules,int(_state.campaign_cursor),quote,bindings):reject("This contract's mission or destination is not supported yet");return {}
	if not equipment is Equipment:reject("The contract requires the retained inventory");return {}
	var owned: Dictionary=equipment.snapshot()
	if owned.is_empty() or not owned.get("training_inventory_released",false) or not equipment.cargo_cache_valid():reject("The contract inventory is unavailable");return {}
	for key in ["base_content_id","binding_id","station_id"]:
		if owned.loadout[key]!=_state[key]:reject("The contract inventory belongs to another station");return {}
	var fee:=acceptance_fee(_rules,quote.mission,float(_state.difficulty))
	var places:=passenger_capacity(_cabins,owned.loadout)
	var reason:=-1
	# The source checks the offered quantity before discarding an old job.
	if int(quote.requirements.cargo_tons)>int(owned.cargo.free_space):reason=int(_rules.courier.capacity_text_id)
	elif int(quote.requirements.passenger_places)>places:reason=int(_rules.passenger.capacity_text_id)
	elif fee>int(_state.credits):reason=int(_rules.acceptance.insufficient_credits_text_id)
	var replacing: bool=not _state.mission.is_empty()
	return {"can_accept":reason<0,"reason_text_id":reason,"fee":fee,
		"missing_credits":maxi(0,fee-int(_state.credits)),"cargo_tons":int(quote.requirements.cargo_tons),
		"passenger_places":int(quote.requirements.passenger_places),"passenger_capacity":places,
		"replacement_required":replacing,"replacement_text_id":int(_rules.acceptance.replacement_text_id) if replacing else -1}

static func acceptance_supported(rules: Dictionary,cursor: int,quote: Dictionary,bindings: RefCounted=null) -> bool:
	# Quotation coverage can grow before the corresponding flight/objective
	# owners. Retained earlier contacts do not grant post-unlock acceptance.
	if OrdinaryContracts.available(bindings) and Campaign.supported(bindings,cursor):
		return rules==bindings.early_contracts and Numbers.integer(quote.get("context",{}).get("campaign_cursor"),Definitions.first_generation_cursor(rules),cursor) and OrdinaryContracts.retained_mission(bindings,quote.get("mission"),cursor)
	return not rules.is_empty() and Numbers.integer(cursor,Definitions.first_generation_cursor(rules),int(rules.last_cursor)) and Numbers.integer(quote.get("context",{}).get("campaign_cursor"),Definitions.first_generation_cursor(rules),int(rules.last_cursor)) and quote.get("choices",{}).has("kind_index")

## The enclosing accepted flight frame owns this clock. Zero stays active until
## the station can present the crew's farewell; it is not an airborne death.
func advance_wingmen(milliseconds: Variant) -> bool:
	error=""
	if not milliseconds is int or not Numbers.integer(milliseconds,0,2147483647):return reject("Invalid wingman flight duration")
	var active: Dictionary=_state.get("wingmen",{}).get("active",{})
	if not active.is_empty():active.remaining_ms=maxi(0,int(active.remaining_ms)-milliseconds)
	return true

## Loma pirate toll (loma_toll_definitions.gd): 0 clears, 1 paid, 2 refused.
## Paying debits the toll from the wallet.
func set_loma_toll(status: int,debit:=0) -> bool:
	error=""
	var Toll=preload("res://src/content/loma_toll_definitions.gd")
	if status not in [0,Toll.PAID,Toll.REFUSED] or debit<0 or (debit>0 and status!=Toll.PAID) or debit>int(_state.get("credits",0)) or not _state.get("progress") is Dictionary:return reject("Invalid Loma toll change")
	_state.credits=int(_state.credits)-debit
	if status==0:_state.progress.erase(Toll.PROGRESS_KEY)
	else:_state.progress[Toll.PROGRESS_KEY]=status
	return true

## The flight reports one native casualty when that pilot enters destruction.
## Loss changes the paid roster, not its terms or the freelance mission.
func record_wingman_loss(pilot: RefCounted) -> bool:
	error=""
	if not is_instance_of(pilot,load("res://src/simulation/opening_combat_actor.gd")):return reject("A companion casualty requires its native body")
	var body: Dictionary=pilot.snapshot()
	if not body.get("wingman",false) or body.get("vitals",{}).get("hull",1)!=0:return reject("Only a destroyed companion can leave the paid roster")
	for key in ["base_content_id","binding_id"]:
		if body.get(key)!=_state.get(key):return reject("The companion casualty belongs to another career")
	var active: Dictionary=_state.get("wingmen",{}).get("active",{})
	if active.is_empty():return true
	if body.get("actor_kind")!=active.faction:return reject("The companion casualty changed its hired faction")
	var index: int=active.names.find(body.get("name",""))
	if index<0:return true
	var names: Array=active.names.duplicate()
	names.remove_at(index)
	if names.is_empty():_state.wingmen.active={}
	else:active.names=names
	return true

func expired_wingmen() -> Dictionary:
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return {}
	var active: Dictionary=_state.get("wingmen",{}).get("active",{})
	return active.duplicate(true) if not active.is_empty() and active.remaining_ms==0 else {}

func dismiss_expired_wingmen() -> bool:
	if expired_wingmen().is_empty():return reject("No expired crew awaits its station farewell")
	_state.wingmen.active={}
	return true

## Kaamo Club docking: the first talk opens the offer; the purchase pays here
## (the station owner debits the Buskat from the hold).
func advance_kaamo(purchase: bool) -> bool:
	var Kaamo=preload("res://src/content/kaamo_club_definitions.gd")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty() or _state.station_id!=Kaamo.STATION_ID:return reject("The Kaamo Club requires an idle docking")
	var current:=Kaamo.state(_state.progress)
	if current!=(Kaamo.OFFERED if purchase else Kaamo.OPEN):return reject("The Kaamo Club is not at this step")
	if purchase:
		if _state.credits<=Kaamo.PRICE:return reject("Insufficient credits.")
		_state.credits-=Kaamo.PRICE
		# Anything sold to the club before is gone; the storage starts empty.
		_state.progress.kaamo_storage={"items":[],"ships":[]}
	_state.progress.kaamo_state=current+1
	return true

## Standing::applyDelict: an offence against a race (0-3), doubled at Extreme;
## Terrans/Vossk share axis 0, Nivelians/Midorians axis 1 (clamped to +-100).
func apply_delict(race: int,amount: int) -> bool:
	if race<0 or race>3 or not _state.get("reputation") is Dictionary:return reject("An offence needs a race and a career standing")
	var change: int=amount*(2 if float(_state.get("difficulty",Difficulty.NORMAL))==Difficulty.EXTREME else 1)*(1 if race%2 else -1)
	var axes: Array=_state.reputation.axes.duplicate()
	axes[race/2]=clampi(int(axes[race/2])+change,-100,100)
	_state.reputation=_state.reputation.duplicate(true);_state.reputation.axes=axes
	_state.progress.reputation=_state.reputation.duplicate(true)
	return true

## Supernova 148: a broker's bar talk is heard once per career.
func hear_bar_flavor() -> bool:
	var Campaign=preload("res://src/content/valkyrie_campaign_definitions.gd")
	var talk: int=Campaign.bar_flavor(int(_state.campaign_cursor),int(_state.station_id))
	if talk<0:return reject("No bar talk waits at this docking")
	_state.progress.bar_heard=int(_state.progress.get("bar_heard",0))|(1<<(talk-148))
	return true

## A medal reward blueprint (fireworks) granted at docking.
func unlock_medal_blueprint(item_id: int) -> bool:
	if _blueprints==null or not _flight.is_empty() or not _pending_flight.is_empty():return reject("Medal rewards require an idle docking")
	var project: RefCounted=_blueprints.fork_for_transaction()
	if not project.unlock(item_id):return reject(project.error)
	_blueprints=project
	return true

## The fee an unwelcome pilot pays before the hangar opens.
func pay_docking_fee(amount: int) -> bool:
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("The docking fee requires an idle docking")
	if amount<0 or _state.credits<amount:return reject("Insufficient credits.")
	_state.credits-=amount
	return true

## Pays a destroyed pirate base's reward once, at the next idle docking.
func collect_pirate_base_thanks(pending_bit: int,reward: int) -> bool:
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Pirate-base thanks require an idle docking")
	var mask:=int(_state.progress.get("pirate_bases",0))
	if mask & pending_bit==0:return reject("No pirate-base thanks are pending")
	_state.progress.pirate_bases=mask & ~pending_bit;_state.credits+=reward
	return true

func wingman_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	if _lounges==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before hiring wingmen")
	if not preload("res://src/simulation/lounge_dialogue.gd").available(bindings):return fail("Wingman dialogue is unavailable for this content")
	var owned: Dictionary=equipment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=bindings.get(key):return fail("The wingmen and career belong to different content")
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	var active:={}
	for contact in _lounges.location(int(_state.station_id)).get("population",{}).get("contacts",[]):
		if contact.contact_id==contact_id:active=Wingmen.offer(contact,int(_state.station_id),bindings);break
	if active.is_empty():return fail("This contact has no valid wingman roster")
	var retained: Dictionary=_state.get("wingmen",{"hired_total":0,"active":{}})
	var busy: bool=not retained.active.is_empty()
	var hired: bool=contact_id in _lounges.location(int(_state.station_id)).get("purchased_goods",[])
	var count: int=active.names.size()
	var price: int=active.price
	return {"kind":"wingmen","contract":active,"crew_size":count,"total_price":price,
		"intro_text_id":767+count,"busy":busy,"consumed":hired,"missing_credits":maxi(0,price-int(_state.credits)),
		"can_accept":not hired and not busy and price<=int(_state.credits) and int(retained.hired_total)<=2147483647-count}

func hire_lounge_wingmen(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> bool:
	var quote:=wingman_preview(bindings,contact_id,equipment)
	if quote.is_empty():return false
	if not quote.can_accept:return reject("This captain was hired already, another wingman roster is active or this hire exceeds the current credits")
	var cache: RefCounted=_lounges.fork()
	if not cache.consume_wingmen(int(_state.station_id),contact_id):return reject(cache.error)
	_lounges=cache
	var hired: int=_state.get("wingmen",{}).get("hired_total",0)
	_state.wingmen={"hired_total":hired+int(quote.crew_size),"active":quote.contract.duplicate(true)}
	_state.credits-=int(quote.total_price)
	return true

func diplomat_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	if _lounges==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before using a diplomat")
	if not preload("res://src/simulation/lounge_dialogue.gd").available(bindings):return fail("Diplomat dialogue is unavailable for this content")
	var owned: Dictionary=equipment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=bindings.get(key):return fail("The diplomat and career belong to different content")
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	var contact: Dictionary=_lounges.diplomat_contact(int(_state.station_id),contact_id)
	if contact.is_empty():return fail("This contact is not a diplomat")
	var quote:=Reputation.diplomat_quote(_state.reputation,int(contact.faction))
	if quote.is_empty():return fail("The diplomat requires valid retained faction standing")
	quote.merge(contact);quote.kind="diplomat"
	quote.can_accept=quote.eligible and not quote.consumed and int(_state.credits)>=int(quote.total_price)
	quote.missing_credits=maxi(0,int(quote.total_price)-int(_state.credits))
	return quote

func purchase_lounge_diplomat(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> bool:
	var quote:=diplomat_preview(bindings,contact_id,equipment)
	if quote.is_empty():return false
	if not quote.can_accept:return reject("This diplomat is not needed, has already been used, or exceeds the current credits")
	var cache: RefCounted=_lounges.fork()
	if not cache.consume_diplomat(int(_state.station_id),contact_id):return reject(cache.error)
	_state.credits-=int(quote.total_price)
	_state.reputation=quote.reputation_after.duplicate(true)
	_state.progress.reputation=_state.reputation.duplicate(true)
	_lounges=cache
	return true

func blueprint_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	if _lounges==null or _blueprints==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before buying a blueprint")
	var owned: Dictionary=equipment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if bindings==null or _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=bindings.get(key):return fail("Blueprint seller and career belong to different content")
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	var quote: Dictionary=_lounges.blueprint_quote(int(_state.station_id),contact_id)
	if quote.is_empty():return fail("This contact has no blueprint for sale")
	var recipe: Dictionary=_blueprints.entry(int(quote.item_id))
	if recipe.is_empty():return fail("This contact's blueprint has no retained recipe")
	quote.kind="blueprint";quote.consumed=bool(recipe.available)
	quote.can_accept=not quote.consumed and int(_state.credits)>=int(quote.total_price)
	quote.missing_credits=maxi(0,int(quote.total_price)-int(_state.credits))
	return quote

func purchase_lounge_blueprint(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> bool:
	var quote:=blueprint_preview(bindings,contact_id,equipment)
	if quote.is_empty():return false
	if not quote.can_accept:return reject("This blueprint is already owned or exceeds the current credits")
	var project: RefCounted=_blueprints.fork_for_transaction()
	if not project.unlock(int(quote.item_id)):return reject(project.error)
	# The saved recipe bit outlives lounge-cache eviction and prevents recharging.
	_state.credits-=int(quote.total_price);_blueprints=project
	return true

func coordinate_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	if _lounges==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before buying coordinates")
	var owned: Dictionary=equipment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if bindings==null or _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=bindings.get(key):return fail("Coordinate seller and career belong to different content")
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	var quote: Dictionary=_lounges.coordinate_quote(int(_state.station_id),contact_id)
	if quote.is_empty():return fail("This contact has no coordinates for sale")
	quote.kind="coordinates";quote.can_accept=not quote.consumed and int(_state.credits)>=int(quote.total_price)
	quote.missing_credits=maxi(0,int(quote.total_price)-int(_state.credits))
	return quote

func purchase_lounge_coordinates(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> bool:
	var quote:=coordinate_preview(bindings,contact_id,equipment)
	if quote.is_empty():return false
	if not quote.can_accept:return reject("These coordinates are already known or exceed the current credits")
	var cache: RefCounted=_lounges.fork()
	if not cache.purchase_coordinates(int(_state.station_id),contact_id):return reject(cache.error)
	_state.credits-=int(quote.total_price);_lounges=cache
	return true

func merchant_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	if _lounges==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before buying lounge goods")
	var owned: Dictionary=equipment.snapshot()
	for key in ["base_content_id","binding_id"]:
		if bindings==null or _state.get(key)!=bindings.get(key) or owned.get("loadout",{}).get(key)!=bindings.get(key):return fail("Merchant and inventory belong to different content")
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	if not equipment.cargo_cache_valid():return fail(equipment.error)
	var quote: Dictionary=_lounges.merchant_quote(int(_state.station_id),contact_id)
	if quote.is_empty():return fail("This contact has no goods for sale")
	quote.kind="merchant";quote.can_accept=not quote.consumed and int(_state.credits)>=int(quote.total_price)
	quote.missing_credits=maxi(0,int(quote.total_price)-int(_state.credits))
	return quote

## The Kaamo Club's mechanics (mods for the flown ship) and dealers (one
## special item; one ship for the club's storage once the club is owned).
func kaamo_preview(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> Dictionary:
	error=""
	var Kaamo=preload("res://src/content/kaamo_club_definitions.gd")
	var Agents=preload("res://src/content/persistent_contact_definitions.gd")
	if _lounges==null or not equipment is Equipment or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the current flight or result before trading")
	var owned: Dictionary=equipment.snapshot()
	if owned.loadout.station_id!=_state.station_id or _lounges.selection_state().current_station_id!=_state.station_id or owned.get("ordinary_shopping_open",false):return fail("Open the current station lounge with the hangar closed")
	var quote: Dictionary=_lounges.kaamo_contact(int(_state.station_id),contact_id)
	if quote.is_empty():return fail("This contact sells nothing")
	quote.kaamo_kind=quote.kind;quote.kind="kaamo";quote.ship_id=int(owned.loadout.ship_id)
	match quote.kaamo_kind:
		"mod":
			var ship: Dictionary=owned.loadout.get("ship_instance",{})
			quote.total_price=int(ship.get("unit_price",0))*int(Agents.KAAMO_MOD_PERCENT[int(quote.mod)])/100*Agents.KAAMO_PRICE_FACTOR
			# Mechanics sell again for the next ship; a hull takes each mod once.
			quote.consumed=int(quote.mod) in ship.get("upgrade_tags",[])
		"item":quote.total_price=int(quote.price)*Agents.KAAMO_PRICE_FACTOR
		"ship":
			var stored: Array=_state.progress.get("kaamo_storage",{}).get("ships",[]).map(func(row):return int(row.ship_id))
			var left: Array=Agents.KAAMO_SHIPS.filter(func(id):return id!=int(owned.loadout.ship_id) and id not in stored)
			quote.greeting=Kaamo.state(_state.progress)!=Kaamo.OWNED
			quote.consumed=quote.consumed or left.is_empty() or quote.greeting
			quote.offer_ship_id=-1 if left.is_empty() else int(left[0])
			quote.total_price=0 if left.is_empty() else int(_catalogues.tables.ships[int(left[0])].stats.base_price)*Agents.KAAMO_PRICE_FACTOR
	quote.can_accept=not quote.consumed and int(_state.credits)>=int(quote.total_price)
	quote.missing_credits=maxi(0,int(quote.total_price)-int(_state.credits))
	return quote

func purchase_kaamo(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> RefCounted:
	var quote:=kaamo_preview(bindings,contact_id,equipment)
	if quote.is_empty():return null
	if not quote.can_accept:return _shopping_reject("This purchase is unavailable or exceeds the current credits")
	var inventory: RefCounted=equipment.fork()
	var cache: RefCounted=_lounges.fork()
	match quote.kaamo_kind:
		"mod":
			if not inventory.add_ship_mod(bindings,_catalogues,int(quote.mod)):return _shopping_reject(inventory.error)
		"item":
			if not inventory.receive_lounge_goods(int(quote.item_id),1) or not cache.consume_kaamo(int(_state.station_id),contact_id):return _shopping_reject(inventory.error+cache.error)
		"ship":
			if not cache.consume_kaamo(int(_state.station_id),contact_id):return _shopping_reject(cache.error)
			# A bare hull, parked in the club's storage (use it from the hangar).
			var kept: Dictionary=_state.progress.get("kaamo_storage",{"items":[],"ships":[]}).duplicate(true)
			kept.ships.append({"ship_id":int(quote.offer_ship_id),"unit_price":int(_catalogues.tables.ships[int(quote.offer_ship_id)].stats.base_price),"faction_id":0})
			_state.progress.kaamo_storage=kept
	_state.credits-=int(quote.total_price);_lounges=cache
	return inventory

func purchase_lounge_goods(bindings: RefCounted,contact_id: int,equipment: RefCounted) -> RefCounted:
	var quote:=merchant_preview(bindings,contact_id,equipment)
	if quote.is_empty():return null
	if not quote.can_accept:return _shopping_reject("This purchase is unavailable or exceeds the current credits")
	var inventory: RefCounted=equipment.fork()
	if not inventory.receive_lounge_goods(int(quote.item_id),int(quote.quantity)):return _shopping_reject(inventory.error)
	var cache: RefCounted=_lounges.fork()
	if not cache.consume_goods(int(_state.station_id),contact_id):return _shopping_reject(cache.error)
	_state.credits-=int(quote.total_price);_lounges=cache
	if not _retain_booze_type(int(quote.item_id)):return null
	if BaseMedals.booze_type_bit(int(quote.item_id))!=0 and not settle_base_medals():return null
	return inventory

func begin_lounge_visit() -> bool:
	error=""
	if _lounges==null:return reject("The lounge is unavailable")
	_lounges=_lounges.fork();_lounges.begin_social_visit()
	return true

func inspect_contact(bindings: RefCounted,contact_id: int,library: RefCounted=null) -> bool:
	error=""
	if _lounges==null or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Resolve the current flight or result before inspecting a contact")
	var conversations: Variant=_state.get("conversations",0)
	if not Numbers.integer(conversations,0,2147483646):return reject("The retained conversation count is invalid")
	var cache: RefCounted=_lounges.fork()
	var context:={"station_id":_state.station_id,"campaign_cursor":_state.campaign_cursor,"rank":_state.rank,"reputation":_state.reputation.duplicate(true)}
	if not cache.inspect_contact(bindings,_catalogues,context,contact_id,_station_context,library):return reject(cache.error)
	_lounges=cache;_state.offers=cache.location(int(_state.station_id)).offers
	_state.conversations=int(conversations)+1
	return true

func decline(offer_id: int) -> bool:
	error=""
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return reject("Resolve the current flight or result before refusing a job")
	var row: Variant=_state.get("offers",{}).get(offer_id)
	if not row is Dictionary or row.get("consumed")!=false or not row.get("offer") is Dictionary:return reject("This contact has no available job to refuse")
	var rejected: Variant=_state.get("rejected_jobs",0)
	if not Numbers.integer(rejected,0,2147483646):return reject("The retained refused-job count is invalid")
	_state.rejected_jobs=int(rejected)+1
	return settle_base_medals()

func accept(offer_id: int,equipment: RefCounted,replace_current: bool=false,bindings: RefCounted=null) -> RefCounted:
	var terms:=preview(offer_id,equipment,bindings)
	if terms.is_empty():return null
	if not terms.can_accept:reject("The contract requirements are not satisfied");return null
	if terms.replacement_required and not replace_current:reject("Confirm discarding the current mission first");return null
	var next: Dictionary=_state.duplicate(true)
	var quote: Dictionary=next.offers[offer_id].offer
	var candidate: RefCounted=equipment.fork()
	var hold: Dictionary=candidate.snapshot().cargo
	var mission_cargo:=int(_rules.courier.cargo_item_id)
	_drop_mission_goods(next,hold)
	if int(quote.mission.kind)==int(_rules.courier.kind):
		var merged:=false
		for row in hold.entries:
			if row.item_id==mission_cargo:
				# Original cargo merging compares item IDs and keeps the existing
				# row's marker. Do not turn unrelated cargo into protected cargo.
				row.quantity+=int(quote.mission.quantity);merged=true;break
		if not merged:hold.entries.append({"item_id":mission_cargo,"quantity":int(quote.mission.quantity),"mission":true})
	elif int(quote.mission.kind)==int(_rules.passenger.kind):next.passengers=int(quote.mission.quantity)
	hold.used=0
	for row in hold.entries:hold.used+=int(row.quantity)
	hold.free_space=int(hold.capacity)-int(hold.used)
	if not candidate.retain_flight_cargo(hold):reject(candidate.error);return null
	next.credits-=int(terms.fee);next.active_offer_id=offer_id
	var stats: Dictionary=next.get("stats",{}).duplicate();stats.accepted_jobs=int(stats.get("accepted_jobs",0))+1;next.stats=stats
	next.mission=quote.mission.duplicate(true);next.offers[offer_id].consumed=true
	next.erase("contract_phase");next.erase("station_outcome")
	if next.has("accepted_contact"):
		next.accepted_contact={"offer_id":offer_id,"station_id":int(next.station_id),"offer":quote.duplicate(true),"name":""}
		for contact in next.get("population",{}).get("contacts",[]):
			if contact.contact_id==offer_id:
				next.accepted_contact.name=contact.name
				next.accepted_contact.portrait=contact.portrait.duplicate(true)
				break
	var lounges: RefCounted=_lounges.fork() if _lounges!=null else null
	if lounges!=null and next.has("population") and not lounges.consume(int(next.station_id),offer_id):reject(lounges.error);return null
	# Procedural contacts have source ID -1. Their consumed flag remains set
	# when replaced; re-registering the same contact cannot duplicate its cargo.
	_state=next;_lounges=lounges
	return candidate

## Removes the current job's protected cargo or passengers from `next`/`hold`.
func _drop_mission_goods(next: Dictionary,hold: Dictionary) -> void:
	if next.mission.is_empty():return
	var mission_cargo:=int(_rules.courier.cargo_item_id)
	if _rules.acceptance.clear_cargo_kinds.any(func(value):return int(value)==int(next.mission.kind)):
		for index in hold.entries.size():
			var row: Dictionary=hold.entries[index]
			if row.item_id==mission_cargo and row.get("mission",false):hold.entries.remove_at(index);break
	elif int(next.mission.kind)==int(_rules.passenger.kind):next.passengers=0

## Missions log "Discard": the docked pilot drops the accepted freelance job.
## Its protected cargo and passengers leave the ship; nothing is paid or charged.
func discard_mission(equipment: RefCounted) -> RefCounted:
	error=""
	if _state.get("mission",{}).is_empty() or not _state.get("pending_result",{}).is_empty() or equipment==null:reject("There is no freelance mission to discard");return null
	var next: Dictionary=_state.duplicate(true)
	var candidate: RefCounted=equipment.fork()
	var hold: Dictionary=candidate.snapshot().cargo
	_drop_mission_goods(next,hold)
	hold.used=0
	for row in hold.entries:hold.used+=int(row.quantity)
	hold.free_space=int(hold.capacity)-int(hold.used)
	if not candidate.retain_flight_cargo(hold):reject(candidate.error);return null
	next.mission={};next.active_offer_id=-1
	next.erase("contract_phase");next.erase("station_outcome")
	if next.has("accepted_contact"):next.accepted_contact={}
	_state=next
	return candidate

func active_mission_for(station_id: int,bindings: RefCounted=null) -> Dictionary:
	# The active world mission and the retained side slot are different things.
	# Station-only objectives never select a special flight at their destination.
	var ordinary: bool=OrdinaryContracts.retained_mission(bindings,_state.get("mission"),int(_state.campaign_cursor)) and Campaign.supported(bindings,_state.get("campaign_cursor"))
	if not _rules.has("delivery_results") or (station_id not in _stations and not ordinary) or _state.mission.is_empty() or not _state.pending_result.is_empty():return {}
	var mission: Dictionary=_state.mission
	var delivery:=Recipe.station_delivery(_rules,mission)
	if mission.station_id!=station_id or _state.get("station_outcome",0)==2 or (not delivery.is_empty() and not delivery.select_flight):return {}
	return mission.duplicate(true)

func flight_context(station_id: int,bindings: RefCounted=null) -> Dictionary:
	error=""
	if not _flight.is_empty():reject("Retain the current contract flight before preparing another encounter");return {}
	var ordinary: bool=OrdinaryContracts.available(bindings) and Campaign.supported(bindings,_state.get("campaign_cursor")) and not load("res://src/content/free_flight_definitions.gd").flight(bindings,station_id,int(_state.get("campaign_cursor",-1))).is_empty()
	if _state.is_empty() or not Definitions.encounter_parameters(_rules) or (station_id not in _stations and not ordinary):
		reject("This contract session has no supported encounter context");return {}
	if not _state.pending_result.is_empty():reject("Acknowledge the contract result before preparing another encounter");return {}
	return _selected_contract_context(station_id,bindings)

func _selected_contract_context(station_id: int,bindings: RefCounted) -> Dictionary:
	var mission:=active_mission_for(station_id,bindings)
	var result:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"campaign_cursor":_state.campaign_cursor,"station_id":station_id,
		"rank":_state.rank,"difficulty":_state.difficulty,"reputation":_state.reputation.duplicate(true),
		"mission":mission,"client_faction":-1,"contact_name":""}
	if mission.is_empty():
		# A story flight here takes the cast; a kept side job without a flight
		# at this station stays accepted.
		result.mission=StoryFlights.story_job(bindings,_state.campaign_cursor,station_id,_state.progress.merged({"difficulty":float(_state.difficulty)}))
		return result
	var retained: Dictionary=_state.get("accepted_contact",{})
	var accepted: Dictionary=_state.offers.get(_state.active_offer_id,{}) if retained.is_empty() else {"consumed":true,"offer":retained.offer}
	if accepted.is_empty() or not accepted.consumed or not ContractProgress.matches(_state,accepted.offer,_catalogues):
		reject("The flight mission has no retained accepted contact");return {}
	if _state.has("station_outcome"):result.station_outcome=int(_state.station_outcome)
	result.client_faction=int(accepted.offer.context.client_faction)
	if not retained.is_empty():result.contact_name=retained.name
	else:
		for contact in _state.get("population",{}).get("contacts",[]):
			if contact.contact_id==_state.active_offer_id:result.contact_name=contact.name;break
	return result

## A story flight set in the alien world (station -1, 154): the job the Void
## visit builds. It depends on the career's cursor and progress only.
func void_story_context(bindings: RefCounted) -> Dictionary:
	if bindings==null or _state.is_empty():return {}
	var job:=StoryFlights.story_job(bindings,_state.campaign_cursor,-1,_state.progress.merged({"difficulty":float(_state.difficulty)}))
	if job.is_empty():return {}
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"campaign_cursor":_state.campaign_cursor,"station_id":-1,"rank":_state.rank,"difficulty":_state.difficulty,
		"reputation":_state.reputation.duplicate(true),"mission":job,"client_faction":-1,"contact_name":""}

func free_flight_context(bindings: RefCounted,station_id: int) -> Dictionary:
	var context:=retained_station_context(bindings,station_id)
	if context.is_empty():return {}
	if load("res://src/content/free_flight_definitions.gd").flight(bindings,station_id,int(_state.campaign_cursor)).is_empty():return fail("This station requires its selected story flight")
	return context

## A saved station may be waiting to launch an authored encounter. Validate
## its career without granting an ordinary departure at the same location.
func retained_station_context(bindings: RefCounted,station_id: int) -> Dictionary:
	error=""
	var definitions=load("res://src/content/free_flight_definitions.gd")
	if not definitions.available(bindings) or definitions.Worlds.location(bindings,station_id).is_empty() or not Campaign.supported(bindings,_state.get("campaign_cursor")) or _state.get("station_id")!=station_id:return fail("The station requires its retained unlocked career")
	if _state.get("base_content_id")!=bindings.base_content_id or _state.get("binding_id")!=bindings.binding_id or _rules!=bindings.early_contracts:return fail("The ordinary career belongs to another content identity")
	if GateArrival.available(bindings) and not GateArrival.valid_statistics(_state.get("travel_statistics")):return fail("The ordinary career lost its earned travel statistics")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Resolve the retained flight or result before ordinary departure")
	var side: Dictionary=_state.get("mission",{})
	if not side.is_empty():
		if not OrdinaryContracts.retained_mission(bindings,side,int(_state.campaign_cursor)):return fail("This accepted side mission has no supported ordinary flight")
		var contact: Dictionary=_state.get("accepted_contact",{})
		if contact.get("offer_id")!=_state.active_offer_id or not ContractProgress.matches(_state,contact.get("offer",{}),_catalogues):return fail("The ordinary side mission lost its accepted contact")
		var selected:=_selected_contract_context(station_id,bindings)
		if selected.is_empty():return {}
		selected.side_mission=side.duplicate(true)
		return selected
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"campaign_cursor":_state.campaign_cursor,"station_id":station_id,"rank":_state.rank,
		"difficulty":_state.difficulty,"reputation":_state.reputation.duplicate(true),
		"mission":StoryFlights.story_job(bindings,_state.campaign_cursor,station_id,_state.progress.merged({"difficulty":float(_state.difficulty)})),"client_faction":-1,"contact_name":""}

func poll_station(equipment: RefCounted,bindings: RefCounted=null) -> bool:
	error=""
	if not _flight.is_empty():return reject("Retain the current flight before polling station results")
	if not _rules.has("delivery_results"):return reject("This content has no supported delivery results")
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return false
	if not _poll_station_results(owned,equipment):return false
	return true if not _state.pending_result.is_empty() else settle_base_medals()

func _poll_station_results(owned: Dictionary,equipment: RefCounted) -> bool:
	if not _rules.has("delivery_results"):return reject("This content has no supported delivery results")
	if not _state.pending_result.is_empty():
		return true if owned==_result_inventory else reject("The pending delivery must retain its destination inventory")
	if _state.mission.is_empty():return true
	var rules: Dictionary=_rules.delivery_results
	var mission: Dictionary=_state.mission
	var delivery:=Recipe.station_delivery(_rules,mission)
	if delivery.is_empty() or (not delivery.get("any_station",false) and Recipe.station_objective(_rules,mission,_state.get("accepted_contact",{}))!=owned.loadout.station_id):return true
	var completed:=true
	if delivery.get("deferred",false):
		if not _state.has("station_outcome"):return true
		completed=_state.station_outcome==1
	var retained: Dictionary=_state.get("accepted_contact",{})
	var accepted: Dictionary=_state.offers.get(_state.active_offer_id,{}) if retained.is_empty() else {"consumed":true,"offer":retained.offer}
	if accepted.is_empty() or not accepted.consumed:return reject("The delivery has no accepted contact")
	var quote: Dictionary=accepted.offer
	if not ContractProgress.matches(_state,quote,_catalogues) or mission.story:return reject("Only the retained non-story delivery can settle here")
	if not delivery.required_cargo.is_empty():
		var required: Dictionary=delivery.required_cargo
		var observed: Dictionary=equipment.delivery_cargo(owned.loadout,int(required.item_id),int(required.quantity))
		if observed.is_empty():return reject(equipment.error)
		if not observed.satisfied:return true
	var reward: int=int(mission.reward)+int(mission.bonus) if completed else 0
	if not Numbers.integer(reward,0,int(rules.maximum_station_reward)) or not Numbers.integer(_state.credits,0,2147483647):return reject("The delivery payment is outside the supported source range")
	if not Reputation.valid_state(_state.reputation):return reject("The delivery lost the retained faction standing")
	# Opening the source success result marks it completed and changes faction
	# standing. Money, delivered quantities and the success count wait for Close.
	var standing: Dictionary=Delivery.standing_after(rules,_state.reputation,int(quote.context.client_faction),float(_state.difficulty)) if completed else _state.reputation.duplicate(true)
	_state.reputation=standing;_state.progress.reputation=standing.duplicate(true)
	_state.result_serial+=1
	_state.pending_result={"serial":_state.result_serial,"offer_id":_state.active_offer_id,
		"station_id":int(owned.loadout.station_id),"kind":int(mission.kind),"mode":int(rules.success_result_mode) if completed else int(_rules.flight_results.failure_result_mode),
		"acknowledgement_required":true,"reward_credits":reward,"completed":completed,"failed":not completed}
	_result_inventory=owned
	return true

func acknowledge_delivery_result(equipment: RefCounted,bindings: RefCounted=null) -> RefCounted:
	error=""
	if not _flight.is_empty():reject("The current result belongs to flight");return null
	if not _rules.has("delivery_results") or _state.get("pending_result",{}).is_empty():reject("No delivery result awaits acknowledgement");return null
	var owned:=_station_inventory(equipment,bindings)
	if owned.is_empty():return null
	return _acknowledge_delivery_inventory(equipment,owned)

func _acknowledge_delivery_inventory(equipment: RefCounted,owned: Dictionary) -> RefCounted:
	if not _rules.has("delivery_results") or _state.get("pending_result",{}).is_empty():reject("No delivery result awaits acknowledgement");return null
	if owned!=_result_inventory:reject("The delivery result belongs to another destination inventory");return null
	var next:=_state.duplicate(true)
	var rules: Dictionary=_rules.delivery_results
	if not Numbers.integer(next.completed_side_missions,0,2147483646):reject("The contract success count is outside its supported range");return null
	var completed: bool=next.pending_result.completed
	var progress: Dictionary=next.progress
	var earned:=Career.calculate_progress(_progress_rules,next.campaign_cursor,progress.player_kills,progress.pirate_kills,
		int(progress.other_score)+(int(rules.completion_rank_weight) if completed else 0))
	if earned.is_empty():reject("The delivery score exceeds the supported career range");return null
	var delivery:=Recipe.station_delivery(_rules,next.mission)
	if delivery.is_empty():reject("The retained job has no station settlement recipe");return null
	var inventory: RefCounted=equipment.fork()
	if delivery.unload=="required_cargo":
		var required: Dictionary=delivery.required_cargo
		if not inventory.debit_delivery_cargo(int(required.item_id),int(required.quantity)):reject(inventory.error);return null
	elif delivery.unload=="required_stack":
		if not inventory.debit_delivery_stack(int(delivery.required_cargo.item_id)):reject(inventory.error);return null
	elif delivery.unload=="marked_cargo":
		var hold: Dictionary=owned.cargo.duplicate(true)
		for index in hold.entries.size():
			var row: Dictionary=hold.entries[index]
			if row.get("mission",false) and rules.clear_first_marked_item_ids.any(func(value):return int(value)==int(row.item_id)):
				hold.used-=int(row.quantity);hold.free_space+=int(row.quantity)
				hold.entries.remove_at(index);break
		if not inventory.retain_flight_cargo(hold):reject(inventory.error);return null
	if delivery.statistic=="passengers":
		next.passengers=0;next.delivery_statistics.passengers+=int(next.mission.quantity)
	elif delivery.statistic=="cargo":next.delivery_statistics.cargo+=int(next.mission.quantity)
	var reward:=int(next.pending_result.reward_credits)
	next.credits=credit_balance(int(next.credits),reward,rules)
	next.completed_side_missions+=int(rules.completion_increment) if completed else 0
	next.progress.merge(earned,true);next.rank=earned.rank
	next.last_result=next.pending_result.duplicate(true)
	next.last_result.acknowledgement_required=false
	next.last_result.notification_sound_id=int(rules.notification_sound_id) if reward!=0 else -1
	next.mission={};next.active_offer_id=-1;next.pending_result={}
	next.erase("contract_phase");next.erase("station_outcome")
	if next.has("accepted_contact"):next.accepted_contact={}
	if not _bank_medals(next):reject("The acknowledged delivery lost its medal evidence");return null
	_state=next;_result_inventory={}
	return inventory

func bind_flight(controller: RefCounted,bindings: RefCounted=null) -> bool:
	error=""
	if not _flight.is_empty() or not FlightResults.parameters(_rules.get("flight_results")) or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("This contract session cannot bind a new flight")
	var scene: Dictionary=controller.snapshot()
	var clock: Dictionary=scene.get("contract_result",{})
	var encounter: Dictionary=scene.get("combat",{}).get("contract_encounter",{})
	if clock.is_empty() or clock.elapsed_ms!=0 or clock.mode!=0 or clock.retired or not scene.has("accounting"):return reject("Bind the prepared flight before its first actor update")
	var station:=int(encounter.get("context",{}).get("station_id",-1))
	var context:=void_story_context(bindings) if station==-1 and _state.get("station_id")==-1 else flight_context(station,bindings)
	var capability: RefCounted=controller.mission_context_owner()
	var supported: bool=capability!=null and capability.has_contract_actors() and capability.contract_context()==context
	if not supported or context!=encounter.get("context"):return reject("This flight does not belong to the accepted contract")
	if not scene.accounting.events.is_empty() or not scene.combat.reputation.events.is_empty() or not scene.combat.get("contract_settlement",{}).is_empty():return reject("A new flight cannot adopt unrecorded combat results")
	if not scene.combat.get("recovery",{}).is_empty():return reject("Bind the flight before cargo recovery changes its career")
	_flight={"encounter":encounter.duplicate(true),"accounting":scene.accounting.duplicate(true),
		"reputation_events":[],"settlement":{},"elapsed_ms":0,"retired":false}
	_flight_identity=controller.flight_identity()
	return true

func bind_world(controller: RefCounted,context: Dictionary,bindings: RefCounted=null) -> bool:
	error=""
	if not _rules.has("world_initialization") or not _flight.is_empty() or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("Bind an ordinary world to its retained contract session")
	var expected:=void_story_context(bindings) if context.get("station_id")==-1 and _state.get("station_id")==-1 else free_flight_context(bindings,int(context.get("station_id",-1))) if bindings!=null and Campaign.supported(bindings,context.get("campaign_cursor")) else flight_context(int(context.get("station_id",-1)))
	if expected.is_empty() or context!=expected:return reject("The prepared world changed its retained contract context")
	var scene: Dictionary=controller.snapshot()
	if not scene.get("contract_result",{}).is_empty():return bind_flight(controller,bindings)
	return _bind_accounted_world(controller,context,scene)

func campaign_flight_context(bindings: RefCounted,mission: Dictionary) -> Dictionary:
	error=""
	if bindings==null:return fail("Select the retained career's content before preparing flight")
	if not _rules.has("world_initialization") or not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty():return fail("Prepare the campaign flight from its retained station career")
	var sahi: bool=Campaign.sahi_at(bindings.mido_travel,_state.get("campaign_cursor"),_state.get("station_id")) and mission==Campaign.mission(bindings.mido_travel,int(_state.get("campaign_cursor",-1)))
	var bakka:=Bakka.selected(bindings,_state.get("campaign_cursor"),mission,_state.get("station_id"))
	var dekato:=Dekato.selected(bindings,_state.get("campaign_cursor"),mission,_state.get("station_id"))
	var rescue:=Campaign.Outcome.selected(bindings,_state.get("campaign_cursor"),mission)
	var station:=int(mission.station_id) if sahi or bakka or dekato else int(bindings.mido_travel.kappa_outcome.station_id)
	if (not sahi and not rescue and not bakka and not dekato) or _rules!=bindings.early_contracts or _state.get("progress",{}).get("campaign_cursor")!=_state.get("campaign_cursor") or _state.get("station_id")!=station:return fail("The campaign flight requires its earned station acknowledgement")
	for key in ["base_content_id","binding_id"]:
		if _state.get(key)!=bindings.get(key):return fail("The campaign departure belongs to another content identity")
	if dekato and (_void_source==null or _blueprints==null or _lounges==null or _state.get("reputation")!=_state.progress.get("reputation")):return fail("Dekato requires the retained Void, blueprint and location career")
	var side: Dictionary=_state.get("mission",{})
	if not side.is_empty():
		var contact: Dictionary=_state.get("accepted_contact",{})
		if not OrdinaryContracts.retained_mission(bindings,side,int(_state.campaign_cursor)) or contact.get("offer_id")!=_state.get("active_offer_id") or not ContractProgress.matches(_state,contact.get("offer",{}),_catalogues):return fail("The campaign flight lost its accepted delivery")
	var result:={"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,"campaign_cursor":_state.campaign_cursor,
		"station_id":_state.station_id,"system_id":int(Dekato.declarations(bindings).mission.system_id) if dekato else int(bindings.mido_travel.bakka_contest.mission.system_id) if bakka else int(bindings.mido_travel.thynome_expedition.mission28.system_id) if sahi and _state.campaign_cursor==28 else 9 if sahi else int(bindings.mido_travel.kappa_rescue.system_id),"mission_kind":int(mission.kind),
		"mission_story":true,"mission_completed":false,"rank":_state.rank,"difficulty":_state.difficulty}
	if sahi or dekato:result.mission_failed=false
	if dekato and not Dekato.context_valid(bindings,result):return fail("Dekato requires its supported native story context")
	return result

## A source-selected story40 world does not select or settle the independent
## accepted passenger job. Bind its native accounting to the retained origin;
## this component is not a navigation receipt or permission to release flight.
func bind_selected40_world(bindings: RefCounted,controller: RefCounted,scenery: RefCounted) -> bool:
	error=""
	var rules=load("res://src/content/selected40_population_definitions.gd")
	if not _flight.is_empty() or not _pending_flight.is_empty() or not _state.get("pending_result",{}).is_empty() or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("Selected40 career requires an unresolved native world and no prior result or flight")
	var combat: RefCounted=controller.combat_owner()
	var world: RefCounted=null if combat==null else combat.selected40_world_owner()
	if not rules.matches_world(scenery,world):return reject("Selected40 career requires the same native scenery and cast generation")
	var sequence: Dictionary=controller.career_snapshot().get("selected40_sequence",{})
	if sequence.get("revision")!=0 or sequence.get("elapsed_ms")!=0:return reject("Bind selected40 career before its first native sequence frame")
	var context: Dictionary=world.snapshot().selected40_context
	if not rules.context_valid(bindings,context) or not Delivery.parameters(_rules.get("delivery_results")):return reject("Selected40 career lacks its source mission and independent delivery declarations")
	for key in ["base_content_id","binding_id","campaign_cursor","rank","difficulty"]:
		if context.get(key)!=_state.get(key):return reject("Selected40 world differs from its retained career: "+key)
	if _state.station_id!=context.origin_station_id or _state.progress.campaign_cursor!=context.campaign_cursor:return reject("Selected40 career lost its earned origin or campaign acknowledgement")
	var entry: Dictionary=scenery.read_snapshot().departure_population.selected40_entry
	if _void_source==null or _lounges==null or entry.source_before!=_void_source.snapshot():return reject("Selected40 career lost its retained source selection or location owners")
	if not _selected40_side_slot_valid(bindings):return false
	context=context.duplicate(true)
	context.station_id=entry.station_id;context.system_id=entry.system_id;context.mission={}
	if not _bind_accounted_world(controller,context,controller.snapshot()):return false
	_flight.story_mission=rules.Nehma.declarations(bindings).next_mission.duplicate(true)
	_flight.selected40_entry=entry.duplicate(true)
	return true

func _selected40_side_slot_valid(bindings: RefCounted) -> bool:
	var mission: Dictionary=_state.mission;var contact: Dictionary=_state.get("accepted_contact",{})
	if mission.is_empty():
		if _state.passengers!=0 or _state.active_offer_id!=-1 or not contact.is_empty():return reject("Empty side slot retained passengers or an accepted contact")
	else:
		var passengers:=ContractProgress.occupied_passengers(_state)
		if not OrdinaryContracts.retained_mission(bindings,mission,int(_state.campaign_cursor)) or _state.passengers!=passengers:return reject("The selected story lost its independently retained side job")
		if contact.is_empty() or contact.get("offer_id")!=_state.active_offer_id or not ContractProgress.matches(_state,contact.get("offer",{}),_catalogues):return reject("The selected story's side job lost its accepted contact")
	return true

func bind_campaign_world(bindings: RefCounted,controller: RefCounted,mission: Dictionary) -> bool:
	error=""
	if not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("Bind the actual prepared campaign flight")
	var context:=campaign_flight_context(bindings,mission)
	if context.is_empty():return false
	if context!=controller.kappa_context(true):return reject("The rescue construction differs from the retained career")
	# The story owns this encounter. The accepted delivery remains in the side
	# slot and cannot acquire a random flight success/failure here.
	context.mission={}
	if not _bind_accounted_world(controller,context,controller.snapshot()):return false
	_flight.story_mission=mission.duplicate(true)
	return true

func _bind_accounted_world(controller: RefCounted,context: Dictionary,scene: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if scene.get(key)!=_state[key]:return reject("The ordinary world belongs to another career")
	if context.mission.get("kind",-1) not in [-1,0] or scene.get("combat",{}).get("provocation",{}).get("station_id")!=context.station_id or not scene.has("accounting") or not scene.get("contract_result",{}).is_empty() or controller.flight_identity()==null:return reject("This world cannot use ordinary contract-free accounting")
	if not scene.accounting.events.is_empty() or not scene.combat.reputation.events.is_empty() or controller.combat_owner().current_reputation()!=_state.reputation:return reject("Bind the ordinary world before combat changes its career")
	if not scene.combat.get("recovery",{}).is_empty():return reject("Bind the world before cargo recovery changes its career")
	_flight={"ordinary_context":context.duplicate(true),"accounting":scene.accounting.duplicate(true),
		"reputation_events":[],"settlement":{},"elapsed_ms":0,"retired":false}
	_flight_identity=controller.flight_identity()
	return true

func evaluate_flight(controller: RefCounted,radio_active: bool=false,poll_results: bool=true,periodic_poll_allowed: bool=true,radio_finished: Array=[],world_facts: Dictionary={},private_copies: bool=false) -> Dictionary:
	# The session and controller commit together. A failed result preparation
	# cannot pay, change career, discard actors or partially freeze a live flight.
	error=""
	if not _valid_flight(controller):return {}
	# A caller that already passes private forks of both skips the second copy.
	var next: RefCounted=self if private_copies else fork()
	var flight: RefCounted=controller if private_copies else controller.fork_for_frame(false)
	if not _pending_flight.is_empty():
		if controller.snapshot()!=_pending_flight:return fail("The pending result must retain its frozen flight")
		return {"session":next,"controller":flight,"opened":false}
	if not next._retain_combat_progress(flight):return fail(next.error)
	if _flight.has("ordinary_context") or not poll_results or flight.mission_context_owner().recipe().result.get("defer_to_station",false):return {"session":next,"controller":flight,"opened":false}
	var result: Dictionary=flight.poll_contract_result(radio_active,periodic_poll_allowed,radio_finished,world_facts)
	if result.is_empty():return fail(flight.error)
	var advance: Dictionary=flight.mission_context_owner().recipe().get("story_advance",{})
	# A failed story flight shows the ordinary failure result (no pay, cursor
	# unchanged); the player retries by flying the mission again.
	if not advance.is_empty() and result.mode!=0 and result.mode!=int(_rules.flight_results.success_result_mode) and not _flight.has("story_transition"):advance={}
	if not advance.is_empty():
		# A story flight moves the career on without a result screen or pay;
		# its cast and radio keep running in the same world.
		if result.mode==0 or _flight.has("story_transition"):return {"session":next,"controller":flight,"opened":false}
		if result.mode!=int(_rules.flight_results.success_result_mode) or not flight.acknowledge_contract_result():return fail("The story flight has no silent advance: "+flight.error)
		var progress: Dictionary=next._state.progress
		var earned:=Career.calculate_progress(_progress_rules,int(advance.campaign_cursor),progress.player_kills,progress.pirate_kills,progress.other_score)
		if earned.is_empty():return fail("The story advance exceeds the supported career range")
		next._state.progress.merge(earned,true);next._state.rank=earned.rank
		next._state.progress.merge(advance.get("progress",{}),true)
		var pay:=int(advance.get("previous_mission",{}).get("reward",0))
		if pay>0:next._state.credits=credit_balance(next._state.credits,pay,_rules.delivery_results)
		for station in advance.get("story_unvisit",[]):
			if not next.forget_location_visit(int(station)):return fail(next.error)
		if not advance.get("unlock_system_ids",[]).is_empty():
			next._lounges=next._lounges.fork()
			if not next._lounges.unlock_story_systems(_rules.base_navigation,advance.unlock_system_ids):return fail(next._lounges.error)
		next._state.campaign_cursor=int(advance.campaign_cursor);next._state.progress.campaign_cursor=int(advance.campaign_cursor)
		next._flight.story_transition=advance.merged({"station_id":_state.station_id},true)
		next._flight.retired=true
		next._flight.settlement=flight.snapshot().combat.get("contract_settlement",{}).duplicate(true)
		return {"session":next,"controller":flight,"opened":false}
	var opened: bool=result.mode!=0
	if opened:
		var rules: Dictionary=_rules.delivery_results
		var succeeded: bool=result.mode==int(_rules.flight_results.success_result_mode)
		# A failed story flight has no accepted job; its story job stands in.
		var mission: Dictionary=next._state.mission if not next._state.mission.is_empty() else flight.mission_context_owner().recipe().mission
		var continuation: Dictionary=flight.mission_context_owner().recipe().get("continuation",{}) if succeeded else {}
		# The admitted mission runner owns whether this flight has failed. Only
		# the wager rule changes the balance when an ordinary job is lost.
		var delta:=0 if not continuation.is_empty() else (int(mission.reward)+int(mission.bonus) if succeeded else (-int(mission.reward) if int(mission.kind)==int(_rules.flight_results.penalty_kind) else 0))
		if absi(delta)>int(rules.maximum_credit_delta):return fail("The contract settlement exceeds the supported credit range")
		if succeeded and continuation.is_empty():
			if not Numbers.integer(next._state.completed_side_missions,0,2147483646):return fail("The contract count exceeds the supported career range")
			var progress: Dictionary=next._state.progress
			var earned:=Career.calculate_progress(_progress_rules,next._state.campaign_cursor,progress.player_kills,progress.pirate_kills,int(progress.other_score)+int(rules.completion_rank_weight))
			if earned.is_empty():return fail("The contract success exceeds the supported career range")
			next._state.progress.merge(earned,true);next._state.rank=earned.rank
			next._state.completed_side_missions+=int(rules.completion_increment)
		next._state.reputation=flight.combat_owner().current_reputation()
		next._state.progress.reputation=next._state.reputation.duplicate(true)
		next._state.result_serial+=1
		next._state.pending_result={"serial":next._state.result_serial,"offer_id":next._state.active_offer_id,
			"station_id":int(mission.station_id),"kind":int(mission.kind),"mode":int(result.mode),"flight":true,
			"acknowledgement_required":true,"credit_delta":delta,"completed":succeeded,"failed":not succeeded}
		if not continuation.is_empty():
			if not ContractProgress.continue_delivery(next._state,continuation,_catalogues):return fail("The earned continuation lost its accepted contract")
			next._state.pending_result.continuation=continuation.duplicate(true)
			next._state.pending_result.result_text_id=int(continuation.result_text_id)
			next._state.pending_result.station_id=int(next._state.mission.station_id)
		next._pending_flight=flight.snapshot()
	next._flight.settlement=flight.snapshot().combat.get("contract_settlement",{}).duplicate(true)
	return {"session":next,"controller":flight,"opened":opened}

func acknowledge_flight_result(controller: RefCounted,serial: int) -> Dictionary:
	error=""
	if not _valid_flight(controller):return {}
	var pending: Dictionary=_state.get("pending_result",{})
	if pending.is_empty() or not pending.get("flight",false) or pending.serial!=serial or _pending_flight.is_empty() or controller.snapshot()!=_pending_flight:return fail("No matching frozen flight result awaits acknowledgement")
	var next:=fork();var flight: RefCounted=controller.fork_for_frame()
	if not flight.acknowledge_contract_result():return fail(flight.error)
	next._state.credits=credit_balance(int(next._state.credits),int(pending.credit_delta),_rules.delivery_results)
	next._state.last_result=pending.duplicate(true)
	next._state.last_result.acknowledgement_required=false
	next._state.last_result.notification_sound_id=int(_rules.delivery_results.notification_sound_id) if pending.completed and pending.credit_delta!=0 else -1
	if pending.get("continuation",{}).is_empty():
		next._state.mission={};next._state.active_offer_id=-1
		next._state.erase("contract_phase");next._state.erase("station_outcome")
		if next._state.has("accepted_contact"):next._state.accepted_contact={}
	next._state.pending_result={}
	next._pending_flight={};next._flight.retired=true
	next._flight.settlement=flight.snapshot().combat.contract_settlement.duplicate(true)
	return {"session":next,"controller":flight,"clear_player_control":true,"clear_world_path":true}

func finish_flight(controller: RefCounted,retain_active_mission: bool=false) -> RefCounted:
	# Arrival retains any combat after acknowledgement before releasing the
	# flight ledger. Station relocation and scene disposal belong to the caller.
	error=""
	if not _valid_flight(controller):return null
	if _flight.has("selected40_entry"):reject("Selected40 career accounting does not authorize a departure, docking or campaign result");return null
	if _flight.has("story_failure") or (not _flight.retired and not (_rules.has("world_initialization") and retain_active_mission)) or not _state.pending_result.is_empty():reject("Resolve the current contract flight before releasing it");return null
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	next._flight={}
	next._flight_identity=null
	return next

## Not generic finish_flight: only the exact native late portal can release
## selected40's ledger and advance a detached career while retaining the job.
func transfer_selected40_portal(bindings: RefCounted,controller: RefCounted,departure: RefCounted) -> RefCounted:
	error=""
	if not _valid_flight(controller):return null
	if not _selected40_side_slot_valid(bindings):return null
	if not is_instance_of(departure,load("res://src/simulation/selected40_flight_frame.gd")) or not departure.successor41_ready(bindings) or not departure.successor41_controller_matches(controller):reject("Only the retained native late-portal frame can release selected40");return null
	if _state.campaign_cursor!=40 or _state.progress.campaign_cursor!=40 or not _flight.has("selected40_entry") or not _pending_flight.is_empty() or not _state.pending_result.is_empty():reject("Selected40 has no unresolved source-owned onward transition");return null
	var source: Dictionary=departure.prepare_portal_transition()
	if _flight.selected40_entry.source_before!=source.source_before or _state.station_id!=source.return_station_id or _flight.ordinary_context.system_id!=source.return_system_id:reject("The onward portal belongs to another selected world");return null
	if departure.career_owner().snapshot()!=snapshot():reject("The onward portal has another retained career branch");return null
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	next._flight={};next._flight_identity=null;next._selected40_entry=null
	if not next._retain_story_progress(bindings,next._state.progress,40,41,_state.station_id,-1,true):reject(next.error);return null
	return next

func acknowledge_campaign_visit(bindings: RefCounted,controller: RefCounted,visit: RefCounted) -> RefCounted:
	# Keep the existing world and its accounting ledger. The new story cursor
	# changes the career; it does not regenerate ships or reset the flight clock.
	error=""
	if not _valid_flight(controller):return null
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")) or not _flight.has("ordinary_context") or _flight.has("story_transition") or not _state.pending_result.is_empty():reject("No campaign visit awaits acknowledgement in this flight");return null
	var transition: Dictionary=visit.transition()
	var scene: Dictionary=controller.snapshot()
	if transition.is_empty() or not Campaign.active_visit(bindings.mido_travel,scene.combat.get("free_context",{})):reject("The campaign visit does not belong to the active world");return null
	for key in ["base_content_id","binding_id"]:
		if transition.get(key)!=_state[key] or bindings.get(key)!=_state[key]:reject("The campaign visit belongs to another content identity");return null
	if transition.from_cursor!=_state.campaign_cursor or transition.station_id!=_state.station_id or transition.previous_mission!=Campaign.mission(bindings.mido_travel,_state.campaign_cursor) or transition.mission!=Campaign.mission(bindings.mido_travel,transition.campaign_cursor) or transition.reward_credits!=0:reject("The campaign visit changed its earned transition");return null
	return _acknowledge_flight_campaign(controller,transition)

func acknowledge_campaign_result(bindings: RefCounted,controller: RefCounted,visit: RefCounted,rescue: RefCounted) -> RefCounted:
	error=""
	if not _valid_flight(controller):return null
	if not is_instance_of(visit,load("res://src/simulation/campaign_visit.gd")) or not is_instance_of(rescue,load("res://src/simulation/kappa_rescue.gd")) or not _flight.has("story_mission") or _flight.has("story_transition") or _flight.has("story_failure") or not _state.pending_result.is_empty():reject("No campaign result awaits acknowledgement in this flight");return null
	var mission: Dictionary=_flight.story_mission
	if not Campaign.Outcome.selected(bindings,_state.campaign_cursor,mission) or not rescue.matches_flight(controller) or not visit.matches_result_observation(rescue):reject("The result lost its observed native rescue flight");return null
	var receipt: Dictionary=visit.transition();var observed: Dictionary=rescue.snapshot()
	for key in ["base_content_id","binding_id"]:
		if receipt.get(key)!=_state[key] or bindings.get(key)!=_state[key]:reject("The campaign result belongs to another career");return null
	if receipt.get("from_cursor")!=_state.campaign_cursor or receipt.get("previous_mission")!=mission or receipt.get("reward_credits")!=0:reject("The result changed its earned campaign transition");return null
	var rules: Dictionary=bindings.mido_travel.kappa_outcome
	if receipt.get("outcome")=="completed":
		if not observed.completion_ready or receipt.get("campaign_cursor")!=int(rules.success.next_cursor) or receipt.get("station_id")!=_state.station_id or not Campaign.Outcome.Equal.equal_value(receipt.get("mission"),rules.success.next_mission):reject("The rescue has no acknowledged return mission");return null
		return _acknowledge_flight_campaign(controller,receipt)
	if receipt.get("outcome")!="failed" or not observed.failure_ready or receipt.has("campaign_cursor") or receipt.get("source_state")!=int(rules.failure.continue_source_state):reject("The rescue has no acknowledged failure exit");return null
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	next._flight.story_failure=receipt.duplicate(true)
	return next

func _acknowledge_flight_campaign(controller: RefCounted,transition: Dictionary) -> RefCounted:
	var next:=fork()
	if not next._retain_combat_progress(controller):reject(next.error);return null
	var progress: Dictionary=next._state.progress
	var earned:=Career.calculate_progress(_progress_rules,transition.campaign_cursor,progress.player_kills,progress.pirate_kills,progress.other_score)
	if earned.is_empty():reject("The campaign visit exceeds the supported career range");return null
	next._state.progress.merge(earned,true);next._state.rank=earned.rank
	next._state.campaign_cursor=transition.campaign_cursor
	next._flight.story_transition=transition.duplicate(true)
	return next

## The story step a live flight has already taken, if any.
func story_transition() -> Dictionary:return _flight.get("story_transition",{}).duplicate(true)

func _valid_flight(controller: RefCounted) -> bool:
	if _flight.is_empty() or not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("The retained contract has no matching flight owner")
	if _flight_identity==null or controller.flight_identity()!=_flight_identity:return reject("The contract lost its retained native flight")
	var scene: Dictionary=controller.career_snapshot()
	for key in ["base_content_id","binding_id"]:
		if scene.get(key)!=_state[key]:return reject("The contract flight belongs to another career")
	var transition: Dictionary=_flight.get("story_transition",{})
	if transition.is_empty():
		if scene.get("campaign_cursor")!=_state.campaign_cursor:return reject("The contract flight belongs to another campaign stage")
	elif (not _flight.has("ordinary_context") and not _flight.has("encounter")) or scene.get("campaign_cursor")!=transition.from_cursor or _state.campaign_cursor!=transition.campaign_cursor or _state.station_id!=transition.station_id:
		return reject("The retained world lost its acknowledged story transition")
	if _flight.has("ordinary_context"):
		if _flight.has("selected40_entry") and scene.get("selected40_sequence",{}).get("elapsed_ms",-1)<_flight.elapsed_ms:return reject("Selected40 career lost its retained native sequence clock")
		if not scene.has("accounting") or scene.has("contract_result") or scene.get("combat",{}).get("provocation",{}).get("station_id")!=_flight.ordinary_context.station_id:return reject("The ordinary flight changed its retained station or accounting")
		return true
	if scene.get("combat",{}).get("contract_encounter")!=_flight.encounter or not scene.has("accounting") or not scene.has("contract_result"):return reject("The contract flight changed its accepted encounter")
	if scene.combat.get("contract_settlement",{})!=_flight.settlement or scene.contract_result.retired!=_flight.retired:return reject("The contract flight lost its retained result")
	if scene.contract_result.elapsed_ms<_flight.elapsed_ms:return reject("The contract flight regressed its clock")
	if _state.pending_result.is_empty() and scene.contract_result.mode!=0:return reject("The flight result was not opened by its retained contract owner")
	return true

func _retain_combat_progress(controller: RefCounted) -> bool:
	var scene: Dictionary=controller.career_snapshot()
	var accounting: Dictionary=scene.accounting
	var events: Array=scene.combat.reputation.events
	if accounting.events.slice(0,_flight.accounting.events.size())!=_flight.accounting.events or events.slice(0,_flight.reputation_events.size())!=_flight.reputation_events:return reject("The contract flight lost its retained combat history")
	var delta: Dictionary=accounting.counter_deltas
	var previous: Dictionary=_flight.accounting.counter_deltas
	var progress: Dictionary=_state.progress
	var earned:=Career.calculate_progress(_progress_rules,_state.campaign_cursor,
		int(progress.player_kills)+int(delta.player_kills)-int(previous.player_kills),
		int(progress.pirate_kills)+int(delta.pirate_kills)-int(previous.pirate_kills),int(progress.other_score))
	if earned.is_empty():return reject("Combat progress exceeds the supported career range")
	if delta.has("debris_destroyed"):
		var count:=int(progress.get("debris_destroyed",0))+int(delta.debris_destroyed)-int(previous.get("debris_destroyed",0))
		if not Numbers.integer(count,0,2147483647):return reject("Debris progress exceeds the supported career range")
		earned.debris_destroyed=count
	# The native world accumulates accepted transfers once. Retain only the
	# new portion; repeated polling, story acknowledgement and docking can all
	# observe the same frame without granting another career increment.
	var recovered: int=scene.combat.get("recovery",{}).get("accepted_quantity",0)
	var retained: int=_flight.get("cargo_recovered",0)
	if recovered!=retained or progress.has("cargo_recovered"):
		var count:=Career.recovered_cargo_total(int(progress.get("cargo_recovered",0)),recovered,retained)
		if count<0:return reject("The flight lost its retained recovery quantity or exceeded the supported career range")
		earned.cargo_recovered=count
	# Alien Hunter: units picked up from Void (kind 9) crates. Like story kills,
	# a smaller total than retained means a new combat world after a jump.
	var remains: Variant=scene.combat.get("recovery",{}).get("kind9_quantity",0)
	if not Numbers.integer(remains,0,2147483647):return reject("The flight lost its retained Void cargo quantity")
	var retained_remains: int=_flight.get("alien_remains",0)
	if remains<retained_remains:retained_remains=0;_flight.alien_remains=0
	var new_remains: int=int(remains)-retained_remains
	var booze_flags: Variant=scene.combat.get("recovery",{}).get("item_flags",[])
	if not booze_flags is Array:return reject("The flight lost its retained Barkeeper item history")
	var booze_mask: Variant=progress.get("booze_types_mask",0)
	if not Numbers.integer(booze_mask,0,BaseMedals.BOOZE_TYPE_MASK):return reject("The retained Barkeeper type history exceeds the supported source domain")
	for index in booze_flags:
		if not Numbers.integer(index,0,BaseMedals.BOOZE_LAST_ID-BaseMedals.BOOZE_FIRST_ID):return reject("The flight has an invalid Barkeeper item index")
		booze_mask=int(booze_mask) | (1 << int(index))
	if not booze_flags.is_empty() or progress.has("booze_types_mask"):earned.booze_types_mask=int(booze_mask)
	# A story mission may count ships its weapon destroys (Valkyrie 59: Liberators).
	var story_owner: RefCounted=controller.mission_context_owner() if controller.has_method("mission_context_owner") else null
	var excluded: Array=[] if story_owner==null else story_owner.recipe().get("story_excluded_actors",[])
	var counted: Array=scene.combat.get("lethal_items",[]).filter(func(kill):return StoryFlights.counts_kill(_state.campaign_cursor,kill,excluded))
	# Each jump builds a new combat world whose kill log starts empty; a
	# shorter log than the retained count means a new world (kills are polled
	# every frame, so none are lost across the switch).
	var retained_kills: int=_flight.get("story_kills",0)
	if counted.size()<retained_kills:retained_kills=0;_flight.story_kills=0
	if counted.size()>retained_kills:
		var total:=int(progress.get("story_counter",0))+counted.size()-retained_kills
		if not Numbers.integer(total,0,2147483647):return reject("The story counter exceeds the supported career range")
		earned.story_counter=total
	var standing: Dictionary=scene.combat.get("current_reputation",{})
	if not Reputation.valid_state(standing):return reject("The flight lost its retained reputation")
	_state.progress.merge(earned,true);_state.rank=earned.rank
	_state.reputation=standing;_state.progress.reputation=standing.duplicate(true)
	_flight.accounting=accounting.duplicate(true);_flight.reputation_events=events.duplicate(true)
	if recovered>0:_flight.cargo_recovered=recovered
	if new_remains>0:
		_state.stats=_state.get("stats",{}).duplicate()
		_state.stats.alien_remains=mini(int(_state.stats.get("alien_remains",0))+new_remains,2147483647)
		_flight.alien_remains=int(remains)
	if counted.size()>retained_kills:_flight.story_kills=counted.size()
	_flight.elapsed_ms=scene.selected40_sequence.elapsed_ms if _flight.has("selected40_entry") else scene.get("contract_result",{}).get("elapsed_ms",0)
	var capability: RefCounted=controller.mission_context_owner()
	if _flight.has("encounter") and capability!=null and capability.recipe().result.get("defer_to_station",false):
		var observed: Dictionary=controller.defeat_status()
		if observed.is_empty():return reject("The deferred station objective lost its observed actors")
		if observed.failed:_state.station_outcome=2
		elif observed.satisfied and _state.get("station_outcome",0)!=2:_state.station_outcome=1
	return true

static func credit_balance(current: int,delta: int,rules: Dictionary) -> int:
	if absi(delta)>int(rules.maximum_credit_delta):return current
	var signed:=(current+delta)&0xffffffff
	if signed>=0x80000000:signed-=0x100000000
	return maxi(int(rules.minimum_credits),signed)

func _station_inventory(equipment: RefCounted,bindings: RefCounted=null) -> Dictionary:
	if not equipment is Equipment:reject("A delivery result requires the retained station inventory");return {}
	var owned: Dictionary=equipment.snapshot()
	if not owned.get("training_inventory_released",false) or not owned.get("prototype_drill_replaced",false) or not equipment.cargo_cache_valid():reject("The delivery inventory is unavailable");return {}
	for key in ["base_content_id","binding_id"]:
		if owned.loadout.get(key)!=_state[key]:reject("The delivery inventory belongs to another content identity");return {}
	if load("res://src/simulation/mission_station_context.gd").permits(bindings,_state.campaign_cursor,owned.loadout.station_id,_station_context) and not _station_context.completed_career(bindings):
		if _state.station_id!=owned.loadout.station_id or owned.loadout.system_id!=_station_context.snapshot().system_id:return fail("The continuation station changed its retained inventory location")
	elif bindings!=null and Campaign.supported(bindings,_state.campaign_cursor):
		var free_rules: Dictionary=load("res://src/content/free_flight_definitions.gd").flight(bindings,int(owned.loadout.station_id),_state.campaign_cursor)
		if free_rules.is_empty() or owned.loadout.system_id!=int(free_rules.system_id) or _state.base_content_id!=bindings.base_content_id or _state.binding_id!=bindings.binding_id:reject("The ordinary station is outside the supported content");return {}
	elif bindings!=null and load("res://src/content/nehma_return_definitions.gd").station_supported(bindings,_state.campaign_cursor,int(owned.loadout.station_id)):
		# Retain the acknowledged station-only continuation without admitting its
		# as-yet unsupported special flight or changing the living world cursor.
		var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").location(bindings,int(owned.loadout.station_id))
		if world.is_empty() or owned.loadout.system_id!=int(world.system_id):reject("The continuation station differs from its source world");return {}
	elif owned.loadout.system_id!=int(_rules.system_id) or owned.loadout.station_id not in _stations:reject("The delivery station is outside the supported system");return {}
	var candidate: RefCounted=equipment.fork()
	if not candidate.retain_flight_cargo(owned.cargo):reject(candidate.error);return {}
	return owned

func result_pending() -> bool:return not _state.get("pending_result",{}).is_empty()
func station_id() -> int:return int(_state.get("station_id",-1))

func has_progress(key: String) -> bool:return _state.get("progress",{}).has(key)

func snapshot() -> Dictionary:
	var result:=_copy_state()
	if not _flight.is_empty():result.flight=_flight.duplicate(true)
	if _lounges!=null:result.lounges=_lounges.read_snapshot()
	if _void_source!=null:result.void_source=_void_source.snapshot()
	if _blueprints!=null:result.blueprints=_blueprints.read_snapshot()
	return result

## A private copy of the live state. The generated contact population is only
## ever replaced whole, so its read-only copy is shared instead of copied.
func _copy_state() -> Dictionary:
	var population: Variant=_state.get("population")
	if not population is Dictionary:return _state.duplicate(true)
	# Restored saves arrive editable; the same value is frozen on first copy.
	if not population.is_read_only():population=Readonly.freeze(population.duplicate(true));_state.population=population
	var copy: Dictionary=_state.duplicate();copy.erase("population")
	copy=copy.duplicate(true);copy.population=population
	return copy

## The career a flight frame forked for itself is updated in place by that
## frame, which is discarded whole on failure; any other caller gets a fork.
func frame_copy() -> RefCounted:return self if FrameTransaction.owns(_txn) else fork()

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._txn=FrameTransaction.current
	# Configuration is immutable after setup; only live state needs a private copy.
	result._state=_copy_state();result._rules=_rules;result._cabins=_cabins
	result._progress_rules=_progress_rules;result._stations=_stations;result._result_inventory=_result_inventory.duplicate(true)
	result._flight=_flight.duplicate(true);result._pending_flight=_pending_flight.duplicate(true)
	result._flight_identity=_flight_identity
	# Locations are copy-on-write: every mutation first detaches a private fork.
	result._lounges=_lounges
	result._catalogues=_catalogues
	result._void_source=_void_source.fork() if _void_source!=null else null
	result._blueprints=_blueprints.fork_for_transaction() if _blueprints!=null else null
	result._selected40_entry=_selected40_entry.fork() if _selected40_entry!=null else null
	result._station_context=_station_context
	result._shopping_booze_quantity=_shopping_booze_quantity
	return result

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
