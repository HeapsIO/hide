package hrt.shgraph;

import Type as HaxeType;
using hxsl.Ast;

import h3d.scene.Mesh;

using Lambda;
using hrt.shgraph.Utils;
import hrt.shgraph.AstTools.*;
import hrt.shgraph.ShaderGraph;

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

typedef InputInfo = {name: String, type: SgType, ?def: ShaderDefInput};
typedef OutputInfo = {name: String, type: SgType};
typedef VariableDecl = {v: TVar, display: String, ?vertexOnly: Bool};
typedef AliasInfo = {?nameSearch: String, ?nameOverride : String, ?description : String, ?args : Array<Dynamic>, ?group: String};
@:autoBuild(hrt.shgraph.Macros.autoRegisterNode())
@:keepSub
@:keep
class ShaderNode {

	public var id : Int;
	public var showPreview : Bool = true;
	@prop public var nameOverride : String;


	public var defaults : Dynamic = {};

	//
	// New API =======================================================================================
	//
	public function getInputs() : Array<InputInfo> {
		return [];
	}

	public function getOutputs() : Array<OutputInfo> {
		return [];
	}

	public function generate(ctx: NodeGenContext) : Void {
		throw "generate is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
	}

	function getDef(name: String, def: Float) {
		var defaultValue = Reflect.getProperty(defaults, name);
		if (defaultValue != null) {
			def = Std.parseFloat(defaultValue) ?? def;
		}
		return def;
	}

	// Old API ======================================================================================

	public function getAliases(name: String, group: String, description: String) : Array<AliasInfo> {
		var cl = HaxeType.getClass(this);
		var meta = haxe.rtti.Meta.getType(cl);
		var aliases : Array<AliasInfo> = [];

		if (meta.alias != null) {
			for (a in meta.alias) {
				aliases.push({nameOverride: '$a'});
			}
		}
		return aliases;
	}

	static var availableVariables = [
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "_sg_out_color",
						type: Type.TVec(3, VFloat)
					},
					{
						parent: null,
						id: 0,
						kind: Global,
						name: "_sg_out_alpha",
						type: Type.TFloat
					},
				];


	public function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		throw "getShaderDef is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	public var connections : Array<ShaderGraph.Connection> = [];

	public var outputCompiled : Map<String, Bool> = []; // todo: put with outputs variable

	// TODO(ces) : caching

	public function getOutputs2(domain: ShaderGraph.Domain, ?inputTypes: Array<Type>) : Map<String, {v: TVar, index: Int}> {
		return [for (id => i in getOutputs()) i.name => {v: {id: 0, name: i.name, type: sgTypeToType(i.type), kind: Local}, index: id}];
	}

	public function getInputs2(domain: ShaderGraph.Domain) : Map<String, {v: TVar, ?def: hrt.shgraph.ShaderGraph.ShaderDefInput, index: Int}> {
		return [for (id => i in getInputs()) i.name => {v: {id: 0, name: i.name, type: sgTypeToType(i.type), kind: Local}, index: id}];
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
		showPreview = props.showPreview ?? true;
		nameOverride = props.nameOverride;

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

	final public function shouldShowPreview() : Bool {
		return showPreview && canHavePreview();
	}

	public function canHavePreview() : Bool {
		return true;
	}

	public function saveProperties() : Dynamic {
		var parameters : Dynamic = {};

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

		parameters.nameOverride = nameOverride;
		parameters.showPreview = showPreview;

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