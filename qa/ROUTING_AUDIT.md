# Navigator routing audit

## Geometry review (2026-10-17)

A source-level sweep compared corridor centre-lines on the 7016×4960 source-map coordinate system:

- Floor 1: 12 segments.
- Floor 2: 25 segments.
- Floor 3: 22 segments after removing one duplicate segment.
- The sweep found one collinear, overlapping duplicate on floor 3: the old “Подход к Информационно-библиотечному центру” segment (x=2813…3557, y=3517) exactly overlapped the “Длинный бирюзовый коридор” from x=2713…3557 at y=3517. The shorter duplicate has been removed; the long corridor still contains the library/room anchor projections.

The room cluster 315–318 has several manually mapped connectors that meet at intersections. The geometric sweep did not find an exact/near-collinear duplicate among those local segments, so I have not deleted a connection solely on appearance: removing a non-duplicate edge may disconnect the blue wing or invent a wall-crossing route. Route regression tests now check 317↔318, 317↔315 and 316↔317 in both directions, with upper distance bounds, and representative short routes on floors 1 and 2.

## Existing graph constraints

- Door and room anchor projections must be within 450 source-map pixels of a corridor.
- Stair transitions are heavily penalized so a same-floor path is preferred whenever possible.
- Staircase by the sleeping-corpus passage does not connect to floor 3; the purple-wing staircase is used for 2↔3 routing.
- Hidden connectors are still part of the routing graph; the hidden flag affects map/debug rendering rather than making an edge non-routable.

## Remaining validation

This is a geometry/code audit, not yet a walk-through against a newly confirmed as-built school plan. The school should validate the 315–318 junction, each stair transition and evacuation routes with an authorised staff member before deployment. In particular, this application is not a substitute for official fire-safety signage, the sound system or staff instructions.

Historical fixes covered the second-floor turquoise/campus connector, room 215 approach, and the local 216–218 and 315–318 corridors.
