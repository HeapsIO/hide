package hide.comp;

import hscript.Checker.TType in Type;

enum DomkitEditorKind {
	DML;
	Less;
}

private enum PropParser {
	PUnknown;
	PNamed( name : String );
	POpt( t : PropParser, def : String );
	PEnum( e : hscript.Checker.CEnum );
}

private typedef TypedProperty = {
	var type : Type;
	var comp : TypedComponent;
	var field : String;
	var parser : PropParser;
}

private typedef TypedComponent = {
	var name : String;
	var ?parent : TypedComponent;
	var properties : Map<String, TypedProperty>;
	var vars : Map<String, Type>;
	var arguments : Array<{ name : String, t : Type, ?opt : Bool }>;
	var domkitComp : domkit.Component<Dynamic,Dynamic>;
}

private class DomkitCssParser extends domkit.CssParser {

	var dom : DomkitChecker;

	public function new(dom) {
		super();
		this.dom = dom;
	}

	override function resolveComponent(i:String, p:Int) {
		var c = @:privateAccess dom.components.get(i);
		return c?.domkitComp;
	}

}


class DomkitChecker extends ScriptEditor.ScriptChecker {

	var t_string : Type;
	var parsers : Array<domkit.CssValue.ValueParser>;
	var components : Map<String, TypedComponent>;
	var properties : Map<String, Array<TypedProperty>>;
	var definedIdents : Map<String, Array<TypedComponent>>;

	public function new(config) {
		super(config,"domkit");
		t_string = checker.types.resolve("String");

		parsers = [new h2d.domkit.BaseComponents.CustomParser()];
		var dcfg : Array<String> = config.get("domkit-parsers");
		if( dcfg != null ) {
			for( name in dcfg ) {
				var cl = Type.resolveClass(name);
				if( cl == null ) {
					ide.error("Couldn't find custom domkit parser "+name);
					continue;
				}
				dcfg.push(Type.createInstance(cl,[]));
			}
		}
		initComponents();
	}

	public function checkDML( dmlCode : String, filePath : String, position = 0 ) {
		// reset locals
		checker.check({ e : EBlock([]), pmin : 0, pmax : 0, origin : "", line : 0 });
		definedIdents = new Map();
		var parser = new domkit.MarkupParser();
		parser.allowRawText = true;
		var expr = parser.parse(dmlCode,filePath, position);
		try {
			checkDMLRec(expr, true);
		} catch( e : hscript.Expr.Error ) {
			throw new domkit.Error(e.toString(), e.pmin, e.pmax);
		}
	}

	public function checkLess( cssCode : String ) {
		var includes : Array<String> = config.get("less.includes", []);
		var parser = new DomkitCssParser(this);
		parser.allowSubRules = true;
		parser.allowVariablesDecl = true;
		for( file in includes ) {
			var content = sys.io.File.getContent(ide.getPath(file));
			try {
				parser.parseSheet(content);
			}  catch( e : domkit.Error ) {
				var line = content.substr(0, e.pmin).split("\n").length;
				ide.quickError(file+":"+line+": "+e.message);
			}
		}

		var rules = parser.parseSheet(cssCode);
		var w = parser.warnings[0];
		if( w != null )
			throw new domkit.Error(w.msg, w.pmin, w.pmax);
		for( r in rules ) {
			var comp = { r : null };
			inline function setComp(c:TypedComponent) {
				if( comp.r == null || comp.r == c )
					comp.r = c;
				else
					comp = null;
			}
			for( c in r.classes ) {
				if( c.component == null ) {
					if( c.id != null ) {
						var comps = definedIdents.get("#"+c.id.toString());
						if( comps == null || comps.length > 1 )
							comp = null;
						else
							setComp(comps[0]);
					} else
						comp = null;
				} else {
					var comp = components.get(c.component.name);
					setComp(comp);
				}
			}
			for( s in r.style )
				typeProperty(s.p.name, s.pmin, s.pmax, s.value, comp?.r);
		}
	}


	function haxeToCss( name : String ) {
		return name.charAt(0).toLowerCase()+~/[A-Z]/g.map(name.substr(1), (r) -> "-"+r.matched(0).toLowerCase());
	}

	function makeComponent(name) {
		var c : TypedComponent = {
			name : name,
			properties : [],
			arguments : [],
			vars : [],
			domkitComp : domkit.Component.get(name, true),
		};
		if( c.domkitComp == null ) {
			c.domkitComp = Type.createEmptyInstance(domkit.Component);
			c.domkitComp.name = name;
		}
		components.set(name, c);
		return c;
	}

	function makePropParser( t : Type ) {
		return switch( checker.follow(t) ) {
		case TInt: PNamed("Int");
		case TFloat: PNamed("Float");
		case TBool: PNamed("Bool");
		case TAbstract(a,params):
			return switch( a.name ) {
			case "Null": POpt(makePropParser(params[0]), "none"); // todo : auto?
			default: PUnknown;
			}
		case TInst(c,_):
			switch( c.name ) {
			case "String": PNamed("String");
			default: PUnknown;
			}
		case TEnum(e,_):
			PEnum(e);
		default:
			PUnknown;
		}
	}

	function initComponents() {
		components = [];
		properties = [];
		var cdefs = [];
		var cmap = new Map();
		for( t in @:privateAccess checker.types.types ) {
			var c = switch( t ) {
			case CTClass(c) if( c.meta != null ): c;
			default: continue;
			}
			var name = null;
			for( m in c.meta ) {
				if( m.name == ":build" && m.params.length > 0 ) {
					var str = hscript.Printer.toString(m.params[0]);
					if( str == "h2d.domkit.InitComponents.build()" ) {
						for( f in c.statics ) {
							if( f.name == "ref" ) {
								switch( f.t ) {
								case TInst(c,_) if( StringTools.startsWith(c.name,"domkit.Comp") ):
									name = haxeToCss(c.name.substr(11));
									break;
								default:
								}
							}
						}
						break;
					}
				}
			}
			if( name == null )
				continue;
			var comp = makeComponent(name);
			cmap.set(c.name, comp);
			if( StringTools.startsWith(c.name,"h2d.domkit.") )
				cmap.set("h2d."+c.name.substr(11,c.name.length-11-4), comp);
			if( c.constructor != null ) {
				switch( c.constructor.t ) {
				case TFun(args,_): comp.arguments = args;
				default:
				}
			}
			for( f in c.fields ) {
				var prop = null;
				if( f.meta != null ) {
					for( m in f.meta )
						if( m.name == ":p" ) {
							prop = m;
							break;
						}
				}
				if( prop != null ) {
					var parser = switch( prop.params[0] ) {
					case null: null;
					case { e : EIdent(def = "auto"|"none") }:
						switch( makePropParser(f.t) ) {
						case POpt(p,_), p: POpt(p,def);
						}
					case { e : EIdent(name) }: PNamed(name.charAt(0).toUpperCase()+name.substr(1));
					default: null;
					};
					if( parser == null )
						parser = makePropParser(f.t);
					var name = haxeToCss(f.name);
					var p : TypedProperty = { field : f.name, type : f.t, parser : parser, comp : comp };
					comp.properties.set(name, p);
					var pl = properties.get(name);
					if( pl == null ) {
						pl = [];
						properties.set(name, pl);
					}
					var dup = false;
					for( p2 in pl )
						if( p2.parser.equals(p.parser) && p2.type.equals(p.type) ) {
							dup = true;
							break;
						}
					if( !dup )
						pl.push(p);
				} else {
					switch( f.t ) {
					case TFun(_):
					default:
						comp.vars.set(f.name, f.t);
					}
				}
			}
			cdefs.push({ name : name, c : c });
		}
		for( def in cdefs ) {
			var comp = components.get(def.name);
			var c = def.c;
			if( c.superClass != null )
				switch( c.superClass ) {
				case TInst(csup,_):
					var parent = cmap.get(csup.name);
					if( parent == null )
						throw "Missing parent "+csup.name;
					comp.parent = parent;
				default:
				}
		}
	}

	function resolveComp( name : String ) : TypedComponent {
		return components.get(name);
	}

	function parseCode( code : String, pos : Int ) {
		var parser = new hscript.Parser();
		return parser.parseString(code, pos);
	}

	function typeCode( code : String, pos : Int ) : Type {
		var e = parseCode(code, pos);
		return @:privateAccess checker.typeExpr(e, Value);
	}

	function unify( t1 : Type, t2 : Type, comp : TypedComponent, prop : String, pos : { pmin : Int, pmax : Int } ) {
		if( !checker.tryUnify(t1, t2) )
			throw new domkit.Error(typeStr(t1)+" should be "+typeStr(t2)+" for "+comp.name+"."+prop, pos.pmin, pos.pmax);
	}

	function typeStr( t : Type ) {
		return hscript.Checker.typeStr(t);
	}

	function resolveProperty( comp : TypedComponent, name : String ) {
		while( comp != null ) {
			var p = comp.properties.get(name);
			if( p != null )
				return p;
			comp = comp.parent;
		}
		return null;
	}

	function typeProperty( pname : String, pmin : Int, pmax : Int, value : domkit.CssValue, ?comp : TypedComponent ) {
		function error(msg) {
			throw new domkit.Error(msg, pmin, pmax);
		}
		var pl = [];
		if( comp != null ) {
			var p = resolveProperty(comp, pname);
			if( p == null )
				error(comp.name+" does not have property "+pname);
			pl = [p];
		} else {
			pl = properties.get(pname);
			if( pl == null )
				error("Unknown property "+pname);
		}
		var err : String = null;
		for( p in pl ) {
			var msg = checkParser(p, p.parser, value);
			if( msg == null ) return;
			if( err == null || err.length < msg.length )
				err = msg;
		}
		error(err);
	}

	function checkParser( p : TypedProperty, parser : PropParser, value : domkit.CssValue ) {
		switch( parser ) {
		case PUnknown:
			// no check
			return null;
		case PNamed(name):
			var err : String = null;
			for( parser in parsers ) {
				var f = Reflect.field(parser, "parse"+name);
				if( f != null ) {
					try {
						Reflect.callMethod(parser, f, [value]);
						return null;
					} catch( e : domkit.Property.InvalidProperty ) {
						if( err == null || (e.message != null && e.message.length < err.length) )
							err = e.message ?? "Invalid property (should be "+name+")";
					}
				}
			}
			return err ?? "Could not find matching parser";
		case POpt(t, def):
			switch( value ) {
			case VIdent(n) if( n == def ):
				return null;
			default:
				return checkParser(p, t, value);
			}
		case PEnum(e):
			switch( value ) {
			case VIdent(i):
				for( c in e.constructors ) {
					if( (c.args == null || c.args.length == 0) && haxeToCss(c.name) == i )
						return null;
				}
			default:
			}
			return domkit.CssParser.valueStr(value)+" should be "+[for( c in e.constructors ) if( c.args == null || c.args.length == 0 ) haxeToCss(c.name)].join("|");
		}
	}

	function defineIdent( c : TypedComponent, cl : String ) {
		var comps = definedIdents.get(cl);
		if( comps == null ) {
			comps = [];
			definedIdents.set(cl, comps);
		}
		if( comps.indexOf(c) < 0 )
			comps.push(c);
	}

	function checkDMLRec( e : domkit.MarkupParser.Markup, isRoot=false ) {
		switch( e.kind ) {
		case Node(null):
			for( c in e.children )
				checkDMLRec(c,isRoot);
		case Node(name):
			var c = resolveComp(name);
			if( isRoot ) {
				var parts = name.split(":");
				var parent = null;
				if( parts.length == 2 ) {
					name = parts[0];
					c = resolveComp(name);
					parent = resolveComp(parts[1]);
					if( parent == null ) {
						var start = e.pmin + name.length + 1;
						throw new domkit.Error("Unknown parent component "+parts[1], start, start + parts[1].length);
					}
				}
				if( c == null )
					c = makeComponent(name);
				c.parent = parent;
				c.arguments = parent == null ? [] : c.arguments;
			}
			if( c == null && isRoot )
				c = resolveComp("flow");
			if( c == null )
				throw new domkit.Error("Unknown component "+name, e.pmin, e.pmin + name.length);
			for( i => a in e.arguments ) {
				var arg = c.arguments[i];
				if( arg == null )
					throw new domkit.Error("Too many arguments (require "+[for( a in c.arguments ) a.name].join(",")+")",a.pmin,a.pmax);
				var t = switch( a.value ) {
				case RawValue(_): t_string;
				case Code(code): typeCode(code, a.pmin);
				};
				unify(t, arg.t, c, arg.name, a);
			}
			for( i in e.arguments.length...c.arguments.length )
				if( !c.arguments[i].opt )
					throw new domkit.Error("Missing required argument "+c.arguments[i].name,e.pmin,e.pmax);
			for( a in e.attributes ) {
				var pname = haxeToCss(a.name);
				switch( pname ) {
				case "class":
					switch( a.value ) {
					case RawValue(str):
						for( cl in ~/[ \t]+/g.split(str) )
							defineIdent(c,cl);
					case Code(code):
						var e = parseCode(code, a.pmin);
						switch( e.e ) {
						case EObject(fl):
							for( f in fl ) {
								defineIdent(c, f.name);
								unify(@:privateAccess checker.typeExpr(f.e, Value), TBool, c,"class",f.e);
							}
						default:
							throw new domkit.Error("Invalid class value",a.pmin,a.pmax);
						}
					}
					continue;
				case "id":
					switch( a.value ) {
					case RawValue("true"):
						for( a in e.attributes )
							if( a.name == "class" ) {
								switch( a.value ) {
								case RawValue(str) if( str.indexOf(" ") < 0 ):
									defineIdent(c, "#"+str);
								default:
									throw new domkit.Error("Auto-id reference invalid class",a.pmin,a.pmax);
								}
							}
					case RawValue(id):
						defineIdent(c, "#"+id);
					case Code(_):
						throw new domkit.Error("Not constant id is not allowed",a.pmin,a.pmax);
					}
					continue;
				default:
				}
				var p = resolveProperty(c, pname);
				if( p == null ) {
					var t = null, cur = c;
					while( t == null && cur != null ) {
						t = cur.vars.get(a.name);
						cur = cur.parent;
					}
					if( t == null )
						throw new domkit.Error(c.name+" does not have property "+a.name, a.pmin, a.pmax);
					var pt = switch( a.value ) {
					case RawValue(_): t_string;
					case Code(code): typeCode(code, a.pmin);
					}
					unify(t, pt, c, a.name, a);
					continue;
				}
				switch( a.value ) {
				case RawValue(str):
					typeProperty(pname, a.pmin, a.pmax, new domkit.CssParser().parseValue(str), c);
				case Code(code):
					var t = typeCode(code, a.pmin);
					unify(t, p.type, c, pname, a);
				}
			}
			for( c in e.children )
				checkDMLRec(c);
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			switch( expr.e ) {
			case EFor(n,it,_): @:privateAccess {
				var et = checker.getIteratorType(expr,checker.typeExpr(it,Value));
				var prev = checker.locals.get(n);
				checker.locals.set(n, et);
				for( c in e.children )
					checkDMLRec(c);
				if( prev == null )
					checker.locals.remove(n);
				else
					checker.locals.set(n, prev);
			}
			default:
				throw "assert";
			}
		case Text(_):
			// nothing
		case CodeBlock(v):
			throw new domkit.Error("Code block not supported", e.pmin);
		case Macro(id):
			throw new domkit.Error("Macro not supported", e.pmin);
		}
	}

}


class DomkitEditor extends CodeEditor {

	public var kind : DomkitEditorKind;
	public var checker : DomkitChecker;

	public function new( config, kind, code : String, ?checker, ?parent : Element, ?root : Element ) {
		this.kind = kind;
		super(code, kind == DML ? "html" : "less", parent, root);
		saveOnBlur = false;
		if( checker == null )
			checker = new DomkitChecker(config);
		this.checker = checker;
	}

	public function setDomkitError( e : domkit.Error ) {
		var lines = code.substr(0, e.pmin).split("\n");
		setError(e.message, lines.length, e.pmin, e.pmax);
	}

	public function check() {
		try {
			switch( kind ) {
			case DML: checker.checkDML(code, "", 0);
			case Less: checker.checkLess(code);
			}
			clearError();
		} catch( e : domkit.Error ) {
			setDomkitError(e);
		}
	}

}