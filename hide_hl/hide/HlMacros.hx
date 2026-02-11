package hide;

class HlMacros {
	#if macro
	// needed ref for macro compilation
	var parser : hrt.ui.CssParser;

	public static function init() {
		#if hui
		domkit.Macros.registerComponentsPath("hrt.ui.$");
		domkit.Macros.setDefaultParser("hrt.ui.CssParser");

		hscript.LiveClass.enable("hide_hl/api.xml",[".","hide_hl"]);
		domkit.Macros.allowInterp();
		#end

		@:privateAccess hide.tools.Macros.includeShaderSources();
	}
	#end
}