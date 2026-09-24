"""Mac departure/construction variants retain bounded, coherent source proofs."""
import copy
import hashlib
import unittest
from unittest.mock import patch
from declaration_fixture import literal_fixture
from gof2_content import first_flight, station_departure, mining_targeting, mining_briefing
from gof2_content import mining_approach, mining_drill, mining_session
from gof2_content import mining_objective, station_exterior, station_autopilot
from gof2_content import station_flight, station_return, flight_notices
from gof2_content import full_hold_departure
from gof2_content import full_hold_flight, full_hold_pirate, full_hold_control
from gof2_content import full_hold_destruction, full_hold_story, full_hold_return, full_hold_appearance
from gof2_content import player_destruction, game_over_presentation, engine_particles, full_hold_particles
from gof2_content import station_equipment, combat_training, combat_training_control
from gof2_content import combat_training_weapons, combat_training_destruction, combat_training_story, combat_training_visuals

READERS = [station_departure,first_flight,mining_targeting,mining_briefing,
           mining_approach,mining_drill,mining_session,mining_objective,
           station_exterior,station_autopilot,station_flight,station_return,flight_notices,
           full_hold_departure,full_hold_flight,full_hold_pirate,full_hold_control,
           full_hold_destruction,full_hold_story,full_hold_return,full_hold_appearance,
           player_destruction,game_over_presentation,engine_particles,full_hold_particles,
           station_equipment,combat_training,combat_training_control,combat_training_weapons,
           combat_training_destruction,combat_training_story,combat_training_visuals]


def fixture(reader, rows, shift=0):
    if reader is first_flight:
        layout = {k:[v[1],v[2],v[3]] for k,v in rows.items()}
        constants = [k for k,v in rows.items() if v[0] == '__const']
    elif len(next(iter(rows.values())))==4:
        layout = {k:[v[0],v[1],v[3]] for k,v in rows.items()}
        constants = [k for k,v in rows.items() if v[2] == '__const' and not k.endswith('_vtable')]
    else:
        layout, constants = rows, []
    replacements=copy.deepcopy(rows)
    digest_only=reader in [combat_training_story,combat_training_visuals]
    hashed=[k for k,v in layout.items() if digest_only or v[-1].startswith('sha256:')]
    for key in hashed:
        raw=bytes(layout[key][1])
        layout[key][-1]=raw.hex()
        replacements[key][-1]=('' if digest_only else 'sha256:')+hashlib.sha256(raw).hexdigest()
    ordered={k:layout[k] for k in [*hashed,*(k for k in layout if k not in hashed)]}
    mach, origin, offset, low = literal_fixture('x86_64',ordered,shift,constants)
    if hashed:
        # A broad hash proof can contain another, shorter literal proof. Hash
        # the completed synthetic buffer after all of those spans are written.
        for key in hashed:
            delta,size,_=layout[key]
            raw=mach.data[offset+delta-low:offset+delta-low+size]
            replacements[key][-1]=('' if digest_only else 'sha256:')+hashlib.sha256(raw).hexdigest()
        mach.proof_layout_override=replacements
        mach.proof_layout_name='MAC_ALTERNATE' if rows is reader.MAC_ALTERNATE else 'LAYOUTS'
    if reader is not first_flight and len(next(iter(rows.values())))==4:
        for key,(delta,size,section,_) in rows.items():
            if section in ['__data','__cstring'] or key.endswith('_vtable'):
                anchor=mach.text['address']+origin-mach.slice_offset-mach.text['offset']
                mach.sections.append({'segment':b'__TEXT' if section=='__cstring' else b'__DATA','name':section.encode(),
                    'address':anchor+delta,'offset':offset+delta-low,'length':size})
    return mach, {'provenance':{'actor':{'offset':origin,'bytes':315}}}, offset, low, layout


def extract(reader, rows, mach, arrival, imports=True):
    if hasattr(mach,'proof_layout_override'):
        with patch.object(reader,mach.proof_layout_name,mach.proof_layout_override):
            return _extract(reader,rows,mach,arrival,imports)
    return _extract(reader,rows,mach,arrival,imports)


def _extract(reader, rows, mach, arrival, imports=True):
    departure = {'scope':'first_station_departure'}
    if reader is station_departure:
        return reader.extract_station_departure(mach,arrival,{'scope':'first_station_entry'},
                                               {'flight_cache':True,'repair':True})
    if reader is full_hold_departure:
        return reader.extract_full_hold_departure(mach,arrival,departure,
            {'scope':'first_mining_station_return','cursor_after_acknowledgement':4,
             'next_mission_kind':154,'next_mission_parameter':25})
    flight = {'scope':'first_mining_flight_construction'}
    second = {'scope':'full_hold_mining_flight_construction','actor_count':1}
    npc = {k:True for k in ['construction','routes','world_initialization','guidance',
                           'holding','hostility','primary_weapon','flight','destruction','death_accounting']}
    npc['hull']={'rank':0}
    npc['destruction']={'effect_type':0,'model_ids':[16821,16820]}
    actors = {'npc_initialization':npc,'player_initialization':{'flight_cache':True,'repair':True}}
    training={'scope':'combat_training_encounter_construction'}
    control={'scope':'combat_training_live_control'}
    equipment={'scope':'var_hastra_equipment_tutorial'}
    training_weapons={'scope':'combat_training_ordinary_weapons'}
    if reader is station_equipment:
        return reader.extract_station_equipment(mach,arrival,{'scope':'full_hold_station_return'})
    if reader is combat_training:
        return reader.extract_combat_training(mach,arrival,equipment,actors)
    if reader is combat_training_control:
        return reader.extract_combat_training_control(mach,arrival,training,actors)
    if reader is combat_training_weapons:
        return reader.extract_combat_training_weapons(mach,arrival,training,control,equipment,actors,
            {k:True for k in ['ordinary_hit_policy','player_hit_policy','collision_bounds','audio']})
    if reader is combat_training_destruction:
        return reader.extract_combat_training_destruction(mach,arrival,training,control,training_weapons,actors)
    if reader is combat_training_story:
        return reader.extract_combat_training_story(mach,arrival,training,{'scope':'combat_training_cargo_destruction'},
            {'scope':'first_mining_briefing'},{'scope':'first_mining_cargo_objective'},
            {'campaign_cursor':0,'timing':reader.VALUES['radio_timing']},{'scope':'full_hold_mining_story'})
    if reader is combat_training_visuals:
        return reader.extract_combat_training_visuals(mach,arrival,training_weapons,
            {'projectile_visuals':True,'projectile_impacts':True})
    death={'scope':'mac_starter_player_destruction','ship_id':0,'game_over_image_id':1313,'continue_text_id':188}
    damage={'scope':'damage_particle_sprite_presets','emitter_defaults':{},
            'presets':[{'preset_id':15},{'preset_id':42}],
            'owners':{'scope':'fresh_opening_damage_emitters','npc_uses_detail_gate':True}}
    if reader is player_destruction:
        return reader.extract_player_destruction(mach,arrival,second,actors)
    if reader is game_over_presentation:
        return reader.extract_game_over_presentation(mach,arrival,death)
    if reader is engine_particles:
        return reader.extract_engine_particles(mach,arrival,damage)
    if reader is full_hold_particles:
        return reader.extract_full_hold_particles(mach,arrival,second,death,damage)
    if reader is full_hold_flight:
        return reader.extract_full_hold_flight(mach,arrival,{'scope':'full_hold_station_departure'},flight,actors)
    if reader is full_hold_pirate:
        return reader.extract_full_hold_pirate(mach,arrival,second,actors,{'verified':True})
    if reader is full_hold_control:
        return reader.extract_full_hold_control(mach,arrival,{'scope':'full_hold_pirate_combat'},actors)
    if reader is full_hold_destruction:
        return reader.extract_full_hold_destruction(mach,arrival,{'scope':'full_hold_pirate_control'},actors)
    if reader is full_hold_story:
        return reader.extract_full_hold_story(mach,arrival,second,{'scope':'first_mining_briefing'},
                                             {'scope':'first_mining_cargo_objective'})
    if reader is full_hold_return:
        return reader.extract_full_hold_return(mach,arrival,{'scope':'first_mining_station_return'},
                                               {'scope':'full_hold_mining_story'})
    if reader is full_hold_appearance:
        return reader.extract_full_hold_appearance(mach,arrival,{'scope':'full_hold_mining_story'},
                                                   {'scope':'full_hold_pirate_destruction'})
    if reader in [station_exterior,station_flight,station_return,flight_notices]:
        return getattr(reader,'extract_'+reader.__name__.rsplit('.',1)[1])(mach,arrival,flight)
    if reader is mining_objective:
        values=reader.MAC_VALUES if rows is reader.MAC_ALTERNATE else reader.VALUES
        return reader.extract_mining_objective(mach,arrival,flight,
            {'scope':'first_station_presentation'}, {'pairs':[values['desktop_instruction']]},
            {'scope':'first_mining_briefing'})
    if reader is mining_targeting:
        return reader.extract_mining_targeting(mach,arrival,flight)
    if reader is mining_approach:
        return reader.extract_mining_approach(mach,arrival,{'scope':'first_mining_asteroid_selection'})
    if reader is mining_drill:
        return reader.extract_mining_drill(mach,arrival,flight)
    if reader is mining_session:
        return reader.extract_mining_session(mach,arrival,{'scope':'first_mining_approach'},
                                            {'scope':'ordinary_mining_drill'})
    if reader is mining_briefing:
        values = reader.MAC_VALUES if rows is reader.MAC_ALTERNATE else reader.VALUES
        final = values['events'][-1]['text_id']
        return reader.extract_mining_briefing(mach,arrival,flight,
            {'scope':'first_station_presentation'}, {'scope':'mac_desktop_text','pairs':[[final,final+1]]})
    symbols = reader.MAC_IMPORTS if rows is reader.MAC_ALTERNATE else reader.IMPORTS
    anchor = mach.text['address'] + arrival['provenance']['actor']['offset'] - mach.slice_offset - mach.text['offset']
    addresses = {anchor+delta:name.encode() for name,delta in symbols.items()}
    with patch.object(reader,'import_symbol',side_effect=lambda _,address:addresses.get(address) if imports else None):
        if reader is station_autopilot:return reader.extract_station_autopilot(mach,arrival,flight)
        return reader.extract_first_flight(mach,arrival,departure,{'verified':True},{'verified':True})


class FirstFlightLayoutsTests(unittest.TestCase):
    def test_relocated_complete_variants_and_detachment(self):
        for reader in READERS:
            for rows in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
                for shift in [0,0x2400000]:
                    mach,arrival,*_ = fixture(reader,rows,shift)
                    value = extract(reader,rows,mach,arrival)
                    expected = reader.MAC_VALUES if hasattr(reader,'MAC_VALUES') and rows is reader.MAC_ALTERNATE else reader.VALUES
                    self.assertEqual({k:v for k,v in value.items() if k!='provenance'},expected)
                    self.assertEqual(set(value['provenance']),set(rows))
                    value['provenance'].clear()
                    self.assertEqual(set(extract(reader,rows,mach,arrival)['provenance']),set(rows))

    def test_each_proof_boundary_rejects_source_damage(self):
        for reader in READERS:
            for rows in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
                mach,arrival,offset,low,layout = fixture(reader,rows)
                for key,(delta,size,_) in layout.items():
                    for edge in [0,size-1]:
                        bad=copy.copy(mach);data=bytearray(mach.data)
                        data[offset+delta-low+edge]^=255;bad.data=bytes(data)
                        self.assertEqual(extract(reader,rows,bad,arrival),{},(reader.__name__,key,edge))

    def test_context_bounds_and_import_identity(self):
        for reader in READERS:
            for rows in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
                for case in ['architecture','extent','section','truncated']:
                    mach,arrival,*_ = fixture(reader,rows)
                    if case=='architecture':mach.architecture='armv7'
                    elif case=='extent':arrival['provenance']['actor']['bytes']=314
                    elif case=='section':mach.sections=[]
                    else:mach.data=mach.data[:128]
                    self.assertEqual(extract(reader,rows,mach,arrival),{},case)
        for reader in [first_flight,station_autopilot]:
            for rows in [reader.LAYOUTS,reader.MAC_ALTERNATE]:
                mach,arrival,*_ = fixture(reader,rows)
                self.assertEqual(extract(reader,rows,mach,arrival,imports=False),{})

    def test_briefing_rejects_the_other_sources_desktop_alias(self):
        for rows in [mining_briefing.LAYOUTS,mining_briefing.MAC_ALTERNATE]:
            mach,arrival,*_ = fixture(mining_briefing,rows)
            wrong = 1703 if rows is mining_briefing.MAC_ALTERNATE else 1714
            self.assertEqual(mining_briefing.extract_mining_briefing(mach,arrival,
                {'scope':'first_mining_flight_construction'}, {'scope':'first_station_presentation'},
                {'scope':'mac_desktop_text','pairs':[[wrong,wrong+1]]}),{})

    def test_objective_rejects_the_other_sources_desktop_alias(self):
        for rows in [mining_objective.LAYOUTS,mining_objective.MAC_ALTERNATE]:
            mach,arrival,*_ = fixture(mining_objective,rows)
            other = mining_objective.VALUES if rows is mining_objective.MAC_ALTERNATE else mining_objective.MAC_VALUES
            self.assertEqual(mining_objective.extract_mining_objective(mach,arrival,
                {'scope':'first_mining_flight_construction'}, {'scope':'first_station_presentation'},
                {'pairs':[other['desktop_instruction']]}, {'scope':'first_mining_briefing'}),{})
