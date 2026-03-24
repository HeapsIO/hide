package hide.kit;

#if domkit

class Separator extends Element {
	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-separator");
		if (width != null)
			native.get().style.setProperty("--width", '$width');
		#elseif hui
		native = new hrt.ui.HuiSeparator();
		#end
	}
}

#end