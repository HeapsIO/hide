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
	public var onKeyDown(default, set) : hxd.Event->Void = emptyFunc;
	public var onKeyUp(default, set) : hxd.Event->Void = emptyFunc;
	public var onTextInput(default, set) : hxd.Event->Void = emptyFunc;
	public var onFocus(default, set) : hxd.Event->Void = emptyFunc;
	public var onFocusLost(default, set) : hxd.Event->Void = emptyFunc;

	public var huiBg(get, never) : HuiBackground;
	public var parentElement(get, never): HuiElement;
	public var childElements(get, never): Array<HuiElement>;
	public var uiBase(get, never) : HuiBase;

	function set_enable(b) {
		if( !b && dom != null )
			dom.hover = dom.active = false;
		if( dom != null )
			dom.toggleClass("disabled", !b);
		return enable = b;
	}

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

	function set_onOut(v) {onOut = v; makeInteractive(); return v;};
	function set_onOver(v) {onOver = v; makeInteractive(); return v;};
	function set_onClick(v) {onClick = v; makeInteractive(); return v;};
	function set_onPush(v) {onPush = v; makeInteractive(); return v;};
	function set_onKeyDown(v) {onKeyDown = v; makeInteractive(); return v;};
	function set_onKeyUp(v) {onKeyUp = v; makeInteractive(); return v;};
	function set_onTextInput(v) {onTextInput = v; makeInteractive(); return v;};
	function set_onFocus(v) {onFocus = v; makeInteractive(); return v;};
	function set_onFocusLost(v) {onFocusLost = v; makeInteractive(); return v;};

	function get_huiBg() : HuiBackground {return Std.downcast(background, HuiBackground);};
	function get_parentElement() : HuiElement {return Std.downcast(parent, HuiElement);};
	function get_childElements() : Array<HuiElement> {return cast children.filter((e) -> Std.downcast(e, HuiElement) != null);};

	function get_uiBase() : HuiBase {
		var p = parent;
		while(p != null) {
			if (Std.downcast(p, HuiBase) != null)
				return cast p;
			p = p.parent;
		}
		return null;
	}


	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
	}

	public function makeInteractive() {
		if (enableInteractive)
			return;
		enableInteractive = true;

		interactive.name = Type.getClassName(Type.getClass(this));

		interactive.onOver = onOverInternal;
		interactive.onOut = onOutInternal;
		interactive.onClick = onClickInternal;
		interactive.onPush = onPushInternal;
		interactive.onRelease = onReleaseInternal;
		interactive.onReleaseOutside = onReleaseOutsideInternal;
		interactive.onKeyDown = onKeyDownInternal;
		interactive.onKeyUp = onKeyUpInternal;
		interactive.onTextInput = onTextInputInternal;
		interactive.onFocus = onFocusInternal;
		interactive.onFocusLost = onFocusLostInternal;
		interactive.enableRightButton = true;
	}

	public function setWidth(v: Int) {
		minWidth = maxWidth = v;
	}

	public function setHeight(v: Int) {
		minHeight = maxHeight = v;
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

	override function makeScrollBar() {
		var bar = new HuiElement();
		bar.dom.addClass("scrollbar");
		@:privateAccess bar.makeInteractive();
		return bar;
	}

	override function makeScrollBarCursor() {
		var cursor = new HuiElement();
		cursor.dom.addClass("cursor");
		@:privateAccess cursor.makeInteractive();
		cursor.interactive.propagateEvents = true;
		return cursor;
	}

	function onOverInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = true;
		onOver(e);
	}

	function onOutInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = false;
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

	function onKeyDownInternal(e: hxd.Event) {
		if (!enable)
			return;

		onKeyDown(e);
	}

	function onKeyUpInternal(e: hxd.Event) {
		if (!enable)
			return;

		onKeyUp(e);
	}

	function onTextInputInternal(e: hxd.Event) {
		if (!enable)
			return;

		onTextInput(e);
	}

	function onFocusInternal(e: hxd.Event) {
		if (!enable) {
			e.cancel = true;
			return;
		}

		onFocus(e);
	}

	function onFocusLostInternal(e: hxd.Event) {
		if (!enable)
			return;

		onFocusLost(e);
	}

	static function emptyFunc(e: hxd.Event) { }
}

#end
