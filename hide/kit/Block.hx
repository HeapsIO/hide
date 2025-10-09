package hide.kit;

class Block extends Element {
	override function makeSelf() {
		#if js
		native = js.Browser.document.createDivElement();
		#else

		#end
	}
}