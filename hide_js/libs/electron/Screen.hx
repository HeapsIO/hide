package electron;

typedef Rect = {
	x : Int,
	y : Int,
	width : Int,
	height : Int,
}

typedef IndividualScreen = {
	var id : Int;
	// screen bounds, can be negative depending on screen arrangement
	var bounds : Rect;
	// useable area within the screen bounds
	var work_area : Rect;
	var scaleFactor : Float;
	var isBuiltIn : Bool;
	var rotation : Int;
	var touchSupport : String;
}

class Screen {

	public static var screens(get, never) : Array<IndividualScreen>;

	static function get_screens() : Array<IndividualScreen> {
		return Ipc.call("screen.all");
	}

}
