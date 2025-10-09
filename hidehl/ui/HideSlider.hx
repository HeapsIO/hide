package hidehl.ui;

class HideSlider extends Element {
	public var slider: h2d.Slider;

	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();
		slider = new h2d.Slider(this);
	}

	override function onAfterReflow() {
		slider.width = calculatedWidth;
	}
}