class Main extends hxd.App {

	override function init() {
		var resource = hxd.Res.test;
		var template = resource.load();
		var cache = @:privateAccess hxd.res.Loader.currentInstance.cache;
		trace(cache);
		trace(template);
		var cloned = template.make(s3d);
		var box = cloned.find(hrt.prefab.l3d.Box);
		box.name += "Changed";
	}

	static function main() {
		hxd.Res.initEmbed();
		new Main();
	}
}
