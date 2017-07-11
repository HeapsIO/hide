package hide;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
using haxe.macro.ExprTools;

class Macros {

	public static macro function makeTypeDef( e : Expr ) {
		var t = Context.getType(e.toString());
		return buildTypeDef(t);
	}

	#if macro

	static function buildTypeDef( t : Type ) : Expr {
		var m = new Map();
		var e = buildTypeDefRec(t,m);
		var block = [];
		for( t in m )
			block.push(t.decl);
		for( t in m )
			block.push(t.init);
		block.push(e);
		return macro ({$a{block}} : hide.HType);
	}

	static function buildTypeDefRec( t : Type, knownTypes : Map<String,{ value : Expr, decl : Expr, init : Expr }> ) : Expr {
		switch( t ) {
		case TType(t,[pt]) if( t.toString() == "Null" ):
			var e = buildTypeDefRec(pt,knownTypes);
			return macro { var _tmp : hide.HType = $e; _tmp.props.set(PNull); _tmp; };
		case TType(t,[]):
			var key = t.toString();
			var def = knownTypes.get(key);
			if( def != null )
				return def.value;
			var vname = "_"+key.split(".").join("_");
			def = {
				decl : (macro var $vname : hide.HType = { def : null }),
				init : null,
				value : macro $i{vname},
			};
			knownTypes.set(key, def);
			def.init = macro $i{vname}.def = (${buildTypeDefRec(t.get().type,knownTypes)} : hide.HType).def;
			return def.value;
		case TEnum(e,[]):
			var key = e.toString();
			var def = knownTypes.get(key);
			if( def != null )
				return def.value;
			var vname = "_"+key.split(".").join("_");
			def = {
				decl : (macro var $vname : hide.HType = { def : null }),
				init : null,
				value : macro $i{vname},
			};
			knownTypes.set(key, def);
			var edef = e.get();
			var constructs = [for( c in edef.names ) {
				var c = edef.constructs.get(c);
				var args = switch( c.type ) {
				case TFun(args,_): [for( a in args ) macro { name : $v{a.name}, t : ${buildTypeDefRec(a.t,knownTypes)} }];
				default: [];
				};
				macro { name : $v{c.name}, args : [$a{args}] };
			}];
			def.init = macro $i{vname}.def = TEnum([$a{constructs}]);
			return def.value;
		case TAnonymous(a):
			var fields = [for( f in a.get().fields ) macro { name : $v{f.name}, t : ${buildTypeDefRec(f.type,knownTypes)} }];
			return macro { def : TStruct([$a{fields}]) };
		case TAbstract(a,pl):
			var a = a.get();
			switch( a.name ) {
			case "EnumFlags":
				switch( Context.follow(pl[0]) ) {
				case TEnum(e,_):
					var flags = [for( c in e.get().constructs ) macro $v{c.name}];
					return macro { def : TFlags([$a{flags}]) };
				default:
				}
			case "Null":
				var pt = pl[0];
				var e = buildTypeDefRec(pt,knownTypes);
				return macro { var _tmp : hide.HType = $e; _tmp.props.set(PNull); _tmp; };
			default:
			}
		case TInst(c,pl):
			switch( c.toString() ) {
			case "String": return macro { def : TString };
			case "Array": return macro { def : TArray(${buildTypeDefRec(pl[0],knownTypes)}) };
			default:
			}
		default:
		}
		Context.error("Unsupported type "+Std.string(t),Context.currentPos());
		return null;
	}

	#end

}