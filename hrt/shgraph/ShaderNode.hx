package hrt.shgraph;

using hxsl.Ast;

typedef InputInfo = { name : String, type : ShaderType.SType, hasProperty : Bool, isRequired : Bool, ?ids : Array<Int>, ?index : Int };
typedef OutputInfo = { name : String, type : ShaderType.SType, ?id : Int };

@:autoBuild(hrt.shgraph.ParseFieldsMacro.build())
@:keepSub
class ShaderNode {

	public var id : Int;

	static var availableVariables = [
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "pixelColor",
						type: TVec(4, VFloat)
					}];


	public function getShaderDef() : ShaderGraph.ShaderNodeDef {
		throw "Shouln't be called";
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	var inputs : Map<String, NodeVar> = [];
	var outputs : Map<String, TVar> = [];

	public var inputs2 : Map<String, ShaderGraph.Connection> = [];

	public var outputCompiled : Map<String, Bool> = []; // todo: put with outputs variable

	public function setId(id : Int) {
		this.id = id;
	}

	public function setInput(key : String, s : NodeVar) {
		if (s == null)
				inputs.remove(key);
		else
			inputs.set(key, s);
	}

	public function getInput(key : String) : NodeVar {
		return inputs.get(key);
	}

	public function getInputsKey() {
		return [for (k in inputs.keys()) k ];
	}

	public function getInputs() {
		return [for (k in inputs.keys()) inputs.get(k) ];
	}

	public function hasInputs() {
		return inputs.keys().hasNext();
	}

	function addOutput(key : String, t : Type) {
		outputs.set(key, { parent: null,
			id: 0,
			kind: Local,
			name: "output_" + id + "_" + key,
			type: t
		});
	}

	function removeOutput(key : String) {
		outputs.remove(key);
	}

	function addOutputTvar(tVar : TVar) {
		outputs.set(tVar.name, tVar);
	}

	public function computeOutputs() : Void {}

	public function getOutput(key : String) : TVar {
		return outputs.get(key);
	}

	public function getOutputType(key : String) : Type {
		var output = getOutput(key);
		if (output == null)
			return null;
		return output.type;
	}

	public function getOutputTExpr(key : String) : TExpr {
		var o = getOutput(key);
		if (o == null)
			return null;
		return {
			e: TVar(o),
			p: null,
			t: o.type
		};
	}

	public function build(key : String) : TExpr {
		throw "Build function not implemented";
	}

	public function checkTypeAndCompatibilyInput(key : String, type : ShaderType.SType) : Bool {
		var infoKey = getInputInfo(key).type;
		if (infoKey != null && !(ShaderType.checkConversion(type, infoKey))) {
			return false;
		}
		return checkValidityInput(key, type);
	}

	public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {
		return true;
	}

	public function getInputInfoKeys() : Array<String> {
		return [];
	}

	public function getInputInfo(key : String) : InputInfo {
		return null;
	}

	public function getOutputInfoKeys() : Array<String> {
		return [];
	}

	public function getOutputInfo(key : String) : OutputInfo {
		return null;
	}

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		for (f in fields) {
			Reflect.setField(this, f, Reflect.field(props, f));
		}
	}

	public function savePropertiesNode() : Dynamic {
		var parameters = saveProperties();

		var thisClass = std.Type.getClass(this);
		var fields = std.Type.getInstanceFields(thisClass);
		var metas = haxe.rtti.Meta.getFields(thisClass);
		var metaSuperClass = haxe.rtti.Meta.getFields(std.Type.getSuperClass(thisClass));

		for (f in fields) {
			var m = Reflect.field(metas, f);
			if (m == null) {
				m = Reflect.field(metaSuperClass, f);
				if (m == null)
					continue;
			}

			if (Reflect.hasField(m, "prop")) {
				var metaData : Array<String> = Reflect.field(m, "prop");
				if (metaData != null && metaData.length >= 1 && metaData[0] == "macro") {
					Reflect.setField(parameters, f, Reflect.getProperty(this, f));
				}
			}
		}

		return parameters;
	}

	public function saveProperties() : Dynamic {
		var parameters = {};

		var thisClass = std.Type.getClass(this);
		var fields = std.Type.getInstanceFields(thisClass);
		var metas = haxe.rtti.Meta.getFields(thisClass);
		var metaSuperClass = haxe.rtti.Meta.getFields(std.Type.getSuperClass(thisClass));

		for (f in fields) {
			var m = Reflect.field(metas, f);
			if (m == null) {
				m = Reflect.field(metaSuperClass, f);
				if (m == null)
					continue;
			}
			if (Reflect.hasField(m, "prop")) {
				var metaData : Array<String> = Reflect.field(m, "prop");
				if (metaData == null || metaData.length == 0 || metaData[0] != "macro") {
					Reflect.setField(parameters, f, Reflect.getProperty(this, f));
				}
			}
		}
		return parameters;
	}

	#if editor
	public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		return [];
	}

	static public var registeredNodes = new Map<String, Class<ShaderNode>>();

	static public function register(key : String, cl : Class<ShaderNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}
	#end

}