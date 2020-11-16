package hrt.shgraph.nodes;

import hxsl.Types.Vec;
import hxsl.*;

using hxsl.Ast;

@name("Combine")
@description("Create a vector of size 4 from 4 floats")
@group("Channel")
class Combine extends ShaderNode {

	@input("R", false, false) var r = SType.Float;
	@input("G", false, false) var g = SType.Float;
	@input("B", false, false) var b = SType.Float;
	@input("A", false, false) var a = SType.Float;

	@output() var output = SType.Variant;

	var components = [X, Y, Z, W];
	var componentsString = ["r", "g", "b", "a"];
	var numberOutputs = 0;

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

	override public function computeOutputs() {
		numberOutputs = 1;
		if (a != null && !a.isEmpty()) {
			numberOutputs = 4;
		} else if (b != null && !b.isEmpty()) {
			numberOutputs = 3;
		} else if (g != null && !g.isEmpty()) {
			numberOutputs = 2;
		}
		if (numberOutputs == 1) {
			addOutput("output", TFloat);
		} else {
			addOutput("output", TVec(numberOutputs, VFloat));
		}
	}

	override public function build(key : String) : TExpr {

		var args = [];
		var valueArgs = [];
		var opTGlobal : TGlobal = Vec4;
		if (numberOutputs >= 1) {
			args.push({ name: "r", type : TFloat });
			valueArgs.push(r.getVar());
			opTGlobal = ToFloat;
		}
		if (numberOutputs >= 2) {
			args.push({ name: "g", type : TFloat });
			valueArgs.push(g.getVar());
			opTGlobal = Vec2;
		}
		if (numberOutputs >= 3) {
			args.push({ name: "b", type : TFloat });
			valueArgs.push(b.getVar());
			opTGlobal = Vec3;
		}
		if (numberOutputs >= 4) {
			args.push({ name: "a", type : TFloat });
			valueArgs.push(a.getVar());
			opTGlobal = Vec4;
		}

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