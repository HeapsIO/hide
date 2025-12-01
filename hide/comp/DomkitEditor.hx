package hide.comp;

import domkit.Checker;

enum DomkitEditorKind {
	DML;
	Less;
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


class DomkitChecker {

	var ide : hide.Ide;
	var config : hide.Config;
	var checker : domkit.Checker;
	var parsers : Array<domkit.CssValue.ValueParser>;
	var lessVariables : Map<String, domkit.CssValue> = new Map();
	var definedIdents : Map<String, Array<TypedComponent>> = new Map();

	public function new(config) {
		ide = hide.Ide.inst;
		this.config = config;
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
		if( !domkit.Checker.isInit() ) {
			var api : Array<String> = config.get("script.api.files");
			if( api.length == 0 ) ide.error("Missing 'script.api.files' in props.json");
			domkit.Checker.init(ide.getPath(api[0]));
		}
		checker = domkit.Checker.inst;
	}

	function getChecker() {
		var chk = new DMLChecker();
		chk.definedIdents = definedIdents;
		chk.parsers = parsers;
		return chk;
	}

	static var R_PREFIX = ~/<([A-Za-z0-9-]+)/;

	public function checkDML( dmlCode : String, filePath : String, position = 0 ) {
		try {
			var locals = {};
			if( R_PREFIX.match(dmlCode) ) {
				var compName = R_PREFIX.matched(1);
				var c = checker.components.get(compName);
				if( c != null && c.classDef != null ) {
					for( s in c.classDef.statics )
						if( StringTools.endsWith(s.name,"__LOCALS_TYPES") ) {
							switch( s.t ) {
							case TAnon(fields):
								for( f in fields )
									Reflect.setField(locals, f.name, { ctype : f.t });
							default:
							}
							break;
						}
				}
			}
			getChecker().parse(dmlCode,filePath,position,locals);
		} catch( e : hscript.Expr.Error ) {
			var offset = 1; // hscript is pmax-included whereas domkit is pmax-excluded
			throw new domkit.Error(e.toString(), e.pmin, e.pmax + offset);
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
		lessVariables = parser.variables;
		var rules = parser.parseSheet(cssCode, null);
		var w = parser.warnings[0];
		if( w != null )
			throw new domkit.Error(w.msg, w.pmin, w.pmax);
		getChecker().checkCSS(rules);
	}

	public function resolveComp( name : String ) {
		return checker.components.get(name);
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
		return checker.resolveComp(name);
	}

	override function getCompletion( position : Int ) {
		var code = code;
		var results = super.getCompletion(position);
		for( c in domkit.Checker.inst.components )
			results.push({
				kind : Class,
				label : c.name,
			});
		if( kind == DML && (code.charCodeAt(position-1) == "<".code || code.charCodeAt(position-1) == "/".code) )
			return results;
		for( pname => pl in domkit.Checker.inst.properties ) {
			var p = pl[0];
			results.push({
				kind : Field,
				label : kind == Less ? pname : p.field,
			});
		}
		switch( kind ) {
		case Less:
			for( c => def in @:privateAccess checker.lessVariables )
				results.push({
					kind : Property,
					label : "@"+c,
					detail : domkit.CssParser.valueStr(def),
				});
			for( id in @:privateAccess checker.definedIdents.keys() )
				results.push({
					kind : Property,
					label : id.charCodeAt(0) == "#".code ? id : "."+id,
				});
		case DML:
		}
		return results;
	}

}