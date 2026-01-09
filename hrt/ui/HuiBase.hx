package hrt.ui;

#if domkit

class HuiBase {
	static var inst: HuiBase;

	var s2d: h2d.Scene;
	var root : h2d.Flow;
	var style : h2d.domkit.Style;

	public function new(s2d: h2d.Scene) {
		inst = this;
		this.s2d = s2d;
		root = new h2d.Flow();
		root.dom = domkit.Properties.create("flow", root, {"class": "root"});
		root.fillWidth = root.fillHeight = true;

		style = new h2d.domkit.Style();

		style.allowInspect = true;

		loadStyle();

		style.addObject(root);
		s2d.add(root);

		var mainLayout = new HuiMainLayout(root);
		style.addObject(mainLayout);
	}

	function loadStyle() {
		#if !js
		style.loadComponents("ui/style",[hxd.Res.ui.style.common]);
		#if !release
		style.watchInterpComponents();
		#end
		#end
	}
}

#end