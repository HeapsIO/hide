package hrt.sbsgraph.nodes;

class BnWSpotsNoiseShader extends h3d.shader.ScreenShader {
    static var SRC = {
		@param var tex : Sampler2D;
		@param var seed : Float;
		@param var scale : Float;

		function random(inVector : Vec2) : Float {
			return fract(sin(dot(inVector.xy, vec2(12.9898,78.233))) * 43758.5453123);
		}

		// 2D Noise based on Morgan McGuire @morgan3d
		// https://www.shadertoy.com/view/4dS3Wd
		function noise(inVector : Vec2) : Float {
			var i = floor(inVector);
			var f = fract(inVector);

			var a = random(i);
			var b = random(i + vec2(1.0, 0.0));
			var c = random(i + vec2(0.0, 1.0));
			var d = random(i + vec2(1.0, 1.0));

			var u = f*f*(3.0-2.0*f);

			return mix(a, b, u.x) +
					(c - a)* u.y * (1.0 - u.x) +
					(d - b) * u.x * u.y;
		}

        function fragment() {
			pixelColor = vec4(vec3(noise((uvToScreen(calculatedUV) + seed) * scale)) , 1.);
        }

    }
}

@name("BnW Spots Noise")
@description("Black and white spots noise texture")
@width(120)
@group("Texture generation")
class BnWSpotsNoise extends SubstanceNode {
	var inputs = [];
	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	@prop var seed : Float = 0;
	@prop var scale : Float = 1;

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var engine = h3d.Engine.getCurrent();
		var out = new h3d.mat.Texture(outputWidth, outputHeight, null, outputFormat);

		var shader = new BnWSpotsNoiseShader();
		shader.tex = out;
		shader.seed = seed;
		shader.scale = scale;

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
			<label>Scale</label>
			<input type="number" id="scale"/>
		</div>');

		var seedEl = el.find("#seed");
		seedEl.val(seed);
		seedEl.on("change", function(e) {
			this.seed = Std.parseFloat(seedEl.val());
			var substanceEditor = Std.downcast(editor.editor, hide.view.substanceeditor.SubstanceEditor);
			substanceEditor.generate();
		});

		var scaleEl = el.find("#scale");
		scaleEl.val(scale);
		scaleEl.on("change", function(e) {
			this.scale = Std.parseFloat(scaleEl.val());
			var substanceEditor = Std.downcast(editor.editor, hide.view.substanceeditor.SubstanceEditor);
			substanceEditor.generate();
		});

		return el;
	}
	#end
}