package hrt.shgraph;

@name("Custom Global")
@description("Custom shader global input")
@group("Input")
@color("#0e8826")
class ShaderCustomGlobal extends ShaderNode {

	@prop() public var name : String = "";
	@prop() public var type : String = "vec4";

	static var types : Map<String, {display: String, type: SgType}> = [
		// Don't reorder the indices, i
		"vec4" => {display: "Vec4", type: SgFloat(4)},
		"vec3" => {display: "Vec3", type: SgFloat(3)},
		"vec2" => {display: "Vec2", type: SgFloat(2)},
		"float" => {display: "Float",type: SgFloat(1)},
		"int" => {display: "Int",type: SgInt},
		"bool" => {display: "Bool",type: SgBool},
		"sampler" => {display: "Sampler", type: SgSampler},
	];

	var outputs : Array<ShaderNode.OutputInfo>;
	override function getOutputs() {
		if (outputs == null) {
			outputs = [{name: "output", type: types.get(type)?.type ?? SgFloat(4)}];
		}
		return outputs;
	}

	override function generate(ctx:NodeGenContext) {
		var tvar : TVar = {
			name: name,
			id: 0,
			qualifiers: [],
			parent: null,
			kind: Global,
			type: ShaderGraph.sgTypeToType(types.get(type)?.type ?? SgFloat(4)),
		}
		var v = ctx.getGlobalTVar(tvar);
		ctx.setOutput(0, v);
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);



		// name edit
		{
			var element = new hide.Element('<div class="sg-const-name" style="width: ${width-16}px; height: 20px"></div>');

			var editBtn = new hide.Element('<fancy-button class="quieter compact"><div class="ico ico-pencil"></div></fancy-button>');

			element.append(editBtn);

			var input = new hide.Element('<input class="sg-const-name" type="text" id="value" placeholder="Name" value="${this.name}" autocomplete="off" />');

			element.append(input);

			input.on("keydown", function(e) {
				e.stopPropagation();
			});
			input.on("change", function(e) {
				this.name = input.val();
				requestRecompile();
			});

			editBtn.on("click", function(e) {
				input.focus();
				input.select();
			});

			elements.push(element);
		}

		{
			var element =  new hide.Element('<div style="width: 80px; height: 30px;"><select id="index"></select></div>');
			var input = element.find("select");
			for (indexOption => c in types) {
				var name = c.display;
				input.append(new hide.Element('<option value="${indexOption}">${name}</option>'));
				if (this.type == indexOption) {
					input.val(indexOption);
				}
			}

			input.on("change", function(e) {
				var value = input.val();
				outputs = null;
				this.type = value;
				requestRecompile();
			});

			elements.push(element);
		}

		return elements;
	}
	#end
}