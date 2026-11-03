package hide;

/**
	Private hide equivalent of hxd.Res for hide resources (bin/res).
	This is needed because hxd.Res uses hxd.res.Loader.currentInstance which is set
	to the hide project res folder, and so we can't access our files from there.
**/
#if !macro
@:build(hxd.res.FileTree.build("bin/res", "hide"))
#end
class HideRes {
	#if !macro
	static public var fs : hxd.fs.FileSystem;
	static public var loader : hxd.res.Loader;

	public static function init() {
		fs = new hxd.fs.LocalFileSystem(js.Node.__dirname + "/res", "");
		loader = new hxd.res.Loader(fs);
	}
	#end
}
