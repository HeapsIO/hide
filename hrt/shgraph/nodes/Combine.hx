package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Combine")
@description("Create a vector of size 4 from 4 floats")
@group("Channel")
class Combine extends ShaderNode {

	@input("R") var r = SType.Float;
	@input("G") var g = SType.Float;
	@input("B") var b = SType.Float;
	@input("A") var a = SType.Float;

	@output() var output = SType.Vec4;

	var components = [X, Y, Z, W];
	var componentsString = ["r", "g", "b", "a"];

	function generateOutputComp(idx : Int) : TExpr {
		var comp = components[idx];

		var input = getInput(componentsString[idx]);
		return {
					p : null,
					t : output.type,
					e : TBinop(OpAssign, {
						e: TSwiz({
							e: TVar(output),
							p: null,
							t : output.type
						}, [comp]),
						p: null,
						t: TVec(1, VFloat)
					}, input.getVar())
				};
	}

	override public function createOutputs() {
		addOutput("output", TVec(4, VFloat));
	}

	override public function build(key : String) : TExpr {

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
					e: TGlobal(Vec4),
					p: null,
					t: TFun([
						{
							ret: output.type,
							args: [
							{ name: "r", type : TFloat },
							{ name: "g", type : TFloat },
							{ name: "b", type : TFloat },
							{ name: "a", type : TFloat }]
						}
					])
				}, [(r != null) ? r.getVar() : { e: TConst(CFloat(0.0)), p: null, t: TFloat },
					(g != null) ? g.getVar() : { e: TConst(CFloat(0.0)), p: null, t: TFloat },
					(b != null) ? b.getVar() : { e: TConst(CFloat(0.0)), p: null, t: TFloat },
					(a != null) ? a.getVar() : { e: TConst(CFloat(1.0)), p: null, t: TFloat }]
				),
				p: null,
				t: output.type
			})
		};
	}

}