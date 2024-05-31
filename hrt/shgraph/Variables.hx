package hrt.shgraph;

enum abstract Global(Int) to Int {
	var PixelColor;
	var PixelColorColor;
	var PixelColorAlpha;
	var Time;
	var PixelSize;
	var Global;

	var CalculatedUV;

	var Input;
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
	var PreviewColor;

	// Particles
	var ParticleLife;
	var ParticleLifeTime;
	var ParticleRandom;

	// Internal Shadergraph vars
	var SGPixelColor;
	var SGPixelAlpha;
}

enum VariableKind {
	KVar(kind: hxsl.Ast.VarKind, ?parent: Global, ?def: Dynamic);
	KSwizzle(global: Global, swiz: Array<hxsl.Ast.Component>);
}

typedef GlobalInfo = {type: hxsl.Ast.Type, name: String, varkind: VariableKind};
class Variables {
	public static var previewSelectName = "previewSelect_SG";

	public static var Globals : Array<GlobalInfo> = {
		var g : Array<GlobalInfo> = [];

		g[PixelColor] 			= {type: TVec(4, VFloat), 	name: "pixelColor", 	varkind: KVar(Local)};

		g[CalculatedUV] 		= {type: TVec(2, VFloat), 	name: "calculatedUV", varkind: KVar(Var)};

		g[Time] 				= {type: TFloat, 	name: "time", 			varkind: KVar(Global, Global)};
		g[PixelSize]			= {type: TVec(2, VFloat), 	name: "pixelSize", 		varkind: KVar(Global, Global)};
		g[Global] 				= {type: TVoid, 	name: "global", 		varkind: KVar(Global)};

		g[Input]			= {type: TVoid, name: "input", varkind: KVar(Input)};
		g[UV] 					= {type: TVec(2, VFloat), 	name: "uv", varkind: KVar(Input, Input)};
		g[RelativePosition]			= {type: TVec(3, VFloat), name: "relativePosition", varkind: KVar(Local)};
		g[TransformedPosition]		= {type: TVec(3, VFloat), name: "transformedPosition", varkind: KVar(Local)};
		g[ProjectedPosition]		= {type: TVec(4, VFloat), name: "projectedPosition", varkind: KVar(Local)};

		g[Normal] 				= {type: TVec(3, VFloat), name: "normal", varkind: KVar(Input, Input)};
		g[FakeNormal] 			= {type: TVec(3, VFloat), name: "fakeNormal", varkind: KVar(Local)};
		g[TransformedNormal] 	= {type: TVec(3, VFloat), name: "transformedNormal", varkind: KVar(Local)};

		g[Depth] 				= {type: TFloat, name: "depth", varkind: KVar(Local)};
		g[Metalness] 				= {type: TFloat, name: "metalness", varkind: KVar(Local)};
		g[Roughness] 				= {type: TFloat, name: "roughness", varkind: KVar(Local)};
		g[Emissive] 				= {type: TFloat, name: "emissive", varkind: KVar(Local)};
		g[Occlusion]			= {type: TFloat, name: "occlusion", varkind: KVar(Local)};

		g[PreviewSelect]		= {type: TInt, 		name: previewSelectName, varkind: KVar(Param,null, -1)};
		g[PreviewColor] 		= {type: TVec(4,VFloat), name: "_previewColor", varkind: KVar(Local)};


		g[SGPixelColor] 		= {type: TVec(3, VFloat), 	name: "_sg_out_color", varkind: KSwizzle(PixelColor, [X,Y,Z])};
		g[SGPixelAlpha] 		= {type: TFloat, 	name: "_sg_out_alpha", 		varkind: KSwizzle(PixelColor, [W])};

		g[ParticleLife]			= {type: TFloat, name: "particleLife", varkind: KVar(Local)};
		g[ParticleLifeTime]		= {type: TFloat, name: "particleLifeTime", varkind: KVar(Local)};
		g[ParticleRandom] 		= {type: TFloat, name: "particleRandom", varkind: KVar(Local)};



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