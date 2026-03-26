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

		makeInteractive();

		onClick = (e) -> {
			if(e.button == 1) {
				e.cancel = true;
				e.propagate = false;

				var submenu: Array<HuiMenu.MenuItem> = [
					{label: "Fire"},
					{label: "Water"},
					{label: "Air"},
				];
				submenu.push({label: "Recursive", menu: submenu});

				var longMenu = [{label: "Lorem"},{label: "proident"},{label: "in"},{label: "quis"},{label: "deserunt"},{label: "magna"},{label: "voluptate"},{label: "sit"},{label: "irure"},{label: "amet"},{label: "deserunt"},{label: "laborum"},{label: "mollit"},{label: "occaecat"},{label: "ullamco"},{label: "id"},{label: "anim"},{label: "reprehenderit"},{label: "laborum"},{label: "aute"},{label: "aliqua"},{label: "minim"},{label: "ea"},{label: "pariatur"},{label: "magna"},{label: "amet"},{label: "cupidatat"},{label: "esse"},{label: "officia"},{label: "ad"},{label: "nostrud"},{label: "labore"},{label: "magna"},{label: "sint"},{label: "proident"},{label: "voluptate"},{label: "ex"},{label: "eiusmod"},{label: "anim"},{label: "et"},{label: "officia"},{label: "quis"},{label: "ullamco"},{label: "nisi"},{label: "id"},{label: "reprehenderit"},{label: "irure"},{label: "deserunt"},{label: "commodo"},{label: "culpa"}];

				var radio = 0;
				contextMenu(
					[
						{label: "File"},
						{label: "Edit"},
						{label: "Copy", icon: "ui/icons/copy.png"},
						{label: "Paste"},
						{label: "Disabled", enabled: false},
						{isSeparator: true},
						{label: "Recmenu", menu: submenu,},
						{label: "LongSubmenu", menu: longMenu},
						{label: "Submenu3", menu: [
							{label: "Fire"},
							{label: "Water"},
							{label: "Air"},
							{label: "Earth"},
						]},
						{isSeparator: true, label: "Label"},
						{label: "Bar"},
						{isSeparator: true, label: "Check"},
						{label: "A", checked: false, stayOpen: true},
						{label: "B", checked: true, stayOpen: true},
						{label: "C", checked: false, stayOpen: true},
						{isSeparator: true, label: "Radio"},
						{label: "A", radio: () -> radio == 0, stayOpen: true, click: () -> radio = 0},
						{label: "B", radio: () -> radio == 1, stayOpen: true, click: () -> radio = 1},
						{label: "C", radio: () -> radio == 2, stayOpen: true, click: () -> radio = 2},
					]);
			}
		}

		onWheel = (e) -> {
			e.propagate = false;
		}

		// var scene = getScene();
		// var commandHandler = new h2d.Interactive(10000,10000);
		// commandHandler.cursor = null;
		// scene.add(commandHandler, 30);
		// commandHandler.propagateEvents = true;
		// commandHandler.onKeyDown = (e) -> {
		// 	trace(commandFocus, e);
		// 	var current = commandFocus;
		// 	while(current != null) {
		// 		if(current.handleCommand(e)) {
		// 			e.propagate = false;
		// 			break;
		// 		}
		// 		current = current.parentElement;
		// 	}
		// };
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

	public function startDragOperation(who: HuiElement, type: String, data: Dynamic) {
		trace("startDragOperation");
		stopDrag();
		currentDrag = @:privateAccess new HuiDragOp(who, type, data);

		rec((e) -> e.onAnyDragStart(currentDrag));

		@:privateAccess getScene().events.startCapture((e) -> {
			e.propagate = true;
			switch(e.kind) {
				case ERelease, EReleaseOutside:
					if (currentDrag.lastOver != null) {
						currentDrag.lastOver.onDrop(currentDrag);
					}
					@:privateAccess getScene().events.stopCapture();
				default:
			}
		}, () -> {
			trace("cancelled");
			stopDrag();
		});
	}

	public function stopDrag() {
		if (currentDrag != null) {
			@:privateAccess currentDrag.lastOver?.onDragOut(currentDrag);
			currentDrag.origin.onDragEnd(currentDrag);
			rec((e) -> e.onAnyDragEnd(currentDrag));
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