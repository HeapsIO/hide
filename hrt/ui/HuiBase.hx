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
		root.interactive.onRelease = (e) -> {
			if(e.button == 1) {
				e.cancel = true;
				e.propagate = false;

				@:privateAccess var popup = new HuiContextMenu(
					[
						{label: "File"},
						{label: "Edit"},
						{label: "Copy", icon: "ui/icons/copy.png"},
						{label: "Paste"},
						{isSeparator: true},
						{label: "Submenu", menu: [
							{label: "Fire"},
							{label: "Water"},
							{label: "Air"},
							{label: "Earth"},
						]},
						{isSeparator: true, label: "Label"},
						{label: "Bar"},
						], {});
				popup.addDismissable(root);
				popup.setPositionAnchor(s2d.mouseX, s2d.mouseY);
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