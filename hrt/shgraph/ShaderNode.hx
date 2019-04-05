package hrt.shgraph;

import hide.Element;
using hxsl.Ast;

@:autoBuild(hrt.shgraph.ParseFieldsMacro.build())
@:keepSub
class ShaderNode {

	static public var current_id : Int = 0; // TODO : check concurrency

	public var id : Int = current_id++;

	static var availableVariables = [{
						parent: null,
						id: 0,
						kind: Global,
						name: "pixelColor",
						type: TVec(4, VFloat)
					}];

	var inputs : Map<String, NodeVar> = [];
	var outputs : Map<String, TVar> = [];
	public var outputCompiled : Map<String, Bool> = []; // todo: put with outputs variable

	public function setId(id : Int) {
		this.id = id;
		ShaderNode.current_id = id+1;
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

	public function createOutputs() : Void {}

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
		return {
			e: TVar(o),
			p: null,
			t: o.type
		};
	}

	public function build(key : String) : TExpr {
		throw "Not implemented";
	}

	public function checkTypeAndCompatibilyInput(key : String, type : ShaderType.SType) : Bool {
		var infoKey = getInputInfo(key);
		if (infoKey != null && !(ShaderType.checkConversion(type, infoKey))) {
			return false;
		}
		return checkValidityInput(key, type);
	}

	public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {
		return true;
	}

	public function getInputInfo(key : String) : ShaderType.SType {
		return null;
	}

	public function getOutputInfo(key : String) : ShaderType.SType {
		return null;
	}

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		for (f in fields) {
			Reflect.setField(this, f, Reflect.field(props, f));
		}
	}

	public function saveProperties() : Dynamic {
		var parameters = {};

		var fields = std.Type.getInstanceFields(std.Type.getClass(this));
		var metas = haxe.rtti.Meta.getFields(std.Type.getClass(this));

		for (f in fields) {
			var m = Reflect.field(metas, f);
			if (m == null) {
				continue;
			}
			if (Reflect.hasField(m, "prop")) {
				Reflect.setField(parameters, f, Reflect.getProperty(this, f));
			}
		}
		return parameters;
	}

	#if editor
	public function getPropertiesHTML(width : Float) : Array<Element> {
		return [];
	}

	static public var registeredNodes = new Map<String, Class<ShaderNode>>();

	static public function register(key : String, cl : Class<ShaderNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}
	#end

}