# Routing geometry review — source-only audit

This is a source review of `lib/corridor_roads.dart`, not a verified measurement against the school's authoritative floor plans. Do not use the findings below as an evacuation-route certification.

## Third floor: cabinets 315–318 / 317

The local cluster currently includes these four hidden segments:
- (1881,3292) → (1913,3448), labelled near room 318;
- (1913,3448) → (2285,3540), labelled near rooms 317–316;
- (2125,3540) → (2285,3388), labelled near rooms 316–315;
- (2285,3388) → (2157,3467), labelled as the exit to the short blue corridor.

The latter two create an additional diagonal branch through the same small area. They may be legitimate door-side links, but source code alone cannot establish that they represent walkable corridors rather than overlapping/duplicate geometry. Confirm against the original floor plan before deleting either segment. The existing test suite verifies that routes 311→316/317/318 stay on floor 3, but does not assert a minimal turn count or inspect the exact path through this cluster.

## Other suspected redundancy

- Floor 3 purple cross-corridor has two near-parallel segments: (2965,2417) → (2229,2417) and (2845,2414) → (2229,2402). Their overlap is suspicious and could create duplicate graph alternatives. Confirm the drawing before removing the second segment.
- Several floor 2 and floor 3 connections are explicitly marked `hidden: true`; hidden means not drawn as a corridor overlay in the editor, not excluded from route-graph construction. They can still influence the chosen route.
- The router snaps endpoints within 32 source-map pixels and connects anchors to a nearest corridor segment if the connector is within 450 pixels. This can connect close parallel segments or cause visible small jogs when source geometry is approximate.

## Recommended verification

1. Compare each flagged segment against the original floor-plan image at full resolution.
2. Add regression assertions for the exact node/turn sequence for 311→317, 311→316, 318→main blue corridor, and one representative route on each floor.
3. Minimize redundant collinear route points for display separately from editing graph topology.
4. Treat emergency egress routes as school-approved data; do not infer them solely from shortest-path geometry.
