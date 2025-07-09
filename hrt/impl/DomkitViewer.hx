package hrt.impl;

#if (!hscript || !hscriptPos)
#error "DomkitViewer requires --library hscript with -D hscriptPos"
#end

#if (macro && domkit)

import haxe.macro.Expr;
import haxe.macro.Context;

class DomkitViewer {

	static function codeContains( code : haxe.macro.Expr, dynParams : Map<String,Bool> ) {
		return switch( code.expr ) {
		case EConst(CIdent(v)) if( dynParams.exists(v) ): true;
		case EParenthesis(e): codeContains(e,dynParams);
		case EBinop(_,e1,e2): codeContains(e1,dynParams) || codeContains(e2,dynParams);
		default: false;
		}
	}

	static function removeDynParamsRec( m : domkit.MarkupParser.Markup, dynParams : Map<String,Bool> ) {
		if( m.attributes != null ) {
			for( a in m.attributes )
				switch( a.value ) {
				case Code(code) if( codeContains(code,dynParams) ):
					m.attributes.remove(a);
				default:
				}
		}
		if( m.children != null )
			for( c in m.children.copy() ) {
				removeDynParamsRec(c, dynParams);
				if( c.kind == null ) m.children.remove(c);
			}
		if( m.condition != null && codeContains(m.condition.cond,dynParams) )
			m.condition = null;
		switch( m.kind ) {
		case For(cond) if( codeContains(cond,dynParams) ):
			m.kind = null;
		default:
		}
	}

	static function clearImportNames( m : domkit.MarkupParser.Markup ) {
		switch( m.kind ) {
		case Node(n) if( n != null && n.indexOf(".") >= 0 ): m.kind = Node(n.split(".").pop()); // remove root.name
		default:
		}
		if( m.children != null )
			for( c in m.children )
				clearImportNames(c);
	}

	static function remapCDBCode( map : Map<String, Bool>, code : domkit.MarkupParser.CodeExpr ) {
		switch( code.expr ) {
		case EConst(CIdent(name)) if( map.exists(name) ):
			code.expr = EField({ expr : EConst(CIdent(CDB_MODULE)), pos : code.pos }, name+"Kind");
		default:
			haxe.macro.ExprTools.iter(code, remapCDBCode.bind(map));
		}
	}

	static function iterCode( m : domkit.MarkupParser.Markup, f : domkit.MarkupParser.CodeExpr -> Void ) {
		if( m.arguments != null ) {
			for( a in m.arguments )
				switch( a.value ) {
				case Code(code): f(code);
				default:
				}
		}
		if( m.attributes != null ) {
			for( a in m.attributes )
				switch( a.value ) {
				case Code(code): f(code);
				default:
				}
		}
		if( m.condition != null )
			f(m.condition.cond);
		if( m.children != null )
			for( c in m.children )
				iterCode(c, f);
		switch( m.kind ) {
		case For(cond): f(cond);
		default:
		}
	}

	public static function loadSource( path : String, pos : Position, fields : Array<Field>, extraParams : Array<Expr> ) {
		var name = path.split("/").pop().split("_").join("-");
		var dotPos = name.lastIndexOf(".");
		if( dotPos >= 0 ) {
			path = path.substr(0, path.length - name.length + dotPos);
			name = name.substr(dotPos+1);
		}
		path += ".domkit";
		var fullPath = try Context.resolvePath(path) catch( e : Dynamic ) return null;
		if( fullPath == null )
			return null;

		var staticCSS = false;
		var hasCSS = true;
		while( extraParams.length > 0 ) {
			switch( extraParams[0].expr ) {
			case EConst(CIdent("staticCSS")): staticCSS = true;
			case EConst(CIdent("noCSS")): hasCSS = false;
			default:
				Context.error("Invalid parameter", extraParams[0].pos);
				return null;
			}
			extraParams.shift();
		}

		Context.registerModuleDependency(Context.getLocalModule(),fullPath);
		var fullData = sys.io.File.getContent(fullPath);
		var data = DomkitFile.parse(fullData);
		var p = new domkit.MarkupParser();
		var index = fullData.indexOf(data.dml);
		try {
			var m = p.parse(data.dml, fullPath, index);
			for( c in m.children ) {
				switch( c.kind ) {
				case Node(n) if( n.indexOf(":") >= 0 ): c.kind = Node(n.split(":")[0]);
				default:
				}
				if( c.arguments != null ) c.arguments = null;
			}
			var found = null;
			for( c in m.children ) {
				switch( c.kind ) {
				case Node(n) if( n == name ):
					found = c;
					break;
				default:
				}
			}
			if( found == null ) {
				Context.error("Could not find definition for component '"+name+"'", Context.currentPos());
				return null;
			}
			m.children = [found];

			var params = new hscript.Parser().parseString(data.params, path);
			var dynParams = new Map();
			var hasDynParam = false;
			switch( params.e ) {
			case EObject(fields):
				for( f in fields )
					if( f.name == "dynamicParams" ) {
						switch( f.e.e ) {
						case EArrayDecl(values):
							for( v in values )
								switch( v.e ) {
								case EConst(CString(v)):
									dynParams.set(v, true);
									hasDynParam = true;
								default:
								}
						default:
						}
					}
			default:
			}
			if( hasDynParam )
				removeDynParamsRec(m, dynParams);
			clearImportNames(m);

			if( data.enums != null ) {
				var enums : Array<{ path : String, constrs : Array<String> }> = haxe.Json.parse(data.enums);
				for( e in enums )
					if( e.path == "$cdb" ) {
						var map = [for( c in e.constrs ) c => true];
						iterCode(m,remapCDBCode.bind(map));
						break;
					}
			}

			if( hasCSS ) {
				fields.push({
					name : "__CSS",
					access : [AStatic],
					kind : FVar(null, macro hrt.impl.DomkitViewer.DomkitStyle.registerCSSSource($v{path},$v{staticCSS?fullData:null})),
					pos : pos,
				});
			}
			return { dml : m, pos : Context.makePosition({ file : fullPath, min : index, max : index + data.dml.length }) };
		} catch( e : domkit.Error ) {
			Context.error(e.message, Context.makePosition({ file : fullPath, min : e.pmin, max : e.pmax }));
			return null;
		}
	}

	public static var CDB_MODULE = "Data";

	public static function init() {
		domkit.Macros.onSourceLoad = loadSource;
	}

}

#elseif domkit

import h2d.domkit.BaseComponents;
import domkit.MarkupParser.Markup;

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

	public function executeKeyValueLoop( vk : String, vv : String, it : hscript.Expr, callb ) {
		var old = declared.length;
		declared.push({ n : vk, old : locals.get(vk) });
		declared.push({ n : vv, old : locals.get(vv) });
		var it = makeKeyValueIterator(expr(it));
		while( it.hasNext() ) {
			var v = it.next();
			locals.set(vk,{ r : v.key });
			locals.set(vv,{ r : v.value });
			if( !loopRun(callb) )
				break;
		}
		restore(old);
	}

}

class DomkitBaseContext {

	public function new() {
	}

	public function loadTile( url : String ) {
		return hxd.res.Loader.currentInstance.load(url).toTile();
	}

}

private typedef CompMap = Map<String, Array<Dynamic> -> h2d.Object -> h2d.Object>;

class DomkitViewer extends h2d.Object {

	var resource : hxd.res.Resource;
	var style : DomkitStyle;
	var current : h2d.Object;
	var currentObj : h2d.Object;
	var currentRoot : h2d.Object;
	var contexts : Array<Dynamic> = [];
	var variables : Map<String,Dynamic> = [];
	var rebuilding = false;
	var rootObject : h2d.Object;
	var componentsPaths : Array<String> = [];
	var loadedComponents : Array<domkit.Component<h2d.Object, h2d.Object>> = [];
	var compHooks : CompMap = [];
	var definedClasses : Array<String> = [];
	var loadedResources : Array<{ r : hxd.res.Resource, wasLoaded : Bool }> = [];

	var tmpCompMap : CompMap;

	public function new( style : DomkitStyle, res : hxd.res.Resource, ?parent ) {
		super(parent);
		this.style = style;
		this.resource = res;
		addContext(new DomkitBaseContext());
		rebuildDelay();
	}

	function loadResource( res : hxd.res.Resource ) {
		var loaded = false;
		var path = res.entry.path;
		for( r in @:privateAccess style.resources )
			if( r.entry.path == path ) {
				loaded = true;
				break;
			}
		loadedResources.push({ r : res, wasLoaded: loaded });
		if( !loaded ) handleErrors(res, () -> style.load(res));
		res.watch(rebuild);
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

	public function addContext( ctx : Dynamic ) {
		contexts.push(ctx);
		rebuildDelay();
	}

	public function addGlobal( name : String, v : Dynamic ) {
		variables.set(name, v);
		rebuildDelay();
	}

	public function addComponentHook( name : String, make ) {
		compHooks.set(name, make);
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

	override function onRemove() {
		super.onRemove();
		if( currentObj != null )
			currentObj.remove();
		unload();
	}

	function unload() {
		// force rewatch
		for( r in loadedResources ) {
			if( r.wasLoaded )
				style.load(r.r);
			else
				style.unload(r.r);
		}
		for( c in loadedComponents ) {
			@:privateAccess domkit.Component.COMPONENTS.remove(c.name);
			@:privateAccess domkit.CssStyle.CssData.COMPONENTS.remove(c);
		}
		loadedResources = [];
		loadedComponents = [];
	}

	public dynamic function onError( res : hxd.res.Resource, e : domkit.Error ) @:privateAccess {
		var text = res.entry.getText();
		var line = text.substr(0, e.pmin).split("\n").length;
		var err = res.entry.path+":"+line+": "+e.message;
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

	public static function toStr(data:DomkitFileData) {
		var parts = ['<css>\n${data.css}\n</css>'];
		if( data.params != '' && data.params != '{}' )
			parts.push('<params>\n${data.params}\n</params>');
		if( data.enums != null )
			parts.push('<enums>\n${data.enums}\n</enums>');
		parts.push(data.dml);
		return parts.join('\n\n');
	}

	function rebuild() {
		@:privateAccess {
			style.errors = [];
			style.refreshErrors();
		}

		var root = new h2d.Flow();
		root.dom = domkit.Properties.create("flow",root,{ "class" : "debugRoot", layout : "stack", "content-align" : "middle middle", "fill-width" : "true", "fill-height" : "true" });

		unload();
		tmpCompMap = compHooks.copy();
		try {
			loadResource(resource);
		}
		catch(e: domkit.Error) {
			style.cssParser.warnings.push({ msg : e.message, pmin : e.pmin, pmax : e.pmax });
		}

		var inf = loadComponents(resource);

		var obj : h2d.Object = null;
		var mainComp = inf.comps[inf.comps.length - 1];
		if( mainComp != null )
			obj = mainComp([], root);

		if( inf.params != null && obj != null ) {
			var classes : Array<String> = Std.downcast(inf.params.classes,Array);
			if( classes != null ) {
				var checks = new h2d.Flow(root);
				checks.dom = domkit.Properties.create("flow",checks,{ "class" : "debugClasses" });
				var p = root.getProperties(checks);
				p.isAbsolute = true;
				p.verticalAlign = Top;
				p.horizontalAlign = Middle;
				p.paddingTop = 5;

				for( c in definedClasses.copy() )
					if( classes.indexOf(c) < 0 )
						definedClasses.remove(c);

				for( cl in classes ) {
					var c = new h2d.CheckBox(checks);
					c.dom = domkit.Properties.create("flow",c);
					c.text = cl;
					if( definedClasses.indexOf(cl) >= 0 )
						c.selected = true;
					c.onChange = function() {
						obj.dom.toggleClass(cl, c.selected);
						if( c.selected ) definedClasses.push(cl) else definedClasses.remove(cl);
						if( Reflect.field(inf.params,cl) != null )
							rebuild();
					};
				}

				for( c in definedClasses )
					obj.dom.addClass(c);
			}
		}

		if( currentObj != null ) {
			currentObj.remove();
			currentObj = null;
		}
		if( current != null ) {
			current.remove();
			style.removeObject(current);
		}
		addChild(root);
		style.addObject(root);
		current = root;
		currentObj = obj;

		var errors = @:privateAccess style.errors.copy();
		@:privateAccess style.onChange(); // force trigger reload (css might have changed)
		if( errors.length > 0 ) {
			@:privateAccess style.errors = errors.concat(style.errors);
			@:privateAccess style.refreshErrors(getScene());
		}
	}

	inline function error(msg,pmin,pmax) {
		throw new domkit.Error(msg, pmin, pmax);
	}

	function loadComponents( res : hxd.res.Resource ) {
		var fullText = res.entry.getText();
		var data = DomkitFile.parse(fullText);
		var inf = { comps : [], params : (null:Dynamic) };
		handleErrors(res, function() {
			var parser = new domkit.MarkupParser();
			parser.allowRawText = true;
			var eparams = parseCode(data.params, fullText.indexOf(data.params));
			var expr = parser.parse(data.dml,res.entry.path, fullText.indexOf(data.dml));
			var interp = makeInterp();
			if( data.enums != null ) {
				var enums : Array<{ path : String, constrs : Array<String> }> = haxe.Json.parse(data.enums);
				for( e in enums ) {
					var en = Type.resolveEnum(e.path);
					if( en == null ) continue;
					for( c in e.constrs ) {
						var f : Dynamic = try Type.createEnum(en, c) catch( e : Dynamic ) Reflect.makeVarArgs((args) -> Type.createEnum(en,c,args));
						if( f != null && !interp.variables.exists(c) ) interp.variables.set(c, f);
					}
				}
			}
			var mainComp = null;
			for( i in 0...expr.children.length ) {
				var m = expr.children[expr.children.length - i - 1];
				switch( m.kind ) {
				case Node(name):
					mainComp = domkit.Component.get(name, true);
					break;
				default:
				}
			}

			var prev = interp.variables.copy();
			var mainInst : Dynamic = null;
			if( mainComp != null ) {
				var cl = @:privateAccess mainComp.classValue;
				if( cl != null ) {
					mainInst = Type.createEmptyInstance(cl);
					interp.setContext(mainInst);
				}
			}
			var vparams = switch( eparams.e ) {
			case EObject(fl):
				[for( f in fl ) {
					var val : Dynamic = evalCode(interp,f.e);
					var forceNull = res == resource && definedClasses.indexOf(f.name) >= 0;
					if( forceNull ) val = null;
					interp.variables.set(f.name, val);
					if( mainInst != null ) try Reflect.setProperty(mainInst,f.name, val) catch( e : Dynamic ) {};
					{ name : f.name, value : val };
				}];
			default: throw "assert";
			}
			interp.variables = prev;
			for( f in vparams )
				interp.variables.set(f.name, f.value);

			for( m in expr.children ) {
				switch( m.kind ) {
				case Node(name):
					if( tmpCompMap.exists(name) )
						error("Duplicate component "+name, m.pmin, m.pmax);
					var parentName = m.parent?.name ?? "flow";
					var compParent = resolveComponent(parentName, m.pmin);
					var comp = domkit.Component.get(name, true);
					var inst : Dynamic = null;
					if( comp == null ) {
						comp = new domkit.Component(name,null,compParent);
						domkit.CssStyle.CssData.registerComponent(comp);
						loadedComponents.push(cast comp);
					} else {
						var compClass = @:privateAccess comp.classValue;
						if( compClass != null ) {
							inst = Type.createEmptyInstance(compClass);
							interp.setContext(inst);
							for( f in vparams )
								try Reflect.setProperty(inst, f.name, f.value) catch( e : Dynamic ) {}
						}
					}
					var argNames = [];
					if( m.arguments != null ) {
						for( arg in m.arguments ) {
							switch( arg.value ) {
							case Code(code):
								var code = parseCode(code.split(":")[0], arg.pmin);
								switch( code.e ) {
								case EIdent(a):
									argNames.push(a);
									continue;
								default:
								}
							default:
							}
							error("Invalid argument decl", arg.pmin, arg.pmax);
						}
					}

					function make( args : Array<Dynamic>, parent : h2d.Object ) : h2d.Object {
						var prev = interp.variables.copy();
						var obj = null;
						handleErrors(res, function() {

							if( args.length > 0 && argNames.length > 0 ) {
								for( i => arg in argNames ) {
									interp.variables.set(arg, args[i]);
									if( inst != null )
										try Reflect.setProperty(inst, arg, args[i]) catch( e : Dynamic ) {};
								}
							}

							var fmake = tmpCompMap.get(comp.parent.name);
							if( fmake == null ) fmake = compHooks.get(comp.parent.name);
							if( fmake == null ) {
								fmake = comp.parent.make;
								if( m.parent != null )
									args = evalArgs(interp, m.parent.arguments);
							}
							obj = fmake(args, parent);
							if( obj.dom == null )
								obj.dom = new domkit.Properties(obj, cast comp);
							else
								@:privateAccess obj.dom.component = cast comp;

							interp.variables.set("this", inst ?? obj);
							if( inst != null )
								inst.dom = obj.dom;
						});
						var prevRoot = currentRoot;
						currentRoot = cast obj.dom.contentRoot;
						for( c in m.children )
							handleErrors(res, () -> addRec(c, interp, obj));
						interp.variables = prev;
						@:privateAccess obj.dom.contentRoot = currentRoot;
						currentRoot = prevRoot;
						if( inst != null )
							inst.dom = null;
						return obj;
					}

					tmpCompMap.set(name, make);
					inf.comps.push(make);
				default:
				}
			}
			inf.params = {};
			for( v in vparams )
				Reflect.setField(inf.params, v.name, v.value);
		});
		return inf;
	}

	function parseCode( codeStr : String, pos : Int ) {
		var parser = new hscript.Parser();
		return parser.parseString(codeStr, "");
	}

	function evalCode( interp : hscript.Interp, e : hscript.Expr ) : Dynamic {
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

	function handleErrors( res : hxd.res.Resource, callb ) {
		try {
			callb();
		} catch( e : domkit.Error ) {
			onError(res, e);
		} catch( e : hscript.Expr.Error ) {
			var p = e.toString().split(": ");
			p.shift();
			var msg = p.join(": ");
			onError(res, new domkit.Error(msg, e.pmin, e.pmax));
		}
	}

	function resolveComponent( fullName : String, pmin : Int ) {
		var name = fullName.split(".").pop();
		var comp = domkit.Component.get(name, true);
		if( comp == null ) {
			for( path in componentsPaths ) {
				var res = try hxd.res.Loader.currentInstance.load(path+"/"+name+".domkit") catch( e : hxd.res.NotFound ) continue;
				loadResource(res);
				loadComponents(res);
				comp = domkit.Component.get(name, true);
				if( comp == null ) {
					error(res.entry.path+" does not define component "+name, pmin, pmin + name.length);
					return null;
				}
				break;
			}
		}
		if( comp == null )
			error("Unknown component "+name, pmin, pmin + name.length);
		return comp;
	}

	function evalArgs( interp : DomkitInterp, args : Array<domkit.MarkupParser.Argument> ) : Array<Dynamic> {
		return [for( a in args ) {
			var v : Dynamic = switch( a.value ) {
			case RawValue(v): v;
			case Code(code):
				var code = parseCode(code, a.pmin);
				evalCode(interp, code);
			}
			v;
		}];
	}

	function addRec( e : domkit.MarkupParser.Markup, interp : DomkitInterp, parent : h2d.Object ) {
		var parentObj = cast(parent.dom?.contentRoot,h2d.Object) ?? parent;
		switch( e.kind ) {
		case Node(name):
			if( e.condition != null ) {
				var expr = parseCode(e.condition.cond, e.condition.pmin);
				if( !evalCode(interp, expr) )
					return;
			}
			var comp = resolveComponent(name, e.pmin+1);
			var args = evalArgs(interp, e.arguments);
			var make = tmpCompMap.get(comp.name);
			var obj = make != null ? make(args, parentObj) : comp.make(args, parentObj);
			if( obj == null )
				return;
			var p : domkit.Properties<Dynamic> = obj.dom;
			if( p == null )
				p = obj.dom = new domkit.Properties(obj, cast comp);

			var attributes = {};
			for( a in e.attributes ) {
				if( a.name == "id" ) {
					var objId = switch( a.value ) {
					case RawValue("true"):
						var name = null;
						for( a in e.attributes )
							if( a.name == "class" ) {
								name = switch( a.value ) { case RawValue(v): v; default: null; };
								break;
							}
						name;
					case RawValue(name) if( StringTools.endsWith(name,"[]") ):
						name.substr(0,name.length - 2);
					case RawValue(name):
						name;
					case Code(_): null;
					}
					if( objId != null )
						(attributes:Dynamic).id = objId;
					continue;
				}
				if( a.name == "__content__" ) {
					currentRoot = obj;
					continue;
				}
				switch( a.value ) {
				case RawValue(v):
					Reflect.setField(attributes,a.name,v);
				case Code(_):
					// skip (init after)
				}
			}
			p.initAttributes(attributes);
			for( a in e.attributes ) {
				switch( a.value ) {
				case RawValue(_):
				case Code(code):
					var h = comp.getHandler(domkit.Property.get(a.name));
					var v : Dynamic = evalCode(interp, parseCode(code, a.pmin));
					@:privateAccess p.initStyle(a.name, v);
					if( h == null ) {
						// might be a class field
						try Reflect.setProperty(obj, a.name, v) catch( e : Dynamic ) {}
					} else {
						h.apply(p.obj, v);
					}
				}
			}
			for( c in e.children )
				addRec(c, interp, cast p.contentRoot);
		case Text(text):
			var tf = new h2d.HtmlText(hxd.res.DefaultFont.get(), parentObj);
			tf.dom = domkit.Properties.create("html-text", tf);
			tf.text = text;
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			switch( expr.e ) {
			case EFor(n,it,_):
				interp.executeLoop(n, it, function() {
					for( c in e.children )
						addRec(c, interp, parent);
				});
				return;
			case EForGen(it,_):
				hscript.Tools.getKeyIterator(it, function(vk,vv,it) {
					if( vk == null ) {
						throw new domkit.Error("Invalid for loop", e.pmin);
						return;
					}
					interp.executeKeyValueLoop(vk,vv,it,function() {
						for( c in e.children )
							addRec(c, interp, parent);
					});
				});
				return;
			default:
			}
			throw new domkit.Error("Invalid for loop", e.pmin);
		case CodeBlock(v):
			throw new domkit.Error("Code block not supported", e.pmin);
		case Macro(id):
			throw new domkit.Error("Macro not supported", e.pmin);
		}
	}

}


class DomkitStyle extends h2d.domkit.Style {

	public function new() {
		super();
	}

	public function loadDefaults( globals : Array<hxd.res.Resource> ) {
		for( r in globals )
			load(r, true, true);
		for( path in CSS_SOURCES ) {
			var content = CONTENT.get(path);
			if( content == null )
				load(hxd.res.Loader.currentInstance.load(path));
			else
				load(new hxd.res.Resource(new hxd.fs.BytesFileSystem.BytesFileEntry(path,haxe.io.Bytes.ofString(content))));
		}
	}

	override function loadData( r : hxd.res.Resource ) {
		if( r.entry.extension != "domkit" )
			return super.loadData(r);
		var fullData = r.entry.getText();
		var data = DomkitFile.parse(fullData);
		return data.css;
	}

	static var CSS_SOURCES = [];
	static var CONTENT = new Map();
	public static function registerCSSSource( path : String, ?content : String ) {
		if( CSS_SOURCES.indexOf(path) >= 0 )
			return false;
		CSS_SOURCES.push(path);
		if( content != null ) CONTENT.set(path, content);
		return true;
	}
}

#end

typedef DomkitFileData = { css : String, params : String, dml : String, ?enums : String };

class DomkitFile {

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

		var enums = null;
		if( StringTools.startsWith(content,"<enums>") ) {
			var pos = content.indexOf("</enums>");
			enums = StringTools.trim(content.substr(7, pos - 8));
			content = content.substr(pos + 8);
			content = StringTools.trim(content);
		}

		return {
			css : cssText,
			params : paramsText,
			dml : content,
			enums : enums,
		}
	}

}
