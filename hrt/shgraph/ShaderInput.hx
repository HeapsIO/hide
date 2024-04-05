package hrt.shgraph;

using hxsl.Ast;

@name("Inputs")
@description("Shader inputs of Heaps, it's dynamic")
@group("Property")
@color("#0e8826")
class ShaderInput extends ShaderNode {
	@prop("Variable") public var variable : String = "pixelColor";

	public function new(variable = "pixelColor") {
		this.variable = variable;
	}

	var outputs : Array<ShaderNode.OutputInfo>;
	override function getOutputs() {
		if (outputs == null) {
			var global = availableInputs[variable].g;
			var info = Variables.Globals[global];
			outputs = [{name: "output", type: ShaderGraph.typeToSgType(info.type)}];
		}
		return outputs;
	}

	override function generate(ctx: NodeGenContext) {
		var input = ctx.getGlobalInput(availableInputs[variable].g);

		ctx.setOutput(0, input);
		ctx.addPreview(input);
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (key => input in hrt.shgraph.ShaderInput.availableInputs) {
			aliases.push({
				nameSearch : name + " - " + input.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}

	override function loadProperties(props:Dynamic) {
		super.loadProperties(props);
		var ivar = availableInputs.get(this.variable);
		if (ivar == null) {
			for (k => v in availableInputs) {
				variable = k;
				break;
			}
		}
	}

	public static var availableInputs : Map<String, {display: String, g: Variables.Global}> = [
		"pixelColor" => {display: "Pixel Color", g: PixelColor},
		"alpha" => {display: "Pixel Color", g: PixelColor},
		"calculatedUv" => {display: "UV", g: CalculatedUV},
		"relativePosition" => {display: "Position (Object Space)", g: RelativePosition},
		"transformedPosition" => {display: "Position (World Space)", g: TransformedPosition},
		"projectedPosition" => {display: "Position (View Space)", g: ProjectedPosition},
		"normal" => {display: "Normal (Object Space)", g: Normal},
		"transformedNormal" => {display: "Normal (World Space)", g: TransformedNormal},

		"depth" => {display: "Depth", g: Depth},
		"metalness" => {display: "Metalness", g: Metalness},
		"roughness" => {display: "Roughness", g: Roughness},
		"emissive" => {display: "Emissive", g: Emissive},
		"occlusion" => {display: "Occlusion", g: Occlusion},

		"uv" => {display: "Source UV", g: UV},
	];

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (variable == null) {
			variable = "position";
		}

		var input = element.children("select");
		var indexOption = 0;
		for (k => variable in availableInputs) {
			input.append(new hide.Element('<option value="${k}">${variable.display}</option>'));
		}
		input.val(variable);

		input.on("change", function(e) {
			variable = input.val();
			outputs = null;
		});

		elements.push(element);

		return elements;
	}
	#end

}