package hide.tools;

#if shiro

// See `shiro/tools/rscript/remote-script.md`
class RemoteApi extends shiro.tools.rscript.RemoteApi {

	override function getPort() : Int {
		var args = Sys.args();
		var i = args.indexOf("--scriptport");
		return i < 0 ? shiro.tools.rscript.RemoteApi.DEFAULT_PORT : Std.parseInt(args[i + 1]);
	}

	override function isReady() {
		return app?.ui != null && hxd.Timer.frameCount >= 5;
	}

	override function getS2d() return app?.s2d;

	override function getClasses() : Map<String, Dynamic> {
		return [
			"Ide" => hide.Ide, "App" => hide.App,
		];
	}

	// ----- Globals -----

	public var ide(get, never) : hide.Ide;
	function get_ide() return hide.Ide.inst;

	public var app(get, never) : hide.App;
	function get_app() return hide.Ide.inst?.app;
}

#end
