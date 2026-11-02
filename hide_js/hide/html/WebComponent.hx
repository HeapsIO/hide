package hide.html;

#if !macro
@:autoBuild(hide.html.WebComponentMacro.build())
interface IWebComponent {
	function connectedCallback() : Void;
	function disconnectedCallback() : Void;
	function adoptedCallback() : Void;
	function attributeChangedCallback(name : String, oldValue : Null<String>, newValue : Null<String>) : Void;
}

/**
	`extendsTag` is the tag of the built-in element extended (e.g. "button"), used with `<button is="htmlName">`.
	Custom elements need a native class constructor, which es5 output lacks : `cl` is wrapped in an es6 class whose prototype chains to it.
	Components must then be created by the DOM (`create()`, html parsing), not with `new`.
**/
function register(cl : Class<IWebComponent>, htmlName : String, ?extendsTag : String) : Int {
	var ctor : Dynamic = cl;
	ctor.__tag__ = htmlName;
	ctor.__extends__ = extendsTag;
	ctor = js.Syntax.code("(function(cl, attrs) {
		var base = cl;
		while (base.__super__ != null)
			base = base.__super__;
		var c = class extends base { constructor() { super(); cl.call(this); } };
		Object.setPrototypeOf(c.prototype, cl.prototype);
		c.observedAttributes = attrs;
		return c;
	})({0}, {1})", cl, getObservedAttributes(cl));
	if (extendsTag == null)
		js.Syntax.code("customElements.define({0}, {1})", htmlName, ctor);
	else
		js.Syntax.code("customElements.define({0}, {1}, {extends: {2}})", htmlName, ctor, extendsTag);
	return 0;
}

/**
	`observedAttributes` and `@:attr` names (`__internalAttributes`) of `cl` and its parent classes.
**/
private function getObservedAttributes(cl : Class<Dynamic>) : Array<String> {
	var attrs = [];
	while (cl != null) {
		for (field in ["observedAttributes", "__internalAttributes"]) {
			var a : Array<String> = Reflect.field(cl, field);
			if (a != null)
				attrs = attrs.concat(a);
		}
		cl = Type.getSuperClass(cl);
	}
	return attrs;
}

@:build(hide.html.WebComponentMacro.base())
abstract class WebComponent extends js.html.Element implements IWebComponent {
	public var saveDisplayKey : String;

	function getDisplayState(key : String) : Dynamic {
		if (saveDisplayKey == null)
			return null;
		var v = hide.Ide.inst.localStorage.getItem(saveDisplayKey + "/" + key);
		if (v == null)
			return null;
		return haxe.Json.parse(v);
	}

	function saveDisplayState(key : String, value : Dynamic) {
		if (saveDisplayKey == null)
			return;
		hide.Ide.inst.localStorage.setItem(saveDisplayKey + "/" + key, haxe.Json.stringify(value));
	}

	function removeDisplayState(key : String) {
		if (saveDisplayKey == null)
			return;
		hide.Ide.inst.localStorage.removeItem(saveDisplayKey + "/" + key);
	}
}

@:build(hide.html.WebComponentMacro.base())
abstract class WebComponentButton extends js.html.ButtonElement implements IWebComponent {}
#end
