package hide.comp;

class CdbCell extends Component {

	static var UID = 0;
	static var typeNames = [for( t in Type.getEnumConstructs(cdb.Data.ColumnType) ) t.substr(1).toLowerCase()];

	var table : CdbTable;
	var col : cdb.Data.Column;
	var obj : Dynamic;
	public var value(default, set) : Dynamic;

	public function new( root : Element, table : CdbTable, col : cdb.Data.Column, obj : Dynamic ) {
		super(root);
		this.table = table;
		this.col = col;
		this.obj = obj;
		value = Reflect.field(obj, col.name);
		root.addClass("t_" + typeNames[col.type.getIndex()]);
		/*
				v.data("index", cindex);
				v.click(function(e) {
					if( inTodo ) {
						// nothing
					} else if( e.shiftKey && cursor.s == sheet ) {
						cursor.select = { x : cindex, y : index };
						updateCursor();
						e.stopImmediatePropagation();
					} else
						setCursor(sheet, cindex, index);
					e.stopPropagation();
				});

				function set(val2:Dynamic) {
					var old = val;
					val = val2;
					if( val == null )
						Reflect.deleteField(obj, c.name);
					else
						Reflect.setField(obj, c.name, val);
					html = valueHtml(c, val, sheet, obj);
					v.html(html);
					updateClasses(v, c, val);
					//this.changed(sheet, c, index, old);
					trace("CHANGED");
				}

				// TODO
		*/
	}

	function set_value( v : Dynamic ) {
		value = v;
		refresh();
		return v;
	}

	function refresh() {
		var html = valueHtml(col, value, table.sheet, obj);
		if( html == "&nbsp;" ) root.text(" ") else if( html.indexOf('<') < 0 && html.indexOf('&') < 0 ) root.text(html) else root.html(html);
	}

	public function valueHtml( c : cdb.Data.Column, v : Dynamic, sheet : cdb.Sheet, obj : Dynamic ) : String {
		if( v == null ) {
			if( c.opt )
				return "&nbsp;";
			return '<span class="error">#NULL</span>';
		}
		return switch( c.type ) {
		case TInt, TFloat:
			switch( c.display ) {
			case Percent:
				(Math.round(v * 10000)/100) + "%";
			default:
				v + "";
			}
		case TId:
			v == "" ? '<span class="error">#MISSING</span>' : (table.base.getSheet(sheet.name).index.get(v).obj == obj ? v : '<span class="error">#DUP($v)</span>');
		case TString, TLayer(_):
			v == "" ? "&nbsp;" : StringTools.htmlEscape(v);
		case TRef(sname):
			if( v == "" )
				'<span class="error">#MISSING</span>';
			else {
				var s = table.base.getSheet(sname);
				var i = s.index.get(v);
				i == null ? '<span class="error">#REF($v)</span>' : (i.ico == null ? "" : tileHtml(i.ico,true)+" ") + StringTools.htmlEscape(i.disp);
			}
		case TBool:
			v?"Y":"N";
		case TEnum(values):
			values[v];
		case TImage:
			""; // deprecated
		case TList:
			var a : Array<Dynamic> = v;
			var ps = sheet.getSub(c);
			var out : Array<String> = [];
			var size = 0;
			for( v in a ) {
				var vals = [];
				for( c in ps.columns )
					switch( c.type ) {
					case TList, TProperties:
						continue;
					default:
						vals.push(valueHtml(c, Reflect.field(v, c.name), ps, v));
					}
				var v = vals.length == 1 ? vals[0] : ""+vals;
				if( size > 200 ) {
					out.push("...");
					break;
				}
				var vstr = v;
				if( v.indexOf("<") >= 0 ) {
					vstr = ~/<img src="[^"]+" style="display:none"[^>]+>/g.replace(vstr, "");
					vstr = ~/<img src="[^"]+"\/>/g.replace(vstr, "[I]");
					vstr = ~/<div id="[^>]+><\/div>/g.replace(vstr, "[D]");
				}
				size += vstr.length;
				out.push(v);
			}
			if( out.length == 0 )
				return "[]";
			return out.join(", ");
		case TProperties:
			var ps = sheet.getSub(c);
			var out = [];
			for( c in ps.columns ) {
				var pval = Reflect.field(v, c.name);
				if( pval == null && c.opt ) continue;
				out.push(c.name+" : "+valueHtml(c, pval, ps, v));
			}
			return out.join("<br/>");
		case TCustom(name):
			var t = table.base.getCustomType(name);
			var a : Array<Dynamic> = v;
			var cas = t.cases[a[0]];
			var str = cas.name;
			if( cas.args.length > 0 ) {
				str += "(";
				var out = [];
				var pos = 1;
				for( i in 1...a.length )
					out.push(valueHtml(cas.args[i-1], a[i], sheet, this));
				str += out.join(",");
				str += ")";
			}
			str;
		case TFlags(values):
			var v : Int = v;
			var flags = [];
			for( i in 0...values.length )
				if( v & (1 << i) != 0 )
					flags.push(StringTools.htmlEscape(values[i]));
			flags.length == 0 ? String.fromCharCode(0x2205) : flags.join("|<wbr>");
		case TColor:
			'<div class="color" style="background-color:#${StringTools.hex(v,6)}"></div>';
		case TFile:
			var path = ide.getPath(v);
			var url = "file://" + path;
			var ext = v.split(".").pop().toLowerCase();
			var html = v == "" ? '<span class="error">#MISSING</span>' : StringTools.htmlEscape(v);
			if( v != "" && !table.quickExists(path) )
				html = '<span class="error">' + html + '</span>';
			else if( ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" )
				html = '<span class="preview">$html<div class="previewContent"><div class="label"></div><img src="$url" onload="$(this).parent().find(\'.label\').text(this.width+\'x\'+this.height)"/></div></span>';
			if( v != "" )
				html += ' <input type="submit" value="open" onclick="_.openFile(\'$path\')"/>';
			html;
		case TTilePos:
			return tileHtml(v);
		case TTileLayer:
			var v : cdb.Types.TileLayer = v;
			var path = ide.getPath(v.file);
			if( !table.quickExists(path) )
				'<span class="error">' + v.file + '</span>';
			else
				'#DATA';
		case TDynamic:
			var str = Std.string(v).split("\n").join(" ").split("\t").join("");
			if( str.length > 50 ) str = str.substr(0, 47) + "...";
			str;
		}
	}

	function tileHtml( v : cdb.Types.TilePos, ?isInline ) {
		var path = ide.getPath(v.file);
		if( !table.quickExists(path) ) {
			if( isInline ) return "";
			return '<span class="error">' + v.file + '</span>';
		}
		var id = UID++;
		var width = v.size * (v.width == null?1:v.width);
		var height = v.size * (v.height == null?1:v.height);
		var max = width > height ? width : height;
		var zoom = max <= 32 ? 2 : 64 / max;
		var inl = isInline ? 'display:inline-block;' : '';
		var url = "file://" + path;
		var html = '<div class="tile" id="_c${id}" style="width : ${Std.int(width * zoom)}px; height : ${Std.int(height * zoom)}px; background : url(\'$url\') -${Std.int(v.size*v.x*zoom)}px -${Std.int(v.size*v.y*zoom)}px; opacity:0; $inl"></div>';
		html += '<img src="$url" style="display:none" onload="$(\'#_c$id\').css({opacity:1, backgroundSize : ((this.width*$zoom)|0)+\'px \' + ((this.height*$zoom)|0)+\'px\' '+(zoom > 1 ? ", imageRendering : 'pixelated'" : "") +'}); if( this.parentNode != null ) this.parentNode.removeChild(this)"/>';
		return html;
	}

}