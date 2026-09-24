"""Verify both supplied Mac physical-contact declarations without executing them.

Example: python3 tools/test_physical_scenery_contacts.py APP_EXEC APP_REG OLD_EXEC OLD_REG
The optional fifth argument writes a private Godot component-test fixture.
"""

import copy
import json
import sys
from pathlib import Path

from gof2_content.physical_scenery_contacts import VALUES, extract_physical_scenery_contacts
from gof2_content.registrations import MachO


def profile(source_path, registration_path):
    source = Path(source_path).read_bytes()
    registration_path = Path(registration_path)
    registrations = json.loads(registration_path.read_text())
    header = json.loads((registration_path.parent / 'bindings.json').read_text())
    mach = MachO(source, 'mac-full-hd')
    assert mach.source_sha256 == header['source_executable_sha256']
    result = extract_physical_scenery_contacts(
        mach, registrations['arrival_staging'], registrations['scenery_resources'],
        registrations['station_exterior'], registrations['opening_staging'])
    assert {key: value for key, value in result.items() if key != 'provenance'} == VALUES
    assert len(result['provenance']) == 19
    damaged = bytearray(source)
    damaged[result['provenance']['world_contact']['offset']] ^= 1
    altered = MachO(bytes(damaged), 'mac-full-hd')
    assert not extract_physical_scenery_contacts(
        altered, registrations['arrival_staging'], registrations['scenery_resources'],
        registrations['station_exterior'], registrations['opening_staging'])
    bad_anchor = copy.deepcopy(registrations['arrival_staging'])
    bad_anchor['provenance']['actor']['offset'] += 1
    assert not extract_physical_scenery_contacts(
        mach, bad_anchor, registrations['scenery_resources'], registrations['station_exterior'],
        registrations['opening_staging'])
    bad_opening = copy.deepcopy(registrations['opening_staging'])
    bad_opening['player_motion']['provenance']['release']['offset'] += 1
    assert not extract_physical_scenery_contacts(
        mach, registrations['arrival_staging'], registrations['scenery_resources'],
        registrations['station_exterior'], bad_opening)
    bad_order = copy.deepcopy(registrations['opening_staging'])
    bad_order['player_motion']['motion_before_controller'] = False
    assert not extract_physical_scenery_contacts(
        mach, registrations['arrival_staging'], registrations['scenery_resources'],
        registrations['station_exterior'], bad_order)
    return {
        'policy': result,
        'source_bytes': header['source_executable_bytes'],
        'architecture': header['architecture'],
        'arrival': registrations['arrival_staging'],
        'scenery': registrations['scenery_resources'],
        'station': registrations['station_exterior'],
        'opening': registrations['opening_staging'],
        'base_content_id': header['base_content_id'],
        'binding_id': header['binding_id'],
    }


def main(argv):
    if len(argv) not in (5, 6):
        raise SystemExit('usage: test_physical_scenery_contacts.py APP_EXEC APP_REG OLD_EXEC OLD_REG [PRIVATE_FIXTURE_JSON]')
    app = profile(argv[1], argv[2])
    old = profile(argv[3], argv[4])
    assert app['policy']['provenance'] != old['policy']['provenance']
    if len(argv) == 6:
        Path(argv[5]).write_text(json.dumps([app, old], separators=(',', ':')))
    print('Physical scenery source proofs: App Store and older Mac layouts, mutation and anchor rejection passed')


if __name__ == '__main__':
    main(sys.argv)
