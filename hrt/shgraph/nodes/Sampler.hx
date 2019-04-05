package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

/*
@name("Sampler")
@description("Get color from texture and UV")
@group("AAAAA")
*/
class Sampler extends ShaderNode {

	@input("u") var u = SType.Float;
	@input("v") var v = SType.Float;

	@output("rgba") var rgba = SType.Vec4;

	var components = [X, Y, Z, W];
	var componentsString = ["r", "g", "b", "a"];

	override public function createOutputs() {
		addOutput("rgba", TVec(4, VFloat));
	}

	override public function build(key : String) : TExpr {
		return null;
	}

}