package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Split")
@description("Split all components of a vector into floats")
@group("Channel")
class Split extends ShaderNode {

	@input("RGBA") var input = SType.Vec4;

	@output("R") var r = SType.Float;
	@output("G") var g = SType.Float;
	@output("B") var b = SType.Float;
	@output("A") var a = SType.Float;

	var components = [X, Y, Z, W];
	var componentsString = ["r", "g", "b", "a"];

	override public function computeOutputs() {
		addOutput("r", TFloat);
		addOutput("g", TFloat);
		addOutput("b", TFloat);
		addOutput("a", TFloat);
	}

	override public function build(key : String) : TExpr {
		var compIdx = componentsString.indexOf(key);
		return { e: TBinop(OpAssign, {
					e: TVar(getOutput(key)),
					p: null,
					t: getOutput(key).type
				}, {e: TSwiz(input.getVar(TVec(4, VFloat)), [components[compIdx]]), p: null, t: getOutput(key).type }),
				p: null,
				t: getOutput(key).type
			};
	}

}