package hide.tools;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
using haxe.macro.ExprTools;

class Macros {

	public static macro function include( packages : Array<String> ) {
		includeShaderSources();
		for( p in packages )
			haxe.macro.Compiler.include(p);
		return macro null;
	}

	#if macro
	static function includeShaderSources() {
		var path = Context.resolvePath("h3d/shader/BaseMesh.hx");
		var dir = new haxe.io.Path(path).dir;
		for( f in sys.FileSystem.readDirectory(dir) )
			if( StringTools.endsWith(f,".hx") )
				Context.addResource("shader/" + f.substr(0, -3), sys.io.File.getBytes(dir + "/" + f));
	}
	#end

}