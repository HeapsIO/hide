package hrt.texgraph.nodes;

@name("Outputs")
@description("Parameters outputs")
@width(80)
@group("Output")
@color("#A90707")
class TexOutput extends TexNode {
	@prop public var label : String = "base-color";

	var inputs = [
		{ name : "input", type: h3d.mat.Texture }
	];

	var outputs = [];

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		var out = cast getInputData(vars, 0);
		return [ out ];
	}

	#if editor
	override function getSpecificParametersHTML() {
		var el = new hide.Element('
		<div class="fields">
			<label>Label</label>
			<input id="label"/>
		</div>');

		var labelEl = el.find("#label");
		labelEl.val(label);
		labelEl.on("change", function(e) {
			this.label = labelEl.val();
			var substanceEditor = Std.downcast(editor.editor, hide.view.textureeditor.TextureEditor);
			substanceEditor.generate();
		});

		return el;
	}
	#end
}