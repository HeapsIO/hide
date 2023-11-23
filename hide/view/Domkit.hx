package hide.view;

import hscript.Checker.TType in Type;

private typedef TypedComponent = {
	var name : String;
	var ?parent : TypedComponent;
	var properties : Map<String, Type>;
	var arguments : Array<{ name : String, type : Type, ?opt : Bool }>;
}

class Domkit extends FileView {

	var cssEditor : hide.comp.CodeEditor;
	var dmlEditor : hide.comp.CodeEditor;
	var cssText : String;
	var dmlText : String;
	var prevSave : { css : String, dml : String };
	var t_string : Type;
	var checker : hide.comp.ScriptEditor.ScriptChecker;
	var components : Map<String, TypedComponent>;

	override function onDisplay() {
		element.html('<table class="domkitEditor">
			<tr>
				<td class="cssEditor">
				</td>
				<td class="separator">
				&nbsp;
				</td>
				<td class="dmlEditor">
				</td>
			</tr>
		</div>');

		var content = sys.io.File.getContent(getPath());
		cssText = "";

		if( StringTools.startsWith(content,"<css>") ) {
			var pos = content.indexOf("</css>");
			cssText = content.substr(5, pos - 5);
			content = content.substr(pos + 6);
		}

		cssText = StringTools.trim(cssText);
		dmlText = StringTools.trim(content);

		prevSave = { css : cssText, dml : dmlText };
		cssEditor = new hide.comp.CodeEditor(cssText, "less", element.find(".cssEditor"));
		cssEditor.onChanged = function() {
			cssText = cssEditor.code;
			check();
		};
 		dmlEditor = new hide.comp.CodeEditor(dmlText, "html", element.find(".dmlEditor"));
		dmlEditor.onChanged = function() {
			dmlText = dmlEditor.code;
			check();
		};
		cssEditor.onSave = dmlEditor.onSave = save;
		cssEditor.saveOnBlur = dmlEditor.saveOnBlur = false;

		checker = new hide.comp.ScriptEditor.ScriptChecker(config, "domkit");
		t_string = checker.checker.types.resolve("String");
		initComponents();
		check();
	}

	function initComponents() {
		components = [];
		/*
		for( t in @:privateAccess checker.checker.types.types ) {
			var c = switch( t ) {
			case CTClass(c) if( c.meta != null ): c;
			default: continue;
			}
			var name = null;
			for( m in c.meta ) {
				if( m.name == ":uiComp" ) {
					switch( m.params[0].e ) {
					case EConst(CString(s)):
						name = s;
						break;
					default:
					}
				}
			}
			if( name == null )
				continue;
			var comp : TypedComponent = {
				name : name,
				properties : [],
				arguments : [],
			};
			components.set(name, comp);
			cdefs.push({ name : name, c : c });
		}
		for( def in cdefs ) {
			var comp = components.get(def.name);
			var c = def.c;
		}*/
	}

	function check() {
		modified = prevSave.css != cssText || prevSave.dml != dmlText;

		// reset locals
		checker.checker.check({ e : EBlock([]), pmin : 0, pmax : 0, origin : "", line : 0 });

		function getLine( text:String, min:Int) {
			var lines = text.substr(0, min).split("\n");
			return lines.length;
		}

		try {
			var parser = new domkit.MarkupParser();
			parser.allowRawText = true;
			var expr = parser.parse(dmlText,state.path, 0);
			checkDML(expr, true);
			dmlEditor.clearError();
		} catch( e : domkit.Error ) {
			var line = getLine(dmlText, e.pmin);
			dmlEditor.setError(e.message, line, e.pmin, e.pmax);
		} catch( e : hscript.Expr.Error ) {
			var line = getLine(dmlText, e.pmin);
			dmlEditor.setError(e.toString(), line, e.pmin, e.pmax);
		}


		var includes : Array<String> = config.get("less.includes", []);
		var parser = new domkit.CssParser();
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

		try {
			var css = parser.parseSheet(cssText);
			cssEditor.clearError();
		} catch( e : domkit.Error ) {
			cssEditor.setError(e.message, getLine(cssText,e.pmin), e.pmin, e.pmax);
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
		return @:privateAccess checker.checker.typeExpr(e, Value);
	}

	function tryUnify( t1 : Type, t2 : Type ) {
		return checker.checker.tryUnify(t1,t2);
	}

	function typeStr( t : Type ) {
		return hscript.Checker.typeStr(t);
	}

	function checkDML( e : domkit.MarkupParser.Markup, isRoot=false ) {
		switch( e.kind ) {
		case Node(null):
			for( c in e.children )
				checkDML(c,isRoot);
		case Node(name):
			var c = resolveComp(name);
			if( isRoot ) {
				var arg0 = e.arguments[0];
				switch( arg0?.value ) {
				case null:
				case Code(code):
					e.arguments.shift();
					var code = parseCode(code, e.pmin);
					switch( code.e ) {
					case EIdent(name):
						c = resolveComp(name);
						//if( c == null )
						//	throw new domkit.Error("Unknown parent component "+name, arg0.pmin, arg0.pmax);
					default:
					}
				default:
				}
			}
			if( c == null && isRoot )
				c = resolveComp("flow");
			//if( c == null )
			//	throw new domkit.Error("Unknown component "+name, e.pmin, e.pmin + name.length);
			for( i => a in e.arguments ) {
				/*
				var arg = c.arguments[i];
				if( arg == null )
					throw new domkit.Error("Too many arguments (require "+[for( a in c.arguments ) a.name].join(",")+")",a.pmin,a.pmax);
				*/
				var t = switch( a.value ) {
				case RawValue(_): t_string;
				case Code(code): typeCode(code, a.pmin);
				};
				/*
				if( !tryUnify(t, arg.type) )
					throw new domkit.Error(typeStr(t)+" should be "+typeStr(arg.type)+" for "+arg.name, a.pmin, a.pmax);
				*/
			}
			/*for( i in e.arguments.length...c.arguments.length )
				if( !c.arguments[i].opt )
					throw new domkit.Error("Missing required argument "+c.arguments[i].name,e.pmin,e.pmax);
			*/
			for( a in e.attributes ) {
				//var pt = c.properties.get(a.name);
				//if( pt == null )
				//	throw new domkit.Error(c.name+" does not have property "+a.name, a.pmin, a.pmax);
				var t = switch( a.value ) {
				case RawValue(_): continue; // will be parsed as CSS
				case Code(code): typeCode(code, a.pmin);
				};
				//if( !tryUnify(t, pt) )
				//	throw new domkit.Error(typeStr(t)+" should be "+typeStr(pt)+" for "+c+"."+a.name, a.pmin, a.pmax);
			}
			for( c in e.children )
				checkDML(c);
		case For(cond):
			var expr = parseCode("for"+cond+"{}", e.pmin);
			switch( expr.e ) {
			case EFor(n,it,_): @:privateAccess {
				var et = checker.checker.getIteratorType(expr,checker.checker.typeExpr(it,Value));
				var prev = checker.checker.locals.get(n);
				checker.checker.locals.set(n, et);
				for( c in e.children )
					checkDML(c);
				if( prev == null )
					checker.checker.locals.remove(n);
				else
					checker.checker.locals.set(n, prev);
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

	override function save() {
		super.save();
		sys.io.File.saveContent(getPath(),'<css>\n$cssText\n</css>\n$dmlText');
		prevSave = { css : cssText, dml : dmlText };
	}

	override function getDefaultContent() {
		var tag = getPath().split("/").pop().split(".").shift();
		return haxe.io.Bytes.ofString('<css>\n$tag {\n}\n</css>\n<$tag>\n</$tag>');
	}

	static var _ = FileTree.registerExtension(Domkit,["domkit"],{ icon : "id-card-o", createNew : "Domkit Component" });

}