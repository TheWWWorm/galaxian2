extends RefCounted
## Resolve supported encounter entry differences from validated content.
## Shared player initialization consumes these rules without campaign switches.
const Departure=preload("res://src/content/station_departure_definitions.gd")
const FullHold=preload("res://src/content/full_hold_departure_definitions.gd")
const Pirate=preload("res://src/content/full_hold_pirate_definitions.gd")
const Training=preload("res://src/content/combat_training_weapon_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Alioth=preload("res://src/content/alioth_lifecycle_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const KINDS={0:"opening",1:"arrival",2:"mining",4:"full_hold",7:"training",10:"local",11:"local",12:"local",13:"local",14:"convoy",16:"alioth",18:"free",19:"free"}
var error:=""
var cursor:=-1
var is_arrival:=false
var is_departure:=false
var uses_equipment:=false
var restores_local:=false
var equipped_entry:={}
var _kind:=""
var _departure:={}
var _training:={}
var _pirate:={}
var _travel:={}

func configure(bindings: RefCounted, value: int, station_id: int=-1, restoring_local:=false,ship_id: int=-1) -> bool:
	error="";cursor=-1;is_arrival=false;is_departure=false;uses_equipment=false
	equipped_entry={};_kind="";_departure={};_training={};_pirate={};_travel={};restores_local=false
	if bindings==null or not KINDS.has(value):return reject("Unsupported player entry")
	var kind: String=KINDS[value]
	if value==14 and Travel.navigation_available(bindings.mido_travel,value):kind="local"
	var departure:=kind in ["mining","full_hold","training"]
	if departure and not Departure.parameters(bindings.station_departure):return reject("This profile has no supported first departure")
	if kind=="full_hold" and (not FullHold.parameters(bindings.full_hold_departure) or not FullHold.StationReturn.parameters(bindings.station_return)):return reject("This profile has no supported second mining departure")
	if kind=="training" and not Training.parameters(bindings.combat_training_weapons):return reject("This profile has no supported equipped training entry")
	if kind=="alioth":
		if not Alioth.available(bindings) or station_id!=int(bindings.mido_travel.alioth_attack.station_id) or restoring_local:return reject("Alioth requires its docked equipment and source encounter")
		_travel=bindings.mido_travel.duplicate(true)
		equipped_entry=Cache.alioth_entry(_travel)
		departure=true
	if kind=="free":
		if not FreeFlight.available(bindings):return reject("Ordinary player entry is unavailable")
		equipped_entry=FreeFlight.player_entry(bindings.mido_travel,station_id,ship_id,value)
		if equipped_entry.is_empty():return reject("Ordinary player entry requires its equipped location")
		_travel=bindings.mido_travel.duplicate(true);departure=not restoring_local;restores_local=restoring_local
	if kind in ["local","convoy"]:
		equipped_entry=Travel.player_entry(bindings.mido_travel,station_id,value)
		if equipped_entry.is_empty():return reject("This profile has no supported equipped local entry")
		_travel=bindings.mido_travel.duplicate(true)
		departure=true if kind=="convoy" else (not restoring_local if Travel.navigation_available(_travel,value) else station_id==int(Travel.journey(_travel,value).from_station_id))
		if kind=="convoy" and restoring_local:return reject("The capture encounter starts from its docked equipment")
		restores_local=not departure
	cursor=value;_kind=kind;is_arrival=kind=="arrival";is_departure=departure;uses_equipment=kind=="training"
	if departure:_departure=(bindings.full_hold_departure if kind=="full_hold" else bindings.station_departure).duplicate(true)
	if uses_equipment:
		_training=bindings.combat_training_weapons.duplicate(true)
		equipped_entry=_training.player_entry.duplicate(true)
	if kind in ["local","convoy","alioth","free"]:uses_equipment=true
	if kind=="full_hold":_pirate=bindings.full_hold_pirate.duplicate(true)
	return true

func player_cache(parameters: Dictionary, seed: Dictionary, hull: int, capacities: Dictionary, reset:=false) -> Dictionary:
	if cursor<0:return {}
	if _kind=="alioth":return Cache.alioth_attack_cache(parameters,_travel,seed,hull,capacities,reset)
	if _kind=="free":return Cache.free_flight_cache(parameters,_travel,seed,hull,capacities,reset,cursor)
	if _kind in ["local","convoy"]:return Cache.local_travel_cache(parameters,_travel,seed,hull,capacities,reset,cursor)
	if _kind=="training":return Cache.combat_training_cache(parameters,_training,seed,hull,capacities,reset)
	if is_departure:return Cache.departure_cache(parameters,_departure,seed,hull,capacities,reset)
	if reset:return {}
	return Cache.base_cache(parameters,seed,hull,capacities,cursor)

func contact_weapons(opening_weapon: Dictionary) -> Dictionary:
	if cursor<0:return {}
	if _kind in ["convoy","alioth","free"]:return {"candidates":[],"enabled":false,"context":{}}
	if _kind=="local":
		var armed:=is_departure or Travel.navigation_available(_travel,cursor)
		return {"candidates":[Travel.ordinary_weapon(_travel,cursor)] if armed else [],
			"enabled":armed,"context":{"campaign_cursor":cursor,"nonplayer_source":true}}
	var weapon:=opening_weapon
	if _kind=="full_hold" and not _pirate.is_empty():
		if not Pirate.parameters(_pirate):reject("Unsupported second-trip pirate weapon");return {}
		weapon=_pirate.primary_weapon
	return {"candidates":_training.npc_weapons.duplicate(true) if uses_equipment else [weapon.duplicate(true)],
		"enabled":_kind!="full_hold" or not _pirate.is_empty(),
		"context":{"campaign_cursor":cursor,"nonplayer_source":true} if uses_equipment else {}}

func reject(message: String) -> bool:
	error=message
	return false
