package hrt.ui;

#if hui
class HuiIcon extends HuiElement {
	static var SRC = <hui-icon>
	</hui-icon>

	public function new(img : hxd.res.Image, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.backgroundType = "hui";
		setIcon(img);
	}

	public function setIcon(img : hxd.res.Image) {
		if (img == null)
			return;
		var localEntry = Std.downcast(img.entry, hxd.fs.LocalFileSystem.LocalEntry);
		if (localEntry == null)
			return;
		this.huiBg.image = { path: @:privateAccess localEntry.relPath, mode: CssParser.BackgroundImageMode.Fit };
	}
}

#end