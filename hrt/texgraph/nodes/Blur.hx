package hrt.texgraph.nodes;

@name("Blur")
@description("Blur texture")
@width(100)
@group("Math")
class Blur extends TexNode {
	var inputs = [
		{ name : "input1", type: h3d.mat.Texture }
	];
	var outputs = [
		{ name : "output", type: h3d.mat.Texture }
	];

	@prop var radius : Float = 10;

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var out = createTexture();

		var blurPass = new h3d.pass.Blur(radius);
		blurPass.apply(ctx, cast getInputData(vars, 0), out);

		return [ out ];
	}

	#if editor
	override function getSpecificParametersHTML() {
		var el = new hide.Element('
		<div class="fields">
			<label>Radius</label>
			<input type="range" id="radius"/>
		</div>');

		var radiusEl = el.find("#radius");
		radiusEl.val(radius);
		radiusEl.on("mousemove", function(e) {
			this.radius = Std.parseFloat(radiusEl.val());
			var substanceEditor = Std.downcast(editor.editor, hide.view.textureeditor.TextureEditor);
			substanceEditor.generate();
		});

		return el;
	}
	#end
}