package hrt.shgraph;

using hxsl.Ast;
using Lambda;
using hrt.shgraph.Utils;
using hrt.tools.MapUtils;
import hrt.shgraph.AstTools.*;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;

class NodeGenContextSubGraph extends NodeGenContext {
	public function new(parentCtx : NodeGenContext) {
		super(parentCtx?.domain ?? Fragment);
		this.parentCtx = parentCtx;
	}

	override function getGlobalInput(id: Variables.Global) : TExpr {
		var global = Variables.Globals[id];
		var info = globalInVars.getOrPut(global.name, {type: global.type, id: inputCount++});
		return parentCtx?.nodeInputExprs[info.id] ?? parentCtx?.getGlobalInput(id) ?? super.getGlobalInput(id);
	}

	override  function setGlobalOutput(id: Variables.Global, expr: TExpr) : Void {
		var global = Variables.Globals[id];
		if (outputCount == 0 && parentCtx != null) {
			parentCtx.addPreview(expr);
		}
		var info = globalOutVars.getOrPut(global.name, {type: global.type, id: outputCount ++});
		if (parentCtx != null) {
			parentCtx.setOutput(info.id, expr);
		} else {
			super.setGlobalOutput(id, expr);
		}
	}

	override  function getGlobalParam(name: String, type: Type) : TExpr {
		var info = globalInVars.getOrPut(name, {type: type, id: inputCount ++});
		return parentCtx?.nodeInputExprs[info.id] ?? parentCtx?.getGlobalParam(name, type) ?? super.getGlobalParam(name, type);
	}

	override function setGlobalCustomOutput(name: String, expr: TExpr) : Void {
		if (outputCount == 0 && parentCtx != null) {
			parentCtx.addPreview(expr);
		}
		var info = globalOutVars.getOrPut(name, {type : expr.t, id: outputCount ++});
		if (parentCtx != null) {
			parentCtx.setOutput(info.id, expr);
		} else {
			super.setGlobalCustomOutput(name, expr);
		}
	}

	override function addExpr(expr: TExpr) : Void {
		if (parentCtx != null) {
			parentCtx.addExpr(expr);
		}
	}

	var parentCtx : NodeGenContext;

	var globalInVars: Map<String, {type: Type, id: Int}> = [];
	var globalOutVars: Map<String, {type: Type, id: Int}> = [];
	var inputCount = 0;
	var outputCount = 0;
}

@:allow(hrt.shgraph.ShaderGraph)
class NodeGenContext {
	// Pour les rares nodes qui ont besoin de differencier entre vertex et fragment
	public var domain : ShaderGraph.Domain;
	public var previewDomain: ShaderGraph.Domain = null;

	public function new(domain: ShaderGraph.Domain) {
		this.domain = domain;
	}

	// For general input/output of the shader graph. Allocate a new global var if name is not found,
	// else return the previously allocated variable and assert that v.type == type and devValue == v.defValue
	public function getGlobalInput(id: Variables.Global) : TExpr {
		var global = Variables.Globals[id];
		switch (global.varkind) {
			case KVar(_,_,_):
				var v = getOrAllocateGlobal(id);
				return makeVar(v);
			case KSwizzle(id, swiz):
				var v = getOrAllocateGlobal(id);
				return makeSwizzle(makeVar(v), swiz);
		}
	}

	public function setGlobalOutput(id: Variables.Global, expr: TExpr) : Void {
		var global = Variables.Globals[id];
		switch (global.varkind) {
			case KVar(_,_,_):
				var v = getOrAllocateGlobal(id);
				expressions.push(makeAssign(makeVar(v), expr));
			case KSwizzle(otherId, swiz):
				var v = getOrAllocateGlobal(otherId);
				expressions.push(makeAssign(makeSwizzle(makeVar(v), swiz), expr));
		}
	}

	public function getGlobalParam(name: String, type: Type) : TExpr {
		return makeVar(globalVars.getOrPut(name, {v: {id: hxsl.Tools.allocVarId(), name: name, type: type, kind: Param}, defValue:null, __init__: null}).v);
	}

	public function setGlobalCustomOutput(name: String, expr: TExpr) : Void {
		var v = makeVar(globalVars.getOrPut(name, {v: {id: hxsl.Tools.allocVarId(), name: name, type: expr.t, kind: Param}, defValue:null, __init__: null}).v);
		expressions.push(makeAssign(v, expr));
	}

	function getOrAllocateGlobal(id: Variables.Global) : TVar {
		// Remap id for certains variables
		switch (id) {
			case Normal if (previewDomain == domain):
				id = FakeNormal;
			default:
		}

		var global = Variables.Globals[id];
		var def : ShaderGraph.ExternVarDef = globalVars.get(global.name);

		switch (global.varkind)
		{
			case KVar(kind, parent, defValue):
				var def : ShaderGraph.ExternVarDef = globalVars.get(global.name);
				if (def == null) {
					var v : TVar = {id: hxsl.Tools.allocVarId(), name: global.name, type: global.type, kind: kind};
					def = {v: v, defValue: defValue, __init__: null};
					if (parent != null) {
						var p = Variables.Globals[parent];
						switch (p.varkind) {
							case KVar(kind, _, _):
								v.parent = globalVars.getOrPut(p.name, {v : {id : hxsl.Tools.allocVarId(), name: p.name, type: TStruct([]), kind: kind}, defValue: null, __init__: null}).v;
							default:
								throw "Parent var must be a KVar";
						}
						switch(v.parent.type) {
							case TStruct(arr):
								arr.push(v);
							default: throw "parent must be a TStruct";
						}
					}

					// Post process certain variables
					switch (id) {
						case CalculatedUV:
							var uv = getOrAllocateGlobal(UV);
							var expr = makeAssign(makeVar(v), makeVar(uv));
							def.__init__ = expr;
						default:
					}
					globalVars.set(global.name, def);
				}
				return def.v;
			default: throw "id must be a global Var";
		}
	}

	// Generate a preview block that displays the content of expr
	// in the preview box of the node. Expr must be a type that
	// can be casted a Vec4
	public function addPreview(expr: TExpr) {
		if (previewDomain != domain) return;
		var selector = getGlobalInput(PreviewSelect);
		var outputColor = getOrAllocateGlobal(PreviewColor);

		var previewExpr = makeAssign(makeVar(outputColor), convertToType(TVec(4, VFloat), expr));
		var ifExpr = makeIf(makeEq(selector, makeInt(currentPreviewId)), previewExpr);
		preview = ifExpr;
	}

	public static function convertToType(targetType: hxsl.Ast.Type, sourceExpr: TExpr) : TExpr {

		if (sourceExpr.t.equals(targetType))
			return sourceExpr;

		if (sourceExpr.t.match(TBool)) {
			sourceExpr = makeIf(sourceExpr, makeFloat(1.0), makeFloat(0.0), null, TFloat);
		}

		var sourceSize = switch (sourceExpr.t) {
			case TFloat: 1;
			case TVec(size, VFloat): size;
			default:
				throw "Unsupported source type " + sourceExpr.t;
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
				for (i in 0...targetSize) {
					args.push(sourceExpr);
				}
			}
			else {
				args.push(sourceExpr);
				for (i in 0...delta) {
					// Set alpha to 1.0 by default on upcasts casts
					var value = ((sourceSize + i) == 3) ? 1.0 : 0.0;
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

	public function setOutput(id: Int, e: TExpr) {
		var expectedType = getType(nodeOutputInfo[id].type);
		if (!expectedType.equals(e.t))
			throw "Output " + id + " has different type than declared";
		outputs[id]=e;
	}

	public function getType(type: SgType) : Type {
		switch (type) {
			case SgGeneric(id, consDtraint):
				return getGenericType(id);
			default:
				return inline sgTypeToType(type);
		}
	}

	public inline function getGenericType(id: Int) {
		return genericTypes[id];
	}

	public function getInput(id: Int, ?defValue: SgHxslVar.ShaderDefInput) : Null<TExpr> {
		var input = nodeInputExprs[id];
		var inputType = getType(nodeInputInfo[id].type);
		if (input != null) {
			return convertToType(inputType, input);
		}

		if (defValue != null) {
			switch(defValue) {
				case Const(f):
					return convertToType(inputType, makeFloat(f));
				default:
					throw "def value not handled yet";
			}
		}
		return null;
	}

	/**
		API used by ShaderGraphGenContext
	**/
	function initForNode(node: ShaderNode, nodeInputExprs: Array<TExpr>) {
		nodeInputInfo = node.getInputs();
		nodeOutputInfo = node.getOutputs();
		this.node = node;
		this.nodeInputExprs = nodeInputExprs;

		outputs.resize(0);
		genericTypes.resize(0);
		preview = null;

		for (inputId => input in nodeInputInfo) {
			switch(input.type) {
				case SgGeneric(id, constraint):
					genericTypes[id] = constraint(nodeInputExprs[inputId]?.t, genericTypes[id]);
				default:
			}
		}

		currentPreviewId = node.id + 1;
	}

	function finishNode() {
		if (nodeOutputInfo.length != outputs.length) {
			throw "Missing outputs for node";
		}
		if (preview != null) {
			addExpr(preview);
		}
	}

	var node : ShaderNode = null;

	var currentPreviewId: Int = -1;
	var expressions: Array<TExpr> = [];
	var outputs: Array<TExpr> = [];
	var preview : TExpr = null;
	var nodeOutputInfo: Array<OutputInfo>;


	var genericTypes: Array<Type> = [];
	var nodeInputExprs : Array<TExpr>;

	var nodeInputInfo : Array<InputInfo>;
	var globalVars: Map<String, ShaderGraph.ExternVarDef> = [];
}