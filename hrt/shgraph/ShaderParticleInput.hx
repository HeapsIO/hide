package hrt.shgraph;

using hxsl.Ast;

@name("Particle Inputs")
@description("Particle specific shader inputs")
@group("Input")
@color("#0e8826")
class ShaderParticleInputs extends ShaderNode {
	@prop("Variable") public var variable : String = "life";

	public function new(variable = "life") {
		this.variable = variable;
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = super.getAliases(name, group, description);
		for (key => input in hrt.shgraph.ShaderParticleInputs.availableInputs) {
			aliases.push({
				nameSearch : name + " - " + input.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}

	override function getOutputs() {
		static var outputs : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgFloat(1)}];
		return outputs;
	}

	override function generate(ctx:NodeGenContext) {
		var global = availableInputs[variable].g;
		var expr = ctx.getGlobalInput(global);
		ctx.setOutput(0, expr);
		ctx.addPreview(expr);
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
		"life" => {display: "Particle Life", g: ParticleLife},
		"lifetime" => {display: "Particle Life Time", g: ParticleLifeTime},
		"random" => {display: "Particle Random", g: ParticleRandom},
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
		});

		elements.push(element);

		return elements;
	}
	#end

}