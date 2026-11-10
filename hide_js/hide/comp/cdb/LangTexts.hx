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
}

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
**/
class LangTexts {
	var root = new LangNode();
	var hasPending : Bool;

	public function new( sheets : Map<String, cdb.Lang.LangXml>, old : Null<Map<String, cdb.Lang.LangXml>>, pending : Null<Array<{ version : Int, sheets : Map<String, cdb.Lang.LangXml> }>> ) {
		hasPending = pending != null;
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
		var n = find(line, column);
		if( n?.text == null )
			return Missing;
		return n.originalExport == normalize(original ?? "") ? UpToDate : Outdated;
	}

	// null if the sent texts are unknown
	public function getSentStatus( line : Line, column : cdb.Data.Column, original : String ) : Null<LangSentStatus> {
		if( !hasPending )
			return null;
		var n = find(line, column);
		if( n?.pending == null )
			return NotSent;
		return n.pending == normalize(original ?? "") ? Sent(n.pendingVersion) : SentOutdated(n.pendingVersion);
	}

	function find( line : Line, column : cdb.Data.Column ) : LangNode {
		// same keys as cdb.Lang.apply : the id, else the index
		function lineNode( parent : LangNode, line : Line ) {
			if( parent == null )
				return null;

			var idCol = null, isGuid = false;
			for( c in line.table.sheet.columns )
				switch( c.type ) {
				case TId if( idCol == null || isGuid ): idCol = c; isGuid = false;
				case TGuid if( idCol == null ): idCol = c; isGuid = true;
				default:
				}
			if( idCol == null )
				return parent.get("line" + line.index);

			var id : String = Reflect.field(line.obj, idCol.name);
			if( id == null ) id = "null";
			if( isGuid ) id = "id" + id.split("#").join("_").split("&").join("-");
			return parent.get(id) ?? parent.get("line" + line.index);
		}

		// the node of the line, and the prefix of its fields when in properties
		function resolve( line : Line ) : { node : LangNode, prefix : String } {
			var sub = Std.downcast(line.table, SubTable);
			if( sub == null )
				return { node : lineNode(root.get(line.table.sheet.name), line), prefix : "" };

			var parent = resolve(sub.cell.line);
			var name = parent.prefix + sub.cell.column.name;
			if( sub.polyVal != null )
				name += "." + sub.polyVal.col.name;
			if( sub.displayMode == Properties )
				return { node : parent.node, prefix : name + "." };
			return { node : lineNode(parent.node?.get(name), line), prefix : "" };
		}

		var r = resolve(line);
		return r.node?.get(r.prefix + column.name);
	}
}
