package hrt.sbsgraph.nodes;

class RGBAMergeShader extends h3d.shader.ScreenShader {
    static var SRC = {
		@param var r : Sampler2D;
		@param var g : Sampler2D;
		@param var b : Sampler2D;
		@param var a : Sampler2D;

        function fragment() {
			pixelColor.r = r.get(calculatedUV).r;
			pixelColor.g = g.get(calculatedUV).r;
			pixelColor.b = b.get(calculatedUV).r;
			pixelColor.a = a.get(calculatedUV).r;
        }
    }
}

@name("RGBA Merge")
@description("Merge 4 grayscale images entry in a RGBA image")
@width(100)
@group("Channel")
class RGBAMerge extends SubstanceNode {
	var inputs = [
		{ name : "R", type: h3d.mat.Texture },
		{ name : "G", type: h3d.mat.Texture },
		{ name : "B", type: h3d.mat.Texture },
		{ name : "A", type: h3d.mat.Texture }
	];
	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var out = createTexture();

		var shader = new RGBAMergeShader();
		shader.r = cast getInputData(vars, 0);
		shader.g = cast getInputData(vars , 1);
		shader.b = cast getInputData(vars , 2);
		shader.a = cast getInputData(vars , 3);

		var pass = new h3d.pass.ScreenFx(shader);

		engine.pushTarget(out);
		pass.render();
		engine.popTarget();

		return [ out ];
	}
}