package hide.tools;
import hide.comp.PropsEditor.PropType;

enum ModelKind {
	PrefabDef;
	Shader;
}

typedef TypeModel = {
	var id : String;
	var kind : ModelKind;
	var fields : Array<{ name : String, t : hide.comp.PropsEditor.PropType, def : Dynamic }>;
	var file : TypeFile;
}

typedef TypeFile = {
	var path : String;
	var watch : Void -> Void;
	var models : Array<TypeModel>;
	var files : Array<TypeFile>;
	var error : String;
}

class TypesCache {

	var ide : hide.Ide;
	var needRebuild = true;
	var types : Array<TypeModel> = [];
	var htype : Map<String, TypeModel> = new Map();
	var hfiles : Map<String, TypeFile> = new Map();
	var watchers = [];

	public function new() {
		ide = hide.Ide.inst;
	}

	public function getModels() {
		if( needRebuild )
			rebuild();
		return types;
	}

	public function get( id : String, opt = false ) {
		if( needRebuild )
			rebuild();
		var t = htype.get(id);
		if( t == null && !opt ) throw "Missing model " + id;
		return t;
	}

	function rebuild() {
		var old = hfiles.copy();
		htype = new Map();
		hfiles = new Map();
		types = [];
		needRebuild = false;

		var src : Array<Dynamic> = ide.currentProps.get("haxe.classPath");
		for( dir in src ) {
			var path = ide.projectDir + "/" + dir;
			if( !sys.FileSystem.exists(path) )
				continue;
			browseRec(path,old);
		}
		for( f in old ) {
			var fnew = hfiles.get(f.path);
			if( fnew != null && fnew.error != null ) {
				fnew.models = [for( m in f.models ) { id : m.id, kind : m.kind, fields : [{ t : PUnsupported(fnew.error), name : "", def : null }], file : fnew }];
				for( m in fnew.models ) {
					types.push(m);
					htype.set(m.id, m);
				}
			}
			ide.fileWatcher.unregister(f.path, f.watch);
		}
	}

	function browseRec( path : String, old : Map<String,TypeFile> ) {
		var dir : TypeFile = {
			path : path,
			watch : null,
			files : [],
			models : [],
			error : null,
		};
		addFile(dir);

		for( f in sys.FileSystem.readDirectory(path) ) {
			var fpath = path + "/" + f;
			if( sys.FileSystem.isDirectory(fpath) ) {
				dir.files.push(browseRec(fpath, old));
				continue;
			}
			if( !StringTools.endsWith(f, ".hx") )
				continue;
			var f = old.get(fpath);
			if( f != null ) {
				old.remove(fpath); // reuse
				addFile(f);
				dir.files.push(f);
				continue;
			}
			f = makeFile(fpath);
			addFile(f);
			dir.files.push(f);
		}
		return dir;
	}

	function makeFile( path : String ) {
		var file : TypeFile = {
			path : path,
			watch : null,
			files : [],
			models : [],
			error : null,
		};
		var content = sys.io.File.getContent(path);
		var scan = content.indexOf("hxsl.Shader") >= 0 || content.indexOf("h3d.shader.ScreenShader") >= 0 || content.indexOf("@:prefab") >= 0;
		if( !scan )
			return file;
		var p = new hscript.Parser();
		try {
			var m = p.parseModule(content, path);
			var pack = "";
			for( d in m )
				switch( d ) {
				case DPackage(p):
					pack = p.length == 0 ? "" : p.join(".") + ".";
				case DClass(c) if( c.extend != null && (c.extend.match(CTPath(["hxsl", "Shader"])) || c.extend.match(CTPath(["h3d", "shader", "ScreenShader"]))) ):
					var error = null;
					var shader = try ide.shaderLoader.loadSharedShader(pack + c.name, path) catch( e : hxsl.Ast.Error ) { error = e.toString(); null; };
					var fields = [];
					var fmap = new Map();
					if( shader == null )
						fields.push({ name : "", t : PUnsupported("Failed to load this shader"+(error == null ? "" : " ("+error+")")), def : null });
					else {
						for( v in shader.shader.data.vars ) {
							if( v.kind != Param ) continue;
							if( v.qualifiers != null && v.qualifiers.indexOf(Ignore) >= 0 ) continue;
							var t = makeShaderType(v);
							var fl = { name : v.name, t : t, def : defType(t) };
							fields.push(fl);
							fmap.set(v.name, fl);
						}
						for( i in shader.inits ) {
							var fl = fmap.get(i.v.name);
							if( !fl.t.match(PUnsupported(_)) )
								fl.def = evalConst(i.e);
						}
					}
					file.models.push({ id : pack + c.name, kind : Shader, file : file, fields : fields });
				case DTypedef(t) if( Lambda.exists(t.meta, function(m) return m.name == ":prefab") ):
					var fields = [];
					switch( t.t ) {
					case CTAnon(fl):
						for( f in fl ) {
							var t = makeType(f.t);
							fields.push({ name : f.name, t : t, def : defType(t) });
						}
					default:
					}
					file.models.push({ id : pack + t.name, kind : PrefabDef, file : file, fields : fields });
				default:
				}
		} catch( e : hscript.Expr.Error ) {
			file.error = e.toString();
		}
		return file;
	}

	public static function evalConst( e : hxsl.Ast.TExpr ) : Dynamic {
		return switch( e.e ) {
		case TConst(c):
			switch( c ) {
			case CNull: null;
			case CBool(b): b;
			case CInt(i): i;
			case CFloat(f): f;
			case CString(s): s;
			}
		case TCall({ e : TGlobal(Vec2 | Vec3 | Vec4) }, args):
			var vals = [for( a in args ) evalConst(a)];
			if( vals.length == 1 )
				switch( e.t ) {
				case TVec(n, _):
					for( i in 0...n - 1 ) vals.push(vals[0]);
					return vals;
				default:
					throw "assert";
				}
			return vals;
		default:
			throw "Unhandled constant init " + hxsl.Printer.toString(e);
		}
	}

	function addFile( t : TypeFile ) {
		hfiles.set(t.path, t);
		if( t.watch == null ) {
			t.watch = onFileChange.bind(t);
			ide.fileWatcher.register(t.path, t.watch, true);
		}
		for( m in t.models ) {
			types.push(m);
			htype.set(m.id, m);
		}
	}

	function onFileChange( t : TypeFile ) {
		hfiles.remove(t.path);
		ide.fileWatcher.unregister(t.path, t.watch);
		t.watch = null;
		for( f in t.files )
			onFileChange(f);
		for( m in t.models ) {
			types.remove(m);
			htype.remove(m.id);
		}
		if( !needRebuild )
			haxe.Timer.delay(function() {
				if( !needRebuild ) return;
				for( w in watchers.copy() )
					w();
			}, 200);
		needRebuild = true;
	}

	public function watch( w : Void -> Void ) {
		watchers.push(w);
	}

	public function unwatch( w : Void -> Void ) {
		watchers.remove(w);
	}

	public function getModelName( m : TypeModel ) {
		return switch( m.kind ) {
		case Shader: "Shader " + m.id.split(".").pop();
		case PrefabDef: m.id.split(".").pop();
		}
	}

	public static function defType( t :  hide.comp.PropsEditor.PropType ) : Dynamic {
		switch( t ) {
		case PInt(min, _):
			return if( min == null ) 0 else min;
		case PFloat(min, max):
			if( min < 0 && max > 0 )
				return 0.;
			return min == null ? 0 : min;
		case PBool:
			return false;
		case PTexture:
			return null;
		case PVec(n):
			return [for( i in 0...n ) 0.];
		case PUnsupported(_):
			return null;
		case PChoice(c):
			return c != null && c.length > 0 ? c[0] : null;
		}
	}

	function makeType( t : hscript.Expr.CType ) : hide.comp.PropsEditor.PropType {
		return switch( t ) {
		case CTPath(["Int"]):
			PInt();
		case CTPath(["Float"]):
			PFloat();
		case CTPath(["Bool"]):
			PBool;
		default:
			PUnsupported(new hscript.Printer().typeToString(t));
		}
	}

	public static function makeShaderType( v : hxsl.Ast.TVar ) : hide.comp.PropsEditor.PropType {
		var min : Null<Float> = null, max : Null<Float> = null;
		if( v.qualifiers != null )
			for( q in v.qualifiers )
				switch( q ) {
				case Range(rmin, rmax): min = rmin; max = rmax;
				default:
				}
		return switch( v.type ) {
		case TInt:
			PInt(min == null ? null : Std.int(min), max == null ? null : Std.int(max));
		case TFloat:
			PFloat(min, max);
		case TBool:
			PBool;
		case TSampler2D:
			PTexture;
		case TVec(n, VFloat):
			PVec(n);
		default:
			PUnsupported(hxsl.Ast.Tools.toString(v.type));
		}
	}

}