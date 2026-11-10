package hide.comp.cdb;

/**
	The status of a translation, as exportTrad computes it.
**/
enum LangStatus {
	Missing;
	// the original text changed since the export of the translation
	Outdated;
	UpToDate;
}

/**
	The status of the text sent to the translators and not imported yet, with its exportTrad version.
**/
enum LangSentStatus {
	NotSent;
	Sent( version : Int );
	// the original text changed since it was sent
	SentOutdated( version : Int );
	// the language of the original texts, never sent
	RefLang;
}

/**
	A line of a root sheet or of a list, with the line of the list. `field` : the name of the list column, prefixed by its properties.
**/
typedef LangLine = { sheet : cdb.Sheet, obj : Dynamic, index : Int, ?parent : LangLine, ?field : String }

private class LangNode {
	public var children : Map<String, LangNode>;
	public var text : Null<String>;
	// the normalized original text the translation was made from
	public var originalExport : Null<String>;
	// the normalized original text sent to the translators, from the last version
	public var pending : Null<String>;
	public var pendingVersion : Int;

	public function new() {
	}

	public inline function get( name : String ) {
		return children?.get(name);
	}

	// calls `onText` on the node of each text of `x`, creating the missing nodes
	public function merge( x : cdb.Lang.LangXml, onText : (LangNode, String) -> Void ) {
		if( x._html != null )
			onText(this, StringTools.trim(x._html));
		if( x.elements() == null )
			return;

		for( e in x.elements() )
			getOrCreate(e.nodeName).merge(e, onText);
	}

	public function getOrCreate( name : String ) {
		if( children == null )
			children = new Map();
		var c = children.get(name);
		if( c == null ) {
			c = new LangNode();
			children.set(name, c);
		}
		return c;
	}
}

/**
	The texts of a file of `cdb.Lang.buildXML`, indexed by node name, with their status.
	`old` : the original texts the translations were made from (null if unknown).
	`pending` : the texts sent to the translators and not imported yet, from the last version (null if unknown).
	`compareText` : the status of a text never exported nor sent compares it to the original (the reference language).
**/
class LangTexts {
	var root = new LangNode();
	var hasPending : Bool;
	var compareText : Bool;

	public function new( sheets : Map<String, cdb.Lang.LangXml>, old : Null<Map<String, cdb.Lang.LangXml>>, pending : Null<Array<{ version : Int, sheets : Map<String, cdb.Lang.LangXml> }>>, compareText : Bool ) {
		hasPending = pending != null;
		this.compareText = compareText;
		pending ??= [];
		function mergeAll( sheets : Map<String, cdb.Lang.LangXml>, onText ) {
			for( name => s in sheets )
				root.getOrCreate(name).merge(s, onText);
		}

		mergeAll(sheets, (n, t) -> if( n.text == null ) n.text = t);
		if( old != null )
			mergeAll(old, (n, t) -> if( n.originalExport == null ) n.originalExport = normalize(t));
		for( p in pending )
			mergeAll(p.sheets, (n, t) -> if( n.pending == null ) {
				n.pending = normalize(t);
				n.pendingVersion = p.version;
			});
	}

	static function normalize( s : String ) {
		return StringTools.trim([for( l in s.split("\n") ) StringTools.trim(l)].join("\n"));
	}

	public function getTranslation( line : Line, column : cdb.Data.Column ) : Null<String> {
		return find(line, column)?.text;
	}

	public function getStatus( line : Line, column : cdb.Data.Column, original : String ) : LangStatus {
		return nodeStatus(find(line, column), original);
	}

	// null if the sent texts are unknown
	public function getSentStatus( line : Line, column : cdb.Data.Column, original : String ) : Null<LangSentStatus> {
		return nodeSentStatus(find(line, column), original);
	}

	/**
		The status and sent status of the text `name` of `line`, prefixed by its properties.
	**/
	public function getLineStatus( line : LangLine, name : String, original : String ) : { status : LangStatus, sent : Null<LangSentStatus> } {
		var n = langLineNode(line)?.get(name);
		return { status : nodeStatus(n, original), sent : nodeSentStatus(n, original) };
	}

	function nodeStatus( n : LangNode, original : String ) : LangStatus {
		if( n?.text == null )
			return Missing;

		var current = normalize(original ?? "");
		if( compareText && n.originalExport == null && n.pending == null )
			return normalize(n.text) == current ? UpToDate : Outdated;
		return n.originalExport == current ? UpToDate : Outdated;
	}

	function nodeSentStatus( n : LangNode, original : String ) : Null<LangSentStatus> {
		if( !hasPending )
			return null;
		if( compareText )
			return RefLang;
		if( n?.pending == null )
			return NotSent;
		return n.pending == normalize(original ?? "") ? Sent(n.pendingVersion) : SentOutdated(n.pendingVersion);
	}

	/**
		The original text normalized, and the ones the translation was made from and sent to the translators (null if unknown).
	**/
	public function getOriginals( line : Line, column : cdb.Data.Column, original : String ) : { current : String, exported : Null<String>, sent : Null<String> } {
		var n = find(line, column);
		return { current : normalize(original ?? ""), exported : n?.originalExport, sent : n?.pending };
	}

	// same keys as cdb.Lang.apply : the id, else the index
	static function lineNode( parent : LangNode, sheet : cdb.Sheet, obj : Dynamic, index : Int ) {
		if( parent == null )
			return null;

		var idCol = null, isGuid = false;
		for( c in sheet.columns )
			switch( c.type ) {
			case TId if( idCol == null || isGuid ): idCol = c; isGuid = false;
			case TGuid if( idCol == null ): idCol = c; isGuid = true;
			default:
			}
		if( idCol == null )
			return parent.get("line" + index);

		var id : String = Reflect.field(obj, idCol.name);
		if( id == null ) id = "null";
		if( isGuid ) id = "id" + id.split("#").join("_").split("&").join("-");
		return parent.get(id) ?? parent.get("line" + index);
	}

	function langLineNode( line : LangLine ) : LangNode {
		var parent = line.parent == null ? root.get(line.sheet.name) : langLineNode(line.parent)?.get(line.field);
		return lineNode(parent, line.sheet, line.obj, line.index);
	}

	/**
		The line of the texts of `line`, and the prefix of its fields when in properties.
	**/
	public static function getLangLine( line : Line ) : { line : LangLine, prefix : String } {
		var sub = Std.downcast(line.table, SubTable);
		if( sub == null )
			return { line : { sheet : line.table.sheet, obj : line.obj, index : line.index }, prefix : "" };

		var parent = getLangLine(sub.cell.line);
		var name = parent.prefix + sub.cell.column.name;
		if( sub.polyVal != null )
			name += "." + sub.polyVal.col.name;
		if( sub.displayMode == Properties )
			return { line : parent.line, prefix : name + "." };
		return { line : { sheet : line.table.sheet, obj : line.obj, index : line.index, parent : parent.line, field : name }, prefix : "" };
	}

	function find( line : Line, column : cdb.Data.Column ) : LangNode {
		var r = getLangLine(line);
		return langLineNode(r.line)?.get(r.prefix + column.name);
	}
}
