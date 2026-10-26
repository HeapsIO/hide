package hide.html;

import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import domkit.MarkupParser;
#end

class Html {
	#if macro
	static var nativeTypes : Map<String, ComplexType>;
	#end

	/**
		Creates a tree of elements from markup and appends it to `parent`. Nodes with an `id` are declared as typed locals.
		`hide-*` tags create the web component `hide.html.comp.*`, other tags use `document.createElement`.
		Attributes with a code value are set as properties when they start with `on` (event handlers), others with `setAttribute`, the value being converted to a string as in JS.
	**/
	public static macro function build(parent : ExprOf<js.html.Element>, dml : Expr) : Expr {
		var str = switch (dml.expr) {
			case EMeta({name: ":markup"}, {expr: EConst(CString(s))}): s;
			default: Context.error("Markup expected", dml.pos);
		}
		var pinf = Context.getPosInfos(dml.pos);
		function makePos(pmin : Int, pmax : Int)
			return Context.makePosition({min: pmin, max: pmax, file: pinf.file});
		function error(msg : String, pmin : Int, pmax : Int) : Dynamic
			return Context.error(msg, makePos(pmin, pmax));

		function nativeType(tag : String) : ComplexType {
			if (nativeTypes == null) {
				// Maps tags to the types of the `create*Element` helpers, which call `createElement(tag)`
				nativeTypes = [];
				var doc = switch (Context.getType("js.html.HTMLDocument")) {
					case TInst(c, _): c.get();
					default: throw "assert";
				}
				var helper = ~/^create\w+Element$/;
				for (f in doc.fields.get()) {
					var e = helper.match(f.name) ? f.expr() : null;
					if (e == null)
						continue;
					var tag = null;
					function find(e : TypedExpr)
						switch (e.expr) {
							case TConst(TString(s)): tag = s;
							default: haxe.macro.TypedExprTools.iter(e, find);
						}
					find(e);
					switch (Context.follow(f.type)) {
						case TFun(_, ret) if (tag != null): nativeTypes.set(tag, Context.toComplexType(ret));
						default:
					}
				}
			}
			return nativeTypes.get(tag) ?? macro : js.html.Element;
		}

		var vars : Array<Var> = [];

		function node(m : Markup) : Expr {
			var p = makePos(m.pmin, m.pmax);
			var tag = switch (m.kind) {
				case Node(tag): tag;
				default: error("Node expected", m.pmin, m.pmax);
			}
			if (m.arguments?.length > 0)
				error("Arguments are not supported", m.pmin, m.pmax);
			var type : ComplexType;
			var create : Expr;
			if (StringTools.startsWith(tag, "hide-")) {
				var path = "hide.html.comp." + domkit.CssParser.cssToHaxe(tag.substr(5), false);
				var t = try Context.getType(path) catch (_) error('Unknown web component $path', m.pmin, m.pmax);
				type = Context.toComplexType(t);
				create = macro @:pos(p) $p{path.split(".")}.create();
			} else {
				type = nativeType(tag);
				create = macro @:pos(p) (cast js.Browser.document.createElement($v{tag}) : $type);
			}

			var exprs = [macro @:pos(p) var __el : $type = $create];
			for (a in m.attributes) {
				var ap = makePos(a.pmin, a.pmax);
				switch (a.value) {
					case null:
						exprs.push(macro @:pos(ap) __el.setAttribute($v{a.name}, ""));
					case RawValue(v):
						if (a.name == "id") {
							var name = domkit.CssParser.cssToHaxe(v, true);
							if (Lambda.exists(vars, v -> v.name == name))
								error('Duplicate id $name', a.pmin, a.pmax);
							vars.push({name: name, type: type, expr: macro null});
							exprs.push(macro @:pos(ap) $i{name} = __el);
						}
						exprs.push(macro @:pos(ap) __el.setAttribute($v{a.name}, $v{v}));
					case Code(e):
						if (a.name == "id")
							error("id must be a constant", a.pmin, a.pmax);
						if (StringTools.startsWith(a.name, "on"))
							exprs.push(macro @:pos(ap) $p{["__el", a.name]} = $e);
						else
							exprs.push(macro @:pos(ap) __el.setAttribute($v{a.name}, Std.string($e)));
				}
			}

			function child(c : Markup) : Expr {
				var cp = makePos(c.pmin, c.pmax);
				var e = switch (c.kind) {
					case Node(_): macro @:pos(cp) __el.append(${node(c)});
					case Text(text): macro @:pos(cp) __el.append($v{text});
					case For(it):
						var it = switch (it.expr) {
							case EParenthesis(e): e;
							default: it;
						}
						macro @:pos(cp) for ($it) $b{c.children.map(child)};
					default: error("Unsupported markup", c.pmin, c.pmax);
				}
				return c.condition == null ? e : macro @:pos(cp) if (${c.condition.cond}) $e;
			}
			for (c in m.children)
				exprs.push(child(c));
			exprs.push(macro __el);
			return macro @:pos(p) $b{exprs};
		}

		try {
			var parser = new MarkupParser();
			parser.allowRawText = true;
			var root = parser.parse(str, pinf.file, pinf.min).children[0];
			var init = node(root);
			// Declares the id variables in the caller scope, `_` builds the tree
			vars.push({name: "_", expr: macro {$parent.append($init); true;}});
		} catch (e : domkit.Error) {
			Context.error(e.message, makePos(e.pmin, e.pmax));
		}
		return {expr: EVars(vars), pos: dml.pos};
	}
}
