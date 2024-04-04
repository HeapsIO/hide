package hrt.shgraph;

enum abstract Global(Int) to Int {
	var PixelColor;
	var Time;
	var Global;

	var CalculatedUV;

	var Input;
	var UV;

	var PreviewSelect;

	// Internal Shadergraph vars
	var SGPixelColor;
	var SGPixelAlpha;
}

typedef GlobalInfo = {type: hxsl.Ast.Type, kind: hxsl.Ast.VarKind, name: String, ?display: String, ?parent: Global, ?def: Dynamic};
class Variables {
	public static var previewSelectName = "previewSelect_SG";

	public static var Globals : Array<GlobalInfo> = {
		var g : Array<GlobalInfo> = [];

		g[PixelColor] 			= {type: TVec(4, VFloat), 	name: "pixelColor", 	kind: Local};
		g[CalculatedUV] 		= {type: TVec(2, VFloat), 	name: "calculatedUV", 		kind: Local};

		g[Time] 				= {type: TFloat, 	name: "time", 			kind: Local, parent: Global};
		g[Global] 				= {type: TVoid, 	name: "global", 		kind: Global};

		g[UV] 					= {type: TVec(2, VFloat), 	name: "uv", kind: Input};

		g[PreviewSelect]		= {type: TInt, 		name: previewSelectName, kind: Param, def: -1};

		g[SGPixelColor] 		= {type: TVec(3, VFloat), 	name: "_sg_out_color", 		display: "Pixel Color", kind: Local};
		g[SGPixelAlpha] 		= {type: TFloat, 	name: "_sg_out_alpha", 		display: "Alpha", kind: Local};



		g;
	};

	public static function getGlobalNameMap() {
		static var GlobalNameMap : Map<String, Global>;
		if (GlobalNameMap == null)
			GlobalNameMap = [
				for (id => g in Globals) if (g != null) g.name => (cast id:Global)
			];
		return GlobalNameMap;
	}

}