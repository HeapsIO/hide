package hrt.ui;

#if hui

@:parser(hrt.ui.CssParser)
class HuiElement extends h2d.Flow #if hui implements h2d.domkit.Object #end {
	static var SRC =
		<hui-element>
		</hui-element>


	@:p public var enable(default, set) : Bool = true;
	@:p(bgType) var backgroundType(default, set) : String;
	@:p var saveDisplayKey(default, set): String;
	@:p public var displayName: String;

	public var onOut(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onOver(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onMove(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onClick(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onPush(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onRelease(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onKeyDown(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onKeyUp(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onTextInput(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onFocus(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onFocusLost(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onWheel(default, set) : hxd.Event->Void = emptyFuncEventVoid;
	public var onDoubleClick(default, set) : hxd.Event->Void = null;
	@:p public var propagateEvents(get, set): Bool;

	public var onChildrenChanged : Void -> Void = emtpyFuncVoidVoid;

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

	function set_saveDisplayKey(v: String) : Dynamic {
		if (v == saveDisplayKey)
			return v;
		saveDisplayKey = v;
		onLoadState();
		return saveDisplayKey;
	}

	function set_onOut(v) {onOut = v; makeInteractive(); return v;};
	function set_onOver(v) {onOver = v; makeInteractive(); return v;};
	function set_onMove(v) {onMove = v; makeInteractive(); return v;};
	function set_onClick(v) {onClick = v; makeInteractive(); return v;};
	function set_onPush(v) {onPush = v; makeInteractive(); return v;};
	function set_onRelease(v) {onRelease = v; makeInteractive(); return v;};
	function set_onKeyDown(v) {onKeyDown = v; makeInteractive(); return v;};
	function set_onKeyUp(v) {onKeyUp = v; makeInteractive(); return v;};
	function set_onTextInput(v) {onTextInput = v; makeInteractive(); return v;};
	function set_onFocus(v) {onFocus = v; makeInteractive(); return v;};
	function set_onFocusLost(v) {onFocusLost = v; makeInteractive(); return v;};
	function set_onWheel(v) {onWheel = v; makeInteractive(); return v;};
	function set_onDoubleClick(v) {onDoubleClick = v; makeInteractive(); return v;};

	function get_propagateEvents() {return interactive?.propagateEvents;}
	function set_propagateEvents(v) {makeInteractive(); return interactive.propagateEvents = v;};

	override function set_overflow(v) {
		if (v == h2d.Flow.FlowOverflow.Scroll) {
			makeInteractive();
		}
		return super.set_overflow(v);
	}

	function get_huiBg() : HuiBackground {return Std.downcast(background, HuiBackground);};
	function get_parentElement() : HuiElement {return Std.downcast(parent, HuiElement);};
	function get_childElements() : Array<HuiElement> {return cast children.filter((e) -> Std.downcast(e, HuiElement) != null);};

	function get_uiBase() : HuiBase {
		var p : h2d.Object = this;
		while(p != null) {
			if (Std.downcast(p, HuiBase) != null)
				return cast p;
			p = p.parent;
		}
		return null;
	}

	var lastClickTime : Float = 0;

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
		interactive.onMove = onMoveInternal;
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

	/**
		Override this to load data with "getDisplayState". It will be
		called when saveDisplayKey is properly initialized
	**/
	function onLoadState() {

	}

	override function addChildAt(s:h2d.Object, pos:Int) {
		super.addChildAt(s, pos);
		onChildrenChanged();
	}

	override function removeChild(s:h2d.Object) {
		super.removeChild(s);
		onChildrenChanged();
	}

	function removeChildElements() {
		for (child in childElements) {
			if (child.dom.hasClass("scrollbar"))
				continue;
			removeChild(child);
		}
	}

	function saveDisplayState(key: String, value : Dynamic) : Void {
		if (saveDisplayKey == null)
			return;

		hide.Ide.inst.saveLocalStorage(saveDisplayKey + "/" + key, value);
	}

	function getDisplayState(key: String, def: Dynamic) : Dynamic {
		if (saveDisplayKey == null)
			return def;

		return hide.Ide.inst.getLocalStorage(saveDisplayKey + "/" + key) ?? def;
	}

	function clearDisplayState(key: String) : Void {
		if (saveDisplayKey == null)
			return;

		hide.Ide.inst.clearLocalStorage(saveDisplayKey + "/" + key);
	}

	function getDisplayName() : String {
		return displayName ?? toString();
	}


	function onOverInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = true;
		e.propagate = true;
		onOver(e);
	}

	function onOutInternal(e: hxd.Event) {
		if (!enable)
			return;
		dom.hover = false;
		e.propagate = true;
		onOut(e);
	}

	function onMoveInternal(e: hxd.Event) {
		if (!enable)
			return;

		onMove(e);
	}

	function onClickInternal(e: hxd.Event) {
		if (!enable)
			return;

		if (onDoubleClick != null) {
			var time = haxe.Timer.stamp();
			if (time - lastClickTime < 0.5) {
				onDoubleClick(e);
				lastClickTime = time;
				return;
			}
			lastClickTime = time;
		}

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
		onRelease(e);
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

	override function onMouseWheel(e: hxd.Event) {
		if (!enable)
			return;

		var base = uiBase;
		var now = haxe.Timer.stamp();

		if (base.lastScrollTime + 0.35 < now) {
			uiBase.scrollFocus = null;
		}

		if( overflow == Scroll && (base.scrollFocus == null || base.scrollFocus == this) ) {

			var maxScroll = Std.int(contentHeight - calculatedHeight);
			var newPos = hxd.Math.clamp(scrollPosY + e.wheelDelta * scrollWheelSpeed, 0, maxScroll);

			if (newPos != scrollPosY) {
				scrollPosY = newPos;

				// only take focus if we actually did scroll
				uiBase.scrollFocus = this;
				base.lastScrollTime = now;
			}
			e.propagate = uiBase.scrollFocus == null;
		}

		onWheel(e);
	}

	static function emptyFuncEventVoid(e: hxd.Event) { }
	static function emtpyFuncVoidVoid() {}
}

#end
