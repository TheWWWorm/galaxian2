extends RefCounted
## Native consumers sharing equipped flight mechanics. These sets do not grant
## a departure: content capabilities and the prepared world remain authoritative.
const FREE=[18,19,20,21,22,23,24,27,28,30,31,32]
const LOCAL=[10,11,12,13,14,16]+FREE
const POST_SAHI=[25,26,29]
const EQUIPPED=[7]+LOCAL+POST_SAHI
const FACTIONS=[13,14,16]+FREE+POST_SAHI
const REGENERATING=[11,12,13,14]+FREE
