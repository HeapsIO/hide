package hrt.ui;

#if hui

@:parser(hrt.ui.CssParser)

class HuiElement extends h2d.Flow #if hui implements h2d.domkit.Object #end {
	static var SRC =
		<hui-element>
		</hui-element>

	@:p public var enable(default, set) : Bool = true;
	@:p(bgType) var backgroundType(default, set) : String;

	public var onOut(default, set) : hxd.Event->Void = emptyFunc;
	public var onOver(default, set) : hxd.Event->Void = emptyFunc;
	public var onClick(default, set) : hxd.Event->Void = emptyFunc;
	public var onPush(default, set) : hxd.Event->Void = emptyFunc;

	public var huiBg(get, never) : HuiBackground;

	function set_enable(b) {
		if( !b && dom != null )
			dom.hover = dom.active = false;
		if( dom != null )
			dom.toggleClass("disabled", !b);
		return enable = b;
	}

	function set_onOut(v) {onOut = v; makeInteractive(); return v;};
	function set_onOver(v) {onOver = v; makeInteractive(); return v;};
	function set_onClick(v) {onClick = v; makeInteractive(); return v;};
	function set_onPush(v) {onPush = v; makeInteractive(); return v;};

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

	function get_huiBg() : HuiBackground {return Std.downcast(background, HuiBackground);};

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}

	public function makeInteractive() {
		if (enableInteractive)
			return;
		enableInteractive = true;
		interactive.onOver = onOverInternal;
		interactive.onOut = onOutInternal;
		interactive.onClick = onClickInternal;
		interactive.onPush = onPushInternal;
		interactive.onRelease = onReleaseInternal;
		interactive.onReleaseOutside = onReleaseOutsideInternal;
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

	function onOverInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = true;
		trace("hover in", this);
		onOver(e);
	}

	function onOutInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = false;
		trace("hover out", this);

		onOut(e);
	}

	function onClickInternal(e: hxd.Event) {
		if (!enable)
			return;
		onClick(e);
	}

	function onPushInternal(e: hxd.Event) {
		if (!enable)
			return;

		dom.active = true;
		onPush(e);
	}

	function onReleaseInternal(e: hxd.Event) {
		if (!enable)
			return;

		dom.active = false;
	}

	function onReleaseOutsideInternal(e: hxd.Event) {
		if (!enable)
			return;

		dom.active = false;
	}

	static function emptyFunc(e: hxd.Event) { }
}

#end
