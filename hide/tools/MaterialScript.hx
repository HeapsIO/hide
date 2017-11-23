package hide.tools;

class RendererScript extends h3d.scene.Renderer {

	var callb : Dynamic;
	var hasError = false;

	public function new(callb:Dynamic) {
		super();
		this.callb = callb;
	}

	override function render() {
		if( hasError ) {
			callb();
			return;
		}
		try {
			callb();
		} catch( e : hscript.Expr.Error ) {
			hasError = true;
			hide.ui.Ide.inst.error(hscript.Printer.errorToString(e));
		}
	}

}

class MaterialScript extends h3d.mat.MaterialScript {

	var ide : hide.ui.Ide;

	public function new() {
		super(); // name will be set by script itself
		ide = hide.ui.Ide.inst;
	}

	function loadModule( path : String ) : Dynamic {
		var fullPath = ide.getPath(path);
		var script = try sys.io.File.getContent(fullPath) catch( e : Dynamic ) throw "File not found " + path;
		var parser = new hscript.Parser();
		parser.preprocesorValues.set("script", true);
		var decls = try parser.parseModule(script, path) catch( e : hscript.Expr.Error ) { onError(Std.string(e) + " line " + parser.line); return null; }
		var objs : Dynamic = {};
		for( d in decls )
			switch( d ) {
			case DClass(c):
				Reflect.setField(objs, c.name, makeClass.bind(c));
			default:
			}
		return objs;
	}

	function makeClass( c : hscript.Expr.ClassDecl, ?args : Array<Dynamic> ) {
		var interp = new Interp();
		var obj = null;
		if( c.extend != null )
			switch( c.extend ) {
			case CTPath(["h3d", "scene", "Renderer"], _):
				obj = function() return new RendererScript(interp.variables.get("render"));
				interp.shareEnum(hxsl.Output);
				interp.shareEnum(h3d.impl.Driver.Feature);
				interp.shareEnum(h3d.mat.Data.Wrap);
				interp.shareEnum(h3d.mat.BlendMode);
			default:
			}
		if( obj == null )
			throw "Don't know what to do with " + c.name;

		interp.variables.set("loadShader", function(name) return ide.shaderLoader.load(name));

		var debug = true;
		interp.variables.set("loadTexture", function(name) return {
			if( debug ) {
				trace("TODO:" + name);
				debug = false;
			}
			return h3d.mat.Texture.fromColor(0);
		});

		for( f in c.fields )
			switch( f.kind ) {
			case KVar(v):
				interp.variables.set(f.name, v.expr == null ? null : @:privateAccess interp.exprReturn(v.expr));
			case KFunction(fd):
				var ed : hscript.Expr.ExprDef = EFunction(fd.args, fd.expr, f.name, fd.ret);
				var e = #if hscriptPos { pmin : 0, pmax : 0, origin : null, line : 0, e : ed } #else ed #end;
				interp.variables.set(f.name, @:privateAccess interp.exprReturn(e));
			default:
			}


		// share functions
		var obj = obj();
		interp.shareObject(obj);
		interp.variables.set("super", obj);
		interp.variables.set("this", obj);

		var fnew = interp.variables.get("new");
		if( fnew != null ) Reflect.callMethod(null, fnew, args == null ? [] : args);
		return obj;
	}

}