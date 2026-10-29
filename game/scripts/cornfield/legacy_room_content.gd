extends RefCounted
## Frozen ty2d authored footprints and baseline dimensions; no pixel assets imported.
## The eight V4 dimensions are an immutable, auditable expansion baseline.

const BASELINE_SIZES := {
	"wide_clearing":Vector2(1152,736), "orchard_bend":Vector2(1024,768),
	"irrigation_bank":Vector2(1280,800), "hay_yard":Vector2(960,640),
	"old_farmyard":Vector2(1120,704), "corn_crossing":Vector2(896,608),
	"long_furrows":Vector2(1280,672), "sheltered_plot":Vector2(1024,640),
}
const SIZE_SCALE := 2.0
## Rectangles deliberately preserve a broad central crossing and perimeter loop.
## Different lengths, islands and materials change approach angles and cover.
const TEMPLATES := [
	{"id":"wide_clearing","title":"晒谷空地","baseline":"wide_clearing","species":["beetle","locust"],"blocks":[["hay",.19,.22,.15,.09],["hay",.70,.69,.12,.10],["corn",.72,.21,.09,.16]]},
	{"id":"orchard_bend","title":"老树湾","baseline":"orchard_bend","species":["beetle","rooster"],"blocks":[["tree",.19,.22,.07,.06],["tree",.74,.22,.07,.06],["corn",.23,.68,.16,.12],["tree",.72,.75,.07,.06]]},
	{"id":"irrigation_bank","title":"双口水渠","baseline":"irrigation_bank","species":["snail","beetle"],"blocks":[["water",.22,.18,.045,.24],["water",.22,.63,.045,.19],["water",.73,.18,.045,.19],["water",.73,.61,.045,.22]]},
	{"id":"hay_yard","title":"三垛草院","baseline":"hay_yard","species":["mouse","beetle"],"blocks":[["hay",.19,.23,.17,.08],["hay",.66,.20,.15,.10],["hay",.67,.67,.15,.12],["fence",.22,.74,.17,.025]]},
	{"id":"old_farmyard","title":"旧砖房后院","baseline":"old_farmyard","species":["rooster","mouse"],"blocks":[["brick",.16,.19,.18,.10],["fence",.18,.66,.20,.025],["hay",.69,.22,.10,.09],["well",.73,.72,.06,.06]]},
	{"id":"corn_crossing","title":"四畦玉米岔口","baseline":"corn_crossing","species":["beetle","corn_borer"],"blocks":[["corn",.20,.22,.16,.14],["corn",.65,.22,.15,.13],["corn",.22,.66,.14,.15],["corn",.64,.67,.17,.13]]},
	{"id":"long_furrows","title":"长垄田","baseline":"long_furrows","species":["locust","corn_borer"],"blocks":[["corn",.15,.23,.26,.065],["corn",.62,.23,.23,.065],["corn",.16,.73,.25,.065],["corn",.61,.73,.24,.065]]},
	{"id":"sheltered_plot","title":"缺口篱笆田","baseline":"sheltered_plot","species":["rooster","beetle"],"blocks":[["fence",.17,.24,.23,.025],["fence",.17,.24,.025,.14],["fence",.63,.72,.21,.025],["fence",.81,.62,.025,.12],["hay",.70,.20,.10,.08]]},
	{"id":"pump_corner","title":"机井拐角","baseline":"irrigation_bank","species":["snail","mouse"],"blocks":[["well",.24,.22,.07,.06],["water",.29,.29,.12,.035],["water",.67,.64,.035,.17],["brick",.75,.25,.07,.10]]},
	{"id":"broken_wall","title":"断墙夹道","baseline":"old_farmyard","species":["mouse","rooster"],"blocks":[["brick",.22,.19,.035,.22],["brick",.24,.19,.15,.035],["brick",.68,.62,.035,.19],["brick",.70,.78,.14,.035]]},
	{"id":"straw_s_bend","title":"秸秆折道","baseline":"long_furrows","species":["mouse","locust"],"blocks":[["hay",.19,.22,.21,.07],["hay",.33,.29,.07,.11],["hay",.61,.65,.22,.07],["hay",.61,.72,.07,.11]]},
	{"id":"dry_ditch","title":"干渠石滩","baseline":"irrigation_bank","species":["beetle","snail"],"blocks":[["stone",.19,.28,.08,.07],["stone",.32,.24,.08,.07],["stone",.62,.68,.08,.07],["stone",.76,.73,.08,.07],["water",.69,.18,.035,.17]]},
	{"id":"seedling_islands","title":"补苗小畦","baseline":"corn_crossing","species":["locust","beetle"],"blocks":[["corn",.19,.22,.08,.09],["corn",.32,.32,.08,.09],["corn",.69,.21,.08,.10],["corn",.22,.72,.08,.09],["corn",.68,.68,.08,.09]]},
	{"id":"cart_tracks","title":"板车辙口","baseline":"wide_clearing","species":["mouse","rooster"],"blocks":[["tools",.23,.27,.10,.06],["hay",.67,.24,.16,.09],["fence",.19,.71,.20,.025],["corn",.72,.64,.08,.19]]},
	{"id":"windbreak_rows","title":"挡风双垄","baseline":"long_furrows","species":["locust","corn_borer"],"blocks":[["corn",.20,.18,.07,.23],["corn",.33,.23,.07,.16],["corn",.64,.64,.07,.18],["corn",.77,.60,.07,.23]]},
	{"id":"low_bean_patch","title":"豆畦混种田","baseline":"sheltered_plot","species":["snail","beetle"],"blocks":[["corn",.19,.23,.18,.06],["fence",.19,.34,.18,.025],["corn",.65,.70,.18,.06],["fence",.65,.61,.18,.025]]},
	{"id":"well_ring","title":"井台四石","baseline":"orchard_bend","species":["snail","rooster"],"blocks":[["well",.26,.23,.06,.06],["stone",.19,.34,.07,.055],["stone",.35,.25,.06,.055],["hay",.69,.70,.12,.09],["tree",.73,.24,.06,.06]]},
	{"id":"corn_teeth","title":"锯齿玉米垄","baseline":"wide_clearing","species":["corn_borer","locust"],"blocks":[["corn",.18,.20,.06,.18],["corn",.29,.20,.06,.12],["corn",.66,.70,.06,.12],["corn",.77,.64,.06,.18],["hay",.67,.23,.11,.07]]},
	{"id":"rooster_run","title":"鸡窝外场","baseline":"hay_yard","species":["rooster","mouse"],"blocks":[["fence",.19,.21,.21,.025],["fence",.19,.21,.025,.18],["hay",.26,.26,.09,.07],["fence",.63,.72,.20,.025],["tools",.72,.23,.10,.06]]},
	{"id":"mouse_granary","title":"粮袋角落","baseline":"old_farmyard","species":["mouse","corn_borer"],"blocks":[["brick",.18,.20,.19,.07],["hay",.21,.30,.08,.08],["hay",.69,.64,.08,.08],["hay",.74,.76,.08,.07],["tools",.21,.72,.12,.06]]},
	{"id":"sluice_steps","title":"水闸石阶","baseline":"irrigation_bank","species":["snail","beetle"],"blocks":[["water",.19,.23,.21,.055],["stone",.32,.31,.07,.06],["water",.61,.73,.21,.055],["stone",.62,.63,.07,.06]]},
	{"id":"rest_tree","title":"歪槐树阴","baseline":"orchard_bend","species":["rooster","locust"],"blocks":[["tree",.25,.26,.07,.065],["tree",.70,.69,.07,.065],["corn",.66,.23,.17,.08],["hay",.21,.71,.12,.08]]},
	{"id":"tool_terraces","title":"农具台地","baseline":"sheltered_plot","species":["beetle","mouse"],"blocks":[["tools",.19,.24,.17,.055],["brick",.21,.34,.15,.035],["tools",.66,.69,.16,.055],["brick",.68,.78,.14,.035],["well",.73,.24,.06,.06]]},
	{"id":"borer_nest","title":"倒伏玉米巢","baseline":"wide_clearing","species":["corn_borer","beetle"],"blocks":[["corn",.18,.20,.20,.06],["corn",.18,.20,.055,.19],["corn",.65,.75,.18,.06],["corn",.78,.63,.055,.17],["hay",.68,.23,.12,.08]]},
]

