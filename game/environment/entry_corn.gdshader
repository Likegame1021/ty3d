shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.25,0.42,0.06,1.0);
uniform vec3 player_position = vec3(1000.0);
uniform vec3 chicken_position = vec3(1000.0);
uniform vec3 creature_position = vec3(1000.0);
uniform float creature_active = 0.0;
uniform float night = 0.0;
uniform float animation_time = 0.0;
varying float shade;
void vertex() {
 vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 float tip = pow(clamp(VERTEX.y/2.3,0.0,1.0),1.7);
 float phase = animation_time * 1.75 + world.x*.47 + world.z*.63 + INSTANCE_CUSTOM.x*6.28;
 vec2 player = world.xz-player_position.xz;
 float pd = length(player);
 vec2 chicken = world.xz-chicken_position.xz;
 float cd = length(chicken);
 vec2 creature = world.xz-creature_position.xz;
 float rd = length(creature);
 vec2 bend=vec2(sin(phase)*.075,cos(phase*.79)*.045);
 bend += player/max(pd,.15)*exp(-pd*pd*1.1)*.55;
 bend += chicken/max(cd,.15)*exp(-cd*cd*1.65)*(.09+sin(animation_time*8.0)*.035);
 bend += creature/max(rd,.15)*exp(-rd*rd*.95)*(.32+sin(animation_time*6.5)*.12)*creature_active;
 VERTEX += inverse(mat3(MODEL_MATRIX))*vec3(bend.x,0.0,bend.y)*tip;
 // A small personal clearing preserves the child's silhouette without field-wide transparency.
 VERTEX.y *= 1.0 - exp(-pd*pd*2.1)*.64;
 shade=.88+INSTANCE_CUSTOM.y*.22;
}
void fragment(){ ALBEDO=base_color.rgb*shade; ROUGHNESS=.88; EMISSION=base_color.rgb*night*.035; }
