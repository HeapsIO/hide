package hrt.sbsgraph.nodes;

class WhiteNoiseShader extends h3d.shader.ScreenShader {
    static var SRC = {
		@param var tex : Sampler2D;
		@param var seed : Float;

		function random(inVector : Vec2) : Float {
			return fract(sin(dot(inVector.xy, vec2(12.9898,78.233))) * 43758.5453123);
		}

        function fragment() {
			pixelColor = vec4(vec3(random(uvToScreen(calculatedUV) + seed)) , 1.);
        }

    }
}

@name("White Noise")
@description("White noise texture")
@width(100)
@group("Texture generation")
class WhiteNoise extends SubstanceNode {
	var inputs = [];
	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	@prop var seed : Float = 0;

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var out = new h3d.mat.Texture(outputWidth, outputHeight, null, outputFormat);

		var shader = new WhiteNoiseShader();
		shader.tex = out;
		shader.seed = seed;

		var pass = new h3d.pass.ScreenFx(shader);

		engine.pushTarget(out);
		pass.render();
		engine.popTarget();

		return [ out ];
	}

	#if editor
	override function getSpecificParametersHTML() {
		var el = new hide.Element('
		<div class="fields">
			<label>Seed</label>
			<input type="number" id="seed"/>
		</div>');

		var seedEl = el.find("#seed");
		seedEl.val(seed);
		seedEl.on("change", function(e) {
			this.seed = Std.parseFloat(seedEl.val());
			var substanceEditor = Std.downcast(editor.editor, hide.view.substanceeditor.SubstanceEditor);
			substanceEditor.generate();
		});

		return el;
	}
	#end
}