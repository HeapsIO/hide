package hide.kit;

#if domkit

class Block extends Element {
	override function makeSelf() {
		#if js
		native = js.Browser.document.createElement("kit-block");
		#elseif domkit
		native = new hrt.ui.HuiElement();
		#end
	}
}

#end