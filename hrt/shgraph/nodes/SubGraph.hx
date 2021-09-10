package hrt.shgraph.nodes;

using hxsl.Ast;

@name("SubGraph")
@description("Include a subgraph")
@width(250)
@alwaysshowinputs()
class SubGraph extends ShaderNode {

	@prop() public var pathShaderGraph : String;

	var inputsInfo : Map<String, ShaderNode.InputInfo>;
	var inputInfoKeys : Array<String> = [];
	var outputsInfo : Map<String, ShaderNode.OutputInfo>;
	var outputInfoKeys : Array<String> = [];
	var parameters : Array<ShaderGraph.Parameter> = [];
	var propertiesSubGraph : Map<Int, Dynamic>;

	public var subShaderGraph : ShaderGraph;

	public var varsSubGraph : Array<TVar> = [];

	public function loadGraphShader() {
		if (this.pathShaderGraph != null) {
			try {
				subShaderGraph = new ShaderGraph(pathShaderGraph);
			} catch (e : Dynamic) {
				trace("The shader does not exist.");
				return;
			}
			inputsInfo = new Map<String, ShaderNode.InputInfo>();
			inputInfoKeys = [];
			var paramInfoKeys = [];
			outputsInfo = new Map<String, ShaderNode.OutputInfo>();
			outputInfoKeys = [];
			parameters = [];
			propertiesSubGraph = new Map<Int, Dynamic>();
			var prefixSubGraph = "shgraph_" + id + "_";

			for (node in subShaderGraph.getNodes()) {
				switch (node.type.split(".").pop()) {
					case "ShaderParam": // params become inputs
						var shaderParam = Std.downcast(node.instance, ShaderParam);
						var paramName = subShaderGraph.getParameter(shaderParam.parameterId).name;
						var paramId = "param_" + shaderParam.parameterId;
						var paramInfo = inputsInfo.get(prefixSubGraph+paramId);
						var ids = [];
						if (paramInfo != null && paramInfo.ids != null)
							ids = paramInfo.ids;
						ids.push(node.id);
						if (!inputsInfo.exists(prefixSubGraph + paramId)) {
							paramInfoKeys.push(prefixSubGraph+paramId);
						}
						inputsInfo.set(prefixSubGraph+paramId, { name : paramName , type: ShaderType.getSType(shaderParam.variable.type), hasProperty: false, isRequired : false, ids : ids, index :  subShaderGraph.getParameter(shaderParam.parameterId).index});
					case "ShaderInput":
						var shaderInput = Std.downcast(node.instance, ShaderInput);
						var inputId = "input_" + shaderInput.variable.name;
						var inputInfo = inputsInfo.get(prefixSubGraph+inputId);
						var ids = [];
						if (inputInfo != null && inputInfo.ids != null)
							ids = inputInfo.ids;
						ids.push(node.id);
						if (!inputsInfo.exists(prefixSubGraph+inputId)) {
							inputInfoKeys.push(prefixSubGraph+inputId);
						}
						inputsInfo.set(prefixSubGraph+inputId, { name : "*" + shaderInput.variable.name , type: ShaderType.getSType(shaderInput.variable.type), hasProperty: false, isRequired : false, ids : ids });
					case "ShaderGlobalInput":
						var shaderInput = Std.downcast(node.instance, ShaderGlobalInput);
						var inputId = "globalInput_" + shaderInput.variable.name;
						var inputInfo = inputsInfo.get(prefixSubGraph+inputId);
						var ids = [];
						if (inputInfo != null && inputInfo.ids != null)
							ids = inputInfo.ids;
						ids.push(node.id);
						if (!inputsInfo.exists(prefixSubGraph+inputId)) {
							inputInfoKeys.push(prefixSubGraph+inputId);
						}
						inputsInfo.set(prefixSubGraph+inputId, { name : "*" + shaderInput.variable.name , type: ShaderType.getSType(shaderInput.variable.type), hasProperty: false, isRequired : false, ids : ids });
					case "ShaderCameraInput":
						var shaderInput = Std.downcast(node.instance, ShaderCameraInput);
						var inputId = "cameraInput_" + shaderInput.variable.name;
						var inputInfo = inputsInfo.get(prefixSubGraph+inputId);
						var ids = [];
						if (inputInfo != null && inputInfo.ids != null)
							ids = inputInfo.ids;
						ids.push(node.id);
						if (!inputsInfo.exists(prefixSubGraph+inputId)) {
							inputInfoKeys.push(prefixSubGraph+inputId);
						}
						inputsInfo.set(prefixSubGraph+inputId, { name : "*" + shaderInput.variable.name , type: ShaderType.getSType(shaderInput.variable.type), hasProperty: false, isRequired : false, ids : ids });
					case "ShaderOutput":
						var shaderOutput = Std.downcast(node.instance, ShaderOutput);
						var prefix = shaderOutput.variable.kind == Local ? "" : "*";

						outputsInfo.set(prefixSubGraph+node.id, { name : prefix + shaderOutput.variable.name , type: ShaderType.getSType(shaderOutput.variable.type), id : node.id });
						outputInfoKeys.push(prefixSubGraph+node.id);

						addOutput(prefixSubGraph+node.id, shaderOutput.variable.type);
					default:
						var shaderConst = Std.downcast(node.instance, ShaderConst);
						if (shaderConst != null) { // input static become properties
							if (shaderConst.name.length == 0) continue;
							if (Std.is(shaderConst, BoolConst)) {
								parameters.push({ name : shaderConst.name, type : TBool, defaultValue : null, id : shaderConst.id, index : parameters.length });
							} else if (Std.is(shaderConst, FloatConst)) {
								parameters.push({ name : shaderConst.name, type : TFloat, defaultValue : null, id : shaderConst.id, index : parameters.length });
							} else if (Std.is(shaderConst, Color)) {
								parameters.push({ name : shaderConst.name, type : TVec(4, VFloat), defaultValue : null, id : shaderConst.id, index : parameters.length });
							}
						}
				}
			}
			paramInfoKeys.sort((x,y) -> Reflect.compare(inputsInfo[x].index, inputsInfo[y].index));
			inputInfoKeys = paramInfoKeys.concat(inputInfoKeys);
		}
	}

	override public function build(key : String) : TExpr {

		for (inputKey in inputInfoKeys) {
			var inputInfo = inputsInfo.get(inputKey);
			var inputTVar = getInput(inputKey);

			if (inputTVar != null) {
				for (id in inputInfo.ids) {
					var nodeToReplace = subShaderGraph.getNodes().get(id);
					for (i in 0...nodeToReplace.outputs.length) {
						var inputNode = nodeToReplace.outputs[i];

						for (inputKey in inputNode.instance.getInputsKey()) {
							var input = inputNode.instance.getInput(inputKey);
							if (input.node == nodeToReplace.instance) {
								inputNode.instance.setInput(inputKey, inputTVar);
							}
						}
					}
				}
			}
		}

		for (p in parameters) {
			if (p.defaultValue != null) {
				var node = subShaderGraph.getNode(p.id);
				switch (p.type) {
					case TBool:
						var boolConst = Std.downcast(node.instance, BoolConst);
						@:privateAccess boolConst.value = p.defaultValue;
					case TVec(4, VFloat):
						var colorConst = Std.downcast(node.instance, Color);
						@:privateAccess {
							colorConst.r = p.defaultValue.x;
							colorConst.g = p.defaultValue.y;
							colorConst.b = p.defaultValue.z;
							colorConst.a = p.defaultValue.w;
						}
					case TFloat:
						var floatConst = Std.downcast(node.instance, FloatConst);
						@:privateAccess floatConst.value = p.defaultValue;
					default:
				}
			}
		}

		var shaderDef;
		try {
			shaderDef = subShaderGraph.generateShader(null, id);
		} catch (e : ShaderException) {
			throw ShaderException.t(e.msg, id);
		}
		if (shaderDef.funs.length > 1) {
			throw ShaderException.t("The sub shader is vertex and fragment.", id);
		}
		varsSubGraph = shaderDef.vars;
		var arrayExpr : Array<TExpr> = [];
		switch (shaderDef.funs[0].expr.e) {
			case TBlock(block):
				arrayExpr = block;
			default:

		}

		for (outputKey in outputInfoKeys) {
			var outputInfo = outputsInfo.get(outputKey);
			var outputTVar = getOutput(outputKey);
			if (outputTVar != null) {
				arrayExpr.push({
					p : null,
					t : outputTVar.type,
					e : TBinop(OpAssign, {
							e: TVar(outputTVar),
							p: null,
							t: outputTVar.type
						}, subShaderGraph.getNodes().get(outputInfo.id).instance.getInput("input").getVar(outputTVar.type))
				});
			}
		}

		return {
				p : null,
				t : TVoid,
				e : TBlock(arrayExpr)
			};
	}

	override public function getInputInfo(key : String) : ShaderNode.InputInfo {
		return inputsInfo.get(key);
	}

	override public function getInputInfoKeys() : Array<String> {
		return inputInfoKeys;
	}

	override public function getOutputInfo(key : String) : ShaderNode.OutputInfo {
		return outputsInfo.get(key);
	}

	override public function getOutputInfoKeys() : Array<String> {
		return outputInfoKeys;
	}

	override public function loadProperties(props : Dynamic) {
		this.pathShaderGraph = Reflect.field(props, "pathShaderGraph");
		loadGraphShader();

		var parametersValues : Array<hrt.shgraph.ShaderGraph.Parameter> = Reflect.field(props, "parametersValues");
		if (parametersValues == null) return;
		var index = 0;
		for (p in this.parameters) {
			if (parametersValues.length <= index) break;
			if (p.id != parametersValues[index].id) {
				continue;
			}
			p.defaultValue = parametersValues[index].defaultValue;
			index++;
		}
	}

	override public function saveProperties() : Dynamic {

		var parametersValues = [];
		for (p in this.parameters) {
			if (p.defaultValue != null) {
				parametersValues.push({id: p.id, defaultValue : p.defaultValue});
			}
		}

		var properties = {
			pathShaderGraph: this.pathShaderGraph,
			parametersValues : parametersValues
		};

		return properties;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		for (p in parameters) {
			var element = new hide.Element('<div class="propertySubShader" style="width: 200px;"></div>');
			element.on("mousedown", function(e) {
				e.stopPropagation();
			});
			switch (p.type) {
				case TBool:
					new hide.Element('<span>${p.name}</span>').appendTo(element);
					var inputBool = new hide.Element('<input type="checkbox" id="value" />').appendTo(element);
					inputBool.on("change", function(e) {
						p.defaultValue = (inputBool.is(":checked")) ? true : false;
					});
					if (p.defaultValue) {
						inputBool.prop("checked", true);
					}
					element.css("height", 20);
				case TFloat:
					new hide.Element('<span>${p.name}</span>').appendTo(element);
					var parentRange = new hide.Element('<input type="range" min="-1" max="1" value="" />').appendTo(element);
					var range = new hide.comp.Range(null, parentRange);
					var rangeInput = @:privateAccess range.f;
					rangeInput.on("mousedown", function(e) {
						e.stopPropagation();
					});
					rangeInput.on("mouseup", function(e) {
						e.stopPropagation();
					});
					parentRange.parent().css("width", 50);
					if (p.defaultValue != null) {
						range.value = p.defaultValue;
					}
					range.onChange = function(moving) {
						p.defaultValue = range.value;
					};
					element.css("height", 40);
				case TVec(4, VFloat):
					new hide.Element('<span>${p.name}</span>').appendTo(element);
					var inputColor = new hide.comp.ColorPicker(true, element);

					if (p.defaultValue != null) {
						var start = h3d.Vector.fromArray([p.defaultValue.x, p.defaultValue.y, p.defaultValue.z, p.defaultValue.w]);
						inputColor.value = start.toColor();
					}

					inputColor.onChange = function(move) {
						var vec = h3d.Vector.fromColor(inputColor.value);
						p.defaultValue = vec;
					};
					element.css("height", 25);
				default:

			}
			elements.push(element);
		}


		return elements;
	}
	#end

}