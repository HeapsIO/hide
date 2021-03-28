package hrt.impl;
import haxe.macro.Context;
import haxe.macro.Expr;

class Macros {

	#if macro
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

				if( serCond == null ) {
					var defVal = e.expr.match(EConst(_) | EBinop(_) | EUnop(_)) ? e : macro @:pos(f.pos) null;
					serCond = macro @:pos(pos) this.$name != $defVal;
				}

				ser.push(macro @:pos(pos) if( $serCond ) obj.$name = this.$name);
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