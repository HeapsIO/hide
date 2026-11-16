package hide.html;

#if js
/**
	Default semantics of a custom element, returned by `attachInternals()`. ARIA values are strings, as their attributes.
**/
@:native("ElementInternals")
extern class ElementInternals {
	var role : Null<String>;
	var ariaExpanded : Null<String>;
}
#end
