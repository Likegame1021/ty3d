shader_type spatial;
uniform vec4 dirt_color : source_color = vec4(.47,.34,.19,1.0);
varying vec3 wp;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float segment_distance(vec2 p,vec2 a,vec2 b){vec2 ab=b-a;return length(p-a-ab*clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0));}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=wp.xz;
 float center=abs(p.x+sin(p.y*.38)*.18);
 float side=min(segment_distance(p,vec2(-1.8,9.2),vec2(-3.8,7.0)),segment_distance(p,vec2(-3.8,7.0),vec2(-5.5,1.0)));
 side=min(side,segment_distance(p,vec2(-5.5,1.0),vec2(-1.7,-2.7)));
 float path=max(1.0-smoothstep(1.05,2.1,center), (1.0-smoothstep(.32,.70,side))*.70);
 float fleck=hash(floor(p*34.0));
 float broad=sin(p.x*2.1+sin(p.y*1.3))*sin(p.y*2.8)*.04;
 vec3 earth=dirt_color.rgb*(.92+fleck*.09+broad);
 vec3 field=vec3(.25,.29,.105)*(.88+fleck*.12);
 ALBEDO=mix(field,earth+vec3(.04,.025,0.0),path);ROUGHNESS=1.0;
}
