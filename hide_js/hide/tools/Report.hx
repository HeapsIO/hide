package hide.tools;

typedef ReportColumn = { name : String, ?num : Bool, ?width : Int };
typedef ReportRow = { cells : Array<String>, ?id : String, ?values : Array<Dynamic> };
typedef ReportTable = { columns : Array<ReportColumn>, rows : Array<ReportRow> };

enum ReportBlock {
	Html( html : String );
	Table( t : ReportTable );
}

typedef ReportSection = {
	var id : String;
	var title : String;
	var blocks : Array<ReportBlock>;
	var ?count : Int;
	var ?open : Bool;
	var ?order : Float;
}

typedef ReportData = {
	var title : String;
	var subtitle : String;
	var summary : Array<ReportBlock>;
	var sections : Array<ReportSection>;
}

typedef ReportKind = {
	var title : String;
	function editParams( bar : js.html.Element, params : Dynamic, onChange : Void -> Void ) : Void;
	function generate( params : Dynamic, onProgress : String -> Void, onDone : ReportData -> Void, onError : haxe.Exception -> Void ) : Void;
}

/**
	HTML fragments of a report. Links are handled by `hide.view.ReportView`:
	`file` opens a resource in hide, `code` a source line in VSCode, `goto` a section or row of the report,
	`shader` the row of a shader in the section "shaders".
**/
class Report {

	static var kinds : Map<String, ReportKind>;

	public static function get( id : String ) {
		return kinds?.get(id);
	}

	public static function register( id : String, kind : ReportKind ) {
		if( kinds == null )
			kinds = new Map();
		kinds.set(id, kind);
		return true;
	}

	public static function el( tag : String, cls : String, parent : js.html.Element ) : js.html.Element {
		var e = js.Browser.document.createElement(tag);
		if( cls != null )
			e.className = cls;
		parent.appendChild(e);
		return e;
	}

	public static function esc( s : String ) {
		return StringTools.htmlEscape(s ?? "", true);
	}

	public static function file( path : String, ?label : String ) {
		return '<a class="r-file" data-file="${esc(path)}" title="${esc(path)}">${esc(label ?? path)}</a>';
	}

	public static function code( file : String, line : Int, ?text : String ) {
		var abs = sys.FileSystem.fullPath(file).split("\\").join("/");
		var link = '<a class="r-code" data-code="${esc(abs)}:$line" title="${esc(abs)}">${esc(file.substr(file.lastIndexOf("/") + 1))}:$line</a>';
		return text == null ? link : link + ' <small>${esc(text)}</small>';
	}

	public static function goto( id : String, html : String ) {
		return '<a class="r-goto" data-goto="${esc(id)}">$html</a>';
	}

	public static function shader( name : String, ?text : String, ?cls : String, ?title : String ) {
		return '<span class="r-shader${cls == null ? "" : " " + cls}" data-shader="${esc(name)}"${title == null ? "" : ' title="${esc(title)}"'}>${esc(text ?? name)}</span>';
	}

	public static function details( summary : String, html : String ) {
		return '<details><summary><small>$summary</small></summary><div>$html</div></details>';
	}

	public static function files( list : Array<String>, max : Int ) {
		return [for( f in list.slice(0, max) ) file(f)].join(", ") + (list.length > max ? ', ... (${list.length})' : "");
	}
}
