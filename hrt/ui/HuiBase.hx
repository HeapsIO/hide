package hrt.ui;

#if hui

class HuiBase {
	static var inst: HuiBase;

	var s2d: h2d.Scene;
	var root : h2d.Flow;
	public var rootOverlay : h2d.Flow;
	var style : h2d.domkit.Style;

	var layers : Array<h2d.Flow>;

	public function new(s2d: h2d.Scene) {
		inst = this;
		this.s2d = s2d;
		root = new h2d.Flow();
		root.dom = domkit.Properties.create("flow", root, {"id": "root"});
		root.fillWidth = root.fillHeight = true;

		rootOverlay = new h2d.Flow();
		style = new h2d.domkit.Style();

		style.allowInspect = true;

		loadStyle();

		style.addObject(root);
		s2d.add(root);

		var mainLayout = new HuiMainLayout(root);

		root.enableInteractive = true;
		root.interactive.enableRightButton = true;
		root.interactive.onClick = (e) -> {
			if(e.button == 1) {
				e.cancel = true;
				e.propagate = false;

				var submenu: Array<HuiContextMenu.MenuItem> = [
					{label: "Fire"},
					{label: "Water"},
					{label: "Air"},
				];
				submenu.push({label: "Recursive", menu: submenu});

				var longMenu = [{label: "Lorem"},{label: "proident"},{label: "in"},{label: "quis"},{label: "deserunt"},{label: "magna"},{label: "voluptate"},{label: "sit"},{label: "irure"},{label: "amet"},{label: "deserunt"},{label: "laborum"},{label: "mollit"},{label: "occaecat"},{label: "ullamco"},{label: "id"},{label: "anim"},{label: "reprehenderit"},{label: "laborum"},{label: "aute"},{label: "aliqua"},{label: "minim"},{label: "ea"},{label: "pariatur"},{label: "magna"},{label: "amet"},{label: "cupidatat"},{label: "esse"},{label: "officia"},{label: "ad"},{label: "nostrud"},{label: "labore"},{label: "magna"},{label: "sint"},{label: "proident"},{label: "voluptate"},{label: "ex"},{label: "eiusmod"},{label: "anim"},{label: "et"},{label: "officia"},{label: "quis"},{label: "ullamco"},{label: "nisi"},{label: "id"},{label: "reprehenderit"},{label: "irure"},{label: "deserunt"},{label: "commodo"},{label: "culpa"}];

				var radio = 0;
				@:privateAccess var popup = new HuiContextMenu(
					[
						{label: "File"},
						{label: "Edit"},
						{label: "Copy", icon: "ui/icons/copy.png"},
						{label: "Paste"},
						{label: "Paste"},
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
					], {});
				popup.addDismissable(root);
				popup.anchor = Point(s2d.mouseX, s2d.mouseY);
			}
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
	}
}

#end