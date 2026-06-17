package hrt.ui;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ExprTools;

/**
	Private hide equivalent of hxd.Res for hide_hl resources.
	This is needed because hxd.Res uses hxd.res.Loader.currentInstance which is set
	to the hide project res folder, and so we can't access our files from there.
**/
#if !macro
@:build(hxd.res.FileTree.build("hide_hl/res"))
#end
class HuiRes {
	static var RES = "hide_hl/res";
	static var ICONS_PATH = '${RES}/ui/icons';

	#if !macro
	static public var fs : hxd.fs.FileSystem;
	static public var loader : hxd.res.Loader;

	public static function init() {
		//fs = hxd.fs.EmbedFileSystem.create("res");
		fs = new hxd.fs.LocalFileSystem(RES, "");
		loader = new hxd.res.Loader(fs);
	}
	#end
}