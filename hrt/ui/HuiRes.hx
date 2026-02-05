package hrt.ui;

#if hui

class HuiRes {
	static public var fs : hxd.fs.EmbedFileSystem;
	static public var loader : hxd.res.Loader;

	public static function init() {
		fs = hxd.fs.EmbedFileSystem.create("res");
		loader = new hxd.res.Loader(fs);
	}
}

#end