extends RefCounted
## Fixed five-map chain. Integer X/Z cells are the single spatial authority.
var rooms: Array = []
var links: Array = []
var walkable := {}
var blockers := {}
var blocked_roads: Array[Vector2i] = []
const STEPS = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
func build():
 rooms.clear(); links.clear(); walkable.clear(); blockers.clear(); blocked_roads.clear()
 var centers = [Vector2i(0,0),Vector2i(16,0),Vector2i(32,0),Vector2i(32,16),Vector2i(16,16)]
 var names = ["Village corn gate","Irrigation plot","Old threshing yard","East corn bend","Harvest shed"]
 for i in range(5):
  var c: Vector2i=centers[i]
  rooms.append({"id":i,"center":c,"name":names[i],"ports":[]})
  for x in range(-4,5):
   for y in range(-4,5): walkable[c+Vector2i(x,y)]="room"
 for i in range(4):
  var a: Vector2i=centers[i]
  var b: Vector2i=centers[i+1]
  var step := Vector2i(signi(b.x-a.x),signi(b.y-a.y))
  var side := Vector2i(-step.y,step.x)
  rooms[i].ports.append(a+step*4)
  rooms[i+1].ports.append(b-step*4)
  var cells: Array[Vector2i]=[]
  for distance in range(5,12):
   for width in range(-1,2):
    var cell := a+step*distance+side*width
    cells.append(cell)
    walkable[cell]="corridor"
  links.append({"id":i,"from":i,"to":i+1,"cells":cells,"spawns":[a+step*7,a+step*10],"step":step})
 # All non-route edges have a full-cell collision fence/corn bank.
 for cell in walkable:
  for step in STEPS:
   var outside: Vector2i=cell+step
   if not walkable.has(outside): blockers[outside]=true
 # Visible dead-end farm tracks are outside the playable route, behind banks.
 for room in rooms:
  for distance in range(5,9): blocked_roads.append(room.center+Vector2i(0,-distance))
 # Reject any accidental decorative overlap with a real connection.
 blocked_roads = blocked_roads.filter(func(cell): return not walkable.has(cell))
func kind_at(cell: Vector2i) -> String:
 return walkable.get(cell,"blocked")
func is_walkable(cell: Vector2i) -> bool:
 return walkable.has(cell)
func can_spawn(cell: Vector2i) -> bool:
 return kind_at(cell)=="corridor"
func cell_at(position: Vector3) -> Vector2i:
 return Vector2i(roundi(position.x),roundi(position.z))
func corridor_contains(link_id: int,position: Vector3) -> bool:
 return links[link_id].cells.has(cell_at(position))
func clamp_to_corridor(link_id: int,position: Vector3,margin: float=.28) -> Vector3:
 var cells: Array=links[link_id].cells
 var lo: Vector2i=cells[0]
 var hi: Vector2i=cells[0]
 for cell in cells:
  lo=Vector2i(mini(lo.x,cell.x),mini(lo.y,cell.y))
  hi=Vector2i(maxi(hi.x,cell.x),maxi(hi.y,cell.y))
 return Vector3(clampf(position.x,lo.x-.5+margin,hi.x+.5-margin),position.y,clampf(position.z,lo.y-.5+margin,hi.y+.5-margin))
