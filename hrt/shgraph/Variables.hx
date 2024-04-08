package hrt.shgraph;

enum abstract Global(Int) to Int {
	var PixelColor;
	var Time;
	var Global;

	var PreviewSelect;

	// Internal Shadergraph vars
	var SGPixelColor;
	var SGPixelAlpha;
}

class Variables {
	public static var previewSelectName = "previewSelect_SG";

	public static var Globals = {
		var g : Array<{type: hxsl.Ast.Type, kind: hxsl.Ast.VarKind, name: String, ?display: String, ?parent: Global, ?def: Dynamic}> = [];

		g[PixelColor] 			= {type: TVec(4, VFloat), 	name: "pixelColor", 	kind: Local};
		g[Time] 				= {type: TFloat, 	name: "time", 			kind: Local, parent: Global};
		g[Global] 				= {type: TFloat, 	name: "global", 		kind: Global};

		g[PreviewSelect]		= {type: TInt, 		name: previewSelectName, kind: Param, def: -1};

		g[SGPixelColor] 		= {type: TVec(3, VFloat), 	name: "_sg_out_color", 		display: "Pixel Color", kind: Local};
		g[SGPixelAlpha] 		= {type: TFloat, 	name: "_sg_out_alpha", 		display: "Alpha", kind: Local};
		g;
	};


}