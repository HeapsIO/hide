package hrt.ui;

#if hui

/**
	Don't use directly, use HuiInputBox instead
**/
class HuiText extends h2d.HtmlText #if hui implements h2d.domkit.Object #end {
	@:p public var baseFont(never, set) : String;

	function set_baseFont(v : String) {
		font = loadFont(v);
		return v;
	}

	public function new(?text: String, ?parent: h2d.Object) {
		super(hxd.res.DefaultFont.get(), parent);
		initComponent();
		this.text = text;
		smooth = true;


		// Highlight text
		defineHtmlTag("h", 0x3185ce);
	}

	override function loadFont(name: String) : h2d.Font {
		return loadFontStatic(name);
	}

	public static function loadFontStatic(name: String) : h2d.Font {
		var paths = fontPairs.get(name);
		if (paths != null) {
			var index = hrt.ui.HuiBase.highDpi ? 1 : 0;
			return getBitmapFont(paths[index], index);
		}
		return hxd.res.DefaultFont.get();
	}

	static var fontPairs: Map<String, Array<String>> = [
		"regular" => ["font/Inter-Regular-cv05-cv08-tnum-13pt.fnt", "font/Inter-Regular-cv05-cv08-tnum-26pt.fnt"],
		"regular-small" => ["font/Inter-Regular-cv05-cv08-tnum-10pt.fnt", "font/Inter-Regular-cv05-cv08-tnum-20pt.fnt"],
		"italic" => ["font/Inter-Italic-cv05-cv08-tnum-13pt.fnt", "font/Inter-Italic-cv05-cv08-tnum-26pt.fnt"],
	];

	static var bitmapFontCache: Map<String, Array<h2d.Font>> = [];
	static function getBitmapFont(path: String, scaleIndex: Int) {
		var fnts = bitmapFontCache.get(path);
		if (fnts == null) {
			fnts = [];
			bitmapFontCache.set(path, fnts);
		}

		var fnt = fnts[scaleIndex];
		if (fnt == null) {
			fnt = HuiRes.loader.load(path).to(hxd.res.BitmapFont).toFont().clone();

			if (scaleIndex == 1)
				fnt.resizeTo(hxd.Math.round(fnt.size * 0.5));

			fnts[scaleIndex] = fnt;
		}
		return fnt;
	}
}
#end
