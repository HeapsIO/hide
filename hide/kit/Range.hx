package hide.kit;

#if domkit

class Range<T:Float> extends Slider<T> {
	public function new(parent: Element, id: String, min: Float, max: Float) {
		super(parent, id);
		this.min = cast min;
		this.max = cast max;
		this.showRange = true;
	}
}

#end