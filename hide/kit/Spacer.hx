package hide.kit;

#if domkit

class Spacer extends Element {
	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-spacer");
		if (width != null)
			native.get().style.setProperty("--width", '$width');
		#elseif hui
		native = new hrt.ui.HuiSpacer();
		#end
	}
}

#end