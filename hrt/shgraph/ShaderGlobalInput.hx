package hrt.shgraph;

using hxsl.Ast;

@name("Global")
@description("Global Inputs")
@group("Input")
@color("#0e8826")
class ShaderGlobalInput extends ShaderNode {

	@prop("Variable") public var variableIdx : Int = 0;

	static public var globalInputs : Array<{display: String, g: Variables.Global}> =
		[
			{display: "Time", g: Time},
			{display: "Pixel Size", g: PixelSize},
			{display: "Camera Global Position", g: CameraPosition},
		];

	public function new(idx: Null<Int>) {
		variableIdx = idx ?? variableIdx;
	}

	var outputs : Array<ShaderNode.OutputInfo>;
	override public function getOutputs() {
		if (outputs == null) {
			var global = globalInputs[variableIdx].g;
			var info = Variables.Globals[global];
			outputs = [{name: "output", type: ShaderGraph.typeToSgType(info.type)}];
		}
		return outputs;
	}

	override function generate(ctx: NodeGenContext) {
		var input = ctx.getGlobalInput(globalInputs[variableIdx].g);

		ctx.setOutput(0, input);
		ctx.addPreview(input);
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (i => input in globalInputs) {
			aliases.push({
				nameSearch : name + " - " + input.display,
				group: group,
				description: description,
				args: [i],
			});
		}
		return aliases;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = [];
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		var input = element.children("select");
		for (indexOption => c in ShaderGlobalInput.globalInputs) {
			var name = c.display;
			input.append(new hide.Element('<option value="${indexOption}">${name}</option>'));
			if (this.variableIdx == indexOption) {
				input.val(indexOption);
			}
		}
		input.on("change", function(e) {
			var value = input.val();
			outputs = null;
			this.variableIdx = value;
			requestRecompile();
		});

		elements.push(element);

		return elements;
	}
	#end

}