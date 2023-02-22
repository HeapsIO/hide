package hrt.prefab2.vlm;

class SphericalHarmonic {

	public var coefR : Array<Float> = [];
	public var coefG : Array<Float> = [];
	public var coefB : Array<Float> = [];
	public var order : Int;

	public function new(order:Int) {
		this.order = order;
		var coefCount = order * order;
		coefR = [for (value in 0...coefCount) 0];
		coefG = [for (value in 0...coefCount) 0];
		coefB = [for (value in 0...coefCount) 0];
	}
}
