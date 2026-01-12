package hide;

class HlMacros {
	#if macro
	var parser : hrt.ui.CssParser;

	public static function init() {
		domkit.Macros.registerComponentsPath("hrt.ui.$");
		domkit.Macros.setDefaultParser("hrt.ui.CssParser");

		hscript.LiveClass.enable("hide_hl/api.xml",[".","hide_hl"]);
		domkit.Macros.allowInterp();

		@:privateAccess hide.tools.Macros.includeShaderSources();
	}
	#end
}