package hrt.shgraph;

enum abstract Global(Int) to Int {
	var PixelColor;
	var Time;
	var Global;

	var CalculatedUV;

	var UV;

	var RelativePosition;
	var TransformedPosition;
	var ProjectedPosition;

	var Normal;
	var FakeNormal;	// used as replacement for normal in previews
	var TransformedNormal;

	var Depth;
	var Metalness;
	var Roughness;
	var Emissive;
	var Occlusion;

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
		g[RelativePosition]			= {type: TVec(3, VFloat), name: "relativePosition", kind: Input};
		g[TransformedPosition]		= {type: TVec(3, VFloat), name: "transformedPosition", kind: Local};
		g[ProjectedPosition]		= {type: TVec(4, VFloat), name: "projectedPosition", kind: Local};

		g[Normal] 				= {type: TVec(3, VFloat), name: "normal", kind: Input};
		g[FakeNormal] 			= {type: TVec(3, VFloat), name: "fakeNormal", kind: Local};
		g[TransformedNormal] 	= {type: TVec(3, VFloat), name: "transformedNormal", kind: Local};

		g[Depth] 				= {type: TFloat, name: "depth", kind: Local};
		g[Metalness] 				= {type: TFloat, name: "metalness", kind: Local};
		g[Roughness] 				= {type: TFloat, name: "depth", kind: Local};
		g[Emissive] 				= {type: TFloat, name: "depth", kind: Local};
		g[Occlusion]			= {type: TFloat, name: "occlusion", kind: Local};

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