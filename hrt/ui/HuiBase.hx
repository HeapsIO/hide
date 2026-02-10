package hrt.ui;

#if hui

class HuiBase extends HuiElement {
	public var rootOverlay : h2d.Flow;
	public var app(default, null): hide.App;
	public var style : h2d.domkit.Style;

	var layers : Array<h2d.Flow>;
	var currentMenu: HuiMenu;
	public var mainLayout: HuiMainLayout;

	// Keep track of the element that currently own the scroll event.
	// Reset when lastScrollTime is too old compared to now (inspired by the same behavior in google chrome)
	@:allow(hrt.ui.HuiElement) var scrollFocus: HuiElement;
	@:allow(hrt.ui.HuiElement) var lastScrollTime: Float;

	public function new(app: hide.App, ?parent: h2d.Object) {
		this.app = app;
		super(parent);
		initComponent();

		rootOverlay = new h2d.Flow();
		style = new h2d.domkit.Style();

		if (hide.App.DEBUG) {
			style.allowInspect = true;
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
	}

	public function contextMenu(items: Array<hrt.ui.HuiMenu.MenuItem>) {
		openMenu(items, {}, {object: Point(getScene().mouseX, getScene().mouseY), directionX: EndOutside, directionY: EndOutside});
	}

	public function openMenu(items: Array<hrt.ui.HuiMenu.MenuItem>, options: hrt.ui.HuiMenu.MenuOptions, ?anchor: hrt.ui.HuiPopup.Anchor) : HuiMenu {
		if (currentMenu != null)
			currentMenu.close();

		var menu = new HuiMenu(items, options);
		menu.addDismissable(this);
		menu.anchor = anchor;
		currentMenu = menu;
		menu.onCloseListeners.push(() -> if (menu == currentMenu) currentMenu = null);

		return currentMenu;
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
	}
}

#end