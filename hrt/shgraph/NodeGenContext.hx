package hrt.shgraph;

using hxsl.Ast;
using Lambda;
using hrt.shgraph.Utils;
import hrt.shgraph.AstTools.*;
import hrt.shgraph.ShaderGraph;

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

	public function getGlobalParam(name: String, type: Type, ?defVal: Dynamic) : TVar {
		return globalVars.getOrPut(name, {v: {id: hxsl.Tools.allocVarId(), name: name, type: type, kind: Param}, isInput: true, isOutput: false, defValue:defVal}).v;
	}

	function getOrAllocateGlobalVar(id: Variables.Global, ?isInput: Bool, ?isOutput: Bool) : TVar {
		var global = Variables.Globals[id];
		var def : ShaderGraph.ExternVarDef = globalVars.get(global.name);
		if (def == null) {
			var v : TVar = {id: hxsl.Tools.allocVarId(), name: global.name, type: global.type, kind: global.kind};
			def = {v: v, isInput: isInput, isOutput: isOutput, defValue: global.def};
			if (global.parent != null) {
				var p = Variables.Globals[global.parent];
				v.parent = globalVars.getOrPut(p.name, {v : {id : hxsl.Tools.allocVarId(), name: p.name, type: TStruct([]), kind: p.kind}, isInput: false, isOutput: false, defValue: null}).v;
				switch(v.parent.type) {
					case TStruct(arr):
						arr.push(v);
					default: throw "parent must be a TStruct";
				}
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
	public function addPreview(expr: TExpr) {
		if (!previewEnabled) return;
		var selector = makeVar(getGlobalInputVar(PreviewSelect));
		var outputColor = makeVar(getGlobalInputVar(PixelColor));

		var previewExpr = makeAssign(outputColor, convertToType(TVec(4, VFloat), expr));
		var ifExpr = makeIf(makeEq(selector, makeInt(currentPreviewId)), previewExpr);
		addExpr(ifExpr);
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

	public function addExpr(e: TExpr) {
		expressions.push(e);
	}

	public function addOutput(e: TExpr, id: Int) {
		outputs[id]=e;
	}

	// Could be done
	//public function getFunction(name: String, expr: TExpr) : T

	// Pour la generation des previews

	public var previewEnabled: Bool = true;
	var currentPreviewId: Int = -1;
	var expressions: Array<TExpr> = [];
	var outputs: Array<TExpr> = [];
	var globalVars: Map<String, ShaderGraph.ExternVarDef> = [];
}