extends SceneTree
var checks:=0
var failures:=0
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;push_error(label)
func _initialize():
 var path:="res://scripts/new_pixel_hero_static_v1/atlas_visual.gd"
 if not ResourceLoader.exists(path):
  check(false,"New real 2D atlas adapter missing")
  quit(1);return
 var sampler=load(path).new()
 check(sampler.load_profile("res://profiles/new_pixel_hero_static_v1.json").is_empty(),"Actual original image profile accepted")
 check(sampler.ready,"Sampler ready")
 var directions=["S","SE","E","NE","N","NW","W","SW"]
 var regions={}
 for row in range(8):
  var angle:float=row*PI/4
  var facing:=Vector3(sin(angle),0,cos(angle))
  var base:Dictionary=sampler.sample_static("idle",facing,Basis.IDENTITY,row)
  check(base.valid and base.direction==row and base.direction_name==directions[row],"Correct independent direction "+directions[row])
  check(base.texture is AtlasTexture and base.texture.atlas.resource_path=="res://assets/new_pixel_hero_static_v1/hd2d-hero-eight-directions-v2.png","Uses original 2D texture via AtlasTexture")
  check(base.texture.filter_clip and base.texture.margin==Rect2(),"Atlas region clips neighboring art")
  check(not regions.has(str(base.texture.region)),"Direction is independently sampled, not mirrored")
  regions[str(base.texture.region)]=true
  var anchor:Vector2=base.feet_anchor
  var size:Vector2=base.texture.get_size()
  check((Vector2(anchor.x-size.x/2,size.y/2-anchor.y)+base.offset).length()<.0001,"Measured foot anchor lands at sprite origin")
  for action in ["run","attack","hurt","recover","unknown"]:
   var sample:Dictionary=sampler.sample_static(action,facing,Basis.IDENTITY,row)
   check(sample.texture==base.texture and sample.frame_index==0 and sample.static_fallback and sample.fallback_for==action,"Explicit static fallback for "+action)
   check(sample.tint==(Color(1.6,.65,.55) if action=="hurt" else Color.WHITE),"Preserve hurt tint only")
  var rotated:Dictionary=sampler.sample_static("idle",facing,Basis(Vector3.UP,PI/2),(row-2+8)%8)
  check(rotated.direction==(row-2+8)%8,"Camera yaw remaps independently of gameplay direction")
 var sprite:=Sprite3D.new()
 sampler.apply_material(sprite)
 check(sprite.hframes==1 and sprite.vframes==1 and not sprite.flip_h and not sprite.flip_v,"One frame, no mirroring")
 check(sprite.alpha_cut==SpriteBase3D.ALPHA_CUT_DISCARD and is_equal_approx(sprite.alpha_scissor_threshold,.5),"Measured alpha cutoff")
 check(sprite.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and not sprite.no_depth_test,"Nearest and real depth")
 check(sprite.billboard==BaseMaterial3D.BILLBOARD_ENABLED and not sprite.shaded,"Consistent billboard material")
 check(not sampler.load_profile("res://profiles/missing-new-2d.json").is_empty() and not sampler.ready,"Missing asset fails closed")
 check(not sampler.sample_static("idle",Vector3.BACK,Basis.IDENTITY,0).valid,"No old art fallback after rejection")
 sprite.free()
 print("NEW 2D STATIC ATLAS checks=",checks," failures=",failures)
 quit(1 if failures else 0)
