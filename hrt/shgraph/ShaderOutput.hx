
package hrt.shgraph;

using hxsl.Ast;

@name("Outputs")
@description("Parameters outputs, it's dynamic")
@group("Output")
@color("#A90707")
class ShaderOutput extends ShaderNode {

	@prop("Variable") public var variable : String = "_sg_out_color";

	var components = [X, Y, Z, W];

	public var generatePreview = false;

	public function new(variable = "_sg_out_color") {
		this.variable = variable;
	}

	var inputs : Array<ShaderNode.InputInfo>;
	override public function getInputs() : Array<ShaderNode.InputInfo> {
		if (inputs == null) {
			var global = availableOutputs[variable].g;
			var info = Variables.Globals[global];
			inputs = [{name: "input", type: ShaderGraph.typeToSgType(info.type)}];
		}
		return inputs;
	}

	override public function generate(ctx: NodeGenContext) {
		var out = ctx.getInput(0, SgHxslVar.ShaderDefInput.Const(getDef("input", 0.0)));
		ctx.setGlobalOutput(availableOutputs[variable].g, out);
		ctx.addPreview(out);
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (key => output in hrt.shgraph.ShaderOutput.availableOutputs) {
			aliases.push({
				nameSearch : name + " - " + output.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}

	public static var availableOutputs : Map<String, {display: String, g: Variables.Global}> = [
		"_sg_out_color" => {display: "Pixel Color", g:SGPixelColor},
		"_sg_out_alpha" => {display: "Alpha", g:SGPixelAlpha},
		"relativePosition" => {display: "Position (Object Space)", g:RelativePosition},
		"transformedPosition" => {display: "Position (World Space)", g:TransformedPosition},
		"projectedPosition" => {display: "Position (View Space)", g:ProjectedPosition},
		"calculatedUV" => { display: "UV", g:CalculatedUV},
		"transformedNormal" => { display: "Normal (World Space)", g:TransformedNormal},

		"metalness" => {display: "Metalness", g: Metalness},
		"roughness" => {display: "Roughness", g: Roughness},
		"emissive" => {display: "Emissive", g: Emissive},
		"occlusion" => {display: "Occlusion", g: Occlusion},
	];

	override function loadProperties(props:Dynamic) {
		super.loadProperties(props);
		var ivar = availableOutputs.get(this.variable);
		if (ivar == null) {
			for (k => v in availableOutputs) {
				variable = k;
				break;
			}
		}
	}


	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 110px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (this.variable == null) {
			variable = "__sg_out_color";
		}
		var input = element.children("select");
		var selectingDefault = false;
		for (k => c in ShaderOutput.availableOutputs) {
			input.append(new hide.Element('<option value="${k}">${c.display}</option>'));
		}
		input.val(variable);

		input.on("change", function(e) {
			variable = input.val();
			inputs = null;
			requestRecompile();
		});

		elements.push(element);

		return elements;
	}
	#end
}