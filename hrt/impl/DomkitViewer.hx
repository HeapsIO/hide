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
	var variables : Map<String,Dynamic> = [];
	var rebuilding = false;
	var compArgs : Map<String,Dynamic>;
	var rootObject : h2d.Object;

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

	#if castle
	public function addCDB( cdb : cdb.Types.IndexId<Dynamic,Dynamic> ) {
		var obj = {};
		var idName = null;
		for( c in @:privateAccess cdb.sheet.columns ) {
			switch( c.type ) {
			case TId: idName = c.name; break;
			default:
			}
		}
		for( o in cdb.all ) {
			var id = Reflect.field(o, idName);
			if( id == null || id == "" ) continue;
			Reflect.setField(obj, id, id);
		}
		var name = @:privateAccess cdb.name;
		name = name.charAt(0).toUpperCase() + name.substr(1);
		variables.set(name, obj);
		rebuildDelay();
	}
	#end

	function reloadVariables() {
		var vars = baseVariables.copy();
		for( r in variablesFiles ) {
			var p = new domkit.CssParser();
			p.variables = vars;
			try {
				p.parseSheet(r.entry.getText(), r.name);
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
		for( name => value in variables )
			interp.variables.set(name, value);
		return interp;
	}

	function rebuild() {
		var fullText = resource.entry.getText();
		var content = StringTools.trim(fullText);
		var cssText = "";
		var paramsText = "";

		if( StringTools.startsWith(content,"<css>") ) {
			var pos = content.indexOf("</css>");
			cssText = StringTools.trim(content.substr(5, pos - 6));
			content = content.substr(pos + 6);
			content = StringTools.trim(content);
		}

		if( StringTools.startsWith(content,"<params>") ) {
			var pos = content.indexOf("</params>");
			paramsText = StringTools.trim(content.substr(8, pos - 9));
			content = content.substr(pos + 9);
			content = StringTools.trim(content);
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
			var eparams = parseCode(paramsText, fullText.indexOf(paramsText));
			var expr = parser.parse(content,resource.entry.path, fullText.indexOf(content));
			root = domkit.Component.build(<flow class="debugRoot" layout="stack" content-align="middle middle" fill-width="true" fill-height="true"/>);
			interp = makeInterp();
			switch( eparams.e ) {
			case EBlock(el): // prevent local to be removed
				for( e in el ) evalCode(e);
			default:
				evalCode(eparams);
			}
			var vparams : Dynamic = @:privateAccess interp.locals.get("params")?.r;
			if( vparams != null ) {
				@:privateAccess interp.locals.remove("params");
				for( f in Reflect.fields(vparams) )
					interp.variables.set(f, Reflect.field(vparams,f));
			}
			compArgs = null;
			var vargs : Dynamic = interp.variables.get("defaultArgs");
			if( vargs != null ) {
				interp.variables.remove("defaultArgs");
				compArgs = new Map();
				for( f in Reflect.fields(vargs) )
					compArgs.set(f, Reflect.field(vargs,f));
			}
			addRec(expr, root);
			interp = null;
		} catch( e : domkit.Error ) {
			onError(e);
			return;
		} catch( e : hscript.Expr.Error ) {
			onError(new domkit.Error(e.toString(), e.pmin, e.pmax));
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
			if( e.condition != null ) {
				var expr = parseCode(e.condition.cond, e.condition.pmin);
				if( !evalCode(expr) )
					return;
			}
			var isRoot = parent.parent == null;
			var c = domkit.Component.get(name, true);
			// if we are top component, resolve our parent component
			if( isRoot ) {
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
			if( isRoot && compArgs != null  ) {
				if( e.arguments.length == 0 ) {
					for( a in @:privateAccess c.argsNames ) {
						var v : Dynamic = compArgs.get(a);
						args.push(v);
						interp.variables.set(a, v);
					}
				}
				compArgs = null;
			}
			var attributes = {};
			var objId = null, objIdArray = false;
			for( a in e.attributes ) {
				if( a.name == "id" ) {
					objId = switch( a.value ) {
					case RawValue("true"):
						var name = null;
						for( a in e.attributes )
							if( a.name == "class" ) {
								name = switch( a.value ) { case RawValue(v): v; default: null; };
								break;
							}
						name;
					case RawValue(name) if( StringTools.endsWith(name,"[]") ):
						objIdArray = true;
						name.substr(0,name.length - 2);
					case RawValue(name):
						name;
					case Code(_): null;
					}
					if( objId != null )
						(attributes:Dynamic).id = objId;
					continue;
				}
				switch( a.value ) {
				case RawValue(v):
					Reflect.setField(attributes,a.name,v);
				case Code(_):
					// skip (init after)
				}
			}
			var childrenCreated = false;
			if( isRoot ) {
				// only create parent structure, since we will create our own structure here
				@:privateAccess c.createHook = function(obj) {
					rootObject = obj;
					interp.variables.set("this", obj);
					// create children immediately as our post-init code might require some components to be init
					childrenCreated = true;
					for( c in e.children )
						addRec(c, obj);
				};
			}
			var p = @:privateAccess domkit.Properties.createNew(c.name, parent.dom, args, attributes);
			if( isRoot ) {
				rootObject = cast p.obj;
				@:privateAccess c.createHook = null;
				interp.variables.set("this", p.obj);
			}
			if( objId != null ) {
				if( objIdArray ) {
					var arr : Array<Dynamic> = try Reflect.getProperty(rootObject, objId) catch( e : Dynamic ) null;
					if( arr == null ) {
						arr = [];
						try Reflect.setProperty(rootObject, objId, arr) catch( e : Dynamic ) {};
					}
					arr.push(p.obj);
				} else {
					try Reflect.setProperty(rootObject, objId, p.obj) catch( e : Dynamic ) {}
				}
			}
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
					h.apply(p.obj, v);
				}
			}
			if( !childrenCreated ) {
				for( c in e.children )
					addRec(c, cast p.contentRoot);
			}
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