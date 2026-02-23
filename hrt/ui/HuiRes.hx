package hrt.ui;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ExprTools;

#if hui

#if !macro
@:build(hrt.ui.HuiRes.loadIcons())
#end
class HuiRes {
	static var RES = "hide_hl/res";
	static var ICONS_PATH = '${RES}/ui/icons';

	#if !macro
	static public var fs : hxd.fs.EmbedFileSystem;
	static public var loader : hxd.res.Loader;

	public static function init() {
		fs = hxd.fs.EmbedFileSystem.create("res");
		loader = new hxd.res.Loader(fs);
	}
	#end

	#if macro
	public static function loadIcons() {
		var buildFields = Context.getBuildFields();
		var icons = sys.FileSystem.readDirectory(sys.FileSystem.fullPath(ICONS_PATH));

		var iconFields: Array<ObjectField> = [];

		for (icon in icons) {
			if (icon.indexOf(".png") < 0 && icon.indexOf(".jpg") < 0)
				continue;
			var p = sys.FileSystem.fullPath('$ICONS_PATH/$icon');
			p = StringTools.replace(p, "\\", "/");
			p = p.substr(p.indexOf(RES) + RES.length + 1);

			var fieldName = icon.substring(0, icon.indexOf("."));
			iconFields.push({
				field: fieldName,
				expr: macro $v{p}
			});
		}

		buildFields.push({
			name: "icons",
			access: [AStatic, APublic],
			kind: FVar(null, macro ${{expr: EObjectDecl(iconFields), pos: Context.currentPos()}}),
			pos: Context.currentPos(),
		});

		return buildFields;
	}
	#end
}
#end