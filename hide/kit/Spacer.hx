package hide.kit;

#if domkit

class Spacer extends Element {
	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-spacer");
		if (width != null)
			native.style.setProperty("--width", '$width');
		#else
		throw "todo";
		#end
	}
}

#end