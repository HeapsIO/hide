package hide.comp.cdb;

import hxd.Key in K;
using hide.tools.Extensions;

class Cell {

	static var typeNames = [for( t in Type.getEnumConstructs(cdb.Data.ColumnType) ) t.substr(1).toLowerCase()];
	static var imageDims : Map<String, {width : Int, height : Int}> = new Map();

	var ide : hide.Ide;

	public var elementHtml : js.html.Element;
	var editor : Editor;
	var currentValue : Dynamic;
	var watches : Array<String> = new Array<String>();
	public var line(default,null) : Line;
	public var column(default, null) : cdb.Data.Column;
	public var columnIndex(get, never) : Int;
	public var value(get, never) : Dynamic;
	public var table(get, never) : Table;
	var blurOff = false;
	public var inEdit = false;
	var dropdown : js.html.Element = null;

	public function new( root : js.html.Element, line : Line, column : cdb.Data.Column ) {
		this.elementHtml = root;
		ide = hide.Ide.inst;

		this.line = line;
		this.editor = line.table.editor;
		this.column = column;
		@:privateAccess line.cells.push(this);

		root.classList.add("t_" + typeNames[column.type.getIndex()]);
		root.classList.add("n_" + column.name);

		if(line.table.parent == null) {
			var editProps = Editor.getColumnProps(column);
			root.classList.toggle("cat", editProps.categories != null);
			if(editProps.categories != null)
				for(c in editProps.categories)
					root.classList.add("cat-" + c);
			var visible = editor.isColumnVisible(column);
			root.classList.toggle("hidden", !visible);
			if(!visible)
				return;
		}

		if( column.kind == Script ) root.classList.add("t_script");
		refresh();

		switch( column.type ) {
		case TList, TProperties:
			elementHtml.addEventListener("click", function(e) {
				if( e.shiftKey ) return;
				e.stopPropagation();
				line.table.toggleList(this);
			});
		case TString if( column.kind == Script ):
			root.classList.add("t_script");
			elementHtml.addEventListener("click", function(_) edit());
		default:
			if( canEdit() )
				elementHtml.addEventListener("dblclick", function(_) if (!blockEdit()) edit());
			else
				root.classList.add("t_readonly");
		}

		if( column.type == TString && column.kind == Localizable )
			root.classList.add("t_loc");

		elementHtml.addEventListener("click", function(e) {
			editor.cursor.clickCell(this, e.shiftKey);
			e.stopPropagation();
		});

		root.oncontextmenu = function(e) {
			showMenu();
			e.stopPropagation();
			e.preventDefault();
		};
	}

	public function dragDropFile( relativePath : String, isDrop : Bool = false ) : Bool {
		if ( !canEdit() || column.type != TFile) return false;
		if ( isDrop ) {
			setValue(relativePath);
			refresh();
		}
		return true;
	}

	function evaluate() {
		var f = editor.formulas.get(this);
		if( f == null ) return;
		var newV : Float = try f.call(line.obj) catch( e : Dynamic ) Math.NaN;
		if( newV != currentValue ) {
			currentValue = newV;
			Reflect.setField(line.obj, column.name, newV);
			refresh();
		}
	}

	function showMenu() {
		var menu : Array<hide.comp.ContextMenu.ContextMenuItem> = null;
		switch( column.type ) {
		case TId:
			if( value != null && value != "" )
				menu = [
					{
						label : "Show references",
						click : () -> editor.showReferences(this.value),
						keys : this.editor.config.get("key.cdb.showReferences"),
					},
					{
						label : "Show unreferenced IDs",
						click : () -> editor.findUnreferenced(this.column, this.table),
						keys : this.editor.config.get("key.cdb.showUnreferenced"),
					}
				];
		case TRef(sname):
			if( value != null && value != "" )
				menu = [
					{
						label : "Goto",
						click : () -> @:privateAccess editor.gotoReference(this),
						keys : this.editor.config.get("key.cdb.gotoReference"),
					},
					{
						label : "Show references",
						click : () -> editor.showReferences(this.value, editor.base.getSheet(sname)),
						keys : this.editor.config.get("key.cdb.showReferences"),
					},
				];
		case TInt, TFloat:
			function setF( f : Formulas.Formula ) {
				editor.beginChanges();
				editor.formulas.set(this, f);
				line.evaluate();
				editor.endChanges();
				refresh();
			}
			var forms : Array<hide.comp.ContextMenu.ContextMenuItem>;
			var current = editor.formulas.get(this);
			forms = [for( f in editor.formulas.getList(table.sheet) ) { label : f.name, click : () -> if( f == current ) setF(null) else setF(f), checked : f == current }];
			forms.push({ label : "New...", click : () -> editor.formulas.createNew(this, setF) });
			menu = [
				{ label : "Formula", menu : forms }
			];
		default:
		}
		if( menu != null ) {
			focus();
			new ContextMenu(menu);
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

	public function refresh(withSubtable = false) {
		if (dropdown != null) {
			if (js.Browser.document.body.contains(dropdown)) {
				return;
			}
			dropdown = null;
		}
		currentValue = Reflect.field(line.obj, column.name);

		blurOff = true;
		var html = valueHtml(column, value, line.table.getRealSheet(), line.obj, []);
		if( !html.containsHtml )
			elementHtml.textContent = html.str;
		else
			elementHtml.innerHTML = "<div style='max-height: 200px; overflow-y:auto; overflow-x:hidden;'>" + html.str + "</div>";

		switch( column.type ) {
		case TEnum(values):
			elementHtml.title = getEnumValueDoc(values[value]);
		default:
		}
		blurOff = false;

		updateClasses();
		var subTable = line.subTable;
		if( withSubtable && subTable != null && subTable.cell == this) {
			if( column.type == TString && column.kind == Script )
				subTable.refresh();
			else
				table.refreshList(this);
		}
	}

	function watchFile( file : String ) {
		if( file == null ) return;
		if( watches.indexOf(file) != -1 ) return;

		watches.push(file);
		ide.fileWatcher.registerRaw(file, function() { refresh(); }, true, elementHtml);
	}

	function updateClasses() {
		elementHtml.classList.remove("edit");
		elementHtml.classList.remove("edit_long");
		switch( column.type ) {
		case TBool:
			elementHtml.classList.toggle("true", value == true);
			elementHtml.classList.toggle("false", value == false);
		case TInt, TFloat:
			elementHtml.classList.toggle("zero", value == 0 );
			elementHtml.classList.toggle("nan", Math.isNaN(value));
			elementHtml.classList.toggle("formula", editor.formulas.has(this) );
		default:
		}
		if( ide.projectConfig.dbProofread == true ) {
			var classes = elementHtml.className.split(" ");
			switch( column.type ) {
			case TRef(name):
				var sdat = editor.base.getSheet(name);
				if( sdat != null ) {
					for( c in sdat.columns ) {
						switch( c.type ) {
							case TId | TBool:
								for (c2 in classes) {
									if (StringTools.startsWith(c2, "r_" + c.name + "_"))
										elementHtml.classList.remove(c2);
								}
							default:
						}
					}
					for( l in sdat.all ) {
						if( l.id == currentValue ) {
							for( c in sdat.columns ) {
								switch( c.type ) {
									case TId | TBool:
										elementHtml.classList.add("r_" + c.name + "_" + Reflect.field(l.obj, c.name));
									default:
								}
							}
							break;
						}
					}
				}
			default:
			}
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

	function refScope( targetSheet : cdb.Sheet, currentSheet : cdb.Sheet, obj : Dynamic, localScope : Array<{ s : cdb.Sheet, obj : Dynamic }> ) {
		var targetDepth = targetSheet.name.split("@").length;
		var scope = table.getScope().concat(localScope);
		if( scope.length < targetDepth )
			scope.push({ s : currentSheet, obj : obj });
		while( scope.length >= targetDepth )
			scope.pop();
		return scope;
	}

	function valueHtml( c : cdb.Data.Column, v : Dynamic, sheet : cdb.Sheet, obj : Dynamic, scope : Array<{ s : cdb.Sheet, obj : Dynamic }> ) : {str: String, containsHtml: Bool} {

		inline function val(s:String) {
			return {str: Std.string(s), containsHtml:false};
		}

		function html(s: String) {
			return {str: Std.string(s), containsHtml:true};
		}

		if( v == null ) {
			if( c.opt )
				return val(" ");
			return html('<span class="error">#NULL</span>');
		}
		return switch( c.type ) {
		case TInt, TFloat:
			switch( c.display ) {
			case Percent:
				val((Math.round(v * 10000)/100) + "%");
			default:
				val(v);
			}
		case TId:
			if( v == "" )
				html('<span class="error">#MISSING</span>');
			else {
				var id = c.scope != null ? table.makeId(scope,c.scope,v) : v;
				!sheet.duplicateIds.exists(id) ? val(v) : html('<span class="error">#DUP($v)</span>');
			}
		case TString if( c.kind == Script ):  // wrap content in div because td cannot have max-height
			v == "" ? val(" ") : html('<div class="script">${colorizeScript(c,v, sheet.idCol == null ? null : Reflect.field(obj, sheet.idCol.name))}</div>');
		case TString, TLayer(_):
			v == "" ? val(" ") : html(StringTools.htmlEscape(v).split("\n").join("<br/>"));
		case TRef(sname):
			if( v == "" )
				html('<span class="error">#MISSING</span>');
			else {
				var s = editor.base.getSheet(sname);
				var i = s.index.get(s.idCol.scope != null ? table.makeId(refScope(s,sheet,obj,scope),s.idCol.scope,v) : v);
				html(i == null ? '<span class="error">#REF($v)</span>' : (i.ico == null ? "" : tileHtml(i.ico,true).str+" ") + StringTools.htmlEscape(i.disp));
			}
		case TBool:
			val(v?"Y":"N");
		case TEnum(values):
			val(values[v]);
		case TImage:
			html('<span class="error">#DEPRECATED</span>');
		case TList:
			var a : Array<Dynamic> = v;
			var ps = sheet.getSub(c);
			var out : Array<String> = [];
			scope.push({ s : sheet, obj : obj });
			var isHtml = false;
			for( v in a ) {
				var vals = [];
				for( c in ps.columns ) {
					if(c.type == TString && c.kind == Script)
						continue;
					if( !canViewSubColumn(ps, c.name) ) continue;
					var h = valueHtml(c, Reflect.field(v, c.name), ps, v, scope);
					if( h.str != "" && h.str != " " )
					{
						isHtml = isHtml || h.containsHtml;
						vals.push(h.str);
					}
				}
				inline function char(s) return '<span class="minor">$s</span>';
				if (vals.length == 0)
					continue;
				else if (vals.length == 1) {
					out.push(vals[0]);
				}
				else {
					out.push((char('[') + vals.join(char(',')) + char(']')));
					isHtml = true;
				}
			}
			scope.pop();
			if( out.length == 0 )
				return val("");
			return {str: out.join(", "), containsHtml: true};
		case TProperties:
			var ps = sheet.getSub(c);
			var out = [];
			scope.push({ s : sheet, obj : obj });
			for( c in ps.columns ) {
				var pval = Reflect.field(v, c.name);
				if( pval == null && c.opt ) continue;
				if( !canViewSubColumn(ps, c.name) ) continue;
				out.push(c.name+" : "+valueHtml(c, pval, ps, v, scope).str);
			}
			scope.pop();
			html(out.join("<br/>"));
		case TCustom(name):
			var t = editor.base.getCustomType(name);
			var isHtml = false;
			var a : Array<Dynamic> = v;
			var str = "";

			// Temp fix for hack
			try {
				var cas = t.cases[a[0]];
				str = cas.name;
				if( cas.args.length > 0 ) {
					str += "(";
					var out = [];
					var pos = 1;
					for( i in 1...a.length ) {
						var r = valueHtml(cas.args[i-1], a[i], sheet, this, scope);
						isHtml = isHtml || r.containsHtml;
						out.push(r.str);
					}
					str += out.join(",");
					str += ")";
				}
			} catch(e) {};
			{str: str, containsHtml: isHtml};
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
			val(flags.length == 0 ? String.fromCharCode(0x2205) : flags.join("|"+String.fromCharCode(0x200B)));
		case TColor:
			html('<div class="color" style="background-color:#${StringTools.hex(v,6)}"></div>');
		case TFile:
			var path = ide.getPath(v);
			var url = ide.getUnCachedUrl(path);
			var ext = v.split(".").pop().toLowerCase();
			if (v == "") return html('<span class="error">#MISSING</span>');
			var innerHtml = StringTools.htmlEscape(v);
			innerHtml = '<span title=\'$innerHtml\' >' + innerHtml  + '</span>';
			if (!editor.quickExists(path)) return html('<span class="error">#NOTFOUND : $innerHtml</span>');
			else if( ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" ) {
				var dims = imageDims.get(url);
				var dimsText = dims != null ? dims.width+"x"+dims.height : "";
				var onload = dims != null ? "" : 'onload="hide.comp.cdb.Cell.onImageLoad(this, \'$url\');"';
				var img = '<img src="$url" $onload/>';
				var previewHandler = ' onmouseenter="$(this).find(\'.previewContent\').css(\'top\', this.getBoundingClientRect().bottom + \'px\')"';
				if (getCellConfigValue("inlineImageFiles", false)) {
					innerHtml = '<span class="preview inlineImage" $previewHandler>
						<img src="$url"><div class="previewContent"><div class="inlineImagePath">$innerHtml</div><div class="label">$dimsText</div>$img</div>
					</span>';
				} else {
					innerHtml = '<span class="preview" $previewHandler>$innerHtml
						<div class="previewContent"><div class="label">$dimsText</div>$img</div>
					</span>';
				}
			}
			return html(innerHtml + ' <input type="submit" value="open" onclick="hide.Ide.inst.openFile(\'$path\')"/>');
		case TTilePos:
			return tileHtml(v);
		case TTileLayer:
			var v : cdb.Types.TileLayer = v;
			var path = ide.getPath(v.file);
			if( !editor.quickExists(path) )
				html('<span class="error">' + v.file + '</span>');
			else
				val('#DATA');
		case TDynamic:
			var str = Std.string(v).split("\n").join(" ").split("\t").join("");
			if( str.length > 50 ) str = str.substr(0, 47) + "...";
			val(str);
		}
	}

	static function onImageLoad(img : js.html.ImageElement, url) {
		var dims = {width : img.width, height : img.height};
		imageDims.set(url, dims);
		new Element(img).parent().find(".label").text(dims.width+'x'+dims.height);
	}

	static var KWDS = ["for","if","var","this","while","else","do","break","continue","switch","function","return","new","throw","try","catch","case","default"];
	static var KWD_REG = new EReg([for( k in KWDS ) "(\\b"+k+"\\b)"].join("|"),"g");
	function colorizeScript( c : cdb.Data.Column, ecode : String, objID : String ) {
		var code = ecode;
		code = StringTools.htmlEscape(code);
		code = code.split("\n").join("<br/>");
		code = code.split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
		// typecheck
		var chk = new ScriptEditor.ScriptChecker(editor.config, "cdb."+getDocumentName()+(c == this.column ? "" : "."+ c.name),
			[
				"cdb."+table.sheet.name => line.obj,
				"cdb.objID" => objID,
				"cdb.groupID" => line.getGroupID(),
			]
		);
		var cache = chk.getCache(ecode);
		var error : Null<Bool> = cache.get(cache.signature);
		if( error == null ) {
			error = chk.check(ecode) != null;
			cache.set(cache.signature, error);
		}
		if( error )
			return '<span class="error">'+code+'</span>';
		// strings
		code = ~/("[^"]*")/g.replace(code,'<span class="str">$1</span>');
		code = ~/('[^']*')/g.replace(code,'<span class="str">$1</span>');
		// keywords
		code = KWD_REG.map(code, function(r) return '<span class="kwd">${r.matched(0)}</span>');
		// comments
		function unspan(str:String) {
			return str.split('<span class="').join('<span class="_');
		}
		code = ~/(\/\*([^\*]+)\*\/)/g.map(code,function(r) return '<span class="comment">'+unspan(r.matched(1))+'</span>');
		var conf = this.editor.config.get("cdb.script");
		var maxLines = conf != null && conf.maxLines != null ? conf.maxLines : 99;
		var lines = code.split("<br/>");
		if(lines.length > maxLines) {
			lines = lines.slice(0, maxLines);
			lines.push("...");
		}
		code = lines.map(function(line) return ~/(\/\/.*)/.map(line,(r) -> '<span class="comment">'+unspan(r.matched(1))+'</span>')).join("<br/>");
		return code;
	}

	public function getDocumentName() {
		var name = table.sheet.name.split("@").join(".");
		if( table.sheet.props.hasGroup ) {
			var gid : Null<Int> = Reflect.field(line.obj, "group");
			if( gid != null ) {
				var index = 0;
				for( s in table.sheet.separators ) {
					if( s.title != null ) {
						if( index == gid ) {
							name += "[group="+s.title+"]";
							break;
						}
						index++;
					}
				}
			}
		}
		name += "."+column.name;
		return name;
	}

	function tileHtml( v : cdb.Types.TilePos, ?isInline ) : {str: String, containsHtml: Bool} {
		var path = ide.getPath(v.file);
		if( !editor.quickExists(path) ) {
			if( isInline ) return {str: "", containsHtml: false};
			return {str: '<span class="error">' + v.file + '</span>', containsHtml: true};
		}
		var width = v.size * (v.width == null?1:v.width);
		var height = v.size * (v.height == null?1:v.height);
		var max = width > height ? width : height;
		var zoom = max <= 32 ? 2 : 64 / max;
		var inl = isInline ? 'display:inline-block;' : '';
		var url = ide.getUnCachedUrl(path);

		var px = Std.int(v.size*v.x*zoom);
		var py = Std.int(v.size*v.y*zoom);
		var bg = 'background : url(\'$url\') -${px}px -${py}px;';
		if( zoom > 1 )
			bg += "image-rendering : pixelated;";
		var html = '<div
			class="tile toload"
			path="$path"
			zoom="$zoom"
			style="width : ${Std.int(width * zoom)}px; height : ${Std.int(height * zoom)}px; opacity:0; $bg $inl"
		></div>';
		queueTileLoading();
		watchFile(path);
		return {str: html, containsHtml: true};
	}

	static var isTileLoadingQueued = false;
	static function queueTileLoading() {
		if (!isTileLoadingQueued) {
			isTileLoadingQueued = true;
			haxe.Timer.delay(function() {
				startTileLoading();
				isTileLoadingQueued = false;
			}, 0);
		}
	}

	static function startTileLoading() {
		var tiles = new Element(".tile.toload");
		if( tiles.length == 0 ) return;
		tiles.removeClass("toload");
		var imap = new Map();
		for( t in tiles ) {
			imap.set(t.getAttribute("path"), t);
		}
		for( path => elt in imap ) {
			var url = Ide.inst.getUnCachedUrl(path);
			function handleDims(dims: {width : Int, height : Int}) {
				for( t in tiles ) {
					if( t.getAttribute("path") == path ) {
						var zoom = Std.parseFloat(t.getAttribute("zoom"));
						var bgw = Std.int(dims.width * zoom);
						var bgh = Std.int(dims.height * zoom);
						var t1 = new Element(t);
						t1.css("background-size", '${bgw}px ${bgh}px');
						t1.css("opacity", "1");
					}
				}
			}
			var dims = imageDims.get(url);
			if( dims != null ) {
				handleDims(dims);
				continue;
			}

			var img = js.Browser.document.createImageElement();

			img.src = url;
			img.setAttribute("style","display:none");
			img.onload = function() {
				var dims = {width : img.width, height : img.height};
				handleDims(dims);
				imageDims.set(url, dims);
				img.remove();
			};
			elt.parentElement.append(img);
		}
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

	function getEnumValueDoc(v: String) {
		var colDoc = column.documentation == null ? [] : column.documentation.split("\n");
		var d = colDoc.find(l -> new EReg('\\b$v\\b', '').match(l));
		if( d != null ) {
			if( d.indexOf(':') >= 0 )
				return StringTools.ltrim(d.substr(d.indexOf(':') + 1));
			else if( d.indexOf('->') >= 0 )
				return StringTools.ltrim(d.substr(d.indexOf('->') + 2));
			else if( d.indexOf('=>') >= 0 )
				return StringTools.ltrim(d.substr(d.indexOf('=>') + 2));
		}
		return null;
	}

	// kept available until we're confident in the new system
	var useSelect2 = false;
	public function edit() {
		if( !canEdit() )
			return;
		//useSelect2 = this.editor.config.get("cdb.useSelect2") || (Std.isOfType(editor, ObjEditor) && editor.element.parent().hasClass("detached"));
		inEdit = true;

		switch( column.type ) {
		case TString if( column.kind == Script ):
			open();
		case TInt, TFloat, TString, TId, TCustom(_), TDynamic:
			var str = value == null ? "" : Std.isOfType(value, String) ? value : editor.base.valToString(column.type, value);

			elementHtml.innerHTML = null;
			elementHtml.classList.add("edit");



			var i = new Element("<div contenteditable='true' tabindex='1' class='custom-text-edit'>");
			i[0].innerText = str;
			var textHeight = i[0].offsetHeight;
			var longText = textHeight > 25 || str.indexOf("\n") >= 0;

			elementHtml.appendChild(i[0]);
			i.keypress(function(e) {
				e.stopPropagation();
			});
			i.dblclick(function(e) e.stopPropagation());
			//if( str != "" && (table.displayMode == Properties || table.displayMode == AllProperties) )
			//	i.css({ width : Math.ceil(textWidth - 3) + "px" }); -- bug if small text ?
			/*if( longText ) {
				elementHtml.classList.add("edit_long");
				i.css({ height : Math.max(25,Math.ceil(textHeight - 1)) + "px" });
			}*/
			i.val(str);
			function closeEdit() {
				i.off();
				this.closeEdit();
			}
			i.keydown(function(e) {
				var t : js.html.HtmlElement = cast e.target;
				var textHeight = t.offsetHeight;
				var longText = textHeight > 25 || t.innerText.indexOf("\n") >= 0;
				switch( e.keyCode ) {
				case K.ESCAPE:
					inEdit = false;
					refresh();
					focus();
					table.editor.element.focus();
				case K.ENTER if( !e.shiftKey || !column.type.match(TString|TDynamic|TCustom(_)) ):
					closeEdit();
					e.preventDefault();
				case K.UP, K.DOWN if( !longText ):
					closeEdit();
					return;
				case K.TAB:
					closeEdit();
					e.preventDefault();
					editor.cursor.move(e.shiftKey ? -1 : 1, 0, false, false, true);
					var c = editor.cursor.getCell();
					if( c != this ) c.edit();
				}
				e.stopPropagation();
			});
			i.keyup(function(e) try {
				var t : js.html.HtmlElement = cast e.target;
				var v = editor.base.parseValue(column.type, t.innerText);

				if (column.type == TId && !isUniqueID((v:String), true)) {
					throw v + " is not a unique id";
				}

				setErrorMessage(null);
			} catch( e : Dynamic ) {
				setErrorMessage(StringTools.htmlUnescape(""+e));
			});
			i.keyup(null);
			i.blur(function(_) {
				if (!blurOff)
					closeEdit();
			});
			i.focus();

			// Select whole content of contenteditable div
			{
				var range =  js.Browser.document.createRange();
				range.selectNodeContents(i[0]);
				var sel = js.Browser.window.getSelection();
				sel.removeAllRanges();
				sel.addRange(range);
			}


			if( longText ) i.scrollTop(0);
		case TBool:
			setValue( currentValue == false && column.opt && table.displayMode != Properties ? null : currentValue == null ? true : currentValue ? false : true );
			closeEdit();
		case TProperties, TList:
			open();
		case TRef(name):
			var sdat = editor.base.getSheet(name);
			if( sdat == null ) return;
			elementHtml.innerHTML = null;
			elementHtml.classList.add("edit");

			if (!useSelect2) {
				var isLocal = sdat.idCol.scope != null;
				var elts: Array<hide.comp.Dropdown.Choice>;
				function makeClasses(o: cdb.Sheet.SheetIndex) {
					var ret = [];
					for( c in sdat.columns ) {
						switch( c.type ) {
							case TId | TBool:
								ret.push("r_" + c.name + "_" + Reflect.field(o.obj, c.name));
							case TEnum( values ):
								ret.push("r_" + c.name + "_" + values[Reflect.field(o.obj, c.name)]);
							case TFlags( values ):
							default:
						}
					}
					return ret;
				}
				if( isLocal ) {
					var scope = refScope(sdat,table.getRealSheet(),line.obj,[]);
					var prefix = table.makeId(scope, sdat.idCol.scope, null)+":";
					elts = [ for( d in sdat.all ) if( StringTools.startsWith(d.id,prefix) ) {
						id : d.id.split(":").pop(),
						ico : d.ico,
						text : d.disp,
						classes : makeClasses(d),
					}];
				} else {
					elts = [ for( d in sdat.all ) {
						id : d.id,
						ico : d.ico,
						text : d.disp,
						classes : makeClasses(d),
					}];
				}
				if( column.opt || currentValue == null || currentValue == "" ) {
					elts.unshift({
						id : null,
						ico : null,
						text : "--- None ---",
					});
				}
				function makeIcon(c: hide.comp.Dropdown.Choice) {
					if (sdat.props.displayIcon == null)
						return null;
					if (c.ico == null)
						return new Element("<div style='display:inline-block;width:16px'/>");
					return new Element(tileHtml(c.ico, true).str);
				}
				var d = new Dropdown(new Element(elementHtml), elts, currentValue, makeIcon, true);
				dropdown = d.element[0];
				d.onSelect = function(v) {
					setValue(v);
				}
				d.onClose = function() {
					dropdown = null;
					closeEdit();
				}
				d.filterInput.keydown(function(e) {
					switch( e.keyCode ) {
					case K.LEFT, K.RIGHT:
						d.filterInput.blur();
						return;
					case K.TAB:
						d.filterInput.blur();
						editor.cursor.move(e.shiftKey? -1:1, 0, false, false, true);
						var c = editor.cursor.getCell();
						if( c != this && !c.blockEdit() ) c.edit();
						e.preventDefault();
					default:
					}
					e.stopPropagation();
				});

			} else {
				var s = new Element("<select>");
				var isLocal = sdat.idCol.scope != null;
				var elts;
				if( isLocal ) {
					var scope = refScope(sdat,table.getRealSheet(),line.obj,[]);
					var prefix = table.makeId(scope, sdat.idCol.scope, null)+":";
					elts = [for( d in sdat.all ) if( StringTools.startsWith(d.id,prefix) ) { id : d.id.split(":").pop(), ico : d.ico, text : d.disp }];
				} else
					elts = [for( d in sdat.all ) { id : d.id, ico : d.ico, text : d.disp }];
				if( column.opt || currentValue == null || currentValue == "" )
					elts.unshift( { id : "~", ico : null, text : "--- None ---" } );
				elementHtml.appendChild(s[0]);

				var props : Dynamic = { data : elts };
				if( sdat.props.displayIcon != null ) {
					function buildElement(i) {
						var text = StringTools.htmlEscape(i.text);
						return new Element("<div>"+(i.ico == null ? "<div style='display:inline-block;width:16px'/>" : tileHtml(i.ico,true).str) + " " + text+"</div>");
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
			}
		case TEnum(values):
			elementHtml.innerHTML = null;
			elementHtml.classList.add("edit");

			if (!useSelect2) {
				var elts : Array<hide.comp.Dropdown.Choice> = [for( i in 0...values.length ){
					id : "" + i,
					text : values[i],
					doc : getEnumValueDoc(values[i]),
				}];
				if( column.opt )
					elts.unshift( { id : "-1", text : "--- None ---" } );
				var d = new Dropdown(new Element(elementHtml), elts, "" + currentValue, true);
				d.onSelect = function(v) {
					var val = Std.parseInt(v);
					if( val < 0 ) val = null;
					setValue(val);
				}
				d.onClose = function() {
					closeEdit();
				}
				d.filterInput.keydown(function(e) {
					switch( e.keyCode ) {
					case K.LEFT, K.RIGHT:
						d.filterInput.blur();
						return;
					case K.TAB:
						d.filterInput.blur();
						editor.cursor.move(e.shiftKey? -1:1, 0, false, false, true);
						var c = editor.cursor.getCell();
						if( c != this && !c.blockEdit() ) c.edit();
						e.preventDefault();
					default:
					}
					e.stopPropagation();
				});

			} else { // TODO fix comp.Dropdown for detached cdb panel (in the prefab editor)
					// so this can finally be removed
				var s = new Element("<select>");
				var elts = [for( i in 0...values.length ){ id : ""+i, ico : null, text : values[i] }];
				if( column.opt )
					elts.unshift( { id : "-1", ico : null, text : "--- None ---" } );
				elementHtml.appendChild(s[0]);

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
				new Element("input.select2-search__field").keydown(function(e) {
					switch( e.keyCode ) {
					case K.LEFT, K.RIGHT:
						s.blur();
						return;
					case K.TAB:
						s.blur();
						editor.cursor.move(e.shiftKey? -1:1, 0, false, false, true);
						var c = editor.cursor.getCell();
						if( c != this && !c.blockEdit() ) c.edit();
						e.preventDefault();
					default:
					}
					e.stopPropagation();
				});
				s.on("select2:close", function(_) closeEdit());
			}
		case TColor:
			var elem = new Element(elementHtml);
			var preview = elem.find(".color");
			if (preview.length < 1) {
				elem.html('<div class="color" style="background-color:#${StringTools.hex(0xFFFFFF,6)}"></div>');
				preview = elem.find(".color");
			}
			var cb = new ColorPicker(false, elem, preview);
			cb.value = currentValue;
			cb.onChange = function(drag) {
				preview.css({backgroundColor : '#'+StringTools.hex(cb.value,6) });
			};
			cb.onClose = function() {
				setValue(cb.value);
				cb.remove();
				closeEdit();
			};
		case TFile:
			ide.chooseFile(["*"], function(file) {
				setValue(file);
				closeEdit();
			}, false, currentValue);
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
				var line = new Element("<label>");
				line.text(values[i]).appendTo(div).prepend(f);
				var doc = getEnumValueDoc(values[i]);
				if( doc != null ) {
					line.attr("title", doc);
					new Element('<i style="margin-left: 5px" class="ico ico-book"/>').appendTo(line);
				}
			}
			elementHtml.innerHTML = null;
			var modal = new Element("<div>").addClass("hide-modal");
			elementHtml.appendChild(modal[0]);
			elementHtml.appendChild(div[0]);
			modal.click(function(e) {
				setValue(val);
				closeEdit();
			});
		case TTilePos:
			var modal = new hide.comp.Modal(new Element(elementHtml));
			modal.modalClick = function(_) closeEdit();

			inline function usesSquareBase(t : cdb.Types.TilePos) {
				return t.size != 1
					|| t.x / t.width != Math.floor(t.x / t.width)
					|| t.y / t.height != Math.floor(t.y / t.height);
			}
			function getDims(t : cdb.Types.TilePos) {
				if (t == null)
					return {width: 16, height: 16};
				if (!usesSquareBase(t)) {
					return {
						width: (t.width != null && t.width > 0) ? t.width : t.size,
						height: (t.height != null && t.height > 0) ? t.height : t.size,
					};
				}
				return {width: t.size, height: t.size};
			}

			var t : cdb.Types.TilePos = currentValue;
			var file = t == null ? null : t.file;
			var dims = getDims(t);
			var pos = { x : 0, y : 0, width : 1, height : 1 };
			if (t != null) {
				pos = {
					x : Math.floor(t.x / (usesSquareBase(t) ? 1 : t.width)),
					y : Math.floor(t.y / (usesSquareBase(t) ? 1 : t.height)),
					width : (t.width == null || !usesSquareBase(t)) ? 1 : t.width,
					height : (t.height == null || !usesSquareBase(t)) ? 1 : t.height,
				};
			}
			if( file == null ) {
				var y = line.index - 1;
				while( y >= 0 ) {
					var o = line.table.lines[y--];
					var v2 = Reflect.field(o.obj, column.name);
					if( v2 != null ) {
						file = v2.file;
						dims = getDims(v2);
						break;
					}
				}
			}

			function setVal() {
				var size = dims.width;
				var v : Dynamic = { file : file, size : size, x : pos.x, y : pos.y };
				if( pos.width != 1 ) v.width = pos.width;
				if( pos.height != 1 ) v.height = pos.height;

				if( dims.height != dims.width ) {
					v.size = 1;
					v.x = pos.x * dims.width;
					v.y = pos.y * dims.height;
					v.width = pos.width * dims.width;
					v.height = pos.height * dims.height;
				}
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
				},true);
				return;
			}

			var ts = new hide.comp.TileSelector(file,dims,modal.content);
			ts.allowRectSelect = true;
			ts.allowSizeSelect = true;
			ts.allowFileChange = true;
			ts.value = pos;
			ts.onChange = function(cancel) {
				if( !cancel ) {
					file = ts.file;
					dims = ts.size;
					pos = ts.value;
					setVal();
				}
				closeEdit();
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

			// prevent opening the script if we are undo/redo-ing as this
			// will get our script windowed focus and prevent further undo/redo action
			if( immediate && !Editor.inRefreshAll ) return;

			var str = value == null ? "" : editor.base.valToString(column.type, value);
			table.toggleList(this, immediate, function() return new ScriptTable(editor, this));
		} else
			table.toggleList(this, immediate);
	}

	public function setErrorMessage( msg : String ) {
		var prevError = elementHtml.querySelector("div.error");
		if (prevError != null)
			prevError.remove();
		if( msg == null ) return;
		var div = js.Browser.document.createDivElement();
		div.classList.add("error");
		div.innerText = msg;
		elementHtml.appendChild(div);
	}

	public function isUniqueID(id : String, ignoreSelf:Bool = false) {
		var scope = table.getScope();
		var idWithScope : String = if (column.scope != null) table.makeId(scope, column.scope, id) else id;
		return editor.isUniqueID(table.getRealSheet(), if(ignoreSelf) line.obj else {}, idWithScope);
	}

	function setRawValue( str : Dynamic ) {
		var newValue : Dynamic;
		if( Std.isOfType(str,String) ) {
			newValue = try editor.base.parseValue(column.type, str, false) catch( e : Dynamic ) return;
		} else
			newValue = str;

		if( newValue == null || newValue == currentValue )
			return;

		switch( column.type ) {
		case TId:
			if (isUniqueID(newValue, true)) {
				editor.changeID(line.obj, newValue, column, table);
				currentValue = newValue;
			}
			focus();
		case TString if( column.kind == Script || column.kind == Localizable ):
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
			closeEdit();
		default:
			setValue(newValue);
		}
	}

	public function blockEdit() {
		return useSelect2 && inEdit && (column.type.match(TRef(_)) || column.type.match(TEnum(_)));
	}

	public function setValue( value : Dynamic ) {
		currentValue = value;
		editor.changeObject(line,column,value);
	}

	public function closeEdit() {
		inEdit = false;
		var input = elementHtml.querySelector("div[contenteditable]");
		if(input != null && input.innerText != null ) setRawValue(input.innerText);
		refresh();
		focus();
	}

}
