extends RefCounted
## Opt-in visual adapter only. Does not load art, replace a controller, own a
## clock, invent animation, emit hits or change gameplay state.
const CANONICAL = ["S","SE","E","NE","N","NW","W","SW"]
var columns := 8
var grid := Vector2i(8,8)
var row_map: Array[int] = [0,1,2,3,4,5,6,7]
var offset := Vector2(0,20)
var pixel_size := .039
func configure(metadata: Dictionary, texture_size: Vector2i) -> String:
 # Validate everything before changing this profile. JSON numbers may be float.
 var cell = metadata.get("cell_size",[])
 var anchor = metadata.get("feet_anchor",[])
 var directions = metadata.get("directions",[])
 var count = metadata.get("columns",0)
 var height_px = metadata.get("visible_height_px",0)
 var height_world = metadata.get("world_height",0)
 if not cell is Array or cell.size() != 2 or not anchor is Array or anchor.size() != 2:
  return "cell_size and feet_anchor must be two-number arrays"
 for value in cell + anchor + [count,height_px,height_world]:
  if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):
   return "Dimensions and anchors must be finite numbers"
 if cell[0] <= 0 or cell[1] <= 0 or cell[0] != int(cell[0]) or cell[1] != int(cell[1]):
  return "Cell dimensions must be positive integers"
 if count < 1 or count != int(count): return "columns must be a positive integer"
 if anchor[0] < 0 or anchor[0] > cell[0] or anchor[1] < 0 or anchor[1] > cell[1]:
  return "Foot anchor must lie inside the cell"
 if height_px <= 0 or height_px > cell[1] or height_world <= 0:
  return "Visible pixel height and world height must be positive; pixel height must fit cell"
 var single_view: bool = metadata.get("single_view",false) == true
 var direction_count := 1 if single_view else 8
 if not directions is Array or directions.size() != direction_count:
  return "Direction count must match explicit single-view or eight-way mode"
 if single_view:
  if int(count) != 1 or not CANONICAL.has(directions[0]): return "Single-view mode requires one static canonical direction"
 else:
  for direction_name in CANONICAL:
   if directions.count(direction_name) != 1: return "Each canonical direction must occur exactly once"
 var next_grid := Vector2i(int(count),direction_count)
 if metadata.has("atlas_grid"):
  var requested_grid = metadata.atlas_grid
  if not requested_grid is Array or requested_grid.size() != 2:
   return "atlas_grid must contain two positive integers"
  for value in requested_grid:
   if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < 1 or value != int(value):
    return "atlas_grid must contain two positive integers"
  if int(count) != 1 or int(requested_grid[0])*int(requested_grid[1]) != direction_count:
   return "Explicit atlas_grid must match the declared static direction count"
  next_grid = Vector2i(int(requested_grid[0]),int(requested_grid[1]))
 if texture_size != Vector2i(int(cell[0])*next_grid.x,int(cell[1])*next_grid.y):
  return "Texture dimensions do not match cell dimensions, columns and eight rows"
 var mapped: Array[int] = []
 for direction_name in CANONICAL: mapped.append(directions.find(direction_name))
 columns = int(count)
 grid = next_grid
 row_map = mapped
 offset = Vector2(float(cell[0])*.5-float(anchor[0]),float(anchor[1])-float(cell[1])*.5)
 pixel_size = float(height_world)/float(height_px)
 return ""
func apply_settings(sprite: Sprite3D, sampler: RefCounted) -> void:
 sprite.hframes = grid.x
 sprite.vframes = grid.y
 sprite.offset = offset
 sprite.pixel_size = pixel_size
 sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
 sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
 sprite.alpha_scissor_threshold = .4
 sprite.no_depth_test = false
 sprite.shaded = false
 sampler.frame_count = columns
 sampler.foot_offset = offset
func apply_sample(sprite: Sprite3D, sample_output: Dictionary) -> bool:
 var direction := clampi(int(sample_output.direction),0,7)
 if row_map[direction] < 0: return false
 var column := posmod(int(sample_output.frame),columns)
 sprite.frame = row_map[direction]*columns+column
 sprite.modulate = sample_output.tint
 sprite.offset = offset
 return true
