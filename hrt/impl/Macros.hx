package hrt.impl;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

class Macros {

	public static function enumOrNullByName<T>(e:Enum<T>, constr:String, ?params:Array<Dynamic>):T {
		var value = try {
			haxe.EnumTools.createByName(e, constr, params);
		} catch (_) {
			null;
		};

		if (value == null) {
			var defaultConstructors = Type.allEnums(e);
			if (defaultConstructors.length > 0) value = defaultConstructors[0];
		}

		return value;
	}

	#if macro

	// Get the field in the specified field path or null if any element of the path is not null
	static function getOrDefault(path: Array<String>, ?startIndex: Int, ?defaultValue: Expr) : Expr {
		function recursive(path: Array<String>, index : Int, defaultValue: Expr) : Expr {
			var pos = Context.currentPos();
			if (index == path.length - 1) {
				return macro @:pos(pos) $p{path};
			}
			else {
				var subpath = path.slice(0, index+1);
				return macro @:pos(pos) $p{subpath} != null ? ${recursive(path, index+1, defaultValue)} : $defaultValue;
			}
		}

		return recursive(path, startIndex != null ? startIndex : 0, defaultValue != null ? defaultValue : macro null);
	}

	static function forEachFieldInType(t: Type, path: Array<String>, pos, func: (t: Type, path : Array<String>, pos: Position) -> Void) : Void {
		var trueType = Context.follow(t, false);
			switch(trueType) {
				case TAnonymous(a):
					for (f in a.get().fields) {
						path.push(f.name);
						forEachFieldInType(f.type, path, pos, func);
						path.pop();
					}
				default:
					func(t, path, pos);
			}
	}

	static function getTypeExpression(t : Type, path : Array<String>, pos) : Expr {
		var trueType = Context.follow(t, false);
		switch(trueType) {
			case TAnonymous(a):
				return createAnonDecl(a, path, pos);
			case TEnum(_,_):
				trace("found enum");
				var objFields : Array<ObjectField> = [];
				objFields.push({field : "name", expr : macro haxe.EnumTools.EnumValueTools.getName($p{path})});
				objFields.push({field : "parameters", expr : macro haxe.EnumTools.EnumValueTools.getParameters($p{path})});
				return {expr: EObjectDecl(objFields), pos : pos};
			default:
				return macro $p{path};
		}
	}

	static function createAnonDecl(anonType: Ref<AnonType>, path: Array<String>, pos) {
		var objFields : Array<ObjectField> = [];
		for (f in anonType.get().fields) {
			path.push(f.name);
			var e = getTypeExpression(f.type, path, pos);
			path.pop();
			objFields.push({field : f.name, expr : e});
		}
		return {expr: EObjectDecl(objFields), pos : pos};
	}

	public static function buildPrefab() {
		var fields = Context.getBuildFields();
		var toSerialize = [], toCopy = [];
		var isRoot = Context.getLocalClass().toString() == "hrt.prefab.Prefab";
		var localType = haxe.macro.Tools.TTypeTools.toComplexType(Context.getLocalType());
		var changed = false;

		for( f in fields ) {
			if( f.name == "copy" && !isRoot ) {
				// inject auto cast to copy parameter
				switch( f.kind ) {
				case FFun(f) if( f.args.length == 1 && f.expr != null ):
					var name = f.args[0].name;
					var expr = f.expr;
					f.expr = macro @:pos(f.expr.pos) { var $name : $localType = cast $i{name}; $expr; }
					changed = true;
				default:
				}
			}
			if( f.meta == null ) continue;
			for( m in f.meta ) {
				switch( m.name ) {
				case ":s":
					toSerialize.push(f);
				case ":c":
					toCopy.push(f.name);
				default:
				}
			}
		}
		if( toSerialize.length + toCopy.length == 0 )
			return changed ? fields : null;
		var ser = [], unser = [], copy = [];
		var pos = Context.currentPos();

		for( f in toSerialize ) {

			switch( f.kind ) {
			case FProp(_, _, t, e), FVar(t,e):
				var name = f.name;
				var serCond = null;
				if( e == null ) {
					var setDef = true;
					var c : Constant = switch( t ) {
					case null: Context.error("Invalid var decl", f.pos);
					case TPath({ pack : [], name : "Int"|"Float" }): CInt("0");
					case TPath({ pack : [], name : "Bool" }): CIdent("false");
					//case TPath(p): setDef = false; trace(p); CIdent("null");
					default: setDef = false; CIdent("null");
					}
					e = { expr : EConst(c), pos : f.pos };
					if( setDef ) {
						f.kind = switch( f.kind ) {
						case FVar(t,_): FVar(t,e);
						case FProp(get,set,t,_): FProp(get,set,t,e);
						default: throw "assert";
						}
					}
				} else {
					var echeck = e;
					if( e.expr.match(EArrayDecl([])) )
						serCond = macro @:pos(f.pos) this.$name.length != 0;
				}


				var type = null;
				if (t != null) {
					type = haxe.macro.ComplexTypeTools.toType(t);
				}
				else if (e != null) {
					type = Context.typeof(e);
				}
				if (type == null) throw "assert";

				var expr = getTypeExpression(type, ["this", name], pos);

				if( serCond == null ) {
					var defVal = e.expr.match(EConst(_) | EBinop(_) | EUnop(_)) ? e : macro @:pos(f.pos) null;
					serCond = macro @:pos(pos) this.$name != $defVal;
				}

				ser.push(macro @:pos(pos) if( $serCond ) obj.$name = $expr);

				forEachFieldInType(type, ["obj", name], pos, function(t: Type, path: Array<String>, pos: Position) : Void
				{
					switch(t) {
						case TEnum(enumRef,_): {
							var name = path.copy(); name.push("name");
							var params = path.copy(); params.push("parameters");
							var parentPath = path.copy(); parentPath.pop();
							var expr = macro @:pos(pos) {
								var objNullCheck = ${getOrDefault(parentPath)};
								if (objNullCheck != null)
									$p{path} = hrt.impl.Macros.enumOrNullByName($i{enumRef.get().name}, ${getOrDefault(name, parentPath.length)}, ${getOrDefault(params, parentPath.length)});
							};
							unser.push(expr);
						}
						default: {}
					}
				});

				unser.push(macro @:pos(pos) this.$name = obj.$name == null ? $e : obj.$name);
				copy.push(macro @:pos(pos) this.$name = p.$name);
			default:
				Context.error("Invalid serialization field", f.pos);
			}
		}
		for( name in toCopy ) {
			copy.push(macro @:pos(pos) this.$name = p.$name);
		}
		if( !isRoot ) {
			ser.unshift(macro @:pos(pos) super.saveSerializedFields(obj));
			unser.unshift(macro @:pos(pos) super.loadSerializedFields(obj));
			copy.unshift(macro @:pos(pos) var p : $localType = cast p);
			copy.unshift(macro @:pos(pos) super.copySerializedFields(p));
		}
		function makeFun(name,block) : Field {
			return {
				name : name,
				kind : FFun({
					ret : null,
					expr : { expr : EBlock(block), pos : pos },
					args : [{ name : "obj", type : macro : Dynamic }],
				}),
				meta : [{ name : ":noCompletion", pos : pos }],
				access : isRoot ? [] : [AOverride],
				pos : pos,
			};
		}
		if( toSerialize.length > 0 ) {
			fields.push(makeFun("saveSerializedFields",ser));
			fields.push(makeFun("loadSerializedFields",unser));
		}
		fields.push({
			name : "copySerializedFields",
			kind : FFun({
				ret : null,
				expr : { expr : EBlock(copy), pos : pos },
				args : [{ name : "p", type : macro : hrt.prefab.Prefab }],
			}),
			meta : [{ name : ":noCompletion", pos : pos }],
			access : isRoot ? [] : [AOverride],
			pos : pos,
		});
		return fields;
	}
	#end

}