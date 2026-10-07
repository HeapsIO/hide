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
	/** Also forward public non-generic methods, as function vars (writable for dynamic methods). **/
	var ?functions : Bool;
	/** Metadata copied from forwarded members (e.g. ":p"). **/
	var ?copyMeta : Array<String>;
	/** Forward members of superclasses up to this class (inclusive). If null, only the var's class is forwarded. **/
	var ?forwardDepth : Class<Dynamic>;
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
		of its class as public members of the host class, forwarding to it. Members already declared by the host are not forwarded.
		Generic methods are not supported and are ignored.
		Takes an optional `ForwardConfig`, e.g. `@:forwardDecls({ prefix: "foo", whitelistMeta: [":s"] })`.
	**/
	public static function forward() : Array<Field> {
		var fields = Context.getBuildFields();
		var hostNames = [for( f in fields ) f.name => true];
		var names = hostNames.copy();
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
			var depth : String = null;
			var cfg : ForwardConfig = switch( meta.params ) {
				case []: {};
				case [e]:
					// getValue doesn't support map literals or type paths, parse renames and forwardDepth separately
					var obj = switch( e.expr ) {
						case EObjectDecl(fl):
							for( f in fl ) switch( f.field ) {
								case "renames": switch( f.expr.expr ) {
									case EArrayDecl(el): for( r in el ) switch( r.expr ) {
										case EBinop(OpArrow, { expr: EConst(CString(a)) }, { expr: EConst(CString(b)) }): renames.set(a, b);
										default: Context.error("\"from\" => \"to\" expected", r.pos);
									}
									default: Context.error("Map literal expected", f.expr.pos);
								}
								case "forwardDepth": switch( Context.getType(haxe.macro.ExprTools.toString(f.expr)).follow() ) {
									case TInst(c, _): depth = c.get().pack.concat([c.get().name]).join(".");
									default: Context.error("Class expected", f.expr.pos);
								}
								default:
							}
							{ expr: EObjectDecl([for( f in fl ) if( f.field != "renames" && f.field != "forwardDepth" ) f]), pos: e.pos };
						default: e;
					}
					try haxe.macro.ExprTools.getValue(obj) catch( _ ) Context.error("ForwardConfig literal expected", e.pos);
				default: Context.error("@:forwardDecls takes a single ForwardConfig", pos);
			}
			cfg.renames = renames;
			var unused = [for( k in renames.keys() ) k => true];
			var owner = f.name;
			var seen = new Map<String, Bool>();

			function add( cf : ClassField, type : Type, c : ClassType ) {
				var field = cf.name;
				switch( cf.kind ) {
					case FVar(AccNo | AccNever, AccNo | AccNever | AccCtor), FMethod(MethMacro): return;
					case FMethod(_) if( cfg.functions != true ): return;
					// a function var can't have type parameters
					case FMethod(_) if( cf.params.length > 0 ): return;
					default:
				}
				if( !cf.isPublic || seen.exists(field) || (cfg.whitelistMeta != null && !Lambda.exists(cfg.whitelistMeta, cf.meta.has)) )
					return;
				seen.set(field, true);
				var name = cfg.renames.get(field) ?? (cfg.prefix == null ? field : cfg.prefix + field.charAt(0).toUpperCase() + field.substr(1));
				unused.remove(field);
				// declared by the host, which takes precedence
				if( hostNames.exists(name) )
					return;
				if( names.exists(name) )
					Context.error('@:forwardDecls: field $name already exists', pos);
				names.set(name, true);
				var metas = cfg.copyMeta == null ? [] : [for( m in cf.meta.get() ) if( cfg.copyMeta.contains(m.name) ) m];
				// Forcing a lazy type flushes pending builds, which can require the host before it is built : defer it with MacroType
				var t = switch( type ) {
					case TLazy(_):
						var path = c.module.split(".").pop() == c.name ? c.module : c.module + "." + c.name;
						macro : haxe.macro.MacroType<[hrt.tools.Macros.fieldType($v{path}, $v{field})]>;
					default: type.toComplexType();
				}
				// Methods are forwarded as function vars, as their signature can't be read without forcing their type
				var read = true, write = false;
				switch( cf.kind ) {
					case FVar(r, w):
						read = !r.match(AccNo | AccNever);
						write = w.match(AccNormal | AccCall);
					case FMethod(MethDynamic):
						write = true;
					default:
				}
				added.push({ name: name, access: [APublic], meta: metas, pos: pos, kind: FProp(read ? "get" : "never", write ? "set" : "never", t) });
				if( read )
					added.push({ name: "get_" + name, access: [AInline], pos: pos, kind: FFun({ args: [], ret: t, expr: macro return this.$owner.$field }) });
				if( write )
					added.push({ name: "set_" + name, access: [AInline], pos: pos, kind: FFun({ args: [{ name: "v", type: t }], ret: t, expr: macro return this.$owner.$field = v }) });
			}

			function collect( c : ClassType, params : Array<Type> ) {
				for( cf in c.fields.get() )
					add(cf, cf.type.applyTypeParameters(c.params, params), c);
				if( c.superClass != null && depth != null && c.pack.concat([c.name]).join(".") != depth )
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

	public static function fieldType( path : String, field : String ) : Type {
		return switch( Context.getType(path) ) {
			case TInst(c, _): TypeTools.findField(c.get(), field).type;
			default: throw "assert";
		}
	}

	#end
}
