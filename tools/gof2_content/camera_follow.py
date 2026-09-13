"""Read camera offsets, response rates and a constant polynomial coefficient table.

The table is normalized constant data. No original executable behavior is emitted;
the native camera uses its own vector transforms and generic curve evaluation.
"""
import math
import struct
from .opening_loadout import template
from . import opening_camera as opening
from .ship_models import section_bytes

MAC_CURVE = """
554889e5f3440f5ae0450f28c4f2450f59c0450f28d0f2450f59d4450f28caf2450f59cc410f28d9f2410f59dc440f28dbf2450f59dc410f28fbf2410f59fcf20f1005
{ref_3f:4}
f20f59c70f28f7f2410f59f4f20f1015
{ref_53:4}
f20f59d6f20f58d0f20f100d
{ref_63:4}
f20f59cff20f1005
{ref_6f:4}
f20f59c6f20f58c1f20f100d
{ref_7f:4}
f2410f59cbf20f58c8f20f1005
{ref_90:4}
f20f59c3f20f58c1f20f100d
{ref_a0:4}
f2410f59cbf20f58caf20f1015
{ref_b1:4}
f20f59d3f20f58d1f20f100d
{ref_c1:4}
f2410f59c9f20f58caf20f1015
{ref_d2:4}
f2410f59d2f20f58d1f20f102d
{ref_e3:4}
f2410f59e9f20f58e8f20f100d
{ref_f4:4}
f20f59cff20f1005
{ref_100:4}
f20f59c6f20f58c1f20f100d
{ref_110:4}
f2410f59cbf20f58c8f20f1005
{ref_121:4}
f20f59c3f20f58c1f20f1025
{ref_131:4}
f2410f59e1f20f58e0f20f1005
{ref_142:4}
f2410f59c2f20f58c5f20f100d
{ref_153:4}
f20f59cff20f102d
{ref_15f:4}
f20f59eef20f58e9f20f100d
{ref_16f:4}
f2410f59c8f20f58caf20f593d
{ref_180:4}
f20f5935
{ref_188:4}
f20f58f7f20f103d
{ref_194:4}
f2410f59fcf20f58f9f20f1015
{ref_1a5:4}
f2410f59d3f20f58d5f20f102d
{ref_1b6:4}
f2410f59e8f20f58e8f20f100d
{ref_1c7:4}
f2410f59caf20f58ccf20f1005
{ref_1d8:4}
f2410f59c0f20f58c1f20f100d
{ref_1e9:4}
f2410f59ccf20f58c8f20f110ef20f1005
{ref_1fe:4}
f2410f59c4f20f58c5f20f1025
{ref_20f:4}
f20f59e3f20f58e2f2440f591d
{ref_21f:4}
f20f583d
{ref_228:4}
f2440f58def20f1035
{ref_235:4}
660f57fef20f113af20f1015
{ref_245:4}
f2410f59d1f2440f590d
{ref_252:4}
f20f591d
{ref_25b:4}
f20f58d4f20f1025
{ref_267:4}
f2410f59e2f2440f5915
{ref_274:4}
f20f5805
{ref_27d:4}
f20f1101f20f1005
{ref_289:4}
f2410f59c4f2440f5925
{ref_296:4}
f2440f58d2f20f1015
{ref_2a4:4}
f2410f59d0f2440f5905
{ref_2b1:4}
f2410f58dbf2410f58d9f20f58dcf2410f58d8f2410f58dcf20f581d
{ref_2d2:4}
f2410f1118f2410f58d2f20f58d0f20f5815
{ref_2e8:4}
660f57d6f2410f11115dc3
"""

ARM_CURVE = """
41ec101b
{literal_4:4}
{literal_8:4}
f7eec00addf804900299009860eea02b60eea24b60eea46b60eea68b60eea8ab60eeaacb20eeac0b6ceeaeeb20ee022b72ee2eeb
{literal_40:4}
{literal_44:4}
2aee822b72ee2eeb
{literal_50:4}
20ee044b28ee822b7eee82eb
{literal_60:4}
{literal_64:4}
26ee822b72ee2eeb
{literal_70:4}
20ee066b2cee822b32ee042b
{literal_80:4}
{literal_84:4}
2aee844b32ee042b
{literal_90:4}
60ee211b28ee844b34ee022b
{literal_a0:4}
26ee844b32ee042b
{literal_ac:4}
2cee844b36ee044b
{literal_b8:4}
2aee866b36ee044b
{literal_c4:4}
28ee866b34ee064b
{literal_d0:4}
2cee866b36ee216b
{literal_dc:4}
6aeea11b36ee216b
{literal_e8:4}
68eea11b31ee866b
{literal_f4:4}
6ceea1cb
{literal_fc:4}
20ee210b7cee80cb
{literal_108:4}
6aee80ab7ceeaaab
{literal_114:4}
{literal_118:4}
68eeac8b
{literal_120:4}
78eeaa8b
{literal_128:4}
66eeaccb66eeaaab66ee806b
{literal_138:4}
78eeac8b24ee800b30ee020b
{literal_148:4}
76ee2aab24ee822b7eee82eb
{literal_158:4}
76ee846b62ee82cb
{literal_164:4}
{literal_168:4}
24ee822b72ee2aab
{literal_174:4}
7aeeacab24ee822b64ee844b76eea44b
{literal_188:4}
72ee288b62eea66b
{literal_194:4}
76ee806b
{literal_19c:4}
60ee82cb
{literal_1a4:4}
{literal_1a8:4}
22ee800b22ee822b62ee842b72eea42b
{literal_1bc:4}
70ee2eeb60eea44b74eea64b
{literal_1cc:4}
{literal_1d0:4}
60eea66b20ee800b7eeea66b
{literal_1e0:4}
78ee828b60eeae0b70ee2aab7ceea22b
{literal_1f4:4}
{literal_1f8:4}
74eeae4b76ee826b
{literal_204:4}
{literal_208:4}
70eea80b7aee808b72eeac2bf1ee644bf1ee666bc2ed000bc3ed004bc0ed008bc9ed002bc1ed006b7047
"""

MAC_FOLLOW = """
8b4324898540fdffff488b431c48898538fdffff8b4318898530fdffff488b431048898528fdffff488dbde8feffffe8
{call_2f:4}
488d7b28488db518fdfffff30f118d20fdfffff30f118518fdffff660f70c001f30f11851cfdffffe8
{call_5c:4}
4c8d7b104c8d631cf643540175
{jump_6d:1}
4c8d7340e9
{jump_73:4}
c785d8fcffff0000803f48c785e4fcffff0000000048c785dcfcffff00000000c785ecfcffff0000803f48c785f8fcffff0000000048c785f0fcffff00000000c78500fdffff0000803fc78504fdffff00000000c78508fdffff0000803f488dbd98fcffff4c8db5d8fcffffc7850cfdffff0000803fc78510fdffff0000803ff30f105360f30f104358f30f104b5c4c89f6ba02000000e8
{call_10f:4}
488dbde8feffff4c89f6e8
{call_11e:4}
4c8d73404c89f7e8
{call_12a:4}
0f28c8f30f1083b80000000f2ec875
{jump_13d:1}
7b
{jump_13f:1}
f30f5ec14c89f7e8
{call_148:4}
4c8dade8feffff4c89ef4c89f6e8
{call_15a:4}
f30f118d90fcfffff30f118588fcffff660f70c001f30f11858cfcffff488db588fcffff4c89ffe8
{call_186:4}
488d73344c89efe8
{call_192:4}
488db578fcfffff30f118d80fcfffff30f118578fcffff660f70c001f30f11857cfcffff4c89e7e8
{call_1be:4}
4c8dad38fdffff4c89e74c89eee8
{call_1d0:4}
8b9534fbffff899534fbfffff30f2adaf30f1015
{ref_1e5:4}
f30f5ed34863c24889c1480fafc90f57dbf2480f2ad9f20f119d18fbffff480fafc8480fafc1f2480f2ae8f20f11ad20fbfffff2480f2af1f20f11b528fbfffff20f2ae2f20f11a508fbffff4c8db568fcfffff30f118d70fcfffff30f118568fcffff660f70c001f30f11856cfcfffff30f5ad2f20f119510fbfffff20f104370f20f59c6f20f104b68f20f59cdf20f58c8f20f104378f20f59c3f20f58c1f20f108b80000000f20f59ccf20f58c8f20f108388000000f20f58c1f20f59c2f20f5ac04c89f7e8
{call_2b3:4}
4c89ef4c89f6e8
{call_2be:4}
488db558fcfffff30f118d60fcfffff30f118558fcffff660f70c001f30f11855cfcffff4c89e7e8
{call_2ea:4}
488db528fdffff4c89ffe8
{call_2f9:4}
488dbd48fcfffff30f118d50fcfffff30f118548fcffff660f70c001f30f11854cfcfffff20f108d28fbfffff20f598b98000000f20f108520fbfffff20f598390000000f20f58c10f28c8f20f108518fbfffff20f5983a0000000f20f58c1f20f108d08fbfffff20f598ba8000000f20f58c8f20f1083b0000000f20f58c1f20f598510fbfffff20f5ac0e8
{call_389:4}
f683080100000174
{jump_395:1}
488dbd48fcffffe8
{call_39e:4}
f30f58830c010000f30f11830c010000f30f100d
{ref_3b3:4}
0f2ec80f978308010000488dbd28fdffff488db548fcffffe8
{call_3d3:4}
f30f118d40fcfffff30f118538fcffff660f70c001f30f11853cfcffff488db538fcffff4c89ffe8
{call_3ff:4}
"""

ARM_FOLLOW = """
d4ed050b72ade069eaa97a90cded780bd4ed020b206977902846cded750b
{call_1e:4}
04f120002946
{call_28:4}
94f84c0004f1080b04f114010028
{jump_3a:2}
c0ef500063ae0891311d4ff07e50639041f98f0a06f11801689041f98f0a00216d906e9131466f90709071900220d4e9142394ed160a019054a88ded000a20ef1001
{call_7e:4}
eaa83146
{call_86:4}
04f138063046
{call_90:4}
94ed2b0a40ec110bb4eec01af1ee10fa
{jump_a4:2}
80ee010a304610ee101a
{call_b0:4}
{jump_b4:2}
089104f1380651ad0df56a78324628464146
{call_c8:4}
58462946
{call_d0:4}
4ead04f12c0241462846
{call_de:4}
089e29463046
{call_e8:4}
4ba878aa3146
{call_f2:4}
cdf81cb08afb0ab84feaea73abfb0a510bfb0311a5fb0a0208fb0a1605fb032206fb0a21
{call_11a:4}
0690284605913146
{call_126:4}
41ec180b069805994aec19ab94ed17ab94ed19cb41ec1d0b5846414694ed1beb94ed1dbbddf81cb0
{call_152:4}
6dee0a2b4bae68ee0c0b41ec1f0b3046b8eec9ab6fee0e4b72eea00bbbff09166aee0b2b87ef100f70eea40b80ee010a70eea20bd4ed1f2bb7eec0ca72eea00b6cee200bb7eee00b10ee101a
{call_1a2:4}
48ad78a932462846
{call_1ae:4}
08982946
{call_1b6:4}
45ad75aa59462846
{call_1c2:4}
d4ed210b2846d4ed232b6dee200b68ee222bd4ed254b70eea20b6fee244bd4ed276b70eea40b6aee262b70eea20bd4ed292b72eea00b6cee200bb7eee00b10ee101a
{call_208:4}
94f8fc00
{jump_210:2}
45a8
{call_214:4}
94ed400a40ec300b
{literal_220:4}
002000ef800db4eec20a84ed400af1ee10fa48bf012084f8fc0042ad75a945aa2846
{call_246:4}
58462946
{call_24e:4}
"""

MAC_RESET = """
554889e5c78730010000
{rate_4:4}
c78734010000
{rate_e:4}
f30f1005
{ref_18:4}
5de9
{jump_21:4}
"""

ARM_RESET = """
{word_0:4}
{word_4:4}
4ff07e51
{word_c:4}
{word_10:4}
c0e94923
{jump_18:4}
"""

MAC_RATE_SCALE = """
554889e553500f28c8f30f114df44889fbf30f108330010000f30f59c1488d7368488d5370488d4b784989d84983e8804c8d8b88000000e8
{call_37:4}
f30f108334010000f30f5945f4488db390000000488d9398000000488d8ba00000004c8d83a80000004c8d8bb00000004883c4085b5de9
{jump_72:4}
"""

ARM_RATE_SCALE = """
90b501af2ded028b83b0044641ec181b94ed490a04f16c0304f17402009300ff180d019204f17c0004f15c0204f16403029010ee101a
{call_36:4}
94ed4a0a04f1940304f19c02009300ff180d019204f1a40004f1840204f18c03029010ee101a
{call_60:4}
03b0bdec028b90bd
"""

MAC_SCALE = """
554889e548897df8f30f1145f4488b7df8f30f1045f4f30f5907f30f1107f30f1045f4f30f594704f30f114704f30f1045f4f30f594708f30f1147084889f85dc36666666666662e0f1f840000000000
"""

ARM_SCALE = """
82b041ec101bb0ee402a01908ded002a01989ded002a90ed004a22ee042a80ed002a9ded002a90ed014a22ee042a80ed012a9ded002a90ed024a22ee042a80ed022a02b0704700bf
"""

MAC_ADD = """
554889e54883ec4048897de8488975e0488b7de8f30f1007f30f104f04f30f1016f30f105e04f30f58d0f30f58d9f30f104708f30f104e08f30f58c8488d7df00f28c2f30f114dcc0f28cbf30f1055cce8
{call_50:4}
f30f1045f0f30f104df4f30f1055f8f30f1155d8f30f114dd4f30f1145d0f30f104dd8f30f7e45d04883c4405dc3666666662e0f1f840000000000
"""

ARM_ADD = """
80b56f4683b002910192029991ed000a019991ed002a30ee020a029991ed012a019991ed014a32ee042a029991ed024a019991ed026a34ee064a10ee101a12ee102a14ee103a
{call_46:4}
009003b080bd
"""

MAC_SUBTRACT = """
554889e54883ec3048897de8488975e0488b7de8f30f1007f30f104f04f30f1016f30f105e04f30f5cc2f30f5ccbf30f105708f30f105e08f30f5cd3488d7df0e8
{call_40:4}
f30f1045f0f30f104df4f30f1055f8f30f1155d8f30f114dd4f30f1145d0f30f104dd8f30f7e45d04883c4305dc3666666662e0f1f840000000000
"""

ARM_SUBTRACT = """
80b56f4683b002910192029991ed000a019991ed002a30ee420a029991ed012a019991ed014a32ee442a029991ed024a019991ed026a34ee464a10ee101a12ee102a14ee103a
{call_46:4}
009003b080bd
"""

MAC_POINT = """
554889e54883ec4048897de8488975e0488b7de8f30f1006f30f104e04f30f1017f30f105f04f30f59d0f30f59d9f30f58daf30f105608f30f106708f30f59e2f30f58e3f30f105f0cf30f58dcf30f106710f30f59e0f30f106f14f30f59e9f30f58ecf30f106718f30f59e2f30f58e5f30f106f1cf30f58ecf30f106720f30f59e0f30f104724f30f59c1f30f58c4f30f104f28f30f59caf30f58c8f30f10472cf30f58c1488d7df0f30f1145cc0f28c30f28cdf30f1055cce8
{call_b9:4}
f30f1045f0f30f104df4f30f1055f8f30f1155d8f30f114dd4f30f1145d0f30f104dd8f30f7e45d04883c4405dc30f1f4000
"""

ARM_POINT = """
80b56f4683b002910192019991ed000a029991ed002a20ee020a019991ed012a029991ed014a22ee042a30ee020a019991ed022a029991ed024a22ee042a30ee020a029991ed032a30ee020a019991ed002a029991ed044a22ee042a019991ed014a029991ed056a24ee064a32ee042a019991ed024a029991ed066a24ee064a32ee042a029991ed074a32ee042a019991ed004a029991ed086a24ee064a019991ed016a029991ed091a26ee016a34ee064a019991ed026a029991ed0a1a26ee016a34ee064a029991ed0b6a34ee064a10ee101a12ee102a14ee103a
{call_dc:4}
009003b080bd00bf
"""

ARM_FIELDS = {'ARM_CURVE': {'literal_4': {'kind': 'vldr', 'register': 'd30'}, 'literal_8': {'kind': 'vldr', 'register': 'd2'}, 'literal_40': {'kind': 'vldr', 'register': 'd2'}, 'literal_44': {'kind': 'vldr', 'register': 'd4'}, 'literal_50': {'kind': 'vldr', 'register': 'd2'}, 'literal_60': {'kind': 'vldr', 'register': 'd2'}, 'literal_64': {'kind': 'vldr', 'register': 'd6'}, 'literal_70': {'kind': 'vldr', 'register': 'd2'}, 'literal_80': {'kind': 'vldr', 'register': 'd4'}, 'literal_84': {'kind': 'vldr', 'register': 'd17'}, 'literal_90': {'kind': 'vldr', 'register': 'd4'}, 'literal_a0': {'kind': 'vldr', 'register': 'd4'}, 'literal_ac': {'kind': 'vldr', 'register': 'd4'}, 'literal_b8': {'kind': 'vldr', 'register': 'd6'}, 'literal_c4': {'kind': 'vldr', 'register': 'd6'}, 'literal_d0': {'kind': 'vldr', 'register': 'd6'}, 'literal_dc': {'kind': 'vldr', 'register': 'd17'}, 'literal_e8': {'kind': 'vldr', 'register': 'd17'}, 'literal_f4': {'kind': 'vldr', 'register': 'd17'}, 'literal_fc': {'kind': 'vldr', 'register': 'd17'}, 'literal_108': {'kind': 'vldr', 'register': 'd0'}, 'literal_114': {'kind': 'vldr', 'register': 'd28'}, 'literal_118': {'kind': 'vldr', 'register': 'd0'}, 'literal_120': {'kind': 'vldr', 'register': 'd28'}, 'literal_128': {'kind': 'vldr', 'register': 'd26'}, 'literal_138': {'kind': 'vldr', 'register': 'd0'}, 'literal_148': {'kind': 'vldr', 'register': 'd2'}, 'literal_158': {'kind': 'vldr', 'register': 'd2'}, 'literal_164': {'kind': 'vldr', 'register': 'd2'}, 'literal_168': {'kind': 'vldr', 'register': 'd4'}, 'literal_174': {'kind': 'vldr', 'register': 'd2'}, 'literal_188': {'kind': 'vldr', 'register': 'd22'}, 'literal_194': {'kind': 'vldr', 'register': 'd2'}, 'literal_19c': {'kind': 'vldr', 'register': 'd0'}, 'literal_1a4': {'kind': 'vldr', 'register': 'd2'}, 'literal_1a8': {'kind': 'vldr', 'register': 'd4'}, 'literal_1bc': {'kind': 'vldr', 'register': 'd20'}, 'literal_1cc': {'kind': 'vldr', 'register': 'd22'}, 'literal_1d0': {'kind': 'vldr', 'register': 'd0'}, 'literal_1e0': {'kind': 'vldr', 'register': 'd30'}, 'literal_1f4': {'kind': 'vldr', 'register': 'd30'}, 'literal_1f8': {'kind': 'vldr', 'register': 'd2'}, 'literal_204': {'kind': 'vldr', 'register': 'd28'}, 'literal_208': {'kind': 'vldr', 'register': 'd0'}}, 'ARM_FOLLOW': {'call_1e': {'kind': 'bl'}, 'call_28': {'kind': 'bl'}, 'jump_3a': {'kind': 'beq'}, 'call_7e': {'kind': 'bl'}, 'call_86': {'kind': 'bl'}, 'call_90': {'kind': 'bl'}, 'jump_a4': {'kind': 'beq'}, 'call_b0': {'kind': 'bl'}, 'jump_b4': {'kind': 'b'}, 'call_c8': {'kind': 'bl'}, 'call_d0': {'kind': 'bl'}, 'call_de': {'kind': 'bl'}, 'call_e8': {'kind': 'bl'}, 'call_f2': {'kind': 'bl'}, 'call_11a': {'kind': 'blx'}, 'call_126': {'kind': 'blx'}, 'call_152': {'kind': 'blx'}, 'call_1a2': {'kind': 'bl'}, 'call_1ae': {'kind': 'bl'}, 'call_1b6': {'kind': 'bl'}, 'call_1c2': {'kind': 'bl'}, 'call_208': {'kind': 'bl'}, 'jump_210': {'kind': 'cbz', 'register': 'r0'}, 'call_214': {'kind': 'bl'}, 'literal_220': {'kind': 'vldr', 'register': 's4'}, 'call_246': {'kind': 'bl'}, 'call_24e': {'kind': 'bl'}}, 'ARM_RESET': {'word_0': {'kind': 'movw', 'register': 'r2'}, 'word_4': {'kind': 'movw', 'register': 'r3'}, 'word_c': {'kind': 'movt', 'register': 'r2'}, 'word_10': {'kind': 'movt', 'register': 'r3'}, 'jump_18': {'kind': 'b.w'}}, 'ARM_RATE_SCALE': {'call_36': {'kind': 'bl'}, 'call_60': {'kind': 'bl'}}, 'ARM_SCALE': {}, 'ARM_ADD': {'call_46': {'kind': 'blx'}}, 'ARM_SUBTRACT': {'call_46': {'kind': 'blx'}}, 'ARM_POINT': {'call_dc': {'kind': 'blx'}}}

MAC_TERMS = [[[-1, 'ref_2e8'], [-1, 'ref_289'], [-1, 'ref_2a4'], [-1, 'ref_274'], [-1, 'ref_245'], [-1, 'ref_20f'], [-1, 'ref_1a5'], [-1, 'ref_153'], [-1, 'ref_15f']], [[1, 'ref_2d2'], [1, 'ref_296'], [1, 'ref_2b1'], [1, 'ref_267'], [1, 'ref_252'], [1, 'ref_25b'], [1, 'ref_21f'], [1, 'ref_180'], [1, 'ref_188']], [[1, 'ref_27d'], [1, 'ref_1fe'], [1, 'ref_1b6'], [1, 'ref_142'], [1, 'ref_e3'], [1, 'ref_90'], [1, 'ref_7f'], [1, 'ref_63'], [1, 'ref_6f']], [[-1, 'ref_228'], [-1, 'ref_194'], [-1, 'ref_16f'], [-1, 'ref_d2'], [-1, 'ref_c1'], [-1, 'ref_b1'], [-1, 'ref_a0'], [-1, 'ref_3f'], [-1, 'ref_53']], [[0, None], [1, 'ref_1e9'], [1, 'ref_1d8'], [1, 'ref_1c7'], [1, 'ref_131'], [1, 'ref_121'], [1, 'ref_110'], [1, 'ref_f4'], [1, 'ref_100']]]

ARM_TERMS = [[[-1, 'literal_1f8'], [-1, 'literal_1cc'], [-1, 'literal_19c'], [-1, 'literal_148'], [-1, 'literal_60'], [-1, 'literal_50'], [-1, 'literal_40'], [-1, 'literal_4'], [-1, 'literal_8']], [[1, 'literal_204'], [1, 'literal_194'], [1, 'literal_1a8'], [1, 'literal_168'], [1, 'literal_118'], [1, 'literal_c4'], [1, 'literal_b8'], [1, 'literal_ac'], [1, 'literal_64']], [[1, 'literal_208'], [1, 'literal_1d0'], [1, 'literal_158'], [1, 'literal_164'], [1, 'literal_128'], [1, 'literal_e8'], [1, 'literal_dc'], [1, 'literal_d0'], [1, 'literal_84']], [[-1, 'literal_1f4'], [-1, 'literal_1bc'], [-1, 'literal_188'], [-1, 'literal_138'], [-1, 'literal_a0'], [-1, 'literal_90'], [-1, 'literal_80'], [-1, 'literal_70'], [-1, 'literal_44']], [[0, None], [1, 'literal_1e0'], [1, 'literal_1a4'], [1, 'literal_174'], [1, 'literal_120'], [1, 'literal_114'], [1, 'literal_108'], [1, 'literal_f4'], [1, 'literal_fc']]]

def extract_camera_follow(mach, camera):
    import capstone
    mac = mach.architecture == 'x86_64'
    if not camera or (not mac and mach.architecture != 'armv7'): return {}
    text = mach.text
    code = mach.data[text['offset']:text['offset'] + text['length']]
    base = text['address']; prefix = 'MAC_' if mac else 'ARM_'
    decoder = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_THUMB); decoder.detail = True
    provenance = {}; blocks = {}
    def require(value):
        if not value: raise ValueError('Unsupported camera follow declaration')
    def instruction(m, key):
        rows=list(decoder.disasm(m[key],base+m.start(key)))
        require(len(rows)==1 and rows[0].size==len(m[key]));return rows[0]
    def match(key, spec, metadata=None, at=None):
        found=[m for m in template(spec).finditer(code) if (mac or m.start()%2==0) and (at is None or base+m.start()==at)]
        require(len(found)==1);m=found[0]
        if not mac and metadata:
            for field,expected in metadata.items():
                ins=instruction(m,field)
                require(ins.mnemonic==expected['kind'])
                if 'register' in expected:require(ins.reg_name(ins.operands[0].reg)==expected['register'])
                if field.startswith('literal_'):require(ins.operands[1].type==3 and ins.reg_name(ins.operands[1].mem.base)=='pc')
                if field.startswith('word_'):require(ins.operands[1].type==2)
        provenance[key]={'offset':mach.slice_offset+text['offset']+m.start(),'bytes':len(m[0])}
        blocks[key]=m;return m
    def address(m):return base+m.start()
    def target(m,key):
        if mac:return base+m.end(key)+int.from_bytes(m[key],'little',signed=True)
        ins=instruction(m,key);require(ins.operands[-1].type==2);return ins.operands[-1].imm
    def constant(key,field,size=8):
        m=blocks[key]
        if mac:dest=target(m,field);section=b'__const'
        else:
            ins=instruction(m,field);dest=((ins.address+4)&~3)+ins.operands[1].mem.disp;section=b'__text'
        found=section_bytes(mach,dest,size,section);require(found is not None)
        provenance[key+'_'+field]={'offset':found[1],'bytes':size}
        return found[0]
    def scalar(key,field,size=8):
        return struct.unpack('<d' if size==8 else '<f',constant(key,field,size))[0]
    def wide_float(m,lo,hi):
        low=instruction(m,lo).operands[1].imm if lo else 0
        high=instruction(m,hi).operands[1].imm
        return struct.unpack('<f',struct.pack('<I',low|(high<<16)))[0]
    def links(key,fields,dest):
        for field in fields: require(target(blocks[key],field)==dest)
    try:
        for key in ['curve','follow','reset','rate_scale','scale','add','subtract','point']:
            name=prefix+key.upper()
            field=({'scale':'call_2b3','add':'call_2be','subtract':'call_1d0','point':'call_15a'} if mac else {'scale':'call_1a2','add':'call_1ae','subtract':'call_f2','point':'call_c8'}).get(key)
            at=target(blocks['follow'],field) if field else None
            match(key,globals()[name],ARM_FIELDS.get(name),at)
        for key in ['attach','defaults','increment']:
            name=prefix+key.upper();match(key,getattr(opening,name),opening.ARM_FIELDS.get(name))
            require(provenance[key]==camera['provenance'][key])
        curve,follow,reset,rate_scale=[blocks[k] for k in ['curve','follow','reset','rate_scale']]
        if mac:
            links('defaults',['call_3c4','call_3f4'],address(curve))
            links('rate_scale',['call_37','jump_72'],address(curve))
            links('reset',['jump_21'],address(rate_scale))
            require(address(follow)==target(blocks['increment'],'jump_52')+0x795)
            for key,fields in [('point',['call_15a','call_192']),('scale',['call_2b3','call_389']),('add',['call_2be','call_3d3']),('subtract',['call_1d0','call_2f9'])]:links('follow',fields,address(blocks[key]))
            # Captured code fixes output fields and parameter ownership. Read
            # the inline float operands rather than supplying native defaults.
            look_rate=struct.unpack('<f',reset['rate_4'])[0]
            eye_rate=struct.unpack('<f',reset['rate_e'])[0]
            multiplier=scalar('reset','ref_18',4)
            numerator=scalar('follow','ref_1e5',4)
            require(constant('curve','ref_235')==bytes.fromhex('0000000000000080'))
            terms=MAC_TERMS
            # Six stack initialization operands in the verified attachment.
            offsets=[]
            for rel in [0x43,0x4a,0x51,0x65,0x6c,0x73]: offsets.append(struct.unpack_from('<f',blocks['attach'][0],rel)[0])
            look_offset,eye_offset=offsets[:3],offsets[3:]
            fixed_edges={'jump_6d':0x78,'jump_73':0x14d,'jump_13d':0x141,'jump_13f':0x14d,'jump_395':0x3c5}
        else:
            links('defaults',['call_206','call_228'],address(curve))
            links('rate_scale',['call_36','call_60'],address(curve))
            links('reset',['jump_18'],address(rate_scale))
            require(address(follow)==target(blocks['increment'],'jump_44')+0x43c)
            for key,fields in [('point',['call_c8','call_de']),('scale',['call_1a2','call_208']),('add',['call_1ae','call_246']),('subtract',['call_f2','call_1c2'])]:links('follow',fields,address(blocks[key]))
            look_rate=wide_float(reset,'word_0','word_c');eye_rate=wide_float(reset,'word_4','word_10')
            multiplier=1.0; numerator=1.0  # Literal VFP/immediate operands in the matched blocks.
            terms=ARM_TERMS
            attach=blocks['attach'];y=wide_float(attach,None,'word_2c')
            look_offset=[0.0,y,wide_float(attach,'word_24','word_30')]
            eye_offset=[0.0,y,wide_float(attach,'word_40','word_46')]
            fixed_edges={'jump_3a':0xb6,'jump_a4':0xbc,'jump_b4':0xbc,'jump_210':0x23e}
        for field,relative in fixed_edges.items():require(target(follow,field)==address(follow)+relative)
        matrix=[]
        for row in terms:
            matrix.append([sign*scalar('curve',ref) if ref else 0.0 for sign,ref in row])
        # Verify code/stub links without retaining any target bytes in the pack.
        for key,m in blocks.items():
            for field in m.groupdict():
                if not field.startswith(('call_','jump_')):continue
                dest=target(m,field)
                backed=section_bytes(mach,dest,2,b'__text')
                if backed is None:
                    # Vector constructors and ARM integer-to-double conversions
                    # are import-time identification only, never runtime calls.
                    backed=section_bytes(mach,dest,6 if mac else 16,b'__stubs' if mac else b'__picsymbolstub4')
                require(backed is not None)
        values=[look_rate,eye_rate,multiplier,numerator,*look_offset,*eye_offset,*[v for row in matrix for v in row]]
        require(all(math.isfinite(v) for v in values))
        require(0<look_rate<=1 and 0<eye_rate<=1 and 0<multiplier<=100 and 0<numerator<=100)
        require(all(abs(v)<=10000000 for v in look_offset+eye_offset))
        rates=[struct.unpack('<f',struct.pack('<f',r*multiplier))[0] for r in [look_rate,eye_rate]]
        require(all(0<r<=1 for r in rates))
        return {'look_offset':look_offset,'eye_offset':eye_offset,'look_rate':rates[0],'eye_rate':rates[1],
                'response_matrix':matrix,'reciprocal_numerator':numerator,'provenance':provenance}
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,struct.error):return {}
