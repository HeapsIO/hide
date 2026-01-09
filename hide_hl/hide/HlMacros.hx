package hide;

class HlMacros {
	#if macro
	public static function init() {
		domkit.Macros.registerComponentsPath("hrt.ui.$");

		hscript.LiveClass.enable("hide_hl/api.xml",[".","hide_hl"]);
		domkit.Macros.allowInterp();

		@:privateAccess hide.tools.Macros.includeShaderSources();
	}
	#end
}