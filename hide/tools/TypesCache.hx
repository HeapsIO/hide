package hide.tools;

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
}

class TypesCache {

	var ide : hide.ui.Ide;
	var needRebuild = true;
	var types : Array<TypeModel> = [];
	var htype : Map<String, TypeModel> = new Map();
	var hfiles : Map<String, TypeFile> = new Map();
	var watchers = [];

	public function new() {
		ide = hide.ui.Ide.inst;
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
		for( f in old )
			ide.fileWatcher.unregister(f.path, f.watch);
	}

	function browseRec( path : String, old : Map<String,TypeFile> ) {
		var dir : TypeFile = {
			path : path,
			watch : null,
			files : [],
			models : [],
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
				case DClass(c) if( c.extend != null && (c.extend.match(CTPath(["hxsl","Shader"])) || c.extend.match(CTPath(["h3d","shader","ScreenShader"]))) ):
					file.models.push({ id : pack + c.name, kind : Shader, file : file, fields : [] });
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
			ide.error(e.toString());
		}
		return file;
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

	function defType( t :  hide.comp.PropsEditor.PropType ) : Dynamic {
		switch( t ) {
		case PInt(min, _):
			return if( min == null ) 0 else min;
		case PFloat(min, max):
			if( min < 0 && max > 0 )
				return 0.;
			return min == null ? 0 : min;
		case PBool:
			return false;
		case PUnsupported(_):
			return null;
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

}