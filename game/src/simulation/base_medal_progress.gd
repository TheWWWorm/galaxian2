extends RefCounted
## Cumulative native medal evidence, banked by the station career transaction.
## Unknown is not unearned: unsupported histories cannot grant or deny an award.
const UNKNOWN := -1
const BASE_COUNT := 36
const BLUEPRINT_GOLD_COUNT := 13
const BOOZE_FIRST_ID := 132
const BOOZE_LAST_ID := 153
const BOOZE_TYPE_MASK := (1 << (BOOZE_LAST_ID-BOOZE_FIRST_ID+1))-1
const STATION_VISIT_THRESHOLDS := [100,50,25]
const SYSTEM_VISIT_THRESHOLDS := [22,10,5]
const COUNTERS := {
	2:{"path":["progress","mined_ore_types_mask"],"thresholds":[11,8,5],"strict":false,"bit_mask":2047},
	3:{"path":["progress","mined_core_types_mask"],"thresholds":[11,8,5],"strict":false,"bit_mask":2047},
	4:{"path":["progress","player_kills"],"thresholds":[250,100,50],"strict":false},
	5:{"path":["delivery_statistics","cargo"],"thresholds":[200,100,25],"strict":true},
	6:{"path":["progress","mined_ore_tons"],"thresholds":[1000,500,100],"strict":true},
	7:{"path":["progress","mined_cores"],"thresholds":[25,10,3],"strict":true},
	8:{"path":["progress","purchased_booze_quantity"],"thresholds":[1000,100,25],"strict":true},
	9:{"path":["progress","booze_types_mask"],"thresholds":[22,16,5],"strict":false,"bit_mask":BOOZE_TYPE_MASK},
	10:{"path":["progress","debris_destroyed"],"thresholds":[150,100,30],"strict":true},
	13:{"path":["blueprints_owned"],"thresholds":[13,6,3],"strict":false},
	14:{"path":["blueprints_constructed"],"thresholds":[13,6,3],"strict":false},
	16:{"path":["completed_side_missions"],"thresholds":[50,25,5],"strict":true},
	17:{"path":["travel_statistics","jumpgates_used"],"thresholds":[100,50,10],"strict":false},
	18:{"path":["delivery_statistics","passengers"],"thresholds":[50,20,5],"strict":true},
	20:{"path":["progress","nuclear_bomb_detonations"],"thresholds":[50,20,5],"strict":true},
	24:{"path":["progress","cargo_recovered"],"thresholds":[500,200,50],"strict":false},
	26:{"path":["conversations"],"thresholds":[100,50,20],"strict":true},
	29:{"path":["progress","asteroids_destroyed"],"thresholds":[250,150,50],"strict":true},
	32:{"path":["rejected_jobs"],"thresholds":[50],"strict":true},
	# Station-observed career stats. These start counting when first seen, so a
	# missing value means zero progress rather than unknown history.
	1:{"path":["stats","min_arrival_hull_percent"],"thresholds":[5,15,30],"below":true,"default":-1},
	15:{"path":["stats","play_ms"],"thresholds":[20,10,5],"strict":true,"default":0,"scale":3600000},
	19:{"path":["stats","cloak_ms"],"thresholds":[5,3,2],"strict":false,"default":0,"scale":60000},
	21:{"path":["stats","alien_remains"],"thresholds":[25,10,5],"strict":true,"default":0},
	22:{"path":["stats","unarmed_departures"],"thresholds":[0],"strict":true,"default":0},
	23:{"path":["stats","max_primaries"],"thresholds":[4,3,2],"strict":false,"default":0},
	25:{"path":["credits"],"thresholds":[1000000,500000,125000],"strict":false,"default":0},
	27:{"path":["wingmen","hired_total"],"thresholds":[20,10,3],"strict":true,"default":0},
	31:{"path":["stats","max_free_cargo"],"thresholds":[500,250,100],"strict":true,"default":0},
	33:{"path":["stats","accepted_jobs"],"thresholds":[10],"strict":true,"default":0},
	34:{"path":["stats","accepted_jobs"],"thresholds":[12],"strict":true,"default":0},
}
## Rows whose evidence can later fall (current credits) keep their award.
const STICKY:=[25,28]
## Original description thresholds for rows without a counter rule.
const FIXED_THRESHOLDS:={0:[0],28:[1],30:[0],35:[0]}
const STAT_KEYS:=["play_ms","cloak_ms","alien_remains","unarmed_departures","max_primaries","max_free_cargo","accepted_jobs"]

static func booze_type_bit(item_id: int) -> int:
	if item_id<BOOZE_FIRST_ID or item_id>BOOZE_LAST_ID:return 0
	return 1 << (item_id-BOOZE_FIRST_ID)

static func _count(value: Variant) -> bool:
	return value is int and value>=0 and value<=2147483647

static func _bit_count(value: int) -> int:
	var remaining:=value;var result:=0
	while remaining>0:
		result+=int(remaining & 1);remaining>>=1
	return result

static func _visit_ids(value: Variant) -> int:
	if not value is Array:return -1
	var previous:=-1
	for id in value:
		if not id is int or id<0 or id>2147483647 or id<=previous:return -1
		previous=id
	return value.size()

static func blueprint_counts(state: Dictionary) -> Dictionary:
	if not state.get("entries") is Array:return {}
	var owned:=0;var built:=0
	for row in state.entries:
		if not row is Dictionary or not row.get("available") is bool or not _count(row.get("completed",0)):return {}
		owned+=int(row.available)
		built+=int(row.get("completed",0)>0)
	return {"blueprints_owned":owned,"blueprints_constructed":built}

static func _blueprint_counts_valid(counts: Dictionary) -> bool:
	if counts.size()!=2:return false
	for key in ["blueprints_owned","blueprints_constructed"]:
		if not _count(counts.get(key)):return false
	return counts.blueprints_constructed<=counts.blueprints_owned

static func _tier(value: int,rule: Dictionary) -> int:
	for index in rule.thresholds.size():
		var limit: int=int(rule.thresholds[index])*int(rule.get("scale",1))
		if rule.get("below",false):
			if value>=0 and value<=limit:return index+1
			continue
		var reached: bool=value>limit if rule.strict else value>=limit
		if reached:return index+1
	return 0

static func _champion_level(levels: Array) -> int:
	if levels.size()!=BASE_COUNT:return UNKNOWN
	for id in 35:
		if levels[id]==UNKNOWN:return UNKNOWN
		if levels[id]<=0:return 0
	return 1

static func observe(career: Dictionary,blueprints: Dictionary={}) -> Dictionary:
	if not _count(career.get("campaign_cursor")):return {}
	var counts:=blueprint_counts(blueprints)
	if not blueprints.is_empty() and not _blueprint_counts_valid(counts):return {}
	var levels: Array=[];levels.resize(BASE_COUNT);levels.fill(UNKNOWN)
	# The native campaign starts with its original service medal. Completion is
	# independent of every other medal and cannot establish the aggregate alone.
	levels[0]=1;levels[30]=1 if career.campaign_cursor>=45 else 0
	for id in COUNTERS:
		var rule: Dictionary=COUNTERS[id]
		var value: Variant=counts if id in [13,14] else career
		for key in rule.path:
			value=value.get(key) if value is Dictionary else null
		if value==null:
			if not rule.has("default"):continue
			value=rule.default
		if not _count(value) and not (rule.get("below",false) and value is int and value==-1):return {}
		if rule.has("bit_mask"):
			if int(value)>int(rule.bit_mask):return {}
			value=_bit_count(int(value))
		levels[id]=_tier(value,rule)
	var travel: Variant=career.get("travel_statistics")
	if travel!=null:
		if not travel is Dictionary:return {}
		var station_ids: Variant=travel.get("visited_station_ids")
		var system_ids: Variant=travel.get("visited_system_ids")
		if station_ids!=null or system_ids!=null:
			var stations:=_visit_ids(station_ids);var systems:=_visit_ids(system_ids)
			if stations<0 or systems<0:return {}
			levels[11]=_tier(stations,{"thresholds":STATION_VISIT_THRESHOLDS,"strict":false})
			var first_22:=0
			for id in system_ids:
				if id<22:first_22+=1
			levels[12]=_tier(first_22,{"thresholds":SYSTEM_VISIT_THRESHOLDS,"strict":false})
	var reputation: Variant=career.get("reputation")
	if reputation!=null:
		if not reputation is Dictionary or reputation.size()!=2 or reputation.get("override")!=-1:return {}
		var axes: Variant=reputation.get("axes")
		if not axes is Array or axes.size()!=2 or not axes.all(func(value):return value is int and value>=-100 and value<=100):return {}
		if axes.any(func(value):return int(value)<-70 or int(value)>70):levels[28]=1
	levels[35]=_champion_level(levels)
	return {"version":1,"levels":levels}

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=2 or not value.get("version") is int or value.version!=1 or not value.get("levels") is Array or value.levels.size()!=BASE_COUNT:return false
	for id in BASE_COUNT:
		var level: Variant=value.levels[id]
		if not level is int or level<UNKNOWN or level>3:return false
		if id==0:
			if level!=1:return false
		elif id==30:
			if level not in [0,1]:return false
		elif id in [11,12]:
			pass
		elif id in [22,28,33,34]:
			if level not in [UNKNOWN,0,1]:return false
		elif id==35:
			if level not in [UNKNOWN,0,1]:return false
		elif not COUNTERS.has(id) and level!=UNKNOWN:return false
	if value.levels[35]!=_champion_level(value.levels):return false
	return true

static func valid_retained(value: Variant,career: Dictionary,blueprints: Dictionary={}) -> bool:
	if not valid_state(value):return false
	var observed:=observe(career,blueprints)
	if observed.is_empty():return false
	for id in BASE_COUNT:
		var prior: int=value.levels[id];var current: int=observed.levels[id]
		# Every supported predicate is cumulative. A retained award needs at
		# least its original evidence; absent legacy fields do not mean zero.
		# Renegade is the exception: current standing can establish the award,
		# while the original retained medal survives later diplomatic repair.
		if id in STICKY and prior>0:continue
		if prior!=UNKNOWN and current==UNKNOWN:return false
		if prior>0 and (current<=0 or current>prior):return false
	return true

static func commit(previous: Dictionary,career: Dictionary,blueprints: Dictionary={}) -> Dictionary:
	var observed:=observe(career,blueprints)
	if observed.is_empty():return {}
	if previous.is_empty():return observed
	if not valid_retained(previous,career,blueprints):return {}
	var retained:=previous.duplicate(true)
	for id in BASE_COUNT:
		var level: int=observed.levels[id];var prior: int=retained.levels[id]
		if prior==UNKNOWN or (level>0 and (prior==0 or level<prior)):
			retained.levels[id]=level
	return retained

static func stock_progress(career: Dictionary,blueprints: Dictionary={}) -> Dictionary:
	var counts:=blueprint_counts(blueprints)
	if career.has("base_medals"):counts.retained=career.base_medals.duplicate(true)
	return counts

static func valid_counts(counts: Dictionary) -> bool:
	if not counts.has("retained"):return _blueprint_counts_valid(counts)
	if not valid_state(counts.retained):return false
	var remaining:=counts.duplicate(true);remaining.erase("retained")
	if remaining.is_empty():return true
	if not _blueprint_counts_valid(remaining):return false
	# A stock receipt keeps the native evidence at generation, not a bare flag.
	for id in [13,14]:
		var level: int=counts.retained.levels[id]
		var observed:=_tier(remaining.blueprints_owned if id==13 else remaining.blueprints_constructed,COUNTERS[id])
		if level>0 and (observed==0 or observed>level):return false
	return true

static func all_base_gold(cursor: int,counts: Dictionary={}) -> Variant:
	if not counts.is_empty() and not valid_counts(counts):return null
	if cursor<45:return false
	if counts.has("blueprints_owned") and (counts.blueprints_owned<BLUEPRINT_GOLD_COUNT or counts.blueprints_constructed<BLUEPRINT_GOLD_COUNT):return false
	if not counts.has("retained"):return null
	var unknown:=false
	for level in counts.retained.levels:
		if level==UNKNOWN:unknown=true
		elif level!=1:return false
	return null if unknown else true

## Original credit reward for reaching a tier (1 gold, 2 silver, 3 bronze).
static func reward_credits(level: int) -> int:
	return [0,5000,2500,1000][level] if level>=1 and level<=3 else 0

static func valid_notices(value: Variant) -> bool:
	# Add-on rows 36-44 have their gold tier only.
	if not value is Array or value.is_empty() or value.size()>BASE_COUNT*3+9:return false
	return value.all(func(row):return row is Array and row.size()==2 and row[0] is int and row[0]>=0 and row[0]<BASE_COUNT+9 and row[1] is int and row[1]>=1 and row[1]<=(1 if row[0]>=BASE_COUNT else 3))

## Threshold shown in a medal's description for an earned level (1 gold .. 3 bronze).
static func description_value(id: int,level: int) -> int:
	var visits:={11:STATION_VISIT_THRESHOLDS,12:SYSTEM_VISIT_THRESHOLDS}
	var thresholds: Array=COUNTERS[id].thresholds if COUNTERS.has(id) else visits[id] if visits.has(id) else FIXED_THRESHOLDS.get(id,[0])
	return int(thresholds[clampi(level-1,0,thresholds.size()-1)])

## Station-observed stats are plain non-negative counters (hull percent may be -1).
static func valid_stats(value: Variant) -> bool:
	if not value is Dictionary:return false
	for key in value:
		if key=="min_arrival_hull_percent":
			if not value[key] is int or value[key]<-1 or value[key]>100:return false
		elif key not in STAT_KEYS or not _count(value[key]):return false
	return true
