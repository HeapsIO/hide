package nw;

typedef IndividualScreen = {
    var id : Int;

    // physical screen resolution, can be negative, not necessarily start from 0,depending on screen arrangement
    var bounds : {
        x : Int,
        y : Int,
        width : Int,
        height : Int,
    };
    // useable area within the screen bound
    var work_area : {
        x : Int,
        y : Int,
        width : Int,
        height : Int,
    };
    var scaleFactor : Float;
    var isBuiltIn : Bool;
    var rotation : Int;
    var touchSupport : Int;
}

extern class Screen {
	public static var screens(default, never) : Array<IndividualScreen>;
	public static function Init() : Void;
	public static function on( event : String, callb : IndividualScreen -> Void ) : Void;
	public static function chooseDesktopMedia(sources : Array<String>, callb : Dynamic -> Void) : Void;

}