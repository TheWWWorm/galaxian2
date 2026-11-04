extends RefCounted
## Valkyrie's special locations: stations with their own assemblies and orbits
## that have no station at all.
const Valkyrie=preload("res://src/content/valkyrie_campaign_definitions.gd")
## Station exterior layers (hull, emissive, additive) for stations that do not
## use their station-ID meshes: Kothar's research station and the Valkyrie base.
const STATION_MODELS:={100:[16931,16932,16933],101:[16928,16929,16930]}
## Orbits without a station while their story is active.
const EMPTY_ORBITS:=[102,103,104,109,110,128,129,130]
## The Valkyrie base is destroyed once its story is over.
const DESTROYED_AFTER:={101:83,111:93}

static func station_models(bindings: RefCounted,station_id: int) -> Array:
	if not Valkyrie.available(bindings) or not STATION_MODELS.has(station_id):return []
	return STATION_MODELS[station_id].duplicate()

## Star-map planet sizes past the imported 22: the App Store table goes on
## 256, 0, 256, 256, 192, 256 for types 22-27 (Talidor and Ginoya planets,
## Katashán's type 26).
const MAP_PLANET_SIZES:=[256,0,256,256,192,256]
static func map_planet_sizes(bindings: RefCounted,imported: Array) -> Array:
	if not Valkyrie.available(bindings) or imported.size()!=22:return imported
	return imported+MAP_PLANET_SIZES

## Star-map sun textures past the imported 16 (sky textures 16-18), and
## Ginoya's map sun, which is always texture 10036 (verified initStarSystem).
const MAP_SUN_TEXTURES:=[10038,10033,10037]
const GINOYA_MAP_SUN:=10036
static func map_sun_texture(bindings: RefCounted,imported: Array,system_id: int,sky_index: int) -> int:
	var known: Array=imported+MAP_SUN_TEXTURES if Valkyrie.available(bindings) and imported.size()==16 else imported
	if Valkyrie.available(bindings) and system_id==int(SUPERNOVA.system_id):return GINOYA_MAP_SUN
	return int(known[sky_index]) if sky_index>=0 and sky_index<known.size() else -1

static func empty_orbit(station_id: int,cursor: int) -> bool:
	return station_id in EMPTY_ORBITS or (DESTROYED_AFTER.has(station_id) and cursor>int(DESTROYED_AFTER[station_id]))

## Station markets that differ from the ordinary generator. Items: "weapons"
## (weapons only), "weapons_or_subtype" (weapons plus one subtype), "category"
## (one category), "goods_list" (commodities from a list plus every system's
## goods), "none". A "ships" list replaces the random shipyard.
const STOCK:={
	101:{"items":"weapons","ships":[]},
	105:{"items":"weapons_or_subtype","subtype":28,"low_tech":false},
	106:{"items":"goods_list","list":[101,102,103,107,108,109,114,124,0],"category":4},
	107:{"items":"category","category":3,"low_tech":false,"ships":[2,11,23,24,25,32,48,60]},
	108:{"items":"none","ships":[]},
	100:{"ships":[37,38,40],"from_cursor":84},
	111:{"items":"none","ships":[],"until_cursor":157},
	112:{"items":"none","ships":[],"until_cursor":157},
	113:{"items":"none","ships":[],"until_cursor":157},
}
const WEAPON_CATEGORIES:=[0,1,2]

## Story items added to a station's buy list (V1; verified
## Generator::getItemBuyList): Bak S'ondorr (126) always sells K'mirkk Toad
## Mutagen (209), one unit while the cursor is 117, else 1-10; every Loma (25)
## station sells Signature: Vossk (190) while the cursor is 139. These items
## never come from the random stock.
const STORY_OFFERS:=[{"station_id":126,"item_id":209,"quantity":[1,10],"quantity_at":{117:1}},
	{"system_id":25,"item_id":190,"quantity":[1,1],"cursors":[139,139]}]
## Volatile cargo (V2; verified Ship::hasVolatileGoods, PlayerEgo::update,
## StarMap::OnTouchEnd): while any of these is in the hold the Khador Drive is
## refused (text 601), blueprint shipping is refused (text 278), and an
## instability level 0..1 rises: per second of boost 0.13 (Polytron Boost 195:
## 0.17), 0.5 per second in state OPEN (see s117-140.md), plus twice the
## largest per-frame steering change. At 1 the ship explodes. It returns to 0
## only once no volatile cargo is carried. A warning sound loops meanwhile.
const VOLATILE_GOODS:={"items":[209,204],"boost_rate":0.13,"boost_rates":{195:0.17},"steer_scale":2.0,"drive_text_id":601,"shipping_text_id":278}

## Items that never come from the random stock (verified getItemBuyList).
const STORY_OFFER_ITEMS:=[209,210,217]
static func story_offers(station_id: int,system_id: int,cursor: int) -> Array:
	var result:=[]
	for row in STORY_OFFERS:
		if int(row.get("station_id",station_id))!=station_id or int(row.get("system_id",system_id))!=system_id:continue
		var span: Array=row.get("cursors",[cursor,cursor])
		if cursor<int(span[0]) or cursor>int(span[1]):continue
		var amount: Array=row.quantity
		if row.get("quantity_at",{}).has(cursor):amount=[int(row.quantity_at[cursor]),int(row.quantity_at[cursor])]
		result.append({"item_id":int(row.item_id),"quantity":amount.duplicate()})
	return result

## Ginoya's supernova (verified Level::createSpace, Level::update,
## Status::getGammaRayDamagePerSecond). While the cursor is below 158 Ginoya
## uses sky 15 plus two overlay meshes (texture 10084, 10085 from 106); at 89
## the pre-supernova sky (mesh 17805, texture 10070). The sun grows 1.37x after
## the 89 blast.
const SUPERNOVA:={"system_id":27,"until_cursor":157,"intro_cursor":89,"intro_sky":[17805,10070],
	"sky":[17815,10080],"overlay_meshes":[17824,17825],"overlay_textures":[[105,10084],[158,10085]],
	# Sun size factor: [up to cursor, scale] (it swells at 106).
	"sun_scales":[[105,0.9918],[157,1.3733]],
	# Flares: [up to cursor, animation speed]; they start 1 s into their loop.
	"overlay_speeds":[[106,1.0],[157,1.5]],"overlay_start_ms":1000,
	# StarSystem's streak mesh texture in the supernova system (sn_sun_011): the
	# glare sprite and the streak.
	"glare_texture":11742}

## The Naneroh implosion bomb (105, LevelScript stages 11-13), times from the
## launch 2.5 s after "Bombs away!": the bomb (model 14247, sound 14) flies on
## from the ship at 13 units/ms with the camera on it; at 6.5 s sound 2248 and
## the sun implodes (x0.95 per 60 Hz frame); at 7.5 s the screen whitens over
## 0.5 s, then clears over 2 s on the swollen sun (1.3733) while the ship,
## turned away from the sun, is thrown off at 12 units/ms tumbling 1.25 rad/s
## on two axes. Assumptions: the camera rumble and the blast's effect on the
## stealth fighters are not shown.
const SUPERNOVA_BOMB:={"model_id":14247,"speed":13.0,"launch_sound":14,"implode_ms":6500,"implode_sound":2248,
	"shrink_per_frame":0.95,"flash_ms":7500,"flash_in_ms":500,"return_ms":8000,"flash_out_ms":2000,"flee_speed":12.0,"tumble_ms_per_radian":800.0}

## The Naneroh blast (89, LevelScript), times from 30 s into the scene: a
## Terran container (16992) trailing an animated beam (14229, pointing back,
## at half speed) starts 500 above the camera and flies for the sun at 10
## units/ms plus 10% of its distance each 60 Hz frame, until 200 km out. At
## 8 s sound 2248 and the sun implodes (x0.95 a frame); at 9 s the screen
## whitens over 0.5 s, then clears over 10 s on the newborn supernova (the
## sun at 0.6867, growing 0.00004 per ms); 7 s later it fades to black over
## 1 s. Assumptions: the supernova sun/sky textures (11761/11762) are not
## recovered, so the old sky stays; no camera rumble.
const NANEROH_BLAST:={"model_id":16992,"trail_model_id":14229,"launch":"camera","rise":500.0,"speed":10.0,"growth_per_frame":0.1,"max_distance":200000.0,
	"launch_sound":-1,"implode_ms":8000,"implode_sound":2248,"shrink_per_frame":0.95,"flash_ms":9000,"flash_in_ms":500,"return_ms":9500,"flash_out_ms":10000,
	"after_scale":0.6867,"after_growth_per_ms":0.00004,"black_ms":16500,"black_in_ms":1000}

## A recipe "supernova" action's scene by name ("" the 105 bomb).
static func supernova_scene(name: String) -> Dictionary:return NANEROH_BLAST if name=="naneroh_blast" else SUPERNOVA_BOMB

## The Valkyrie finale (157, LevelScript stages 9-12). Stage times come from
## the recipe's array_finale actions: "hit" (Keith's line 13 ends), "burn"
## (line 14 ends), "charge" (3 s after line 15 ends). Hit: explosion sound
## 2244 now and 6 s later; Valkyrie burns (19095/19096) from 0.3 s. Burn: it
## burns harder (19097/19098); a big explosion (2243) 9 s after the hit.
## Charge: 6 s later the array beam (19061-19063, pointing -z) fires with
## 2247; at 10 s the camera flies toward the sun at 35 units/ms; 5.7 s into
## that flight Valkyrie is gone in a white flash (2248, white by 6.6 s).
## Assumptions: the burning and beam meshes sit at Valkyrie's origin (the
## array's own point was not recovered); explosion bursts, camera rumble and
## the second, faster drift are not drawn; the burning meshes need an import
## that lists payload meshes (v205) and are skipped otherwise.
const VALKYRIE_FINALE:={"beam":[19061,19062,19063],"burn":[19095,19096],"burn_hard":[19097,19098],"burn_after_ms":300,
	"sounds":[["hit",0,2244],["hit",6000,2244],["hit",9000,2243],["charge",6000,2247],["fly",5700,2248]],
	"fire_ms":6000,"fly_ms":10000,"fly_speed":35.0,"vanish_ms":5700,"white_end_ms":6600,
	# Explosions (the ordinary look-at explosion 16820): [stage, ms, offset from
	# the array point, scale]. Scales are not recovered (assumption).
	# Camera rumble (original shake: strength x a random -20..19 per look axis):
	# [stage, from ms, until stage (or "" = end), strength, ramp ms].
	"rumble":[["hit",9000,"charge",30.0,0],["fly",0,"",30.0,6500]],
	"burst_model":16820,"bursts":[["hit",0,[-2000,1000,-8000],1.5],["hit",6000,[-6000,2000,-10000],1.5],["hit",9000,[0,0,0],4.0],["fly",5500,[0,0,0],5.0]]}

## The supernova flare layers at this location: [{mesh_id, texture_id, speed}],
## none outside Ginoya, at the blast (89) or after the reversal.
static func supernova_sun_scale(system_id: int,cursor: int) -> float:
	if system_id!=int(SUPERNOVA.system_id):return 1.0
	for row in SUPERNOVA.sun_scales:
		if cursor<=int(row[0]):return float(row[1])
	return 1.0

static func supernova_flares(system_id: int,cursor: int) -> Array:
	if system_id!=int(SUPERNOVA.system_id) or cursor==int(SUPERNOVA.intro_cursor) or cursor>int(SUPERNOVA.until_cursor):return []
	var texture:=-1;var speed:=0.0
	for row in SUPERNOVA.overlay_textures:
		if cursor<=int(row[0]):texture=int(row[1]);break
	for row in SUPERNOVA.overlay_speeds:
		if cursor<=int(row[0]):speed=float(row[1]);break
	return SUPERNOVA.overlay_meshes.map(func(id):return {"mesh_id":int(id),"texture_id":texture,"mode":2,"speed":speed})
## Gamma loss per second in each Ginoya orbit: [[from cursor, rate], ...]
## (the last band whose cursor is reached applies). A fitted gamma shield
## (sort 38) cuts it by its attribute-52 percentage. Below 15 a HUD warning;
## at 0 the ship is destroyed. Gamma starts at 100 in every flight whose
## orbit has no radiation; story moves keep it.
const GAMMA_RATES:={109:[[0,0.7],[106,3.0],[158,1.0]],110:[[0,0.4],[106,2.0],[158,0.0]],
	111:[[0,0.4],[106,1.0],[158,0.0]],112:[[0,0.3],[106,0.5],[158,0.0]],113:[[0,0.2],[106,0.3],[158,0.0]]}
const GAMMA_SHIELD_SORT:=38
const GAMMA_SHIELD_ATTRIBUTE:=52
const GAMMA_WARNING:=15
const GAMMA_NOTICE:=44

static func gamma_rate(station_id: int,cursor: int) -> float:
	var rate:=0.0
	for band in GAMMA_RATES.get(station_id,[]):
		if cursor>=int(band[0]):rate=float(band[1])
	return rate

## Once Valkyrie is won (cursor above 83) and owned, Vossk stations may also
## sell the S'Kanarr (39) and ship 41, each on a 1-in-2 draw.
const WON_SHIPS:={"after_cursor":83,"faction":1,"draw_bound":2,"ships":[[39,1],[41,1]]}

## Quineros (107) also sells each Most Wanted board's last criminal's ship
## (entries 6/12/18/24: ships 45-48) once he is terminated, as a pirate (race
## 8) build (verified Generator::getShipBuyList). Docking announces it (3221).
const WANTED_SHIPS:={"station_id":107,"entries":[6,12,18,24],"faction":8}
static func wanted_ships(progress: Dictionary,table: Array) -> Array:
	var state: Variant=progress.get("wanted")
	var ships:=[]
	if not state is Dictionary or not state.get("entries") is Array or state.entries.size()!=table.size():return ships
	for index in WANTED_SHIPS.entries:
		if index<table.size() and (state.entries[index].get("dead",false) or state.entries[index].get("surrendered",false)):ships.append(int(table[index].ship))
	return ships

## The docking announcement for the first terminated ship not yet announced
## in this game run: {} or {"key","text_id","name","ship_text_id"}.
const WANTED_SHIP_TEXT:=3221
const SHIP_NAME_TEXT_BASE:=902
static func wanted_ship_notice(progress: Dictionary,table: Array,shown: Dictionary) -> Dictionary:
	var state: Variant=progress.get("wanted")
	if not state is Dictionary or not state.get("entries") is Array or state.entries.size()!=table.size():return {}
	for index in WANTED_SHIPS.entries:
		var key:="wanted_%d"%index
		if index<table.size() and not shown.has(key) and (state.entries[index].get("dead",false) or state.entries[index].get("surrendered",false)):
			return {"key":key,"text_id":WANTED_SHIP_TEXT,"name":str(table[index].name),"ship_text_id":SHIP_NAME_TEXT_BASE+int(table[index].ship)}
	return {}

## Criminals added to the Most Wanted boards by this docking: 3219 for one,
## 3220 ("#N more") for several (verified ModStation::OnInitialize).
const WANTED_NEWS_TEXTS:=[3219,3220]
static func wanted_news(progress: Dictionary) -> Dictionary:
	var count:=int(progress.get("wanted",{}).get("news",0)) if progress.get("wanted") is Dictionary else 0
	if count<=0:return {}
	return {"text_id":WANTED_NEWS_TEXTS[0] if count==1 else WANTED_NEWS_TEXTS[1],"count":count}

## After the Supernova ending (cursor above 158) station 120 always sells
## ship 49, listed after the first owned-Supernova extra (verified
## Generator::getShipBuyList). Ship 44 comes first there once every base medal
## is gold and all nine add-on medals are earned, or in an Extreme career.
const SUPERNOVA_END_SHIPS:={"station_id":120,"after_cursor":158,"ships":[[49,1]],"all_medals_ship":[44,1]}

static func stock_station(bindings: RefCounted,station_id: int) -> bool:
	return load("res://src/content/ordinary_world_definitions.gd").location(bindings,station_id).get("expansion",false)

## A rule with "from_cursor" applies only from that campaign cursor on.
static func stock_rules(station_id: int,cursor: int=-1) -> Dictionary:
	var rules: Dictionary=STOCK.get(station_id,{}).duplicate(true)
	if cursor<int(rules.get("from_cursor",-1)) or (cursor>=0 and cursor>int(rules.get("until_cursor",cursor))):return {}
	rules.erase("from_cursor");rules.erase("until_cursor")
	return rules
