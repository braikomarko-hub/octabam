# OCTA303 v7.9 research data (moved from the Octa303 project, 9 Nov 2026)

Three data files from the research of 7 Nov 2026, kept here because the claude.ai project has a size limit. They are
byte-identical to the files that were in the project under the same names (sha256 below).

| file | what it is | sha256 |
|---|---|---|
| OCTA303_v79_cycles_table_format.json | sim303 (SPICE-equivalent) cycles: Q8 collector (square) and Q28 source (saw) per model set and note | bef44b595a79428c5d00a3902e71d227b01e80272d16fa6faf8d310e6fdebe2e |
| OCTA303_v79_q12_vd.json | Q12's differential input vd and ladder drive u, 3 steady periods, k 0.86, RES 127, in microvolts | 9159469f7c1296d8813615ce430f2c3fb60b8d2c62d4d79af7a0060b5b2eb88c |
| OCTA303_v79_q12_cycles_B_C2.json | key B_C2 of the researcher's cycles_1024.json (sim303 saw, 1024 points a cycle) | 73fbc526b68ff176832217c4068e37d5b583cbc2f2d1bd30bd8ccc10602da9c0 |

All three are our own circuit simulations; none contains Elektron data.
