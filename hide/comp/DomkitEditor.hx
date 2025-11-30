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
	var ?classDef : hscript.Checker.CClass;
	var ?parent : { comp : TypedComponent, params : Array<Type> };
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
		var c = @:privateAccess dom.resolveComp(i);
		return c?.domkitComp;
	}

}


class DomkitChecker extends ScriptEditor.ScriptChecker {

	var t_string : Type;
	var parsers : Array<domkit.CssValue.ValueParser>;
	var lastVariables : Map<String, domkit.CssValue> = new Map();
	var currentComponent : hscript.Checker.CClass;
	public var params : Map<String, Type> = new Map();
	public var components : Map<String, TypedComponent>;
	public var properties : Map<String, Array<TypedProperty>>;
	public var definedIdents : Map<String, Array<TypedComponent>> = [];

	public function new(config) {
		super(config,"domkit");
		defaultPublicFields = true;
		parsers = [new h2d.domkit.BaseComponents.CustomParser()];
		var dcfg : Array<String> = config.get("domkit.parsers");
		if( dcfg != null ) {
			for( name in dcfg ) {
				var cl = std.Type.resolveClass(name);
				if( cl == null ) {
					ide.error("Couldn't find custom domkit parser "+name);
					continue;
				}
				parsers.push(std.Type.createInstance(cl,[]));
			}
		}
	}

	override function initTypes() {
		if( !super.initTypes() )
			return false;
		t_string = checker.types.resolve("String");
		initComponents();
		return true;
	}

	public function checkDML( dmlCode : String, filePath : String, position = 0 ) {
		init();
		// reset locals and other vars
		checker.check({ e : EBlock([]), pmin : 0, pmax : 0, origin : "", line : 0 });
		@:privateAccess checker.locals = params.copy();
		definedIdents = new Map();
		var parser = new domkit.MarkupParser();
		parser.allowRawText = true;
		var expr = parser.parse(dmlCode,filePath, position);
		try {
			for( c in expr.children ) {
				var prev = @:privateAccess checker.locals.copy();
				var prevGlobals = @:privateAccess checker.globals.copy();

				currentComponent = null;
				switch( c.kind ) {
				case Node(name):
					var comp = resolveComp(name);
					if( comp != null && comp.classDef != null ) {
						currentComponent = comp.classDef;
						checker.setGlobals(comp.classDef, true);
						checker.setGlobal("this",TInst(comp.classDef,[]));
					}
					defineComponent(name, c, params);
				default:
					continue;
				}
				for( c in c.children )
					checkDMLRec(c);
				@:privateAccess {
					checker.locals = prev;
					checker.globals = prevGlobals;
				}
			}
		} catch( e : hscript.Expr.Error ) {
			throw new domkit.Error(e.toString(), e.pmin, e.pmax);
		}
	}

	public function formatDML( code : String ) : String {
		code = StringTools.trim(code);
		code = [for( l in code.split("\n") ) StringTools.rtrim(l)].join("\n");
		var parser = new domkit.MarkupParser();
		parser.allowRawText = true;
		var expr = parser.parse(code,"", 0);
		return domkit.MarkupParser.markupToString(expr);
	}

	public function checkLess( cssCode : String ) {
		var includes : Array<String> = config.get("less.includes", []);
		var parser = new DomkitCssParser(this);
		parser.allowSubRules = true;
		parser.allowVariablesDecl = true;
		for( file in includes ) {
			var content = sys.io.File.getContent(ide.getPath(file));
			try {
				parser.parseSheet(content, file);
			}  catch( e : domkit.Error ) {
				var line = content.substr(0, e.pmin).split("\n").length;
				ide.quickError(file+":"+line+": "+e.message);
			}
		}
		lastVariables = parser.variables;
		var rules = parser.parseSheet(cssCode, null);
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
				if( comp == null ) break;
			}
			for( s in r.style ) {
				var value = s.value;
				switch( s.value ) {
				case VLabel("important", val): value = val;
				default:
				}
				typeProperty(s.p.name, s.pmin, s.pmax, value, comp?.r);
			}
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
			c.domkitComp = std.Type.createEmptyInstance(domkit.Component);
			c.domkitComp.name = name;
		}
		components.set(name, c);
		return c;
	}

	function makePropParser( t : Type ) {
		return switch( t ) {
		case TInt: PNamed("Int");
		case TFloat: PNamed("Float");
		case TBool: PNamed("Bool");
		case TNull(t):
			POpt(makePropParser(t),"none");
		case TInst(c,_):
			switch( c.name ) {
			case "String": PNamed("String");
			default: PUnknown;
			}
		case TEnum(e,_):
			PEnum(e);
		default:
			var t2 = checker.followOnce(t);
			if( t != t2 )
				makePropParser(t);
			else
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
			comp.classDef = c;
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
						domkit.Property.get(name); // force create, prevent warning if used in css
					}
					var dup = false;
					for( p2 in pl )
						if( p2.parser.equals(p.parser) && p2.type.equals(p.type) ) {
							dup = true;
							break;
						}
					if( !dup )
						pl.push(p);
				} else if( f.canWrite )
					comp.vars.set(f.name, f.t);
			}
			cdefs.push({ name : name, c : c });
		}
		for( def in cdefs ) {
			var comp = components.get(def.name);
			var c = def.c;
			var p = c;
			var parent = null;
			var params = null;
			while( parent == null && p.superClass != null ) {
				switch( p.superClass ) {
				case null:
					break;
				case TInst(pp, pl):
					parent = cmap.get(pp.name);
					p = pp;
					if( params == null )
						params = pl;
					else
						params = [for( p in params ) checker.apply(p, pp.params, pl)];
				default:
					throw "assert";
				}
			}
			if( parent != null )
				comp.parent = { comp : parent, params : params };
		}
	}

	function resolveComp( name : String ) : TypedComponent {
		return components.get(name);
	}

	function parseCode( code : String, pos : Int ) {
		var parser = new hscript.Parser();
		return parser.parseString(code, pos);
	}

	function parseType( tstr : String, pos : Int ) {
		var parser = new hscript.Parser();
		parser.allowTypes = true;
		var expr = parser.parseString("(x:"+tstr+")", pos - 3 );
		return switch( expr.e ) {
		case ECheckType(_,t): @:privateAccess checker.makeType(t, expr);
		default: throw "assert";
		}
	}

	function typeCode( code : String, pos : Int, ?et ) : Type {
		var e = parseCode(code, pos);
		return @:privateAccess checker.typeExpr(e, et == null ? Value : WithType(et));
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
			comp = comp.parent?.comp;
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
							err = e.message ?? "Invalid property "+domkit.CssParser.valueStr(value)+" (should be "+name+")";
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

	function domkitError(msg,pmin,pmax=-1) {
		throw new domkit.Error(msg, pmin, pmax);
	}

	static var IDENT = ~/^([A-Za-z_][A-Za-z0-9_]*)$/;

	function defineComponent( name : String, e : domkit.MarkupParser.Markup, params : Map<String,Type> ) {
		var parent = null;
		var c = components.get(name);
		if( e.parent != null ) {
			parent = resolveComp(e.parent.name);
			if( parent == null )
				domkitError("Unknown parent component", e.parent.pmin, e.parent.pmax);
		}
		if( parent == null )
			parent = components.get("flow");
		if( c == null )
			c = makeComponent(name);
		c.parent = parent == null ? null : { comp : parent, params : [] };
		if( e.arguments == null || e.arguments.length == 0 )
			c.arguments = parent == null || (e.parent != null && e.parent.arguments.length != 0) ? [] : parent.arguments;
		else {
			c.arguments = [];
			for( i => a in e.arguments ) {
				var type = null;
				var name = switch( a.value ) {
				case Code(c) if( IDENT.match(c) ):
					c;
				case Code(c):
					var parts = c.split(":");
					var p0len = parts[0].length;
					var name = StringTools.trim(parts.shift());
					if( !IDENT.match(name) )
						null;
					else {
						type = parseType(parts.join(":"),a.pmin + p0len);
						name;
					}
				default:
					null;
				}
				if( name == null ) {
					domkitError("Invalid parameter", a.pmin, a.pmax);
					continue;
				}
				if( type == null && currentComponent != null ) {
					var args = switch( currentComponent.constructor?.t ) { case null: null; case TFun(args,_): args; default: null; };
					if( args != null && args[i].name == name )
						type = args[i].t;
				}
				if( type == null )
					type = params.get(name);
				if( type == null )
					domkitError("Unknown parameter type", a.pmin, a.pmax);
				c.arguments.push({
					name : name,
					t : type,
				});
				@:privateAccess checker.locals.set(name, type);
			}
		}
		if( e.condition != null )
			domkitError("Invalid condition", e.condition.pmin, e.condition.pmax);
		if( e.attributes.length > 0 )
			domkitError("Invalid attribute", e.attributes[0].pmin, e.attributes[0].pmax);
		if( e.parent != null )
			checkArguments(parent, e.parent.arguments, e.parent.pmin, e.parent.pmax);
		return c;
	}

	function checkArguments( c : TypedComponent, args : Array<domkit.MarkupParser.Argument>, pmin, pmax ) {
		for( i => a in args ) {
			var arg = c.arguments[i];
			if( arg == null )
				domkitError("Too many arguments (require "+[for( a in c.arguments ) a.name].join(",")+")",a.pmin,a.pmax);
			var t = switch( a.value ) {
			case RawValue(_): t_string;
			case Code(code): typeCode(code, a.pmin, arg.t);
			};
			unify(t, arg.t, c, arg.name, a);
		}
		for( i in args.length...c.arguments.length )
			if( !c.arguments[i].opt )
				domkitError("Missing required argument "+c.arguments[i].name,pmin,pmax);
	}

	static var R_IDENT = ~/^([A-Za-z_-][A-Za-z0-9_-]*)$/;

	function checkDMLRec( e : domkit.MarkupParser.Markup ) {
		switch( e.kind ) {
		case Node(name):
			var c = resolveComp(name);
			if( c == null )
				domkitError("Unknown component "+name, e.pmin, e.pmin + name.length);
			checkArguments(c, e.arguments, e.pmin, e.pmax);
			for( a in e.attributes ) {
				var pname = haxeToCss(a.name);
				switch( pname ) {
				case "class":
					switch( a.value ) {
					case RawValue(str):
						for( cl in ~/[ \t]+/g.split(str) )
							defineIdent(c,cl);
					case Code(code):
						var e = try parseCode(code, a.pmin) catch( e : hscript.Expr.Error ) parseCode("{"+code+"}",a.pmin-1);
						switch( e.e ) {
						case EObject(fl):
							for( f in fl ) {
								defineIdent(c, f.name);
								unify(@:privateAccess checker.typeExpr(f.e, Value), TBool, c,"class",f.e);
							}
						default:
							domkitError("Invalid class value",a.pmin,a.pmax);
						}
					}
					continue;
				case "id":
					switch( a.value ) {
					case RawValue("true"):
						for( a in e.attributes )
							if( a.name == "class" ) {
								switch( a.value ) {
								case RawValue(str):
									var id = str.split(" ")[0];
									if( R_IDENT.match(id) ) {
										defineIdent(c, "#"+id);
										break;
									}
								default:
								}
								domkitError("Auto-id reference invalid class",a.pmin,a.pmax);
								break;
							}
					case RawValue(id):
						defineIdent(c, "#"+id);
					case Code(_):
						domkitError("Not constant id is not allowed",a.pmin,a.pmax);
					}
					continue;
				case "__content__":
					switch( a.value ) {
					case RawValue("true"):
						continue;
					default:
					}
				default:
				}
				var p = resolveProperty(c, pname);
				if( p == null ) {
					var t = null, cur = c, chain = [];
					while( t == null && cur != null ) {
						t = cur.vars.get(a.name);
						if( t == null )
							chain.unshift(cur);
						cur = cur.parent?.comp;
					}
					if( t == null )
						domkitError(c.name+" does not have property "+a.name, a.pmin, a.pmax);
					for( c in chain )
						if( c.parent.params.length > 0 )
							t = checker.apply(t, c.parent.comp.classDef.params, c.parent.params);
					var pt = switch( a.value ) {
					case RawValue(_): t_string;
					case Code(code): typeCode(code, a.vmin, t);
					}
					unify(pt, t, c, a.name, a);
					continue;
				}
				switch( a.value ) {
				case RawValue(str):
					typeProperty(pname, a.vmin, a.pmax, new domkit.CssParser().parseValue(str), c);
				case Code(code):
					var t = typeCode(code, a.vmin, p.type);
					unify(t, p.type, c, pname, a);
				}
			}
			if( e.condition != null ) {
				var cond = e.condition;
			 	var t = typeCode(cond.cond, cond.pmin, TBool);
				unify(t, TBool, c, "if", cond);
			}
			for( c in e.children )
				checkDMLRec(c);
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			inline function restore(v,t) {
				@:privateAccess if( t == null ) checker.locals.remove(v) else checker.locals.set(v, t);
			}
			switch( expr.e ) {
			case EFor(n,it,_): @:privateAccess {
				var et = checker.getIteratorType(checker.typeExpr(it,Value),it);
				var prev = checker.locals.get(n);
				checker.locals.set(n, et);
				for( c in e.children )
					checkDMLRec(c);
				restore(n, prev);
			}
			case EForGen(it,_):
				hscript.Tools.getKeyIterator(it, function(vk,vv,it) @:privateAccess {
					if( vk == null ) {
						domkitError("Invalid for block", e.pmin);
						return;
					}
					var types = checker.getKeyIteratorTypes(checker.typeExpr(it,Value),it);
					var prevKey = checker.locals.get(vk);
					var prevValue = checker.locals.get(vv);
					checker.locals.set(vk, types.key);
					checker.locals.set(vv, types.value);
					for( c in e.children )
						checkDMLRec(c);
					restore(vk, prevKey);
					restore(vv, prevValue);
				});
			default:
				domkitError("Invalid for block", e.pmin);
			}
		case Text(_):
			// nothing
		case CodeBlock(v):
			domkitError("Code block not supported", e.pmin);
		case Macro(id):
			domkitError("Macro not supported", e.pmin);
		}
	}

}


class DomkitEditor extends CodeEditor {

	public var kind : DomkitEditorKind;
	public var checker : DomkitChecker;

	public function new( config, kind, code : String, ?checker, ?parent : Element, ?root : Element ) {
		this.kind = kind;
		allowScrollBeyondLine = true;
		var lang = kind == DML ? "html" : "less";
		super(code, lang, parent, root);
		switch( kind ) {
		case DML:
			initCompletion(["<","/"]);
		case Less:
			initCompletion();
		}
		saveOnBlur = false;
		if( checker == null )
			checker = new DomkitChecker(config);
		this.checker = checker;

	}

	override function onKey( e : js.jquery.Event ) {
		if( e.keyCode == hxd.Key.F12 ) {
			e.preventDefault();
			var pos = editor.getPosition();
			var line = code.split("\n")[pos.lineNumber - 1];
			var col = pos.column - 1;
			var validChar = ~/[A-Za-z0-9\-]/;
			if( !validChar.match(line.substr(col,1)) )
				return;
			while( col >= 0 ) {
				var c = line.charCodeAt(col);
				if( c == " ".code || c == "\t".code || c == "<".code || c == ",".code ) {
					col++;
					break;
				}
				if( !validChar.match(line.charAt(col)) )
					return;
				col--;
			}
			if( col < 0 ) col = 0;
			var r = ~/^([A-Za-z][A-Za-z0-9\-]*)/;
			if( r.match(line.substr(col)) )
				gotoComponent(r.matched(1));
		}
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

	public dynamic function gotoComponent(name:String) {
	}

	public function getComponent() {
		var compReg = ~/<\/([A-Za-z0-9_-]+)/;
		var last = code.lastIndexOf("</");
		if( last < 0 )
			return null;
		if( !compReg.match(code.substr(last)) )
			return null;
		var name = compReg.matched(1);
		return checker.components.get(name);
	}

	override function getCompletion( position : Int ) {
		var code = code;
		var results = super.getCompletion(position);
		for( c in checker.components )
			results.push({
				kind : Class,
				label : c.name,
			});
		if( kind == DML && (code.charCodeAt(position-1) == "<".code || code.charCodeAt(position-1) == "/".code) )
			return results;
		for( pname => pl in checker.properties ) {
			var p = pl[0];
			results.push({
				kind : Field,
				label : kind == Less ? pname : p.field,
			});
		}
		switch( kind ) {
		case Less:
			for( c => def in @:privateAccess checker.lastVariables )
				results.push({
					kind : Property,
					label : "@"+c,
					detail : domkit.CssParser.valueStr(def),
				});
			for( id in checker.definedIdents.keys() )
				results.push({
					kind : Property,
					label : id.charCodeAt(0) == "#".code ? id : "."+id,
				});
		case DML:
		}
		return results;
	}

}