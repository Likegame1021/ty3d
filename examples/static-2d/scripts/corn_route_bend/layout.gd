extends "res://scripts/corn_route/layout.gd"
## Independent variant. Corridor cells, not their bounding boxes, are authoritative.
func build():
 rooms.clear();links.clear();walkable.clear();blockers.clear();blocked_roads.clear()
 var centers=[Vector2i(0,0),Vector2i(16,8),Vector2i(32,8),Vector2i(32,24),Vector2i(16,24)]
 var names=["Village corn gate","Bent irrigation lane","Old threshing yard","East corn bend","Harvest shed"]
 for i in range(5):
  var c:Vector2i=centers[i]
  rooms.append({"id":i,"center":c,"name":names[i],"ports":[]})
  for x in range(-4,5):
   for z in range(-4,5):walkable[c+Vector2i(x,z)]="room"
 var paths=[
  [Vector2i(4,0),Vector2i(8,0),Vector2i(8,8),Vector2i(12,8)],
  [Vector2i(20,8),Vector2i(28,8)],
  [Vector2i(32,12),Vector2i(32,20)],
  [Vector2i(28,24),Vector2i(20,24)]
 ]
 var spawn_sets=[[Vector2i(6,0),Vector2i(8,6)],[Vector2i(23,8),Vector2i(26,8)],[Vector2i(32,15),Vector2i(32,18)],[Vector2i(25,24),Vector2i(22,24)]]
 for id in range(4):
  var path:Array=paths[id]
  rooms[id].ports.append(path[0]);rooms[id+1].ports.append(path[-1])
  var cells:Array[Vector2i]=[]
  for part in range(path.size()-1):
   var a:Vector2i=path[part]
   var b:Vector2i=path[part+1]
   var step:=Vector2i(signi(b.x-a.x),signi(b.y-a.y))
   var distance:=absi(b.x-a.x)+absi(b.y-a.y)
   for n in range(distance+1):
    var point:=a+step*n
    for x in range(-1,2):
     for z in range(-1,2):
      var cell:=point+Vector2i(x,z)
      if walkable.get(cell,"")=="room":continue
      if not cells.has(cell):cells.append(cell)
      walkable[cell]="corridor"
  links.append({"id":id,"from":id,"to":id+1,"cells":cells,"spawns":spawn_sets[id],"waypoints":path})
 for cell in walkable:
  for step in STEPS:
   var outside:Vector2i=cell+step
   if not walkable.has(outside):blockers[outside]=true
 for room in rooms:
  for distance in range(5,9):
   var cell:Vector2i=room.center+Vector2i(-distance,0)
   if not walkable.has(cell):blocked_roads.append(cell)
func nearest_corridor_cell(link_id:int,position:Vector3)->Vector2i:
 var best:Vector2i=links[link_id].cells[0]
 var best_distance:=INF
 for cell in links[link_id].cells:
  var distance:float=Vector2(position.x-cell.x,position.z-cell.y).length_squared()
  if distance<best_distance:best=cell;best_distance=distance
 return best
func corridor_path(link_id:int,from:Vector3,to:Vector3)->Array:
 var start:=nearest_corridor_cell(link_id,from)
 var goal:=nearest_corridor_cell(link_id,to)
 var previous:={start:start}
 var queue:=[start]
 while not queue.is_empty():
  var cell:Vector2i=queue.pop_front()
  if cell==goal:break
  for direction in STEPS:
   var next:Vector2i=cell+direction
   if links[link_id].cells.has(next) and not previous.has(next):
    previous[next]=cell;queue.append(next)
 if not previous.has(goal):return []
 var result:Array=[goal]
 while result[0]!=start:result.push_front(previous[result[0]])
 return result
func circle_inside(link_id:int,position:Vector3,radius:float)->bool:
 if not corridor_contains(link_id,position):return false
 for i in range(16):
  var angle:float=i*TAU/16
  var sample:=position+Vector3(cos(angle)*radius,0,sin(angle)*radius)
  if not corridor_contains(link_id,sample):return false
 return true
func clamp_to_corridor(link_id:int,position:Vector3,margin:float=.28)->Vector3:
 if circle_inside(link_id,position,margin):return position
 var best:=position
 var best_distance:=INF
 for cell in links[link_id].cells:
  var candidate:=Vector3(clampf(position.x,cell.x-.5+margin,cell.x+.5-margin),position.y,clampf(position.z,cell.y-.5+margin,cell.y+.5-margin))
  var distance:=candidate.distance_squared_to(position)
  if distance<best_distance:best=candidate;best_distance=distance
 return best
