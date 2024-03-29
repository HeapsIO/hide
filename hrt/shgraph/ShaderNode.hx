package hrt.shgraph;

import Type as HaxeType;
using hxsl.Ast;

import h3d.scene.Mesh;

using Lambda;
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

@:allow(hrt.shgraph.ShaderGraph)
class NodeGenContext {
	// Pour les rares nodes qui ont besoin de differencier entre vertex et fragment
	public var domain : ShaderGraph.Domain;

	public function new(domain: ShaderGraph.Domain) {
		this.domain = domain;
	}

	// For general input/output of the shader graph. Allocate a new global var if name is not found,
	// else return the previously allocated variable and assert that v.type == type and devValue == v.defValue
	public function getGlobalInputVar(id: Variables.Global) : TVar {
		return getOrAllocateGlobalVar(id, true, false);
	}

	public function getGlobalOutputVar(id: Variables.Global) : TVar {
		return getOrAllocateGlobalVar(id, false, true);
	}

	function getOrAllocateGlobalVar(id: Variables.Global, ?isInput: Bool, ?isOutput: Bool) : TVar {
		var global = Variables.Globals[id];
		var def : ShaderGraph.ExternVarDef = globalVars.get(global.name);
		if (def == null) {
			var v : TVar = {id: hxsl.Tools.allocVarId(), name: global.name, type: global.type, kind: global.kind};
			def = {v: v, isInput: isInput, isOutput: isOutput, defValue: global.def};
			if (global.parent != null) {
				v.parent = getOrAllocateGlobalVar(global.parent, null, null);
			}
			globalVars.set(global.name, def);
		}
		def.isInput = isInput ?? def.isInput;
		def.isOutput = isOutput ?? def.isOutput;
		return def.v;
	}

	// Generate a preview block that displays the content of expr
	// in the preview box of the node. Expr must be a type that
	// can be casted a Vec3
	public function addPreview(expr: TExpr, outExpr: Array<{e: TExpr, ?outputId: Int}>) {
		if (!previewEnabled) return;
		var selector = makeVar(getGlobalInputVar(PreviewSelect));
		var outputColor = makeVar(getGlobalInputVar(PixelColor));

		var previewExpr = makeAssign(outputColor, convertToType(TVec(4, VFloat), expr));
		var ifExpr = makeIf(makeEq(selector, makeInt(currentPreviewId)), previewExpr);
		outExpr.push({e: ifExpr});
	}

	static function convertToType(targetType: hxsl.Ast.Type, sourceExpr: TExpr) : TExpr {
		var sourceType = sourceExpr.t;

		if (sourceType.equals(targetType))
			return sourceExpr;

		var sourceSize = switch (sourceType) {
			case TFloat: 1;
			case TVec(size, VFloat): size;
			default:
				throw "Unsupported source type " + sourceType;
		}

		var targetSize = switch (targetType) {
			case TFloat: 1;
			case TVec(size, VFloat): size;
			default:
				throw "Unsupported target type " + targetType;
		}

		var delta = targetSize - sourceSize;
		if (delta == 0)
			return sourceExpr;
		if (delta > 0) {
			var args = [];
			if (sourceSize == 1) {
				for (_ in 0...targetSize) {
					args.push(sourceExpr);
				}
			}
			else {

				args.push(sourceExpr);
				for (i in 0...delta) {
					// Set alpha to 1.0 by default on upcasts casts
					var value = i == delta - 1 ? 1.0 : 0.0;
					args.push({e : TConst(CFloat(value)), p: sourceExpr.p, t: TFloat});
				}
			}
			var global : TGlobal = switch (targetSize) {
				case 2: Vec2;
				case 3: Vec3;
				case 4: Vec4;
				default: throw "unreachable";
			}
			return {e: TCall({e: TGlobal(global), p: sourceExpr.p, t:targetType}, args), p: sourceExpr.p, t: targetType};
		}
		if (delta < 0) {
			var swizz : Array<hxsl.Ast.Component> = [X,Y,Z,W];
			swizz.resize(targetSize);
			return {e: TSwiz(sourceExpr, swizz), p: sourceExpr.p, t: targetType};
		}
		throw "unreachable";
	}

	// Could be done
	//public function getFunction(name: String, expr: TExpr) : T

	// Pour la generation des previews

	public var previewEnabled: Bool = true;
	var currentPreviewId: Int = -1;
	var globalVars: Map<String, ShaderGraph.ExternVarDef> = [];
}

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


	public function getInputs() : Array<{name: String, ?type: Type}> {
		return [];
	}

	public function getOutputs() : Array<{name: String, ?type: Type}> {
		return [];
	}

	public function generate(inputs: Array<TExpr>, ctx: NodeGenContext) : Array<{e: TExpr, ?outputId: Int}> {
		throw "generate is not defined for class " + std.Type.getClassName(std.Type.getClass(this));
		return [];
	}

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