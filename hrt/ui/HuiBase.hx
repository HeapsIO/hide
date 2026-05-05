package hrt.ui;

#if hui

@:allow(hrt.ui.HuiElement)
class HuiBase extends HuiElement {
	public var app(default, null): hide.App;
	public var style : h2d.domkit.Style;

	var layers : Array<h2d.Flow>;
	var currentMenu: HuiMenu;
	public var mainLayout: HuiMainLayout;
	var commandFocus: HuiElement;

	var checkedCommandEvents: Map<hxd.Event, Bool> = [];

	var previousUiScale: Float = 0;

	var startDragX : Float = hxd.Math.NaN;
	var startDragY : Float = hxd.Math.NaN;
	var currentDrag: HuiDragOp = null;

	static final dragDistanceThreshold = 5.0;

	// Keep track of the element that currently own the scroll event.
	// Reset when lastScrollTime is too old compared to now (inspired by the same behavior in google chrome)
	@:allow(hrt.ui.HuiElement) var scrollFocus: HuiElement;
	@:allow(hrt.ui.HuiElement) var lastScrollTime: Float;

	public static var cursorForbidden : hxd.Cursor;

	public function new(app: hide.App, ?parent: h2d.Object) {
		this.app = app;
		super(parent);
		initComponent();

		style = new h2d.domkit.Style();

		if (hide.App.DEBUG) {
			style.allowInspect = true;
			style.inspectKeyCode = hxd.Key.SHIFT;
		}

		loadStyle();

		style.addObject(this);

		mainLayout = new HuiMainLayout(this);

		cursorForbidden = hxd.Cursor.Custom(new hxd.Cursor.CustomCursor([HuiRes.loader.load("ui/cursors/forbidden.png").toImage().toBitmap()], 0, 12, 12));

		makeInteractive();

		onWheel = (e) -> {
			e.propagate = false;
		}
	}

	/**
		Try to get the HuiBase for a given h2d object by searching if one of it's parent is a HuiBase.
		Should only be used with element that can't inherit from HuiElement (because they need to inherit another h2d base class).
		For HuiElements, see uiBase
	**/
	public static function get(object: h2d.Object) {
		var current = object;
		while (current != null) {
			var base = Std.downcast(current, HuiBase);
			if (base != null)
				return base;
			current = current.parent;
		}
		return null;
	}

	public function contextMenu(items: Array<hrt.ui.HuiMenu.MenuItem>) {
		openMenu(items, {}, {object: Point(getScene().mouseX, getScene().mouseY), directionX: EndOutside, directionY: EndOutside});
	}

	public function addPopup(popup: HuiPopup, ?anchor: hrt.ui.HuiPopup.Anchor) {
		popup.anchor = anchor;
		@:privateAccess popup.addDismissable(this);
	}

	public function confirm(message: String, ?buttons: hrt.ui.HuiConfirmPopup.ConfirmButtons, onCompletion: hrt.ui.HuiConfirmPopup.ConfirmButton -> Void) {
		var popup = new hrt.ui.HuiConfirmPopup(message, buttons, onCompletion);
		@:privateAccess popup.addModal(this);
	}

	public function openMenu(items: Array<hrt.ui.HuiMenu.MenuItem>, options: hrt.ui.HuiMenu.MenuOptions, ?anchor: hrt.ui.HuiPopup.Anchor) : HuiMenu {
		if (currentMenu != null)
			currentMenu.close();

		var menu = new HuiMenu(items, options);
		addPopup(menu, anchor);
		currentMenu = menu;
		menu.onCloseListeners.push(() -> if (menu == currentMenu) currentMenu = null);

		menu.interactive.focus();

		return currentMenu;
	}

	/**
		Check if event triggers a event if object is the currently focused object in the h2d scene.
		Return true if the event has been handled by a registered command
	**/
	public function checkCommand(event: hxd.Event, object: h2d.Object) : Bool {
		if (checkedCommandEvents.exists(event)) {
			return false;
		}
		checkedCommandEvents.set(event, true);
		var current = object;
		while(current != null) {
			var element = Std.downcast(current, HuiElement);
			if (element != null && element.registeredCommands != null) {
				for (command in element.registeredCommands) {
					if (command.context == ElementAndChildren || (current == object && command.context == Element)) {
						if (command.command.check(event)) {
							event.propagate = false;
							command.callback();
							if (!event.propagate) {
								return true;
							}
						}
					}
				}
			}
			current = current.parent;
		}
		return false;
	}

	/**
		Check if event triggers a event if object is the currently focused object in the h2d scene.
		Return true if the event has been handled by a registered command
	**/
	public function checkCommand2(toCheck: hrt.ui.HuiCommands.HuiCommand, object: h2d.Object) : Bool {
		var current = object;
		while(current != null) {
			var element = Std.downcast(current, HuiElement);
			if (element != null && element.registeredCommands != null) {
				for (command in element.registeredCommands) {
					if (command.context == ElementAndChildren || (current == object && command.context == Element)) {
						if (command.command == toCheck) {
							command.callback();
							return true;
						}
					}
				}
			}
			current = current.parent;
		}
		return false;
	}

	public function startDragOperation(who: HuiElement, type: String, data: Dynamic) : HuiDragOp {
		stopDrag();
		currentDrag = @:privateAccess new HuiDragOp(who, type, data);
		currentDrag.base = this;

		rec((e) -> e.onAnyDragStart(currentDrag));

		@:privateAccess getScene().events.startCapture((e) -> {
			e.propagate = true;
			switch(e.kind) {
				case ERelease, EReleaseOutside:
					if (currentDrag.lastOver != null) {
						currentDrag.event = e;
						var oldX = e.relX;
						var oldY = e.relY;
						var scale = getScene().viewportScaleX;

						e.relX = e.relX / scale - currentDrag.lastOver.absX;
						e.relY = e.relY / scale - currentDrag.lastOver.absY;
						currentDrag.lastOver.onDrop(currentDrag);
						e.relX = oldX;
						e.relY = oldY;
						currentDrag.event = null;
					}
					@:privateAccess getScene().events.stopCapture();
				case EMove:
					if (currentDrag.previewWidget != null) {
						currentDrag.updatePreviewPos(e.relX, e.relY);
					}
				default:
			}
		}, () -> {
			trace("cancelled");
			stopDrag();
		});

		return currentDrag;
	}

	public function stopDrag() {
		if (currentDrag != null) {
			@:privateAccess currentDrag.lastOver?.onDragOut(currentDrag);
			currentDrag.origin.onDragEnd(currentDrag);
			rec((e) -> e.onAnyDragEnd(currentDrag));
			currentDrag.dispose();
			currentDrag = null;
		}
	}


	function loadStyle() {
		#if !js
		style.loadComponents("ui/style",[hxd.Res.ui.style.common]);
		#if !release
		style.watchInterpComponents();
		#end
		#end
	}

	public function updateStyle(dt: Float) {
		style.sync(dt);
		checkedCommandEvents.clear();

		var wantedCursor : hxd.Cursor = null;

		if (currentDrag != null) {
			if (currentDrag.lastOver == null)
				wantedCursor = cursorForbidden;
		}

		if (interactive.cursor != wantedCursor) {
			interactive.cursor = wantedCursor;
		}

		// HiDPI support for hldx targets
		#if hldx
		var monitorDx = @:privateAccess hxd.Window.getInstance().window.getCurrentMonitor();
		var monitors = hxd.Window.getMonitors();

		if (monitorDx != null) {
			var scene = getScene();
			var monitor = Lambda.find(monitors, (m) -> m.name == monitorDx);
			if (monitor != null) {
				// snap to 0.5
				var upscale = hxd.Math.round((monitor.height / 1080.0) * 2.0) / 2.0;

				upscale = hxd.Math.max(upscale, 1.0);

				if (previousUiScale != upscale) {
					previousUiScale = upscale;
					dom.toggleClass("high-dpi", upscale > 1.0);
				}
				var engine = scene.renderer.engine;
				scene.scaleMode = Fixed(Math.ceil(engine.width / upscale), Math.ceil(engine.height / upscale), upscale, Center, Center);
			}
		}
		#end
	}
}

#end