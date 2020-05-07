package hide.comp.cdb;
import hxd.Key in K;

class Cell extends Component {

	static var UID = 0;
	static var typeNames = [for( t in Type.getEnumConstructs(cdb.Data.ColumnType) ) t.substr(1).toLowerCase()];

	var editor : Editor;
	var currentValue : Dynamic;
	public var line(default,null) : Line;
	public var column(default, null) : cdb.Data.Column;
	public var columnIndex(get, never) : Int;
	public var value(get, never) : Dynamic;
	public var table(get, never) : Table;

	public function new( root : Element, line : Line, column : cdb.Data.Column ) {
		super(null,root);
		this.line = line;
		this.editor = line.table.editor;
		this.column = column;
		@:privateAccess line.cells.push(this);
		root.addClass("t_" + typeNames[column.type.getIndex()]);
		if( column.kind == Script ) root.addClass("t_script");
		refresh();
		switch( column.type ) {
		case TList, TProperties:
			element.click(function(e) {
				if( e.shiftKey ) return;
				e.stopPropagation();
				@:privateAccess line.table.toggleList(this);
			});
		case TFile:
			if (canEdit()) {
				element.on("drop", function(e : js.jquery.Event) {
					var e : js.html.DragEvent = untyped e.originalEvent;
					if (e.dataTransfer.files.length > 0) {
						e.preventDefault();
						e.stopPropagation();
						setValue(ide.makeRelative(untyped e.dataTransfer.files.item(0).path));
						refresh();
					}
				});
				element.dblclick(function(_) edit());
			} else {
				root.addClass("t_readonly");
			}
		case TString if( column.kind == Script ):
			element.click(function(_) edit());
		default:
			if( canEdit() )
				element.dblclick(function(_) edit());
			else
				root.addClass("t_readonly");
		}
	}

	public function canEdit() {
		return table.canEditColumn(column.name);
	}

	function get_table() return line.table;
	function get_columnIndex() return table.columns.indexOf(column);
	inline function get_value() return currentValue;

	function getCellConfigValue<T>( name : String, ?def : T ) : T
	{
		var cfg = ide.currentConfig;
		var paths = table.sheet.name.split("@");
		paths.unshift("cdb");
		paths.push(column.name);
		while ( paths.length != 0 ) {
			var config = cfg.get(paths.join("."), null);
			if ( config != null && Reflect.hasField(config, name) )
				return Reflect.field(config, name);
			paths.pop();
		}
		return def;
	}

	public function refresh() {
		currentValue = Reflect.field(line.obj, column.name);
		var html = valueHtml(column, value, line.table.getRealSheet(), line.obj, []);
		if( html == "&nbsp;" ) element.text(" ") else if( html.indexOf('<') < 0 && html.indexOf('&') < 0 ) element.text(html) else element.html(html);
		updateClasses();
	}

	function updateClasses() {
		element.removeClass("edit");
		element.removeClass("edit_long");
		switch( column.type ) {
		case TBool:
			element.removeClass("true false").addClass( value==true ? "true" : "false" );
		case TInt, TFloat:
			element.removeClass("zero");
			if( value == 0 ) element.addClass("zero");
		default:
		}
	}

	function getSheetView( sheet : cdb.Sheet ) {
		var view = table.editor.view;
		if( view == null )
			return null;
		var path = sheet.name.split("@");
		var view = view.get(path.shift());
		for( name in path ) {
			var sub = view.sub == null ? null : view.sub.get(name);
			if( sub == null )
				return null;
			view = sub;
		}
		return view;
	}

	function canViewSubColumn( sheet : cdb.Sheet, column : String ) {
		var view = getSheetView(sheet);
		return view == null || view.show == null || view.show.indexOf(column) >= 0;
	}

	var _cachedScope : Array<{ s : cdb.Sheet, obj : Dynamic }>;
	function getScope() {
		if( _cachedScope != null ) return _cachedScope;
		var scope = [];
		var line = line;
		while( true ) {
			var p = Std.downcast(line.table, SubTable);
			if( p == null ) break;
			line = p.cell.line;
			scope.unshift({ s : line.table.getRealSheet(), obj : line.obj });
		}
		return _cachedScope = scope;
	}

	function makeId( scopes : Array<{ s : cdb.Sheet, obj : Dynamic }>, scope : Int, id : String ) {
		var ids = [];
		if( id != null ) ids.push(id);
		var pos = scopes.length;
		while( true ) {
			pos -= scope;
			if( pos < 0 ) {
				scopes = getScope();
				pos += scopes.length;
			}
			var s = scopes[pos];
			var pid = Reflect.field(s.obj, s.s.idCol.name);
			if( pid == null ) return "";
			ids.unshift(pid);
			scope = s.s.idCol.scope;
			if( scope == null ) break;
		}
		return ids.join(":");
	}

	function refScope( targetSheet : cdb.Sheet, currentSheet : cdb.Sheet, obj : Dynamic, localScope : Array<{ s : cdb.Sheet, obj : Dynamic }> ) {
		var targetDepth = targetSheet.name.split("@").length;
		var scope = getScope().concat(localScope);
		if( scope.length < targetDepth )
			scope.push({ s : currentSheet, obj : obj });
		while( scope.length >= targetDepth )
			scope.pop();
		return scope;
	}

	function valueHtml( c : cdb.Data.Column, v : Dynamic, sheet : cdb.Sheet, obj : Dynamic, scope : Array<{ s : cdb.Sheet, obj : Dynamic }> ) : String {
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
			if( v == "" )
				'<span class="error">#MISSING</span>';
			else {
				var id = c.scope != null ? makeId(scope,c.scope,v) : v;
				var uniq = editor.base.getSheet(sheet.name).index.get(id);
				uniq == null || uniq.obj == obj ? v : '<span class="error">#DUP($v)</span>';
			}
		case TString if( c.kind == Script ):
			v == "" ? "&nbsp;" : colorizeScript(c,v);
		case TString, TLayer(_):
			v == "" ? "&nbsp;" : StringTools.htmlEscape(v).split("\n").join("<br/>");
		case TRef(sname):
			if( v == "" )
				'<span class="error">#MISSING</span>';
			else {
				var s = editor.base.getSheet(sname);
				var i = s.index.get(s.idCol.scope != null ? makeId(refScope(s,sheet,obj,scope),s.idCol.scope,v) : v);
				i == null ? '<span class="error">#REF($v)</span>' : (i.ico == null ? "" : tileHtml(i.ico,true)+" ") + StringTools.htmlEscape(i.disp);
			}
		case TBool:
			v?"Y":"N";
		case TEnum(values):
			values[v];
		case TImage:
			'<span class="error">#DEPRECATED</span>';
		case TList:
			var a : Array<Dynamic> = v;
			var ps = sheet.getSub(c);
			var out : Array<String> = [];
			var size = 0;
			scope.push({ s : sheet, obj : obj });
			for( v in a ) {
				var vals = [];
				for( c in ps.columns )
					switch( c.type ) {
					case TList, TProperties if( c != ps.columns[0] ):
						continue;
					default:
						if( !canViewSubColumn(ps, c.name) ) continue;
						var h = valueHtml(c, Reflect.field(v, c.name), ps, v, scope);
						if( h != "" && h != "&nbsp;" )
							vals.push(h);
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
				vstr = StringTools.trim(vstr);
				size += vstr.length;
				out.push(v);
			}
			scope.pop();
			if( out.length == 0 )
				return "";
			return out.join(", ");
		case TProperties:
			var ps = sheet.getSub(c);
			var out = [];
			scope.push({ s : sheet, obj : obj });
			for( c in ps.columns ) {
				var pval = Reflect.field(v, c.name);
				if( pval == null && c.opt ) continue;
				if( !canViewSubColumn(ps, c.name) ) continue;
				out.push(c.name+" : "+valueHtml(c, pval, ps, v, scope));
			}
			scope.pop();
			return out.join("<br/>");
		case TCustom(name):
			var t = editor.base.getCustomType(name);
			var a : Array<Dynamic> = v;
			var cas = t.cases[a[0]];
			var str = cas.name;
			if( cas.args.length > 0 ) {
				str += "(";
				var out = [];
				var pos = 1;
				for( i in 1...a.length )
					out.push(valueHtml(cas.args[i-1], a[i], sheet, this, scope));
				str += out.join(",");
				str += ")";
			}
			str;
		case TFlags(values):
			var v : Int = v;
			var view = getSheetView(sheet);
			if( view != null && view.options != null ) {
				var mask = Reflect.field(view.options,c.name);
				if( mask != null ) v &= mask;
			}
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
			if (v == "") return '<span class="error">#MISSING</span>';
			var html = StringTools.htmlEscape(v);
			if (!editor.quickExists(path)) return '<span class="error">$html</span>';
			else if( ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" ) {
				var img = '<img src="$url" onload="$(this).parent().find(\'.label\').text(this.width+\'x\'+this.height)"/>';
				var previewHandler = ' onmouseenter="$(this).find(\'.previewContent\').css(\'top\', (this.getBoundingClientRect().bottom - this.offsetHeight) + \'px\')"';
				if (getCellConfigValue("inlineImageFiles", false)) {
					html = '<span class="preview inlineImage" $previewHandler>
						<img src="$url"><div class="previewContent"><div class="inlineImagePath">$html</div><div class="label"></div>$img</div></span>';
				} else {
					html = '<span class="preview" $previewHandler>$html
						<div class="previewContent"><div class="label"></div>$img</div></span>';
				}
			}
			return html + ' <input type="submit" value="open" onclick="hide.Ide.inst.openFile(\'$path\')"/>';
		case TTilePos:
			return tileHtml(v);
		case TTileLayer:
			var v : cdb.Types.TileLayer = v;
			var path = ide.getPath(v.file);
			if( !editor.quickExists(path) )
				'<span class="error">' + v.file + '</span>';
			else
				'#DATA';
		case TDynamic:
			var str = Std.string(v).split("\n").join(" ").split("\t").join("");
			if( str.length > 50 ) str = str.substr(0, 47) + "...";
			str;
		}
	}

	static var KWDS = ["for","if","var","this","while","else","do","break","continue","switch","function","return","new","throw","try","catch","case","default"];
	static var KWD_REG = new EReg([for( k in KWDS ) "(\\b"+k+"\\b)"].join("|"),"g");
	function colorizeScript( c : cdb.Data.Column, ecode : String ) {
		var code = ecode;
		code = StringTools.htmlEscape(code);
		code = code.split("\n").join("<br/>");
		code = code.split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
		// typecheck
		var error = new ScriptEditor.ScriptChecker(editor.config, "cdb."+getDocumentName()+(c == this.column ? "" : "."+ c.name), ["cdb."+table.sheet.name => line.obj]).check(ecode);
		if( error != null )
			return '<span class="error">'+code+'</span>';
		// strings
		code = ~/("[^"]*")/g.replace(code,'<span class="str">$1</span>');
		code = ~/('[^']*')/g.replace(code,'<span class="str">$1</span>');
		// keywords
		code = KWD_REG.map(code, function(r) return '<span class="kwd">${r.matched(0)}</span>');
		// comments
		code = ~/(\/\*([^\*]+)\*\/)/g.replace(code,'<span class="comment">$1</span>');
		code = code.split("<br/>").map(function(line) return ~/(\/\/.*)/.replace(line,'<span class="comment">$1</span>')).join("<br/>");
		return code;
	}

	public function getGroup() : String {
		var gid : Null<Int> = Reflect.field(line.obj, "group");
		if( gid == null ) return null;
		return table.sheet.props.separatorTitles[gid-1];
	}

	public function getDocumentName() {
		var name = table.sheet.name.split("@").join(".");
		if( table.sheet.props.hasGroup ) {
			var g = getGroup();
			if( g != null ) name += "[group="+g+"]";
		}
		name += "."+column.name;
		return name;
	}

	function tileHtml( v : cdb.Types.TilePos, ?isInline ) {
		var path = ide.getPath(v.file);
		if( !editor.quickExists(path) ) {
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

	public function isTextInput() {
		return switch( column.type ) {
		case TString if( column.kind == Script ):
			return false;
		case TString, TInt, TFloat, TId, TCustom(_), TDynamic, TRef(_):
			return true;
		default:
			return false;
		}
	}

	public function focus() {
		editor.focus();
		editor.cursor.set(table, this.columnIndex, this.line.index);
	}

	public function edit() {
		if( !canEdit() )
			return;
		switch( column.type ) {
		case TString if( column.kind == Script ):
			open();
		case TInt, TFloat, TString, TId, TCustom(_), TDynamic:
			var str = value == null ? "" : editor.base.valToString(column.type, value);
			var textSpan = element.wrapInner("<span>").find("span");
			var textHeight = textSpan.height();
			var textWidth = textSpan.width();
			var longText = textHeight > 25 || str.indexOf("\n") >= 0;
			element.empty();
			element.addClass("edit");
			var i = new Element(longText ? "<textarea>" : "<input>").appendTo(element);
			i.keypress(function(e) e.stopPropagation());
			i.dblclick(function(e) e.stopPropagation());
			//if( str != "" && (table.displayMode == Properties || table.displayMode == AllProperties) )
			//	i.css({ width : Math.ceil(textWidth - 3) + "px" }); -- bug if small text ?
			if( longText ) {
				element.addClass("edit_long");
				i.css({ height : Math.max(25,Math.ceil(textHeight - 1)) + "px" });
			}
			i.val(str);
			i.keydown(function(e) {
				switch( e.keyCode ) {
				case K.ESCAPE:
					refresh();
					table.editor.element.focus();
				case K.ENTER if( !e.shiftKey || !column.type.match(TString|TDynamic|TCustom(_)) ):
					closeEdit();
					e.preventDefault();
				case K.ENTER if( !longText ):
					var old = currentValue;
					// hack to insert newline and tranform the input into textarea
					var newVal = i.val() + "\n";
					Reflect.setField(line.obj, column.name, newVal+"x");
					refresh();
					Reflect.setField(line.obj, column.name,old);
					currentValue = newVal;
					edit();
					(cast element.find("textarea")[0] : js.html.TextAreaElement).setSelectionRange(newVal.length,newVal.length);
					e.preventDefault();
				case K.UP, K.DOWN if( !longText ):
					closeEdit();
					return;
				case K.TAB:
					closeEdit();
					e.preventDefault();
					editor.cursor.move(e.shiftKey ? -1 : 1, 0, false, false);
					var c = editor.cursor.getCell();
					if( c != this ) c.edit();
				}
				e.stopPropagation();
			});
			i.keyup(function(_) try {
				editor.base.parseValue(column.type, i.val());
				setErrorMessage(null);
			} catch( e : Dynamic ) {
				setErrorMessage(StringTools.htmlUnescape(""+e));
			});
			i.keyup(null);
			i.blur(function(_) closeEdit());
			i.focus();
			i.select();
			if( longText ) i.scrollTop(0);
		case TBool:
			setValue( currentValue == false && column.opt && table.displayMode != Properties ? null : currentValue == null ? true : currentValue ? false : true );
			refresh();
		case TProperties, TList:
			open();
		case TRef(name):
			var sdat = editor.base.getSheet(name);
			if( sdat == null ) return;
			element.empty();
			element.addClass("edit");

			var s = new Element("<select>");
			var isLocal = sdat.idCol.scope != null;
			var elts;
			if( isLocal ) {
				var scope = refScope(sdat,table.getRealSheet(),line.obj,[]);
				var prefix = makeId(scope, sdat.idCol.scope, null)+":";
				elts = [for( d in sdat.all ) if( StringTools.startsWith(d.id,prefix) ) { id : d.id.split(":").pop(), ico : d.ico, text : d.disp }];
			} else
				elts = [for( d in sdat.all ) { id : d.id, ico : d.ico, text : d.disp }];
			if( column.opt || currentValue == null || currentValue == "" )
				elts.unshift( { id : "~", ico : null, text : "--- None ---" } );
			element.append(s);

			var props : Dynamic = { data : elts };
			if( sdat.props.displayIcon != null ) {
				function buildElement(i) {
					var text = StringTools.htmlEscape(i.text);
					return new Element("<div>"+(i.ico == null ? "<div style='display:inline-block;width:16px'/>" : tileHtml(i.ico,true)) + " " + text+"</div>");
				}
				props.templateResult = props.templateSelection = buildElement;
			}
			(untyped s.select2)(props);
			(untyped s.select2)("val", currentValue == null ? "" : currentValue);
			(untyped s.select2)("open");

			var sel2 = s.data("select2");
			sel2.$dropdown.find("input").on("keydown", function(e) {
				e.stopPropagation();
			});

			s.change(function(e) {
				var val = s.val();
				if( val == "~" ) val = null;
				setValue(val);
				sel2.close();
				closeEdit();
			});
			s.on("select2:close", function(_) closeEdit());
		case TEnum(values):
			element.empty();
			element.addClass("edit");
			var s = new Element("<select>");
			var elts = [for( i in 0...values.length ){ id : ""+i, ico : null, text : values[i] }];
			if( column.opt )
				elts.unshift( { id : "-1", ico : null, text : "--- None ---" } );
			element.append(s);

			var props : Dynamic = { data : elts };
			(untyped s.select2)(props);
			(untyped s.select2)("val", currentValue == null ? "" : currentValue);
			(untyped s.select2)("open");
			var sel2 = s.data("select2");

			s.change(function(e) {
				var val = Std.parseInt(s.val());
				if( val < 0 ) val = null;
				setValue(val);
				sel2.close();
				closeEdit();
			});
			s.keydown(function(e) {
				switch( e.keyCode ) {
				case K.LEFT, K.RIGHT:
					s.blur();
					return;
				case K.TAB:
					s.blur();
					editor.cursor.move(e.shiftKey? -1:1, 0, false, false);
					var c = editor.cursor.getCell();
					if( c != this ) c.edit();
					e.preventDefault();
				default:
				}
				e.stopPropagation();
			});
			s.on("select2:close", function(_) closeEdit());
		case TColor:
			var modal = new Element("<div>").addClass("hide-modal").appendTo(element);
			var color = new ColorPicker(element);
			color.value = currentValue;
			color.open();
			color.onChange = function(drag) {
				element.find(".color").css({backgroundColor : '#'+StringTools.hex(color.value,6) });
			};
			color.onClose = function() {
				setValue(color.value);
				color.remove();
				closeEdit();
			};
			modal.click(function(_) color.close());
		case TFile:
			ide.chooseFile(["*"], function(file) {
				if( file != null ) {
					setValue(file);
					refresh();
				}
			});
		case TFlags(values):
			var div = new Element("<div>").addClass("flagValues");
			div.click(function(e) e.stopPropagation()).dblclick(function(e) e.stopPropagation());
			var view = table.view;
			var mask = -1;
			if( view != null && view.options != null ) {
				var m = Reflect.field(view.options,column.name);
				if( m != null ) mask = m;
			}
			var val = currentValue;
			for( i in 0...values.length ) {
				if( mask & (1<<i) == 0 ) continue;
				var f = new Element("<input>").attr("type", "checkbox").prop("checked", val & (1 << i) != 0).change(function(e) {
					val &= ~(1 << i);
					if( e.getThis().prop("checked") ) val |= 1 << i;
					e.stopPropagation();
				});
				new Element("<label>").text(values[i]).appendTo(div).prepend(f);
			}
			element.empty();
			var modal = new Element("<div>").addClass("hide-modal").appendTo(element);
			element.append(div);
			modal.click(function(e) {
				setValue(val);
				refresh();
			});
		case TTilePos:
			var modal = new hide.comp.Modal(element);
			modal.element.click(function(_) closeEdit());

			var t : cdb.Types.TilePos = currentValue;
			var file = t == null ? null : t.file;
			var size = t == null ? 16 : t.size;
			var pos = t == null ? { x : 0, y : 0, width : 1, height : 1 } : { x : t.x, y : t.y, width : t.width == null ? 1 : t.width, height : t.height == null ? 1 : t.height };
			if( file == null ) {
				var y = line.index - 1;
				while( y >= 0 ) {
					var o = line.table.lines[y--];
					var v2 = Reflect.field(o.obj, column.name);
					if( v2 != null ) {
						file = v2.file;
						size = v2.size;
						break;
					}
				}
			}

			function setVal() {
				var v : Dynamic = { file : file, size : size, x : pos.x, y : pos.y };
				if( pos.width != 1 ) v.width = pos.width;
				if( pos.height != 1 ) v.height = pos.height;
				setRawValue(v);
			}

			if( file == null ) {
				ide.chooseImage(function(path) {
					if( path == null ) {
						closeEdit();
						return;
					}
					file = path;
					setVal();
					closeEdit();
					edit();
				});
				return;
			}

			var ts = new hide.comp.TileSelector(file,size,modal.content);
			ts.allowRectSelect = true;
			ts.allowSizeSelect = true;
			ts.allowFileChange = true;
			ts.value = pos;
			ts.onChange = function(cancel) {
				if( !cancel ) {
					file = ts.file;
					size = ts.size;
					pos = ts.value;
					setVal();
				}
				refresh();
				focus();
			};

		case TLayer(_), TTileLayer:
			// no edit
		case TImage:
			// deprecated
		}
	}

	public function open( ?immediate : Bool ) {
		if( column.type == TString && column.kind == Script ) {
			if( immediate ) return;
			var str = value == null ? "" : editor.base.valToString(column.type, value);
			@:privateAccess table.toggleList(this, function() return new ScriptTable(editor, this));
		} else
			@:privateAccess table.toggleList(this, immediate);
	}

	public function setErrorMessage( msg : String ) {
		element.find("div.error").remove();
		if( msg == null )  return;
		new Element("<div>").addClass("error").html(msg).appendTo(element);
	}

	function setRawValue( str : Dynamic ) {
		var newValue : Dynamic;
		if( Std.is(str,String) ) {
			newValue = try editor.base.parseValue(column.type, str, false) catch( e : Dynamic ) return;
		} else
			newValue = str;

		if( newValue == null || newValue == currentValue )
			return;

		switch( column.type ) {
		case TId:
			var obj = line.obj;
			var prevValue = value;
			var realSheet = table.getRealSheet();
			var isLocal = realSheet.idCol.scope != null;
			var parentID = isLocal ? makeId([],realSheet.idCol.scope,null) : null;
			// most likely our obj, unless there was a #DUP
			var prevObj = value != null ? realSheet.index.get(isLocal ? parentID+":"+value : value) : null;
			// have we already an obj mapped to the same id ?
			var prevTarget = realSheet.index.get(isLocal ? parentID+":"+newValue : newValue);
			editor.beginChanges();
			if( prevObj == null || prevObj.obj == obj ) {
				// remap
				var m = new Map();
				m.set(value, newValue);
				if( isLocal ) {
					var scope = getScope();
					var parent = scope[scope.length - realSheet.idCol.scope];
					editor.base.updateLocalRefs(realSheet, m, parent.obj, parent.s);
				} else
					editor.base.updateRefs(realSheet, m);
			}
			setValue(newValue);
			editor.endChanges();
			Editor.refreshAll();
			focus();
			/*
			// creates or remove a #DUP : need to refresh the whole table
			if( prevTarget != null || (prevObj != null && (prevObj.obj != obj || table.sheet.index.get(prevValue) != null)) )
				table.refresh();
			*/
		case TString if( column.kind == Script ):
			setValue(StringTools.trim(newValue));
		case TTilePos:
			// if we change a file that has moved, change it for all instances having the same file
			editor.beginChanges();
			var obj = line.obj;
			var change = false;
			var oldV : cdb.Types.TilePos = currentValue;
			var newV : cdb.Types.TilePos = newValue;
			if( newV != null && oldV != null && oldV.file != newV.file && !sys.FileSystem.exists(ide.getPath(oldV.file)) && sys.FileSystem.exists(ide.getPath(newV.file)) ) {
				for( l in table.lines) {
					if( l == line ) continue;
					var t : Dynamic = Reflect.field(l.obj, column.name);
					if( t != null && t.file == oldV.file ) {
						t.file = newV.file;
						change = true;
					}
				}
			}
			setValue(newValue);
			editor.endChanges();
			if( change )
				editor.refresh();
		default:
			setValue(newValue);
		}
	}

	public function setValue( value : Dynamic ) {
		currentValue = value;
		editor.changeObject(line,column,value);
	}

	public function closeEdit() {
		var str = element.find("input,textarea").val();
		if( str != null ) setRawValue(str);
		refresh();
		focus();
	}

}
