package hide.html;

/**
	WebComponent docs :

	WebComponent is a helper class around the new html webcomponent api, that allow declaring
	new html tags that have custom scoped style and code behavior. This file tries to build a Haxe translation of this concept.

	WebComponents should be used when a widget is self contained, like a button or a slider, or want to interact with the
	dom tree natively (for example custom containers like TabContainer / SplitContainer). Complex
	hierarchies like Editors should instead keep using the old hide.comp.Element pattern.

	To use it, extends WebComponent and call `static var _ = register(MyClass, "hide-my-dom-tag");`
	at the end of your class to register it.

	You then get access to the WebComponent callbacks defined inside IWebComponent :
	https://developer.mozilla.org/en-US/docs/Web/API/Web_components/Using_custom_elements#custom_element_lifecycle_callbacks

	Attributes :
		The `@:attr` metadata transform a class member into a dom attribute. Setting the member calls setAttribute("var_name", value).
		Only String or Bool are supported, with Int variables being converted to String for convinience.
		Each `@:attr` variable must have a matching set_varname(oldValue, newValue) member function, that will be called each time the
		attribute is set somewhere (carefull, oldValue can be equal to newValue).
		This is the preferred way to setup values inside your WebComponent.

	Example class : `hide.html.comp.Button`
	Example container : SplitContainer

	Additional notes :
	WebComponent rely on recent html api that is not present in haxe. for that we manually patch the haxe definitions inside hide.html.DomPatch

**/


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
