package hide.kit;

class Range extends Slider {
	public function new(properties: Properties, parent: Element, id: String, min: Float, max: Float) {
		super(properties, parent, id);
		this.min = min;
		this.max = max;
	}
}