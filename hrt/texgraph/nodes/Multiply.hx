package hrt.texgraph.nodes;

class MultiplyShader extends h3d.shader.ScreenShader {
    static var SRC = {
		@param var tex1 : Sampler2D;
		@param var tex2 : Sampler2D;

        function fragment() {
			pixelColor = tex1.get(calculatedUV) * tex2.get(calculatedUV);
        }
    }
}

@name("Multiply")
@description("The output is the result of the inputs multiplied")
@width(80)
@group("Math")
class Multiply extends TexNode {
	var inputs = [
		{ name : "input1", type: h3d.mat.Texture },
		{ name : "input2", type: h3d.mat.Texture },
	];

	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var out = createTexture();

		var shader = new MultiplyShader();
		shader.tex1 = cast getInputData(vars, 0);
		shader.tex2 = cast getInputData(vars , 1);

		var pass = new h3d.pass.ScreenFx(shader);

		engine.pushTarget(out);
		pass.render();
		engine.popTarget();

		return [ out ];
	}
}