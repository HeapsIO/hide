package hrt.impl;

#if (!hscript || !hscriptPos)
#error "DomkitViewer requires --library hscript with -D hscriptPos"
#end

#if domkit
import h2d.domkit.BaseComponents;

typedef DomkitFileData = { css : String, params : String, dml : String };

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

class SourceComponent extends domkit.Component<h2d.Object, h2d.Object> {

	var res : hxd.res.Resource;
	var viewer : DomkitViewer;
	var isRec = false;

	public function new(name, res, viewer) {
		this.res = res;
		this.viewer = viewer;
		this.name = name;
		res.watch(function() {
			reload();
			@:privateAccess viewer.rebuild();
		});
		reload();
		super(name, makeComp, parent);
	}

	function reload() {
		var fullText = res.entry.getText();
		var data = DomkitViewer.parse(fullText);
		var p = new domkit.MarkupParser();
		p.allowRawText = true;
		var dml = p.parse(data.dml, res.entry.path, fullText.indexOf(data.dml));
		switch( dml.kind ) {
		case Node(null):
			for( c in dml.children )
				switch( c.kind ) {
				case Node(n) if( n.split(":")[0] == name ):
					dml = c;
					break;
				default:
				}
		default:
		}
		var parentName = "flow"; // todo : extract from source
		switch( dml.kind ) {
		case Node(n):
			var p = n.split(":");
			if( p.length > 1 )
				parentName = p[1];
		default:
		}
		argsNames = [];
		if( dml.arguments != null ) {
			for( e in dml.arguments )
				switch( e.value ) {
				case Code(n): argsNames.push(n);
				default:
				}
		}
		parent = cast @:privateAccess viewer.resolveComponent(parentName);
	}

	function makeComp(args:Array<Dynamic>, parent) : h2d.Object {
		if( isRec ) {
			isRec = false;
			var p = this.parent;
			while( p is SourceComponent )
				p = p.parent;
			var obj : h2d.Object = p.make(args, parent);
			if( obj.dom != null ) @:privateAccess obj.dom.component = this;
			return obj;
		}
		isRec = true;
		return @:privateAccess viewer.createComponent(res, parent, args);
	}

}

class DomkitBaseContext {

	public function new() {
	}

	public function loadTile( url : String ) {
		return hxd.res.Loader.currentInstance.load(url).toTile();
	}

}

class DomkitViewer extends h2d.Object {

	var resource : hxd.res.Resource;
	var variablesFiles : Array<hxd.res.Resource> = [];
	var current : h2d.Object;
	var cssResources : Map<String,CssResource> = [];
	var interp : DomkitInterp;
	var style : h2d.domkit.Style;
	var baseVariables : Map<String,domkit.CssValue>;
	var contexts : Array<Dynamic> = [];
	var variables : Map<String,Dynamic> = [];
	var rebuilding = false;
	var rootObject : h2d.Object;
	var componentsPaths : Array<String> = [];
	var createRootArgs : Array<Dynamic>;
	var evaluatedParams : Dynamic;
	var loadedComponents : Array<domkit.Component<h2d.Object, h2d.Object>> = [];

	public function new( style : h2d.domkit.Style, res : hxd.res.Resource, ?parent ) {
		super(parent);
		this.style = style;
		this.resource = res;
		res.watch(rebuild);
		baseVariables = style.cssParser.variables.copy();
		addContext(new DomkitBaseContext());
		rebuildDelay();
	}

	function rebuildDelay() {
		if( rebuilding ) return;
		rebuilding = true;
		haxe.Timer.delay(() -> { rebuilding = false; rebuild(); },0);
	}

	public function addComponentsPath( dir : String ) {
		componentsPaths.push(dir);
		rebuildDelay();
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
		for( c in cssResources )
			c.watchCallb();
	}

	override function onRemove() {
		super.onRemove();
		for( r in variablesFiles )
			r.watch(null);
		style.cssParser.variables = baseVariables;
		resource.watch(null);
		for( c in cssResources )
			style.unload(c);
		cssResources = new Map();
		for( c in loadedComponents ) {
			@:privateAccess domkit.Component.COMPONENTS.remove(c.name);
			@:privateAccess domkit.CssStyle.CssData.COMPONENTS.remove(c);
		}
		loadedComponents = [];
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

	public static function parse( content : String ) : DomkitFileData {
		var cssText = "";
		var paramsText = "{}";

		content = StringTools.trim(content);

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

		return {
			css : cssText,
			params : paramsText,
			dml : content,
		}
	}

	public static function toStr(data:DomkitFileData) {
		var parts = ['<css>\n${data.css}\n</css>'];
		if( data.params != '' && data.params != '{}' )
			parts.push('<params>\n${data.params}\n</params>');
		parts.push(data.dml);
		return parts.join('\n\n');
	}

	function rebuild() {
		@:privateAccess {
			style.errors = [];
			style.refreshErrors();
		}

		reloadVariables();

		var root = new h2d.Flow();
		root.dom = domkit.Properties.create("flow",root,{ "class" : "debugRoot", layout : "stack", "content-align" : "middle middle", "fill-width" : "true", "fill-height" : "true" });
		var obj = createComponent(resource, root, null);

		if( evaluatedParams != null ) {
			var classes : Array<String> = Std.downcast(evaluatedParams.classes,Array);
			if( classes != null ) {
				var checks = new h2d.Flow(root);
				checks.dom = domkit.Properties.create("flow",checks,{ "class" : "debugClasses", "position" : "absolute", "align" : "middle top", "margin-top" : "5" });
				for( cl in classes ) {
					var c = new h2d.CheckBox(checks);
					c.dom = domkit.Properties.create("flow",c);
					c.text = cl;
					c.onChange = function() {
						obj.dom.toggleClass(cl, c.selected);
					};
				}
			}
		}

		if( current != null ) {
			current.remove();
			style.removeObject(current);
		}
		addChild(root);
		style.addObject(root);
		current = root;
		for( c in cssResources )
			c.watchCallb();
	}

	function createComponent( res : hxd.res.Resource, parent, args : Array<Dynamic> ) {
		var fullText = res.entry.getText();
		var data = parse(fullText);
		var comp = null;
		var prev = interp;
		createRootArgs = args;
		try {
			var parser = new domkit.MarkupParser();
			parser.allowRawText = true;
			var eparams = parseCode(data.params, fullText.indexOf(data.params));
			var expr = parser.parse(data.dml,res.entry.path, fullText.indexOf(data.dml));
			interp = makeInterp();
			var vparams : Dynamic = evalCode(eparams);
			if( vparams != null ) {
				for( f in Reflect.fields(vparams) )
					interp.variables.set(f, Reflect.field(vparams,f));
			}
			comp = addRec(expr, parent, true);
			interp = prev;
			evaluatedParams = vparams;
		} catch( e : domkit.Error ) {
			interp = prev;
			onError(e);
			return null;
		} catch( e : hscript.Expr.Error ) {
			interp = prev;
			onError(new domkit.Error(e.toString(), e.pmin, e.pmax));
			return null;
		}
		createRootArgs = null;
		var css = cssResources.get(res.entry.path);
		if( css == null ) {
			css = new CssResource(res.entry.path);
			css.cssEntry.text = "";
			style.load(css);
			cssResources.set(res.entry.path, css);
		}
		css.cssEntry.text = data.css;
		return comp;
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

	function resolveComponent( name : String ) {
		var c = domkit.Component.get(name, true);
		if( c != null )
			return c;
		for( dir in componentsPaths ) {
			var r = try hxd.res.Loader.currentInstance.load(dir+"/"+name+".domkit") catch( e : hxd.res.NotFound ) continue;
			var c = new SourceComponent(name, r, this);
			loadedComponents.push(c);
			return c;
		}
		return null;
	}

	function addRec( e : domkit.MarkupParser.Markup, parent : h2d.Object, isRoot ) {
		var comp : h2d.Object = null;
		switch( e.kind ) {
		case Node(null):
			for( c in e.children )
				comp = addRec(c, parent, isRoot);
		case Node(name):
			if( e.condition != null ) {
				var expr = parseCode(e.condition.cond, e.condition.pmin);
				if( !evalCode(expr) )
					return null;
			}
			var c = domkit.Component.get(name, true);
			// if we are top component, resolve our parent component
			if( isRoot ) {
				var parts = name.split(":");
				var parent = null;
				if( parts.length == 2 ) {
					name = parts[0];
					c = domkit.Component.get(name, true);
					parent = resolveComponent(parts[1]);
					if( parent == null )
						throw new domkit.Error("Unknown parent component "+parts[1], e.pmin + name.length, e.pmin + name.length + parts[1].length + 1);
				}
				if( parent == null && (c == null || loadedComponents.indexOf(cast c) >= 0) )
					parent = domkit.Component.get("flow");
				if( c == null || (parent != null && c.parent != parent) ) {
					c = new domkit.Component(name,function(args,p) {
						var obj = c.parent.make(args,p);
						if( obj.dom != null )
							obj.dom.component = c;
						return obj;
					},parent);
					domkit.CssStyle.CssData.registerComponent(c);
					@:privateAccess c.argsNames = [];
					loadedComponents.push(cast c);
				}
			} else if( c == null ) {
				c = resolveComponent(name);
			}
			if( c == null )
				throw new domkit.Error("Unknown component "+name, e.pmin, e.pmax);
			var args = [for( a in e.arguments ) {
				var v : Dynamic = switch( a.value ) {
				case RawValue(v): v;
				case Code(code):
					var code = parseCode(code, a.pmin);
					evalCode(code);
				}
				v;
			}];
			if( isRoot && e.arguments.length == 0 && @:privateAccess c.argsNames != null ) {
				for( a in @:privateAccess c.argsNames ) {
					var v : Dynamic = interp.variables.get(a);
					args.push(v);
				}
			}
			if( createRootArgs != null ) {
				args = createRootArgs;
				createRootArgs = null;
				for( i => a in @:privateAccess c.argsNames )
					interp.variables.set(a, args[i]);
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
						addRec(c, obj, false);
				};
			}
			var obj = c.make(args, parent.dom?.contentRoot);
			var p = obj.dom;
			if( p == null ) p = obj.dom = new domkit.Properties(obj, c);
			p.initAttributes(attributes);
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
					addRec(c, cast p.contentRoot, false);
			}
			comp = cast p.obj;
		case Text(text):
			var tf = new h2d.HtmlText(hxd.res.DefaultFont.get(), parent);
			tf.dom = domkit.Properties.create("html-text", tf);
			tf.text = text;
			comp = tf;
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			switch( expr.e ) {
			case EFor(n,it,_):
				interp.executeLoop(n, it, function() {
					for( c in e.children )
						addRec(c, parent, false);
				});
			default:
				throw "assert";
			}
		case CodeBlock(v):
			throw new domkit.Error("Code block not supported", e.pmin);
		case Macro(id):
			throw new domkit.Error("Macro not supported", e.pmin);
		}
		return comp;
	}
}
#end