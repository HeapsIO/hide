package hide.tools;

typedef CachedShader = {
	var file : String;
	var name : String;
	var shader : hxsl.SharedShader;
	var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }>;
	var watch : Void -> Void;
}

class ShaderLoader {

	var ide : hide.Ide;
	var shaderPath : Array<String>;
	var shaderCache = new Map<String, CachedShader>();

	public function new() {
		ide = hide.Ide.inst;
		shaderPath = ide.currentConfig.get("haxe.classPath");
	}

	public function load( name : String ) {
		var s = loadSharedShader(name);
		if( s == null )
			return null;
		var d = new hxsl.DynamicShader(s.shader);
		for( v in s.inits )
			d.hscriptSet(v.variable.name, hxsl.Ast.Tools.evalConst(v.value));
		return d;
	}

	public function loadSharedShader( name : String, ?file : String ) {
		var s = shaderCache.get(name);
		if( s != null )
			return s;
		var e = loadShaderExpr(name, file);
		if( e == null )
			return null;
		var chk = new hxsl.Checker();
		chk.loadShader = function(iname) {
			var e = loadShaderExpr(iname, null);
			if( e == null )
				throw "Could not @:import " + iname + " (referenced from " + name+")";
			return e.expr;
		};
		var s = new hxsl.SharedShader("");
		s.data = chk.check(name, e.expr);
		@:privateAccess s.initialize();
		var convertedInits = [];
		for (init in chk.inits) {
			convertedInits.push({variable: init.v, value: hrt.prefab.Shader.evalConst(init.e) });
		}
		var s : CachedShader = { file : e.file, name : name, shader : s, inits : convertedInits, watch : null };
		if(sys.FileSystem.exists(s.file)) {
			s.watch = onShaderChanged.bind(s);
			ide.fileWatcher.register(s.file, s.watch);
		}
		shaderCache.set(name, s);
		return s;
	}

	function onShaderChanged( s : CachedShader ) {
		shaderCache.remove(s.name);
		ide.fileWatcher.unregister(s.file, s.watch);
	}

	function loadShaderExpr( name : String, file : String ) : { file : String, expr : hxsl.Ast.Expr } {
		if( file != null && sys.FileSystem.exists(file) )
			return { file : file, expr : loadShaderString(file,sys.io.File.getContent(file), name) };
		var path = name.split(".").join("/")+".hx";
		for( s in shaderPath ) {
			var file = ide.projectDir + "/" + s + "/" + path;
			if( sys.FileSystem.exists(file) )
				return { file : file, expr : loadShaderString(file, sys.io.File.getContent(file), null) };
		}
		if( StringTools.startsWith(name,"h3d.shader.") ) {
			var r = haxe.Resource.getString("shader/" + name.substr(11));
			if( r != null ) return { file : null, expr : loadShaderString(path, r, null) };
		}
		return null;
	}

	function loadShaderString( file : String, content : String, name : String ) {
		var parser = new hscript.Parser();
		var decls = parser.parseModule(content, file);
		var cl = null, cf = null;
		for( d in decls ) {
			switch( d ) {
			case DClass(c) if( name == null || c.name == name.split(".").pop() ):
				for( f in c.fields )
					if( f.name == "SRC" ) {
						cl = c;
						cf = f;
						break;
					}
				if( cf != null )
					break;
			default:
			}
		}
		if( cf == null )
			throw file+" does not contain shader class";

		var expr = switch( cf.kind ) {
		case KVar(v): v.expr;
		default: throw "assert";
		}

		var e = new hscript.Macro({ min : 0, max : 0, file : file }).convert(expr);
		var e = new hxsl.MacroParser().parseExpr(e);
		switch( cl.extend ) {
		case CTPath(p,_):
			var path = p.join(".");
			if( path != "hxsl.Shader" ) {
				var pos = e.pos;
				e = { expr : EBlock([ { expr : ECall( { expr : EIdent("extends"), pos : pos }, [ { expr : EConst(CString(path)), pos : pos } ]), pos : pos }, e]), pos : pos };
			}
		default:
		}
		return e;
	}


}