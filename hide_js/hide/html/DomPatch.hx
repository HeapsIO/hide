package hide.html;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Adds DOM APIs missing from the std js.html externs. Fields already declared in std are skipped.
**/
class DomPatch {
	static function init() {
		patch("js.html.SlotElement", "slot");
		patch("js.html.CSSStyleSheet", "styleSheet");
		patch("js.html.ShadowRoot", "shadowRoot");
		patch("js.html.CSS", "css");
	}

	static function patch(cl : String, name : String) {
		haxe.macro.Compiler.addGlobalMetadata(cl, '@:build(hide.html.DomPatch.$name())', false);
	}

	static function merge(add : Array<Field>) {
		var fields = Context.getBuildFields();
		return fields.concat(add.filter(f -> !Lambda.exists(fields, g -> g.name == f.name)));
	}

	static function slot() {
		return merge((macro class {
			function assign(nodes : haxe.extern.Rest<haxe.extern.EitherType<js.html.Element, js.html.Text>>) : Void;
		}).fields);
	}

	static function styleSheet() {
		return merge((macro class {
			function new() : Void;
			function replaceSync(text : String) : Void;
		}).fields);
	}

	static function shadowRoot() {
		return merge((macro class {
			var adoptedStyleSheets : Array<js.html.CSSStyleSheet>;
		}).fields);
	}

	static function css() {
		return merge((macro class {
			static function registerProperty(definition : {name : String, syntax : String, inherits : Bool, ?initialValue : String}) : Void;
		}).fields);
	}
}
#end
