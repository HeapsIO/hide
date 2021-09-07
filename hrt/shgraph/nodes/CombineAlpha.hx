package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Combine Alpha")
@description("Create a vector of size 4 from a RGB and an Alpha float")
@group("Channel")
class CombineAlpha extends ShaderNode {

	@input("RGB") var rgb = SType.Vec3;
	@input("A", true) var a = SType.Float;

	@output("RGBA") var output = SType.Vec4;

	override public function computeOutputs() {

		addOutput("output", TVec(4, VFloat));
	}

	override public function build(key : String) : TExpr {

		var args = [];
		var valueArgs = [];
		var opTGlobal : TGlobal = Vec4;
		args.push({ name: "rgb", type : TVec(3, VFloat) });
		valueArgs.push(rgb.getVar());
		args.push({ name: "a", type : TFloat });
		valueArgs.push(a.getVar());
		opTGlobal = Vec4;

		return {
			p : null,
			t : output.type,
			e : TBinop(OpAssign, {
				e: TVar(output),
				p: null,
				t : output.type
			},
			{
				e: TCall({
					e: TGlobal(opTGlobal),
					p: null,
					t: TFun([
						{
							ret: output.type,
							args: args
						}
					])
				}, valueArgs
				),
				p: null,
				t: output.type
			})
		};
	}

}