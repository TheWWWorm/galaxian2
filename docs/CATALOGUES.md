# Catalogue readers

The native runtime reads four small catalogue resources through the content
library's size and SHA-256 checks. Each table is decoded into declarative records;
the original executable is never loaded. A successful open publishes all four
tables together and records their resource hashes and base content identity.
Failure clears the previous catalogue state.

## Supported record layouts

All integers in these four files are big-endian. Signed integers remain signed.
Names have an unsigned 16-bit byte length followed by strict UTF-8. Names retain
their original accents and whitespace. Arrays have a signed 32-bit count followed
by that many signed 32-bit values. Counts and allocations are bounded.

| File | Record | Supplied iOS / Mac counts |
|---|---|---|
| `ships.bin` | Nine signed 32-bit fields; first field is the record ID | 64 / 61 |
| `stations.bin` | Name and four signed 32-bit fields | 135 / 135 |
| `systems.bin` | Name, eight signed 32-bit fields, four arrays | 34 / 34 |
| `items.bin` | Three arrays; final array contains alternating property keys and values | 233 / 233 |

Every record retains its original fields, source byte offset and byte length.
Ship and station IDs must agree with their record positions. System and item IDs
are implicit record indices. Item property keys remain numeric and edition-local;
the first two arrays are retained without assigning an economic meaning.

The supported layouts reject missing/truncated records, extra bytes, excessive
counts, invalid names, duplicate item property keys and unpaired item arrays.
These checks establish structural decoding. Ship base properties and the world
relationships below additionally have verified field meanings.

## Ship base properties

Each ship keeps its original nine fields and adds a `stats` dictionary. The file
loaders, constructors, accessors and statistics screens were checked independently
on iOS and Mac. The native reader uses this data layout directly; it does not
execute or translate those original routines.

| Field | Native property | Meaning |
|---|---|---|
| 0 | `id` on the record | Edition-local catalogue ID |
| 1 | `armor` | Base armor rating |
| 2 | `cargo_capacity` | Base cargo hold capacity |
| 3 | `base_price` | Unadjusted catalogue price |
| 4 | `primary_slots` | Primary weapon slots |
| 5 | `secondary_slots` | Secondary weapon slots |
| 6 | `turret_slots` | Turret slots |
| 7 | `equipment_slots` | Equipment slots |
| 8 | `handling_factor` | Catalogue handling value divided by 100 |

Zero slots remain zero; negative base properties are rejected. `ship_stats(id)`
returns a copy so changes to an eventual loadout cannot alter the base catalogue.
It rejects IDs outside the current edition. Armor damage scaling, installed
equipment, ship upgrades, market pricing and purchase availability are separate
unimplemented behavior. In particular, base price is not a purchase/sale quote.

Handling is a catalogue rating, not a verified speed, acceleration or angular
velocity. The inspector displays the original integer rating and the data API
retains its normalized factor. Effective handling and its use by flight controls
still require verification; the Mac and iOS effective-handling accessors differ.

The inspector shows properties when a ship ID is entered, including without a
geometry binding pack. Property labels use the selected language with independently
verified edition-local text IDs. Switching language refreshes these labels. The
source properties retain the ship record's resource hash, base identity and byte
extent through the catalogue provenance.

## World relationships

Station field 1 identifies its parent system. Field 3 is exposed as `planet_type`;
the source scenery uses it for planet appearance and sun placement alternatives.
Both editions' station loaders, constructors and scenery accessors establish this
mapping. Its value alone does not establish a complete rendered environment.
System array 1 lists its stations;
array 2 lists linked systems (all positions here are zero-based). The reader checks
that every station is listed exactly once, agrees with its parent, and is in range.
System links must be in range, unique, non-self and reciprocal. Both supplied
editions satisfy these constraints without repairs or missing destinations.

The World tab searches original system and station names, lists the selected
system's stations and follows its source links. A system with an empty link list
remains empty. This screen is an inspection tool; it does not establish that a
system is discovered or reachable in a particular campaign state. Special travel,
equipment requirements, prices, locks and unlock conditions remain unsupported.

System `fields[2]` supplies the default hangar geometry row in the recovered
hangar selector; source-defined station overrides take precedence. This specific
use does not establish every meaning of the field. The World tab can open the
corresponding geometry preview when v4 bindings and prepared textures are loaded.

Other system/station fields remain positional until their meanings are verified.
They must not be used to guess map coordinates, factions, environmental models,
market rules or starting locations. Item records do not yet provide verified
equipment semantics, and ship name/description localization remains unverified.
Optional executable-derived
binding packs supply the catalogue-indexed ship hull resource table: 64 entries
for iOS and 61 for Mac. Four entries per edition lack a usable recovered resource
declaration; original special construction paths and complete ship assembly remain
unimplemented. See [resource bindings](RESOURCE_BINDINGS.md).

## Verification scope

Record layouts were checked against static source loader structure and complete
file consumption. World membership and link interpretation were checked against
source accessors and every relationship in both supplied catalogues. Ship property
tests cover field ordering, handling scale, zero slots, negative values, defensive
copies, invalid IDs, edition-local labels and clearing on failed opens. This is
format evidence, not original-game behavioral or campaign validation.

Run synthetic malformed-input and reference tests, optionally followed by checks
of any private imported fixtures:

```bash
godot --headless --path game --script res://tests/catalogues.gd -- /path/to/ios-content /path/to/mac-content
```

The source package contains only synthetic fixtures. No original catalogue tables,
executable disassembly or original resources are distributed with the engine.

The systems table also exposes `sky_index` from its eighth scalar field. Both
editions' loaders, constructors and background accessors identify this field.
The opening has a separate sky override; the system index alone does not select
the opening background. See [environment rendering](ENVIRONMENTS.md).

## Weapon attachment table

`weapon_mounts.gd` separately reads `weapons_hd.bin` through the same content
library. It contains 59 ship records on supplied iOS and 56 on supplied Mac,
with 552 and 523 attachment records respectively. Unlike the four catalogues
above, its scalars are little-endian. Each ship record starts with signed 16-bit
ship ID and attachment count. Each attachment has four signed 16-bit values:
category and three coordinates. Category 3 additionally contains three binary32
values. There is no table header or trailing sentinel.

Categories 0, 1 and 2 provide primary, secondary and turret mount groups.
Category 3 retains a position and additional vector; effect construction is not
implemented by this reader. Coordinates map `(x, y, z)` to source-space
`(x, z, -y)`; the additional vector maps to `(x, z, y)` without negation.
Order within each category is preserved. Category-slot selection never searches
by weapon item ID or sorts attachments by their coordinates.

Duplicate/out-of-catalogue ship IDs, unknown categories, excessive counts,
truncation, nonfinite vectors and malformed trailing bytes are rejected. Table,
record and part extents remain available with a base content identity and
resource checksum. Missing ship records remain absent: the supplied tables have
no entries for IDs 13, 14, 15, 50 and 53.

Eight shared ship records differ between editions (52, 54–60), including weapon
positions and ordering; iOS additionally supplies IDs 61–63. Each base edition
uses its own table. Supplemental cosmetic assets cannot replace it.
Attachment count does not grant equipment capacity: ships 9 and 35 each contain
three secondary positions but have only two catalogue secondary slots. Equipment
ownership must continue to enforce the ship's slot limits.
Decoding turret or auxiliary attachments is not a claim that their firing or
effects work. [Combat scope](COMBAT.md#authored-fixed-weapon-mounts) describes the
supported native fixed-primary launch path.
