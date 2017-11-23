package hide.tools;

class ShaderLoader {

	var ide : hide.ui.Ide;
	var shaderPath : Array<String>;
	var shaderCache = new Map<String, hxsl.SharedShader>();

	public function new() {
		ide = hide.ui.Ide.inst;
		shaderPath = ide.currentProps.get("haxe.classPath");
	}

	public function load( name : String ) {
		var s = loadSharedShader(name);
		if( s == null )
			return null;
		return new hxsl.DynamicShader(s);
	}

	function loadSharedShader( name : String ) {
		var s = shaderCache.get(name);
		if( s != null )
			return s;
		var e = loadShaderExpr(name);
		if( e == null )
			return null;
		var chk = new hxsl.Checker();
		chk.loadShader = function(iname) {
			var e = loadShaderExpr(iname);
			if( e == null )
				throw "Could not @:import " + iname + " (referenced from " + name+")";
			return e;
		};
		var s = new hxsl.SharedShader("");
		s.data = chk.check(name, e);
		@:privateAccess s.initialize();
		shaderCache.set(name, s);
		return s;
	}

	function loadShaderExpr( name : String ) : hxsl.Ast.Expr {
		var path = name.split(".").join("/")+".hx";
		for( s in shaderPath ) {
			var file = ide.projectDir + "/" + s + "/" + path;
			if( sys.FileSystem.exists(file) )
				return loadShaderString(file,sys.io.File.getContent(file));
		}
		if( StringTools.startsWith(name,"h3d.shader.") ) {
			var r = haxe.Resource.getString("shader/" + name.substr(11));
			if( r != null ) return loadShaderString(path, r);
		}
		return null;
	}

	function loadShaderString( file : String, content : String ) {
		var parser = new hscript.Parser();
		var decls = parser.parseModule(content, file);
		var cl = null, cf = null;
		for( d in decls ) {
			switch( d ) {
			case DClass(c):
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