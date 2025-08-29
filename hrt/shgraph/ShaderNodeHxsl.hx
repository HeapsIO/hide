package hrt.shgraph;

import hxsl.Ast.TExpr;
using hxsl.Ast;
using hrt.shgraph.Utils;
import hrt.tools.MapUtils;

using Lambda;

typedef FunctionCache = {
	fun: TFunction,
	useSgIO: Bool,
}
typedef CacheEntry = {
	expr: TExpr,
	funs: Array<FunctionCache>,
	inputs: Array<ShaderNode.InputInfo>,
	outputs: Array<ShaderNode.OutputInfo>,
	idInputOrder: Map<Int, Int>,
	idOutputOrder: Map<Int,Int>,
};

class CustomSerializer extends hxsl.Serializer {

	// we override readvar to remove the allocation of new variable id
	// because we rely on the variable ID to get our custom info about
	// input and outputs
	override function readVar() : TVar {
		var id = readID();
		if( id == 0 )
			return null;
		var v = varMap.get(id);
		if( v != null ) return v;
		v = {
			id : id,
			name : readString(),
			type : null,
			kind : null,
		}
		varMap.set(id, v);
		v.type = readType();
		v.kind = hxsl.Serializer.VKINDS[input.readByte()];
		v.parent = readVar();
		var nq = input.readByte();
		if( nq > 0 ) {
			v.qualifiers = [];
			for( i in 0...nq ) {
				var qid = input.readByte();
				var q = switch( qid ) {
				case 0: var n = input.readInt32(); Const(n == 0 ? null : n);
				case 1: Private;
				case 2: Nullable;
				case 3: PerObject;
				case 4: Name(readString());
				case 5: Shared;
				case 6: Precision(hxsl.Serializer.PRECS[input.readByte()]);
				case 7: Range(input.readDouble(), input.readDouble());
				case 8: Ignore;
				case 9: PerInstance(input.readInt32());
				case 10: Doc(readString());
				case 11: Borrow(readString());
				case 12: Sampler(readString());
				case 13: Final;
				default: throw "assert";
				}
				v.qualifiers.push(q);
			}
		}
		return v;
	}
}

@:autoBuild(hrt.shgraph.Macros.buildNode())
class ShaderNodeHxsl extends ShaderNode {

	static var cache : Map<{}, CacheEntry> = [];

	override public function getInputs() : Array<ShaderNode.InputInfo> {
		var cl = std.Type.getClass(this);
		return MapUtils.getOrPut(cache, cast cl, genCache(cl)).inputs;
	}

	override public function getOutputs() : Array<ShaderNode.OutputInfo> {
		var cl = std.Type.getClass(this);
		return MapUtils.getOrPut(cache, cast cl, genCache(cl)).outputs;
	}

	function genCache(cl: Class<ShaderNodeHxsl>) : CacheEntry {
		var toUnser = (cl:Dynamic).SRC;
		var className = std.Type.getClassName(cl);
		if (toUnser == null) throw "Node " + className + " has no SRC";
		var shortName = std.Type.getClassName(cl).split(".").pop();

		var unser = new CustomSerializer();
		var data = @:privateAccess unser.unserialize(toUnser);

		var inputs : Array<ShaderNode.InputInfo> = [];
		var outputs : Array<ShaderNode.OutputInfo> = [];
		var idInputOrder : Map<Int,Int> = [];
		var idOutputOrder : Map<Int,Int> = [];
		var inputCount = 0;
		var outputCount = 0;

		var infos : Map<Int, SgHxslVar> = cast (cl:Dynamic)._variablesInfos;
		for (v in data.vars) {
			var info = infos.get(v.id);
			switch (info) {
				case SgInput(isDynamic, defaultValue):
					inputs.push({name: v.name, type: isDynamic ? SgGeneric(0, ShaderGraph.ConstraintFloat) : typeToSgType(v.type), def: defaultValue});
					idInputOrder.set(v.id, inputCount++);
				case SgOutput(isDynamic):
					outputs.push({name: v.name, type: isDynamic ? SgGeneric(0, ShaderGraph.ConstraintFloat) : typeToSgType(v.type)});
					idOutputOrder.set(v.id, outputCount++);
				case SgConst:
				case null:
			}
		}

		var funs : Array<FunctionCache> = [];
		var expr : TExpr = null;
		for (fn in data.funs) {
			if (fn.ref.name == "fragment") {
				expr = fn.expr;
				break;
			} else {
				fn.ref.name = shortName + "_" + fn.ref.name; // De-duplicate function name if multiple nodes declare the same function name to avoid conflics

				var useSgIO = false;
				function hasShaderInput(e: TExpr) : Void {
					switch (e.e) {
						case TVar(v):
							switch(infos.get(v.id)) {
								case SgInput(isDynamic, defaultValue):
									useSgIO = true;
									return;
								case SgOutput(_):
									useSgIO = true;
								case null:
								default:
							}
						default:
							if (!useSgIO)
								e.iter(hasShaderInput);
					}
				};
				fn.expr.iter(hasShaderInput);

				funs.push({
					fun: fn,
					useSgIO: useSgIO,
				});
			}
		}

		return {expr: expr, funs: funs, inputs: inputs, outputs: outputs, idInputOrder: idInputOrder, idOutputOrder: idOutputOrder};
	}

	override public function generate(ctx: NodeGenContext) : Void {
		var cl = std.Type.getClass(this);
		var cache = MapUtils.getOrPut(cache, cast cl, genCache(cl));

		var infos : Map<Int, SgHxslVar> = cast (cl:Dynamic)._variablesInfos;
		var varsOverride : Map<Int, TExpr> = [];
		var varsRemap : Map<Int, TVar> = [];
		var outputs : Array<TVar> = [];
		var genFailure : Bool = false;

		function patch(e: TExpr) : TExpr {
			switch (e.e) {
				case TVar(v):
					var replacement = varsOverride.get(v.id);
					if (replacement != null)
						return replacement;

					var type = e.t;

					var info = infos.get(v.id);

					switch(info) {
						case SgInput(isDynamic, defaultValue):
							if (isDynamic) {
								type = ctx.getType(SgGeneric(0, ShaderGraph.ConstraintFloat));
							}
							var inputId = cache.idInputOrder.get(v.id);
							replacement = ctx.getInput(inputId);

							// default value handling if we have no input connected
							if (replacement == null) {
								switch (defaultValue) {
									case Const(init):
										replacement = NodeGenContext.convertToType(type, makeFloat(getDef(v.name, init)));
									case Var(name):
										var globalId = Variables.getGlobalNameMap().get(name);
										if (globalId != null) {
											replacement = ctx.getGlobalInput(globalId);
										}
									case null, _:
										genFailure = true;
								}
							}
						case SgConst:
							replacement = makeInt(getConstValue(v.name) ?? 0);
						case SgOutput(_):
							var outputId = cache.idOutputOrder.get(v.id);
							var t = ctx.getType(cache.outputs[outputId].type);

							var outputVar : TVar= {
								name: v.name,
								id: hxsl.Ast.Tools.allocVarId(),
								type: t,
								kind: v.kind,
								parent: v.parent,
								qualifiers: v.qualifiers,
							};
							replacement = makeVar(outputVar);
							outputs[outputId] = outputVar;
						case null:
							var tvar = varsRemap.get(v.id);
							if (tvar != null) {
								replacement = {e: TVar(tvar), p: e.p, t: e.t};
							} else {
								switch(v.type) {
									case TFun(_): return e;// don't replace tfun vars with global decls
									default:
										replacement = ctx.getGlobalTVar(v);
								}
							}
					}
					if (replacement == null) {
						genFailure = true;
						replacement = e;
					}
					varsOverride.set(v.id, replacement);

					return replacement;
				case TVarDecl(v, init):
					var tvar = MapUtils.getOrPut(varsRemap, v.id,
						{
							name: v.name,
							id: hxsl.Ast.Tools.allocVarId(),
							type: v.type,
							kind: v.kind,
							parent: v.parent,
							qualifiers: v.qualifiers,
						});
					return makeExpr(TVarDecl(tvar, if( init != null ) patch(init) else null), e.t);
				case TFor(v, it, loop):
					var tvar = MapUtils.getOrPut(varsRemap, v.id,
						{
							name: v.name,
							id: hxsl.Ast.Tools.allocVarId(),
							type: v.type,
							kind: v.kind,
							parent: v.parent,
							qualifiers: v.qualifiers,
						});
					return makeExpr(TFor(tvar, patch(it), patch(loop)), e.t);
				default:
					return e.map(patch);
			}
		}

		var funs: Array<FunctionCache> = [];

		for (fun in cache.funs) {

			if (fun.useSgIO) {
				// If the function use input/outputs, we need to duplicate it per Node invocation,
				// because we need to patch the function to properly set the input/outputs
				var fun = fun.fun;
				var tvar = MapUtils.getOrPut(varsRemap, fun.ref.id,
				{
					name: '${fun.ref.name}_$id',
					id: hxsl.Ast.Tools.allocVarId(),
					type: fun.ref.type,
					kind: fun.ref.kind,
					parent: fun.ref.parent,
					qualifiers: fun.ref.qualifiers,
				});

				var args : Array<TVar> = [];
				for (arg in fun.args) {
					var tvar = MapUtils.getOrPut(varsRemap, arg.id,
					{
						name: arg.name,
						id: hxsl.Ast.Tools.allocVarId(),
						type: arg.type,
						kind: arg.kind,
						parent: arg.parent,
						qualifiers: arg.qualifiers,
					});
					args.push(tvar);
				}

				var replacementFunc : TFunction = {
					ref: tvar,
					expr: fun.expr,
					ret: fun.ret,
					args: args,
					kind: fun.kind
				}

				funs.push({fun: replacementFunc, useSgIO: true});
			}
			else {
				funs.push(fun);
			}
		}

		var expr = patch(cache.expr);
		for (fun in funs) {
			if (fun.useSgIO)
				fun.fun.expr = patch(fun.fun.expr);
		}

		if (genFailure) {
			for (outputId => o in cache.outputs) {
				var t = ctx.getType(o.type);
				var expr = NodeGenContext.convertToType(t, makeVec([0.0,0.0,0.0,0.0]));
				ctx.setOutput(outputId, NodeGenContext.convertToType(t, makeVec([0.0,0.0,0.0,0.0])));
				if (outputId == 0) {
					ctx.addPreview(expr);
				}
			}
		}
		else {
			for (outputId => o in cache.outputs) {
				var tvar = outputs[outputId];
				ctx.addExpr(makeExpr(TVarDecl(tvar), tvar.type));
				var expr = makeVar(tvar);
				ctx.setOutput(outputId, expr);
				if (outputId == 0) {
					ctx.addPreview(expr);
				}
			}

			switch(expr.e){
				case TBlock(exprs):
					for (e in exprs) {
						ctx.addExpr(e);
					}
				default:
					throw "function expr is not a block";
			}
		}

		for (func in funs) {
			ctx.addFunction(func.fun);
		}
	}

	function getConstValue(name: String) : Null<Int> {
		return null;
	}
}
