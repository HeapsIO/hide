package hrt.ui;

#if hui

@:parser(hrt.ui.CssParser)

class HuiElement extends h2d.Flow #if hui implements h2d.domkit.Object #end {
	static var SRC =
		<hui-element>
		</hui-element>

	@:p(bgType) var backgroundType(default, set) : String;

	function set_backgroundType(v) {
		if (backgroundType == v)
			return v;
		backgroundType = v;
		var prevTile = backgroundTile;
		var built = false;
		if (background != null) {
			background.remove();
			background = null;  // Needed, see addChildAt
			if (prevTile != null) {
				backgroundTile = prevTile;
				built = true;
			}
		}
		if (v == "hui" && !built)
			buildBackground(backgroundTile);
		return v;
	}

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}

	override function makeBackground(tile): h2d.ScaleGrid {
		switch (backgroundType) {
			case "hui":
				var b = new HuiBackground();
				b.dom = domkit.Properties.create("hui-background", b);
				return b;
			default:
				return super.makeBackground(tile);
		}
	}
}

#end
