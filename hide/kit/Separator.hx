package hide.kit;

class Separator extends Element {
	override function makeSelf():Void {
		#if js
		native = js.Browser.document.createElement("kit-separator");
		#else
		throw "todo";
		#end
	}
}