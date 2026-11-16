package hide.comp.cdb;

/**
	The state of a localizable text in a translation.
**/
enum LangText {
	Text( s : String );
	Missing;
	/** the line is not exported (`cdb.Lang.IGNORE_EXPORT_FIELD`) **/
	Ignored;
	/** the line has no id to be found in the translation **/
	NoId;
}

typedef LangLineState = { sheet : Bool, line : Null<String> };

/**
	A translation file of `cdb.Lang.buildXML`, edited in place : saving it unchanged writes the same bytes.
	Loaded once, reloaded when it changes on disk.
**/
class LangFile {

	static var files = new Map<String, LangFile>();

	public var path(default, null) : String;
	// the document : the root element, and the text around it
	var doc : Xml;
	var root : Xml;
	var bom : Bool;
	// the formatting of the file, used for the new elements
	var indentUnit = "\t";
	var newLine = "\n";
	// the content last read or written : any other content was written outside of HIDE
	var content : String;
	var dirty = false;
	var watcher : hide.tools.FileWatcher.FileWatchEvent;
	// the child elements by name, the last one when several have the same name (as cdb.Lang reads them)
	var index = new haxe.ds.ObjectMap<Xml, Map<String, Xml>>();

	function new( path ) {
		this.path = path;
	}

	/**
		The file at `path` (relative to the resources), null with an error message when it can't be read.
	**/
	public static function get( path : String ) : LangFile {
		var f = files.get(path);
		if( f != null )
			return f;

		f = new LangFile(path);
		try {
			f.load();
		} catch( e : Dynamic ) {
			hide.Ide.inst.quickError('Can\'t load the lang file $path : $e');
			return null;
		}
		files.set(path, f);
		f.watcher = hide.Ide.inst.fileWatcher.register(path, f.onChange);
		return f;
	}

	public static function saveAll() {
		if( hide.Ide.inst.readOnlyConfig )
			return;

		for( f in files )
			if( f.dirty )
				f.save();
	}

	function load() {
		var raw = sys.io.File.getContent(hide.Ide.inst.getPath(path));
		bom = raw.charCodeAt(0) == 0xFEFF;
		doc = Xml.parse(bom ? raw.substr(1) : raw);
		root = doc.firstElement();
		if( root == null )
			throw "Empty file";
		content = raw;
		dirty = false;
		index = new haxe.ds.ObjectMap();

		// the text before the first child of the root : a new line and one indentation
		indentUnit = "\t";
		newLine = "\n";
		for( c in root ) {
			if( c.nodeType != PCData )
				break;
			var pos = c.nodeValue.lastIndexOf("\n");
			if( pos < 0 || StringTools.trim(c.nodeValue) != "" )
				break;
			newLine = pos > 0 && c.nodeValue.charAt(pos - 1) == "\r" ? "\r\n" : "\n";
			if( pos < c.nodeValue.length - 1 )
				indentUnit = c.nodeValue.substr(pos + 1);
			break;
		}
	}

	function onChange() {
		var raw = try sys.io.File.getContent(hide.Ide.inst.getPath(path)) catch( e : Dynamic ) null;
		if( raw == content )
			return;

		try {
			load();
		} catch( e : Dynamic ) {
			hide.Ide.inst.quickError('Can\'t reload the lang file $path : $e');
			files.remove(path);
			hide.Ide.inst.fileWatcher.unregister(path, onChange);
			Editor.onLangFileRemoved(this);
		}
		Editor.refreshAll(true, false);
	}

	function save() {
		var disk = try sys.io.File.getContent(hide.Ide.inst.getPath(path)) catch( e : Dynamic ) null;
		if( disk != content ) {
			hide.Ide.inst.quickError('$path was modified outside of HIDE : the last change is not saved to keep these modifications, the file is reloaded.');
			haxe.Timer.delay(onChange, 0);
			return;
		}

		content = (bom ? "\u{FEFF}" : "") + haxe.xml.Printer.print(doc);
		sys.io.File.saveContent(hide.Ide.inst.getPath(path), content);
		dirty = false;
		hide.Ide.inst.fileWatcher.ignorePrevChange(watcher);
	}

	public function getSheet( name : String ) : Xml {
		var found = null;
		for( s in root.elementsNamed("sheet") )
			if( s.get("name") == name )
				found = s;
		return found;
	}

	public function child( parent : Xml, name : String ) : Xml {
		if( parent == null )
			return null;

		var m = index.get(parent);
		if( m == null ) {
			m = new Map();
			for( e in parent.elements() )
				m.set(e.nodeName, e);
			index.set(parent, m);
		}
		return m.get(name);
	}

	/**
		The name of the element of a line in its sheet or list (the same as `cdb.Lang.buildXML`), null when it has none.
		The lines of prefabs are found by their id only.
	**/
	public static function lineKey( sheet : cdb.Sheet, obj : Dynamic, index : Int, isPrefab : Bool ) : String {
		if( Reflect.hasField(obj, cdb.Lang.IGNORE_EXPORT_FIELD) )
			return null;

		var idCol = null, isGuid = false;
		for( c in sheet.columns )
			switch( c.type ) {
			case TId if( idCol == null || isGuid ): idCol = c; isGuid = false;
			case TGuid if( idCol == null ): idCol = c; isGuid = true;
			default:
			}
		if( isPrefab && (idCol == null || isGuid) )
			return null;
		if( idCol == null )
			return "line" + index;

		var id : String = Reflect.field(obj, idCol.name);
		if( id == "" )
			return null;
		if( id == null ) {
			if( !idCol.opt )
				return null;
			id = "null";
		}
		return isGuid ? "id" + id.split("#").join("_").split("&").join("-") : id;
	}

	// the element of a line, with the fallback of cdb.Lang.apply on its index
	public function findLine( parent : Xml, sheet : cdb.Sheet, obj : Dynamic, index : Int, isPrefab : Bool ) : Xml {
		var key = lineKey(sheet, obj, index, isPrefab);
		if( key == null )
			return null;

		return child(parent, key) ?? (isPrefab ? null : child(parent, "line" + index));
	}

	/**
		The text of an element, as `cdb.Lang.apply` reads it.
	**/
	public static function getText( e : Xml ) : String {
		var buf = new StringBuf();
		for( c in e )
			switch( c.nodeType ) {
			case Element if( c.nodeName == "br" ): buf.add("\n");
			case Element: buf.add(StringTools.htmlUnescape(haxe.xml.Printer.print(c)));
			case PCData, CData: buf.add(c.nodeValue);
			default:
			}
		return StringTools.trim(buf.toString());
	}

	public function setText( e : Xml, text : String ) {
		for( c in [for( c in e ) c] )
			e.removeChild(c);

		for( i => l in text.split("\r").join("").split("\n") ) {
			if( i > 0 )
				e.addChild(Xml.createElement("br"));
			if( l != "" )
				e.addChild(Xml.createPCData(l));
		}
		dirty = true;
	}

	public function createSheet( name : String ) : Xml {
		var s = Xml.createElement("sheet");
		s.set("name", name);
		addChild(root, s);
		return s;
	}

	/**
		Appends a new element at the end of `parent`, indented with tabs as `cdb.Lang.buildXML` does.
	**/
	public function createChild( parent : Xml, name : String ) : Xml {
		var e = Xml.createElement(name);
		addChild(parent, e);
		return e;
	}

	function addChild( parent : Xml, e : Xml ) {
		var depth = 0;
		var p = parent;
		while( p.parent != null && p.parent.nodeType == Element ) {
			depth++;
			p = p.parent;
		}
		inline function indent( n : Int ) return Xml.createPCData(newLine + [for( i in 0...n ) indentUnit].join(""));

		var children = [for( c in parent ) c];
		var last = children[children.length - 1];
		if( last != null && last.nodeType == PCData && StringTools.trim(last.nodeValue) == "" ) {
			parent.insertChild(indent(depth + 1), children.length - 1);
			parent.insertChild(e, children.length);
		} else {
			parent.addChild(indent(depth + 1));
			parent.addChild(e);
			parent.addChild(indent(depth));
		}
		index.remove(parent);
		dirty = true;
	}

	// removes an element and the indentation before it
	function removeElement( e : Xml ) {
		var parent = e.parent;
		var children = [for( c in parent ) c];
		var prev = children[children.indexOf(e) - 1];
		if( prev != null && prev.nodeType == PCData && StringTools.trim(prev.nodeValue) == "" )
			parent.removeChild(prev);
		parent.removeChild(e);
		index.remove(parent);
		dirty = true;
	}

	/**
		The element `name` of a sheet as text, and if the sheet exists : what the undo keeps.
	**/
	public function getLineState( sheet : String, name : String ) : LangLineState {
		var s = getSheet(sheet);
		var l = child(s, name);
		return { sheet : s != null, line : l == null ? null : haxe.xml.Printer.print(l) };
	}

	public function setLineState( sheet : String, name : String, state : LangLineState ) {
		var s = getSheet(sheet);
		var l = child(s, name);
		if( state.line == null ) {
			if( l != null )
				removeElement(l);
			if( !state.sheet && s != null )
				removeElement(s);
			return;
		}

		if( s == null )
			s = createSheet(sheet);
		var nl = Xml.parse(state.line).firstElement();
		if( l == null ) {
			addChild(s, nl);
			return;
		}
		var children = [for( c in s ) c];
		s.insertChild(nl, children.indexOf(l));
		s.removeChild(l);
		index.remove(s);
		dirty = true;
	}
}
