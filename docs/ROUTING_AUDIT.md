# Routing geometry review — source-only audit

This is a source review of `lib/corridor_roads.dart`, not a verified measurement against the school's authoritative floor plans. Do not use the findings below as an evacuation-route certification.

## Third floor: cabinets 315–318 / 317

The local cluster still includes these hidden segments:
- (1881,3292) → (1913,3448), labelled near room 318;
- (1913,3448) → (2285,3540), labelled near rooms 317–316;
- (2125,3540) → (2285,3388), labelled near rooms 316–315;
- (2285,3388) → (2157,3467), labelled as the exit to the short blue corridor.

The local geometry still contains a diagonal branch around doors 315–316 and a separate join from the 317–318 corridor to the long turquoise corridor. I have retained these connectors because removing them without an authoritative floor-plan check could disconnect the local corridor. The new regression tests verify all catalog destinations are reachable from the main entrance and all third-floor destinations are reachable from room 311 without changing floors. These are graph-connectivity checks, not proof that every segment matches a physically walkable corridor.

## Other suspected redundancy

- Removed the redundant near-parallel purple segment on floor 3: the remaining segment (2965,2417) → (2229,2417) already covers that route.
- Removed a second segment collinear with the long turquoise corridor near the library. The library destination anchor projects directly onto the remaining corridor, so the duplicate road was unnecessary.
- Updated door-to-corridor projection to calculate perpendiculars in the original 7016×4960 pixel coordinate system, rather than projecting directly in non-square normalized coordinates.
- Several floor 2 and floor 3 connections are explicitly marked `hidden: true`; hidden means not drawn as a corridor overlay in the editor, not excluded from route-graph construction. They can still influence the chosen route.
- The router snaps endpoints within 32 source-map pixels and connects anchors to a nearest corridor segment if the connector is within 450 pixels. This can connect close parallel segments or cause visible small jogs when source geometry is approximate.

## Recommended verification

1. Compare each flagged segment against the original floor-plan image at full resolution.
2. Review actual turn-by-turn path screenshots from 311→317 and 311→316 against the floor-plan image once available in the development environment.
3. Keep the corridor geometry tests running: they fail on long collinear overlaps or exact same-floor duplicate segments.
4. Treat emergency egress routes as school-approved data; do not infer them solely from shortest-path geometry.
