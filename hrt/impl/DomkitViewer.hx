package hrt.impl;

#if (!hscript || !hscriptPos)
#error "DomkitViewer requires --library hscript with -D hscriptPos"
#end

#if domkit
class DomkitInterp extends hscript.Async.AsyncInterp {

	public function executeLoop( n : String, it : hscript.Expr, callb ) {
		var old = declared.length;
		declared.push({ n : n, old : locals.get(n) });
		var it = makeIterator(expr(it));
		while( it.hasNext() ) {
			locals.set(n,{ r : it.next() });
			if( !loopRun(callb) )
				break;
		}
		restore(old);
	}

}

class CssEntry extends hxd.fs.FileEntry {

	var nativePath : String;
	public var text : String;

	public function new(path) {
		this.nativePath = path;
	}

	override function getText() {
		return text;
	}

	override function get_path():String {
		return nativePath;
	}

}

class CssResource extends hxd.res.Resource {

	public var cssEntry : CssEntry;
	public var watchCallb : Void -> Void;

	public function new(path) {
		cssEntry = new CssEntry(path);
		super(cssEntry);
	}

	override function watch( callb : Null<Void->Void> ) {
		watchCallb = callb;
	}

}

class DomkitViewer extends h2d.Object {

	var resource : hxd.res.Resource;
	var variablesFiles : Array<hxd.res.Resource> = [];
	var current : h2d.Object;
	var cssResource : CssResource;
	var interp : DomkitInterp;
	var style : h2d.domkit.Style;
	var baseVariables : Map<String,domkit.CssValue>;
	var contexts : Array<Dynamic> = [];
	var rebuilding = false;

	public function new( style : h2d.domkit.Style, res : hxd.res.Resource, ?parent ) {
		super(parent);
		this.style = style;
		this.resource = res;
		res.watch(rebuild);
		baseVariables = style.cssParser.variables.copy();
		rebuildDelay();
	}

	function rebuildDelay() {
		if( rebuilding ) return;
		rebuilding = true;
		haxe.Timer.delay(() -> { rebuilding = false; rebuild(); },0);
	}

	public function addVariables( res : hxd.res.Resource ) {
		variablesFiles.push(res);
		res.watch(rebuild);
		rebuildDelay();
	}

	public function addContext( ctx : Dynamic ) {
		contexts.push(ctx);
		rebuildDelay();
	}

	function reloadVariables() {
		var vars = baseVariables.copy();
		for( r in variablesFiles ) {
			var p = new domkit.CssParser();
			p.variables = vars;
			try {
				p.parseSheet(r.entry.getText());
			} catch( e : domkit.Error ) {
				onError(e);
			}
		}
		style.cssParser.variables = vars;
		if( cssResource != null )
			cssResource.watchCallb();
	}

	override function onRemove() {
		super.onRemove();
		for( r in variablesFiles )
			r.watch(null);
		style.cssParser.variables = baseVariables;
		resource.watch(null);
		if( cssResource != null )
			style.unload(cssResource);
	}

	public dynamic function onError( e : domkit.Error ) @:privateAccess {
		var text = resource.entry.getText();
		var line = text.substr(0, e.pmin).split("\n").length;
		var err = resource.entry.path+":"+line+": "+e.message;
		style.errors.remove(err);
		style.errors.push(err);
		style.refreshErrors(getScene());
	}

	function makeInterp() {
		var interp = new DomkitInterp();
		for( c in contexts )
			interp.setContext(c);
		return interp;
	}

	function rebuild() {
		var fullText = resource.entry.getText();
		var text = fullText;
		var startPos = 0;
		var cssStart = 0;
		var cssText = "";
		if( StringTools.startsWith(text,"<css>") ) {
			var pos = text.indexOf("</css>");
			cssStart = 5;
			cssText = text.substr(cssStart, pos - cssStart);
			startPos = pos + 6;
			text = text.substr(startPos);
		}

		@:privateAccess {
			style.errors = [];
			style.refreshErrors();
		}

		reloadVariables();

		var root;
		try {
			var parser = new domkit.MarkupParser();
			parser.allowRawText = true;
			var expr = parser.parse(text,resource.entry.path, startPos);
			root = domkit.Component.build(<flow class="debugRoot" layout="stack" content-align="middle middle" fill-width="true" fill-height="true"/>);

			interp = makeInterp();
			addRec(expr, root);
			interp = null;
		} catch( e : domkit.Error ) {
			onError(e);
			return;
		}

		if( current != null ) {
			current.remove();
			style.removeObject(current);
		}
		addChild(root);
		style.addObject(root);
		current = root;

		if( cssResource == null ) {
			cssResource = new CssResource(resource.entry.path);
			cssResource.cssEntry.text = "";
			style.load(cssResource);
		}
		cssResource.cssEntry.text = cssText;
		cssResource.watchCallb();
	}


	function parseCode( codeStr : String, pos : Int ) {
		var parser = new hscript.Parser();
		try {
			return parser.parseString(codeStr);
		} catch( e : hscript.Expr.Error ) {
			throw new domkit.Error(e.toString(), e.pmin + pos, e.pmax + pos);
		}
	}

	function evalCode( e : hscript.Expr ) : Dynamic {
		return @:privateAccess interp.expr(e);
	}

	public static function getParentName( expr : hscript.Expr ) {
		switch( expr.e ) {
		case EIdent(name):
			return name;
		case EBinop("-", e1, e2):
			var e1 = getParentName(e1);
			var e2 = getParentName(e2);
			return e1 == null || e2 == null ? null : e1+"-"+e2;
		default:
			return null;
		}
	}

	function addRec( e : domkit.MarkupParser.Markup, parent : h2d.Object ) {
		switch( e.kind ) {
		case Node(null):
			for( c in e.children )
				addRec(c, parent);
		case Node(name):
			var c = domkit.Component.get(name, true);
			// if we are top component, resolve our parent component
			if( parent.parent == null ) {
				var parts = name.split(":");
				var parent = null;
				if( parts.length == 2 ) {
					name = parts[0];
					c = domkit.Component.get(name, true);
					parent = domkit.Component.get(parts[1], true);
					if( parent == null )
						throw new domkit.Error("Unknown parent component "+parts[1], e.pmin + name.length, e.pmin + name.length + parts[1].length + 1);
				}
				if( parent == null && c == null )
					parent = domkit.Component.get("flow");
				if( c == null || (parent != null && c.parent != parent) )
					c = new domkit.Component(name,parent.make,parent);
			} else if( c == null ) {
				// TODO : load other ui component
			}
			if( c == null )
				throw new domkit.Error("Unknown component "+name, e.pmin, e.pmax);
			var args = [for( a in e.arguments ) {
				var v : Dynamic = switch( a.value ) {
				case RawValue(v): v;
				case Code(code):
					var code = parseCode(code, a.pmin);
					// TODO : typecheck code
					evalCode(code);
				}
				// TODO : typecheck argument
				v;
			}];
			var attributes = {};
			for( a in e.attributes ) {
				switch( a.value ) {
				case RawValue(v):
					Reflect.setField(attributes,a.name,v);
				case Code(_):
				}
			}
			var p = @:privateAccess domkit.Properties.createNew(c.name, parent.dom, args, attributes);
			for( a in e.attributes ) {
				var h = p.component.getHandler(domkit.Property.get(a.name));
				if( h == null ) {
					// TODO : add warning
					continue;
				}
				switch( a.value ) {
				case RawValue(_):
				case Code(code):
					var v : Dynamic = evalCode(parseCode(code, a.pmin));
					@:privateAccess p.initStyle(a.name, v);
				}
			}
			for( c in e.children )
				addRec(c, cast p.contentRoot);
		case Text(text):
			var tf = new h2d.HtmlText(hxd.res.DefaultFont.get(), parent);
			tf.dom = domkit.Properties.create("html-text", tf);
			tf.text = text;
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			switch( expr.e ) {
			case EFor(n,it,_):
				interp.executeLoop(n, it, function() {
					for( c in e.children )
						addRec(c, parent);
				});
			default:
				throw "assert";
			}
		case CodeBlock(v):
			throw new domkit.Error("Code block not supported", e.pmin);
		case Macro(id):
			throw new domkit.Error("Macro not supported", e.pmin);
		}
	}
}
#end