package hide.tools;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
using haxe.macro.ExprTools;

class Macros {

	#if macro

	static function includeShaderSources() {
		var paths = [
			"h3d/shader/BaseMesh.hx",
			"hrt/shader/BaseEmitter.hx",
		];

		for (pathStr in paths) {
			var path = Context.resolvePath(pathStr);
			var dir = new haxe.io.Path(path).dir;
			for( f in sys.FileSystem.readDirectory(dir) )
				if( StringTools.endsWith(f,".hx") )
					Context.addResource("shader/" + f.substr(0, -3), sys.io.File.getBytes(dir + "/" + f));
		}
	}

	public static function buildSaveLoad() {

		inline function isSerialized( field : Field ) : Bool {
			return Lambda.find(field.meta, m -> m.name == ":s") != null;
		}

		inline function isOpt( field : Field ) : Bool {
			return Lambda.find(field.meta, m -> m.name == ":opt") != null;
		}

		var fields = haxe.macro.Context.getBuildFields();

		// Add the call of _save and _load
		if( haxe.macro.Context.getLocalClass().get().name == "Prefab" ) {

			var loadField : Field = null;
			var saveField : Field = null;
			for( f in fields ) {
				if( f.name == "save" && f.kind.match(FFun(_)) )
					saveField = f;
				else if( f.name == "load" && f.kind.match(FFun(_)) )
					loadField = f;
				if( loadField != null && saveField != null )
					break;
			}

			var loadFunction = switch loadField.kind {
				case FFun(f): f;
				default: null;
			}
			loadFunction.expr = macro _load(v);

			var saveFunction = switch saveField.kind {
				case FFun(f): f;
				default: null;
			}
			saveFunction.expr = macro return _save();

			fields.push({
				name: "_load",
				access: [APrivate],
				pos: haxe.macro.Context.currentPos(),
				kind: FFun({
					args: [{ name : "obj", type : (macro:Dynamic) }],
					expr: macro return,
					params: [],
					ret: null
				})
			});

			fields.push({
				name: "_save",
				access: [APrivate],
				pos: haxe.macro.Context.currentPos(),
				kind: FFun({
					args: [],
					expr: macro return {},
					params: [],
					ret: (macro:Dynamic)
				})
			});

			return fields;
		}

		// Generate code for every field with :s metadata
		var saveExpr : Array<haxe.macro.Expr> = [];
		var loadExpr : Array<haxe.macro.Expr> = [];
		for( f in fields ) {
			if( !isSerialized(f) )
				continue;
			var name = f.name;
			switch f.kind {
				case FVar(t, e):
					// Don't save a field with his default value
					if( e != null )
						saveExpr.push(macro if( this.$name != $e ) obj.$name = this.$name);
					else {
						switch t {
							// Basic types default values : https://haxe.org/manual/types-nullability.html
							case TPath(p):
								if( p.name == "Bool" )
									saveExpr.push(macro if( this.$name != false) obj.$name = this.$name);
								else if( p.name == "Float" )
									saveExpr.push(macro if( this.$name != #if flash NaN #else 0.0 #end ) obj.$name = this.$name);
								else if( p.name == "Int" )
									saveExpr.push(macro if( this.$name != 0 ) obj.$name = this.$name);
								else
									saveExpr.push(macro if( this.$name != null ) obj.$name = this.$name);
							default:
								saveExpr.push(macro if( this.$name != null ) obj.$name = this.$name);
						}
					}
				case FFun(f): saveExpr.push(macro obj.$name = this.$name );
				case FProp(get, set, t, e): saveExpr.push(macro obj.$name = this.$name );
			}
			loadExpr.push(macro if( obj.$name != null ) this.$name = obj.$name );
		}

		// Generate the functions if not empty
		if( saveExpr.length > 0 ) {
			saveExpr.insert(0, macro var obj : Dynamic = super._save());
			saveExpr.push(macro return obj );
			fields.push({
				name: "_save",
				access: [AOverride, APrivate],
				pos: haxe.macro.Context.currentPos(),
				kind: FFun({
					args: [],
					expr: macro $b{saveExpr},
					params: [],
					ret: (macro:Dynamic)
				})
			});
		}

		if( loadExpr.length > 0 ) {
			loadExpr.insert(0, macro super._load(obj));
			fields.push({
				name: "_load",
				access: [AOverride, APrivate],
				pos: haxe.macro.Context.currentPos(),
				kind: FFun({
					args: [{ name : "obj", type : (macro:Dynamic) }],
					expr: macro $b{loadExpr},
					params: [],
					ret: null
				})
			});
		}

		return fields;
	}
	#end

}
