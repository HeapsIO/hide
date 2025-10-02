package hide.kit;

class Range extends Slider {
	public function new(parent: Element, id: String, min: Float, max: Float) {
		super(parent, id);
		this.min = min;
		this.max = max;
	}
}