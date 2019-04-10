package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Sampler")
@description("Get color from texture and UV")
@group("AAAAA")
class Sampler extends ShaderFunction {

	@input("texture") var texture = SType.Sampler;
	@input("uv") var uv = SType.Vec2;

	public function new() {
		super(Texture);
	}

	override public function computeOutputs() {
		addOutput("rgba", TVec(4, VFloat));
	}

}