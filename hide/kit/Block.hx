package hide.kit;

#if domkit

class Block extends Element {
	override function makeSelf() {
		#if js
		native = js.Browser.document.createElement("kit-block");
		#elseif hui
		native = null;
		#end
	}

	override function get_nativeContent():NativeElement {
		return parent.nativeContent;
	}
}

#end