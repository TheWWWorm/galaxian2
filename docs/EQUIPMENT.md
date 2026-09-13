# Starter equipment at Var Hastra

With current Mac bindings, finish both mining trips and acknowledge the second
return conversation. Open **Hangar**, or press Enter/controller A at the station.
The shop offers one each of Nirai Impulse EX 1, Micro Gun MK I and E2 Exoclad.
These tutorial offers cost zero credits in the supplied Mac content.

Choose **Buy**, then open **Cargo** and **Mount** the acquired item. Either gun
satisfies the weapon requirement. Mount the armor plate as well. **Ship** lists
installed equipment; **Demount** moves eligible equipment back to cargo. Selling
an item from cargo returns it to the same stock at its zero tutorial price.
Gunant's Drill and the starter scanner remain protected from sale and removal.

Close the hangar to return to the station. Owning equipment in cargo is
insufficient: a primary weapon and armor plate must be installed. Gunant's
original line and voice then await acknowledgement. Closing that conversation
selects the combat-training mission and retains acquired cargo and installed
equipment. With current Mac bindings, choose **Depart** and confirm to begin.
Steer with WASD/arrows or the left stick; fire with Space or the right trigger.
The touch-controls preference enables the on-screen flight actions.

Finish the three pirates and acknowledge Gunant's return instructions, then
select the station with P/controller Y. Training releases the protected items
and applies the source inventory prices without removing owned cargo. Mining
remains available on the return trip. Nine station lines lead to a station
reload; the following mission is not yet supported. General trading and saves
remain unfinished.

## Implementation and verification scope

Reader v116 adds optional Mac declarations for the starter stock, equipment
categories, slot selection, protected items and completion sequence. All earlier
payloads are preserved. Re-prepare Mac bindings to enable this step; earlier
packs retain their supported boundaries. No IPA is required.

The native inventory keeps stock, owned cargo and installed slots separate.
Accepted operations update them together; failed operations retain the prior
state. Reopening the hangar does not restock it. The first accepted transaction
recomputes cargo weight from actual ownership, replacing the cached weight left
after the delivered ore was removed. It cannot restore that ore or grant credits.
Pause, focus loss and hidden application views prevent transactions.

The UI uses original localized item names and action labels, the existing
location hangar, original completion portrait/text/voice and mount/demount sounds.
Its inventory layout is native and compact on desktop, with larger phone
controls. Original inventory icon/atlas layout, buying/selling feedback sounds,
quantity-selection previews, general stock/pricing, wallets, equipment outside
these offers, replacement confirmation, later flight initialization and saves
remain unfinished. There is no full-game or complete-tutorial fidelity claim.

Focused Mac checks exercise the application through both earned mining returns,
stock exhaustion, purchase/sale, both gun choices, installed versus owned armor,
protected items, pause, detached snapshots, rejected audio preparation and one-time
acknowledged progression. Visual checks use Linux OpenGL and simulated phone
layout. They do not establish physical device/controller or original-runtime
comparison results.
