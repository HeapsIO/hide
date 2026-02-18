package hrt.ui;

#if hui
class HuiIcon extends HuiElement {
	static var SRC = <hui-icon>
	</hui-icon>

	public function new(iconName: String, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.backgroundType = "hui";
		this.huiBg.image = { path: 'ui/icons/${iconName}.png', mode: CssParser.BackgroundImageMode.Fit };
	}
}

#end