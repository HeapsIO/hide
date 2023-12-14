package hrt.shgraph;

using hxsl.Ast;

import h3d.scene.Mesh;

using Lambda;

class AlphaPreview extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		var screenUV : Vec2;
		function fragment() {
			var gray_lt = vec3(1.0);
			var gray_dk = vec3(229.0) / 255.0;
			var scale = 16.0;
			var localUV = screenUV * scale;

			var checkboard = floor(localUV.x) + floor(localUV.y);
			checkboard = fract(checkboard * 0.5) * 2.0;
			var alphaColor = vec3(checkboard * (gray_dk - gray_lt) + gray_lt);

			pixelColor.rgb = mix(pixelColor.rgb, alphaColor, 1.0 - pixelColor.a);
			pixelColor.a = 1.0;
		}
	}
}

typedef VariableDecl = {v: TVar, display: String};

@:autoBuild(hrt.shgraph.Macros.autoRegisterNode())
@:keepSub
class ShaderNode {

	public var id : Int;

	public var defaults : Dynamic = {};

	static var availableVariables = [
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "_sg_out_color",
						type: TVec(3, VFloat)
					},
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "_sg_out_alpha",
						type: TFloat
					},
				];


	public function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		throw "getShaderDef is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	public var connections : Map<String, ShaderGraph.Connection> = [];

	public var outputCompiled : Map<String, Bool> = []; // todo: put with outputs variable

	// TODO(ces) : caching
	public function getOutputs2(domain: ShaderGraph.Domain, ?inputTypes: Array<Type>) : Map<String, {v: TVar, index: Int}> {
		var def = getShaderDef(domain, () -> 0);
		var map : Map<String, {v: TVar, index: Int}> = [];
		var count = 0;
		for (i => tvar in def.outVars) {
			if (!tvar.internal) {
				map.set(tvar.v.name, {v: tvar.v, index: count});
				count += 1;
			}
		}
		return map;
	}

	// TODO(ces) : caching
	public function getInputs2(domain: ShaderGraph.Domain) : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput, index: Int}> {
		var def = getShaderDef(domain, () -> 0);
		var map : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput, index: Int}> = [];
		var count = 0;
		for (tvar in def.inVars) {
			if (!tvar.internal) {
				map.set(tvar.v.name, {v: tvar.v, def: tvar.defVal, index: count});
				count += 1;
			}
		}
		return map;
	}


	public function setId(id : Int) {
		this.id = id;
	}


	function addOutput(key : String, t : Type) {
		/*outputs.set(key, { parent: null,
			id: 0,
			kind: Local,
			name: "output_" + id + "_" + key,
			type: t
		});*/
	}

	function removeOutput(key : String) {
		/*outputs.remove(key);*/
	}

	function addOutputTvar(tVar : TVar) {
		/*outputs.set(tVar.name, tVar);*/
	}

	public function computeOutputs() : Void {}

	// public function getOutput(key : String) : TVar {
	// 	return outputs.get(key);
	// }

	// public function getOutputType(key : String) : Type {
	// 	var output = getOutput(key);
	// 	if (output == null)
	// 		return null;
	// 	return output.type;
	// }

	// public function getOutputTExpr(key : String) : TExpr {
	// 	var o = getOutput(key);
	// 	if (o == null)
	// 		return null;
	// 	return {
	// 		e: TVar(o),
	// 		p: null,
	// 		t: o.type
	// 	};
	// }

	public function build(key : String) : TExpr {
		throw "Build function not implemented";
	}

	public function checkTypeAndCompatibilyInput(key : String, type : hxsl.Ast.Type) : Bool {
		/*var infoKey = getInputs2()[key].type;
		if (infoKey != null && !(ShaderType.checkConversion(type, infoKey))) {
			return false;
		}
		return checkValidityInput(key, type);*/
		return true;
	}

	public function checkValidityInput(key : String, type : hxsl.Ast.Type) : Bool {
		return true;
	}



	// public function getOutputInfoKeys() : Array<String> {
	// 	return [];
	// }

	// public function getOutputInfo(key : String) : OutputInfo {
	// 	return null;
	// }

	public function loadProperties(props : Dynamic) {
		var fields = Reflect.fields(props);
		for (f in fields) {
			if (f == "defaults") {
				defaults = Reflect.field(props, f);
			}
			else {
				if (Reflect.hasField(this, f)) {
					Reflect.setField(this, f, Reflect.field(props, f));
				}
			}
		}
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

		if (Reflect.fields(defaults).length > 0) {
			Reflect.setField(parameters, "defaults", defaults);
		}

		return parameters;
	}

	#if editor
	final public function getHTML(width: Float, config: hide.Config) {
		var props = getPropertiesHTML(width);
		return props;
	}

	function getPropertiesHTML(width : Float) : Array<hide.Element> {
		return [];
	}

	static public var registeredNodes = new Map<String, Class<ShaderNode>>();

	static public function register(key : String, cl : Class<ShaderNode>) : Bool {
		registeredNodes.set(key, cl);
		return true;
	}
	#end

}