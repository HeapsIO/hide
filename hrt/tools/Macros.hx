package hrt.tools;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.TypeTools;
#end

typedef ForwardConfig = {
	/** Prepended to forwarded names, with the member name's first letter uppercased. **/
	var ?prefix : String;
	/** Only forward members having one of these metadata (e.g. ":s"). **/
	var ?whitelistMeta : Array<String>;
	/** Forwarded member name => name in the host class, ignoring `prefix`. **/
	var ?renames : Map<String, String>;
	/** Also forward public methods. **/
	var ?functions : Bool;
	/** Metadata copied from forwarded members (e.g. ":p"). **/
	var ?copyMeta : Array<String>;
}

/**
	Runs `Macros.forward` on implementing classes. Autobuild macros run before `@:build` ones, and interfaces
	listed last run first : list it after other autobuilding interfaces (e.g. `h2d.domkit.Object`) so they see forwarded members.
**/
@:autoBuild(hrt.tools.Macros.forward())
interface ForwardDecls {}

class Macros {

	#if macro

	/**
		Build macro. Every member var annotated with `@:forwardDecls` exposes the public vars (and optionally methods)
		of its class as public members of the host class, forwarding to it.
		Takes an optional `ForwardConfig`, e.g. `@:forwardDecls({ prefix: "foo", whitelistMeta: [":s"] })`.
	**/
	public static function forward() : Array<Field> {
		var fields = Context.getBuildFields();
		var names = [for( f in fields ) f.name => true];
		var added : Array<Field> = [];

		for( f in fields ) for( meta in f.meta ) {
			if( meta.name != ":forwardDecls" )
				continue;
			var pos = f.pos;
			var ct = switch( f.kind ) {
				case FVar(t, _), FProp(_, _, t, _) if( t != null ): t;
				default: Context.error("@:forwardDecls requires an explicitly typed var", pos);
			}
			var renames = new Map<String, String>();
			var cfg : ForwardConfig = switch( meta.params ) {
				case []: {};
				case [e]:
					// getValue doesn't support map literals, parse renames separately
					var obj = switch( e.expr ) {
						case EObjectDecl(fl):
							for( f in fl ) if( f.field == "renames" ) switch( f.expr.expr ) {
								case EArrayDecl(el): for( r in el ) switch( r.expr ) {
									case EBinop(OpArrow, { expr: EConst(CString(a)) }, { expr: EConst(CString(b)) }): renames.set(a, b);
									default: Context.error("\"from\" => \"to\" expected", r.pos);
								}
								default: Context.error("Map literal expected", f.expr.pos);
							}
							{ expr: EObjectDecl([for( f in fl ) if( f.field != "renames" ) f]), pos: e.pos };
						default: e;
					}
					try haxe.macro.ExprTools.getValue(obj) catch( _ ) Context.error("ForwardConfig literal expected", e.pos);
				default: Context.error("@:forwardDecls takes a single ForwardConfig", pos);
			}
			cfg.renames = renames;
			var unused = [for( k in renames.keys() ) k => true];
			var owner = f.name;
			var seen = new Map<String, Bool>();

			function add( cf : ClassField, type : Type ) {
				var field = cf.name;
				switch( cf.kind ) {
					case FVar(AccNo | AccNever, AccNo | AccNever | AccCtor), FMethod(MethMacro): return;
					case FMethod(_) if( cfg.functions != true ): return;
					default:
				}
				if( !cf.isPublic || seen.exists(field) || (cfg.whitelistMeta != null && !Lambda.exists(cfg.whitelistMeta, cf.meta.has)) )
					return;
				seen.set(field, true);
				var name = cfg.renames.get(field) ?? (cfg.prefix == null ? field : cfg.prefix + field.charAt(0).toUpperCase() + field.substr(1));
				unused.remove(field);
				if( names.exists(name) )
					Context.error('@:forwardDecls: field $name already exists', pos);
				names.set(name, true);
				var metas = cfg.copyMeta == null ? [] : [for( m in cf.meta.get() ) if( cfg.copyMeta.contains(m.name) ) m];
				switch( [cf.kind, type.follow()] ) {
					case [FMethod(_), TFun(args, ret)]:
						var call = macro this.$owner.$field($a{[for( a in args ) macro $i{a.name}]});
						added.push({ name: name, access: [APublic, AFinal, AInline], meta: metas, pos: pos, kind: FFun({
							args: [for( a in args ) { name: a.name, opt: a.opt, type: a.t.toComplexType() }],
							ret: ret.toComplexType(),
							params: [for( p in cf.params ) { name: p.name }],
							expr: ret.toString() == "Void" ? call : macro return $call,
						}) });
					case [FVar(r, w), _]:
						var read = !r.match(AccNo | AccNever);
						var write = w.match(AccNormal | AccCall);
						var t = type.toComplexType();
						added.push({ name: name, access: [APublic], meta: metas, pos: pos, kind: FProp(read ? "get" : "never", write ? "set" : "never", t) });
						if( read )
							added.push({ name: "get_" + name, access: [AInline], pos: pos, kind: FFun({ args: [], ret: t, expr: macro return this.$owner.$field }) });
						if( write )
							added.push({ name: "set_" + name, access: [AInline], pos: pos, kind: FFun({ args: [{ name: "v", type: t }], ret: t, expr: macro return this.$owner.$field = v }) });
					default:
				}
			}

			function collect( c : ClassType, params : Array<Type> ) {
				for( cf in c.fields.get() )
					add(cf, cf.type.applyTypeParameters(c.params, params));
				if( c.superClass != null )
					collect(c.superClass.t.get(), [for( t in c.superClass.params ) t.applyTypeParameters(c.params, params)]);
			}

			switch( Context.resolveType(ct, pos).follow() ) {
				case TInst(c, params): collect(c.get(), params);
				default: Context.error("@:forwardDecls requires a class type", pos);
			}
			for( k in unused.keys() )
				Context.error('@:forwardDecls: renamed field $k is not forwarded', pos);
		}

		return fields.concat(added);
	}

	#end
}
