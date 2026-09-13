"""Second Mac mining departure data. No original code is executed or emitted."""
import copy, hashlib
from .station_exterior import declaration_bytes

def extract_full_hold_departure(mach, arrival, departure, station_return):
    if mach.architecture != 'x86_64': return {}
    try:
        if departure['scope'] != 'first_station_departure' or station_return['scope'] != 'first_mining_station_return': return {}
        if station_return['cursor_after_acknowledgement'] != 4 or station_return['next_mission_kind'] != 154 or station_return['next_mission_parameter'] != 25: return {}
        origin = arrival['provenance']['actor']
        if origin['bytes'] != 315: return {}
        anchor = mach.text['address'] + origin['offset'] - mach.slice_offset - mach.text['offset']
        proof = {}
        for key, (delta, size, section, pattern) in LAYOUTS.items():
            found = declaration_bytes(mach, anchor+delta, size, section.encode())
            if found is None: return {}
            if pattern.startswith('sha256:'):
                if hashlib.sha256(found[0]).hexdigest() != pattern[7:]: return {}
            elif found[0] != bytes.fromhex(pattern): return {}
            proof[key] = {'offset': found[1], 'bytes': size}
        result = copy.deepcopy(VALUES)
        result['provenance'] = proof
        return result
    except (KeyError, TypeError, ValueError, IndexError, OverflowError): return {}

VALUES = {'scope': 'full_hold_station_departure',
 'campaign_cursor': 4,
 'station_id': 78,
 'system_id': 15,
 'ship_id': 0,
 'source_state': 2,
 'world_type': 3,
 'confirmation_text_id': 386,
 'confirmation_required': True,
 'cache_reset': -1,
 'initial_cargo_used': 0,
 'audio_selector': 1,
 'previous_cursor': 3,
 'mission_kind': 154,
 'mission_parameter': 25,
 'requires_acknowledged_delivery': True,
 'requires_empty_cargo': True}

LAYOUTS = {'launch_gates': [437002,
                  744,
                  '__text',
                  'sha256:d0d030d90cc9a541d9a0dfe7b4a8243ec945b80f80a66eaa331ba9603b505d40'],
 'accepted_departure': [431746,
                        259,
                        '__text',
                        '498bbdb00000004489fe4489f2e834b0eeff83f8010f841506000085c00f85f50e000041f6851a010000010f84d200000041c6851a01000000488d1dc0a41e00488b3be862810600488b1b83f830752b488d05a1a41e00488b38be3a000000e8a25befff4889df4889c6e8c97a0600488d05daab1e00c60001eb134889dfe8df8006004889df4889c6e8aa7a0600488d056ba41e00488b08c781a8000000ffffffff488b08c781a0000000ffffffff488b08c781a4000000ffffffff488d0d6da51e00488b00c780ac000000ffffffff488b39e8f855eeff488d0569a41e00488d0d56ab1e00c70101000000488b38be02000000e89fee0d0041c6454000e9150e0000'],
 'mission_dispatch': [871418, 4, '__text', 'a8d5ffff'],
 'mission_factory': [860566,
                     82,
                     '__text',
                     '498bbe0002000031f6e88a05feffbf98000000e87e600a004889c34889dfbe9a00000031d2b94e000000e8d3f5f8ff4c89f74889dee8c8fbffff498b8610020000488b4008488b38be19000000e8cafaf8ff'],
 'station_keeps_ship': [414806,
                        548,
                        '__text',
                        'sha256:57804cdda50a7f2f996f3ed5d980a21aec957ba064c75ff335719a6b87c46d83'],
 'negative_pool_restore': [335297,
                           128,
                           '__text',
                           '488d05ba1d2000488b008bb0a800000085f67816498b4660488b38e8d5130300488d059a1d2000488b008bb0a000000085f67816498b4660488b38e8d3130300488d057a1d2000488b008bb0a400000085f67816498b4660488b38e8df130300488d055a1d2000488b008bb0ac00000085f6780c498b4660488b38e8df130300'],
 'ordinary_pool_refresh': [335425,
                           207,
                           '__text',
                           '498b7e60e84e5e0300488d05311d2000488b38e8d3f9070083f85f0f84ae0000004c8d25191d2000498b3c24e89cf907004889c7e816030600498b0c248981a8000000498b3c24e881f907004889c7e837030600498b0c248981a0000000498b3c24e866f907004889c7e8d6020600498b0c248981a4000000498b0424c780ac00000064000000498b1c244889dfe810f907004889c7e8bcde07004189c7498b3c24e844f907004889df4489fe89c2e8394908000f57c90f2ec175137a11498b4660488b38be64000000e810130300'],
 'cargo_clear': [730926,
                 112,
                 '__text',
                 '554889e54156534989fe4989767841c74610000000004885f67423833e00741e31db488b4608488b3cd8e8958ef3ff4101461048ffc3498b76783b1e72e44c89f7e8a8f2ffff418b46284103460c412b4610488d0dfb131a00488b0939813c0100007d0689813c0100005b415e5dc390'],
 'gamma_environment': [878638,
                       300,
                       '__text',
                       '554889e54157415653504189d789f34989fe488d053bd31700488b00488bb8080200004885ff7419e86fb4f8ff3db7000000750df30f1005b4e00a00e9b60000008d43930f57c083f8040f87a70000004183ff697f3583f8040f8795000000f30f100521590a00488d0daa000000486304814801c8ffe0f30f10058da20a00eb76f30f1005b72c0a00eb6c4181be780200009d0000007f4583f8047757f30f1005db580a00488d0d58000000486304814801c8ffe0f30f10056f590a00eb38f30f1005ad280a00eb2ef30f10058b280a00eb24f30f1005e59f0a00eb1a83fb6d0f94c00fb6c0488d0d07e00a00f30f100481eb030f57c04883c4085b415e415f5dc36690f3ffffffb1ffffffbbffffffc5ffffffcfffffffdfffffff5fffffff5fffffffbbffffff69ffffff']}
