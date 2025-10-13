package hide.kit;

class Block extends Element {
	override function makeSelf() {
		#if js
		native = js.Browser.document.createElement("kit-block");
		#else
		native = new hidehl.ui.Element();
		#end
	}
}