package hrt.ui;

#if hui

/**
	Don't use directly, use HuiInputBox instead
**/
class HuiText extends h2d.HtmlText #if hui implements h2d.domkit.Object #end {
	/**
		Load a font by a string id instread of a path, allows for automatic font changes based on
		dpi and the breakAll feature
	**/
	@:p public var baseFont(default, set) : String;

	/** Allow breaking lines on every character. Need a baseFont **/
	@:p public var breakAll(default, set) : Bool = false;

	function set_baseFont(v : String) {
		if (v != "none") {
			baseFont = v;
			font = loadFont(v);
		}
		else {
			baseFont = null;
		}
		return v;
	}

	function set_breakAll(v : Bool) {
		breakAll = v;
		set_baseFont(baseFont);
		return breakAll;
	}

	public function new(?text: String, ?parent: h2d.Object) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();
		this.text = text;
		smooth = true;


		// Highlight text



	}

	override function loadFont(name: String) : h2d.Font {
		return loadFontStatic(name, breakAll);
	}

	public static function loadFontStatic(name: String, breakAll: Bool) : h2d.Font {
		var paths = fontPairs.get(name);
		if (paths != null) {
			var index = hrt.ui.HuiBase.highDpi ? 1 : 0;
			return getBitmapFont(paths[index], index, breakAll);
		}
		return hxd.res.DefaultFont.get();
	}

	static var fontPairs: Map<String, Array<String>> = [
		"regular" => ["font/Inter-Regular-cv05-cv08-tnum-13pt.fnt", "font/Inter-Regular-cv05-cv08-tnum-26pt.fnt"],
		"regular-small" => ["font/Inter-Regular-cv05-cv08-tnum-10pt.fnt", "font/Inter-Regular-cv05-cv08-tnum-20pt.fnt"],
		"italic" => ["font/Inter-Italic-cv05-cv08-tnum-13pt.fnt", "font/Inter-Italic-cv05-cv08-tnum-26pt.fnt"],
	];

	static var bitmapFontCache: Map<String, Array<h2d.Font>> = [];
	static function getBitmapFont(path: String, scaleIndex: Int, breakAll: Bool) {
		var fnts = bitmapFontCache.get(path);
		if (fnts == null) {
			fnts = [];
			bitmapFontCache.set(path, fnts);
		}

		var fntIndex = scaleIndex + (breakAll ? 2 : 0);
		var fnt = fnts[fntIndex];
		if (fnt == null) {
			fnt = HuiRes.loader.load(path).to(hxd.res.BitmapFont).toFont().clone();

			if (scaleIndex == 1)
				fnt.resizeTo(hxd.Math.round(fnt.size * 0.5));

			if (breakAll) {
				var original = getBitmapFont(path, scaleIndex, false);
				fnt = original.clone();
				fnt.charset = BreakAllCharset.inst;
			}

			fnts[fntIndex] = fnt;
		}
		return fnt;
	}

	static var _ = {
		h2d.HtmlText.defineDefaultHtmlTag("h", 0x3185ce);
		h2d.HtmlText.defineDefaultHtmlTag("hint", 0x999999, "regular-small");
		0;
	};
}

class BreakAllCharset extends hxd.Charset {
	override function isBreakChar(code) {
		return true;
	}

	public static var inst: BreakAllCharset = new BreakAllCharset();
}
#end
