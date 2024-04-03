package hrt.shgraph;

using hxsl.Ast;
using Lambda;
using hrt.shgraph.Utils;
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
		var inputId = globalInVars.getOrPut(global.name, inputCount++);
		return parentCtx?.nodeInputExprs[inputId] ?? parentCtx?.getGlobalInput(id) ?? super.getGlobalInput(id);
	}

	override  function setGlobalOutput(id: Variables.Global, expr: TExpr) : Void {
		var global = Variables.Globals[id];
		if (outputCount == 0 && parentCtx != null) {
			parentCtx.addPreview(expr);
		}
		var outputId = globalOutVars.getOrPut(global.name, outputCount ++);
		if (parentCtx != null) {
			parentCtx.setOutput(outputId, expr);
		} else {
			super.setGlobalOutput(id, expr);
		}
	}

	override  function getGlobalParam(name: String, type: Type, ?defVal: Dynamic) : TExpr {
		var inputId = globalInVars.getOrPut(name, inputCount ++);
		return parentCtx?.nodeInputExprs[inputId] ?? parentCtx?.getGlobalParam(name, type, defVal) ?? super.getGlobalParam(name, type, defVal);
	}

	override function setGlobalCustomOutput(name: String, expr: TExpr) : Void {
		if (outputCount == 0 && parentCtx != null) {
			parentCtx.addPreview(expr);
		}
		var outputId = globalOutVars.getOrPut(name, outputCount ++);
		if (parentCtx != null) {
			parentCtx.setOutput(outputId, expr);
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

	var globalInVars: Map<String, Int> = [];
	var globalOutVars: Map<String, Int> = [];
	var inputCount = 0;
	var outputCount = 0;
}

@:allow(hrt.shgraph.ShaderGraph)
class NodeGenContext {
	// Pour les rares nodes qui ont besoin de differencier entre vertex et fragment
	public var domain : ShaderGraph.Domain;
	public var previewEnabled: Bool = true;

	public function new(domain: ShaderGraph.Domain) {
		this.domain = domain;
	}

	// For general input/output of the shader graph. Allocate a new global var if name is not found,
	// else return the previously allocated variable and assert that v.type == type and devValue == v.defValue
	public function getGlobalInput(id: Variables.Global) : TExpr {
		return makeVar(getOrAllocateGlobal(id, true, false));
	}

	public function setGlobalOutput(id: Variables.Global, expr: TExpr) : Void {
		var v = makeVar(getOrAllocateGlobal(id, false, true));
		expressions.push(makeAssign(v, expr));
	}

	public function getGlobalParam(name: String, type: Type, ?defVal: Dynamic) : TExpr {
		return makeVar(globalVars.getOrPut(name, {v: {id: hxsl.Tools.allocVarId(), name: name, type: type, kind: Param}, isInput: true, isOutput: false, defValue:defVal, __init__: null}).v);
	}

	public function setGlobalCustomOutput(name: String, expr: TExpr) : Void {
		var v = makeVar(globalVars.getOrPut(name, {v: {id: hxsl.Tools.allocVarId(), name: name, type: expr.t, kind: Param}, isInput: false, isOutput: true, defValue:null, __init__: null}).v);
		expressions.push(makeAssign(v, expr));
	}

	function getOrAllocateGlobal(id: Variables.Global, ?isInput: Bool, ?isOutput: Bool) : TVar {
		var global = Variables.Globals[id];
		var def : ShaderGraph.ExternVarDef = globalVars.get(global.name);
		if (def == null) {
			var v : TVar = {id: hxsl.Tools.allocVarId(), name: global.name, type: global.type, kind: global.kind};
			def = {v: v, isInput: isInput, isOutput: isOutput, defValue: global.def, __init__: null};
			if (global.parent != null) {
				var p = Variables.Globals[global.parent];
				v.parent = globalVars.getOrPut(p.name, {v : {id : hxsl.Tools.allocVarId(), name: p.name, type: TStruct([]), kind: p.kind}, isInput: false, isOutput: false, defValue: null, __init__: null}).v;
				switch(v.parent.type) {
					case TStruct(arr):
						arr.push(v);
					default: throw "parent must be a TStruct";
				}
			}
			if (id == CalculatedUV) {
				var uv = getOrAllocateGlobal(UV);
				var expr = makeAssign(makeVar(v), makeVar(uv));
				def.__init__ = expr;
			}
			globalVars.set(global.name, def);
		}
		def.isInput = isInput ?? def.isInput;
		def.isOutput = isOutput ?? def.isOutput;
		return def.v;
	}

	// Generate a preview block that displays the content of expr
	// in the preview box of the node. Expr must be a type that
	// can be casted a Vec4
	public function addPreview(expr: TExpr) {
		if (!previewEnabled) return;
		var selector = getGlobalInput(PreviewSelect);
		var outputColor = getGlobalInput(PixelColor);

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

	public function getInput(id: Int, ?defValue: ShaderGraph.ShaderDefInput) : Null<TExpr> {
		var input = nodeInputExprs[id];
		if (input != null) {
			var inputType = getType(nodeInputInfo[id].type);
			return convertToType(inputType, input);
		}

		if (defValue != null) {
			switch(defValue) {
				case Const(f):
					return makeFloat(f);
				default:
					throw "def value not handled yet";
			}
		}
		return null;
	}

	/**
		API used by ShaderGraphGenContext
	**/
	function initForNode(node: ShaderGraph.Node, nodeInputExprs: Array<TExpr>) {
		nodeInputInfo = node.instance.getInputs();
		nodeOutputInfo = node.instance.getOutputs();
		this.node = node;
		this.nodeInputExprs = nodeInputExprs;

		outputs.resize(0);
		genericTypes.resize(0);

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
	}

	var node : ShaderGraph.Node = null;

	var currentPreviewId: Int = -1;
	var expressions: Array<TExpr> = [];
	var outputs: Array<TExpr> = [];
	var nodeOutputInfo: Array<OutputInfo>;


	var genericTypes: Array<Type> = [];
	var nodeInputExprs : Array<TExpr>;

	var nodeInputInfo : Array<InputInfo>;
	var globalVars: Map<String, ShaderGraph.ExternVarDef> = [];
}