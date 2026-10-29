extends RefCounted
## Deterministic appearance only. Species, placement and combat parameters stay authoritative.
const CORN_SCENE := "res://assets/environment/r48/corn-sentinel-rigged-v002.glb"
static func variant_for_spawn(species:String, segment_index:int, elite:bool) -> String:
 return "corn_sentinel" if species=="beetle" and segment_index==0 and not elite else ""
static func scene_path(variant:String, species:String) -> String:
 return CORN_SCENE if variant=="corn_sentinel" and species=="beetle" else ""
