package hrt.sbsgraph.nodes;

class RGBASplitShader extends h3d.shader.ScreenShader {
    static var SRC = {
		@param var tex : Sampler2D;
		@const var channels : Int;

        function fragment() {
			switch( channels ) {
				case 0:
					pixelColor = vec4(tex.get(calculatedUV).rrr, 1.);
				case 1:
					pixelColor = vec4(tex.get(calculatedUV).ggg, 1.);
				case 2:
					pixelColor = vec4(tex.get(calculatedUV).bbb, 1.);
				case 3:
					pixelColor = vec4(tex.get(calculatedUV).aaa, 1.);
				default:
					pixelColor = vec4(0,0,0,0);
			}
        }
    }
}

@name("RGBA Split")
@description("Separate a RGBA image entry in 4 grayscale images")
@width(100)
@group("Channel")
class RGBASplit extends SubstanceNode {
	var inputs = [
		{ name : "RGBA", type: h3d.mat.Texture }
	];

	var outputs = [
		{ name : "R", type: h3d.mat.Texture },
		{ name : "G", type: h3d.mat.Texture },
		{ name : "B", type: h3d.mat.Texture },
		{ name : "A", type: h3d.mat.Texture }
	];

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();

		var r = createTexture();
		var g = createTexture();
		var b = createTexture();
		var a = createTexture();

		var texs = [ r, g, b, a];

		var shader = new RGBASplitShader();
		shader.tex = cast getInputData(vars, 0);

		var pass = new h3d.pass.ScreenFx(shader);
		for (idx => t in texs) {
			shader.channels = idx;
			engine.pushTarget(t);
			pass.render();
			engine.popTarget();
		}

		return texs;
	}
}