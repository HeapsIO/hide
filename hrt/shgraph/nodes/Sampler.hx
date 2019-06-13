package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sampler")
@description("Get color from texture and UV")
@group("Property")
class Sampler extends ShaderNode {

	@input("texture") var texture = SType.Sampler;
	@input("uv") var uv = SType.Vec2;

	@output("rgba") var rgba = SType.Vec4;
	@output("r") var r = SType.Float;
	@output("g") var g = SType.Float;
	@output("b") var b = SType.Float;
	@output("a") var a = SType.Float;

	var components = [X, Y, Z, W];
	var componentsString = ["r", "g", "b", "a"];

	override public function computeOutputs() {
		addOutput("rgba", TVec(4, VFloat));
		addOutput("r", TFloat);
		addOutput("g", TFloat);
		addOutput("b", TFloat);
		addOutput("a", TFloat);
	}

	override public function build(key : String) : TExpr {
		if (key == "rgba") {
			var args = [];
			var varArgs = [];

			for (k in getInputInfoKeys()) {
				args.push({ name: k, type: getInput(k).getType() });
				var wantedType = ShaderType.getType(getInputInfo(k).type);
				varArgs.push(getInput(k).getVar((wantedType != null) ? wantedType : null));
			}

			return {
						p : null,
						t : rgba.type,
						e : TBinop(OpAssign, {
							e: TVar(rgba),
							p: null,
							t: rgba.type
						}, {
							e: TCall({
								e: TGlobal(Texture),
								p: null,
								t: TFun([
									{
										ret: rgba.type,
										args: args
									}
								])
							}, varArgs),
							p: null,
							t: rgba.type
						})
					};
		} else {
			var arrayExpr = [];
			if (!outputCompiled.get("rgba")) {
				arrayExpr.push({ e : TVarDecl(rgba), t : rgba.type, p : null });
				arrayExpr.push(build("rgba"));
				outputCompiled.set("rgba", true);
			}
			var compIdx = componentsString.indexOf(key);
			arrayExpr.push({ e: TBinop(OpAssign, {
						e: TVar(getOutput(key)),
						p: null,
						t: getOutput(key).type
					}, {e: TSwiz({
							e: TVar(rgba),
							p: null,
							t: rgba.type
						},
						[components[compIdx]]),
						p: null,
						t: getOutput(key).type }),
					p: null,
					t: getOutput(key).type
				});
			if (arrayExpr.length > 1) {
				return {
					p : null,
					t : TVoid,
					e : TBlock(arrayExpr)
				};
			} else {
				return arrayExpr[0];
			}
		}
	}

}