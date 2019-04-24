package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Sampler")
@description("Get color from texture and UV")
@group("Input")
class Sampler extends ShaderFunction {

	@input("texture") var texture = SType.Sampler;
	@input("uv") var uv = SType.Vec2;

	public function new() {
		super(Texture);
	}

	override public function computeOutputs() {
		addOutput("output", TVec(4, VFloat));
	}

}