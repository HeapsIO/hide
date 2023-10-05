package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sampler")
@description("Get color from texture and UV")
@group("Property")
class Sampler extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var texture : Sampler2D;
		@sginput var uv : Vec2;
		@sgoutput var RGBA : Vec4;
		@sgoutput var RGB : Vec3;
		@sgoutput var A : Float;


		function fragment() {
			RGBA = texture.get(uv);
			RGB = RGBA.rgb;
			A = RGBA.a;
		}
	}

	// @input("Texture") var texture = SType.Sampler;
	// @input("UV") var uv = SType.Vec2;



	// var components = [X, Y, Z, W];
	// var componentsString = ["r", "g", "b", "a"];

	// override public function computeOutputs() {
	// 	addOutput("rgba", TVec(4, VFloat));
	// 	addOutput("r", TFloat);
	// 	addOutput("g", TFloat);
	// 	addOutput("b", TFloat);
	// 	addOutput("a", TFloat);
	// }

	// override public function build(key : String) : TExpr {
	// 	if (key == "rgba") {
	// 		var args = [];
	// 		var varArgs = [];

	// 		for (k in getInputInfoKeys()) {
	// 			args.push({ name: k, type: getInput(k).getType() });
	// 			var wantedType = ShaderType.getType(getInputInfo(k).type);
	// 			varArgs.push(getInput(k).getVar((wantedType != null) ? wantedType : null));
	// 		}

	// 		return {
	// 					p : null,
	// 					t : rgba.type,
	// 					e : TBinop(OpAssign, {
	// 						e: TVar(rgba),
	// 						p: null,
	// 						t: rgba.type
	// 					}, {
	// 						e: TCall({
	// 							e: TGlobal(Texture),
	// 							p: null,
	// 							t: TFun([
	// 								{
	// 									ret: rgba.type,
	// 									args: args
	// 								}
	// 							])
	// 						}, varArgs),
	// 						p: null,
	// 						t: rgba.type
	// 					})
	// 				};
	// 	} else {
	// 		var arrayExpr = [];
	// 		if (!outputCompiled.get("rgba")) {
	// 			arrayExpr.push({ e : TVarDecl(rgba), t : rgba.type, p : null });
	// 			arrayExpr.push(build("rgba"));
	// 			outputCompiled.set("rgba", true);
	// 		}
	// 		var compIdx = componentsString.indexOf(key);
	// 		arrayExpr.push({ e: TBinop(OpAssign, {
	// 					e: TVar(getOutput(key)),
	// 					p: null,
	// 					t: getOutput(key).type
	// 				}, {e: TSwiz({
	// 						e: TVar(rgba),
	// 						p: null,
	// 						t: rgba.type
	// 					},
	// 					[components[compIdx]]),
	// 					p: null,
	// 					t: getOutput(key).type }),
	// 				p: null,
	// 				t: getOutput(key).type
	// 			});
	// 		if (arrayExpr.length > 1) {
	// 			return {
	// 				p : null,
	// 				t : TVoid,
	// 				e : TBlock(arrayExpr)
	// 			};
	// 		} else {
	// 			return arrayExpr[0];
	// 		}
	// 	}
	// }

}