package hide.kit;

class Separator extends Element {
	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-separator");
		if (width != null)
			native.style.setProperty("--width", '$width');
		#else
		throw "todo";
		#end
	}
}