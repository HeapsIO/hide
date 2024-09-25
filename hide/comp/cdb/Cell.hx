package hide.comp.cdb;

import hxd.Key in K;
using hide.tools.Extensions;

class Cell {

	static var typeNames = [for( t in Type.getEnumConstructs(cdb.Data.ColumnType) ) t.substr(1).toLowerCase()];
	static var imageDims : Map<String, {width : Int, height : Int}> = new Map();

	var ide : hide.Ide;

	public var elementHtml : Element.HTMLElement;
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
	var dropdown : Element.HTMLElement = null;

	public function new( root : Element.HTMLElement, line : Line, column : cdb.Data.Column ) {
		this.elementHtml = root;
		ide = hide.Ide.inst;

		this.line = line;
		this.editor = line.table.editor;
		this.column = column;
		@:privateAccess line.cells.push(this);

		// This gets used by drag and drop
		if (column.type == TFile) {
			var eroot = new Element(root);
			eroot.prop("cellComp", this);
		}

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
				elementHtml.addEventListener("dblclick", function(_) edit());
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
		function displayError(msg:String) {
			ide.quickError(msg);
		}
		var newV : Float = try editor.formulas.evalBlock(() -> f.call(line.obj))
		catch( e : hscript.Expr.Error ) { displayError(e.toString()); Math.NaN; }
		catch( e : Dynamic ) { displayError(Std.string(e)); Math.NaN; }
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
			#if !hl
			forms.push({ label : "New...", click : () -> editor.formulas.createNew(this, setF) });
			#end
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
		#if js
		if (dropdown != null) {
			if (js.Browser.document.body.contains(dropdown)) {
				return;
			}
			dropdown = null;
		}
		#end
		currentValue = Reflect.field(line.obj, column.name);

		blurOff = true;
		var html = valueHtml(column, value, line.table.getRealSheet(), line.obj, []);
		if( !html.containsHtml )
			elementHtml.textContent = html.str;
		else
			elementHtml.innerHTML = "<div class='cell-root' style='max-height: 200px; overflow-y:auto; overflow-x:hidden;'>" + html.str + "</div>";

		switch( column.type ) {
		case TEnum(values):
			var doc = getEnumValueDoc(values[value]);
			if (doc != null)
				elementHtml.title = doc;
		case TId, TRef(_):
			elementHtml.title = value;
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

		inline function val(s:Dynamic) {
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
			v == "" ? val(" ") : html(spacesToNBSP(StringTools.htmlEscape(v).split("\n").join("<br/>")));
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
			var ext = v.split(".").pop().toLowerCase();
			if (v == "") return html('<span class="error">#MISSING</span>');
			var innerHtml = StringTools.htmlEscape(v);
			innerHtml = '<span title=\'$innerHtml\' >' + innerHtml  + '</span>';
			if (!editor.quickExists(path)) return html('<span class="error">#NOTFOUND : $innerHtml</span>');
			else if( ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "gif" ) {
				#if js
				var url = ide.getUnCachedUrl(path);
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
				#end
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
		case TGradient:
			if (value.colors == null || value.positions == null || value.colors.length == 0 || value.colors.length != value.positions.length)
				return val('#INVALID GRADIENT `${haxe.Json.stringify(value)}`');
			var fill = "";
			function colorToCss(c: Int) {
				var c = h3d.Vector4.fromColor(c);
				return 'rgba(${c.r*255.0}, ${c.g*255.0}, ${c.b*255.0}, ${c.a})';
			}

			if (value.colors.length == 1) {
				fill = colorToCss(value.colors[0]);
			} else {
				fill = 'linear-gradient( 0.25turn, ${[
					for (i in 0...value.colors.length) '${colorToCss(value.colors[i])} ${value.positions[i] * 100}%'
				].join(", ")})';
			}

			var str ='<div class="cdb-gradient"><div class="alpha-bg"></div><div style="background: $fill" class="inner-gradient"></div></div>';

			// uncomment to test generate functionality

			// var gradient : cdb.Types.Gradient = value;
			// var colors = gradient.generate(32);
			// str += '
			// 	<div style="display:flex; width:100%; height: 20px">
			// 		${[ for (c in colors)
			// 			'<div style="width:100%; height: 100%; background: ${colorToCss(c)};"></div>'
			// 		].join("\n")}
			// 	</div>
			// ';

			html(str);
		case TCurve:
			var curve = new cdb.Types.Curve(cast (value ?? []));
			var nbPoints = curve.data.length;
			if (nbPoints % 6 != 0)
				return val('#INVALID CURVE DATA ($nbPoints not a multiple of 6)');

			nbPoints = Std.int(nbPoints / 6);
			var data = "";

			var prefab = new hrt.prefab.Curve(null, null);
			var curve = new cdb.Types.Curve(cast value);
			prefab.initFromCDB(curve);

			var bounds = prefab.getBounds();
			var data = prefab.getSvgString();

			var debugData = '';
			var debugCurveApi = false;
			if (debugCurveApi)
			{
				var bake = curve.bake(128);
				for (i in 0...16) {
					var t = bounds.xMin + (i/16 * bounds.width);
					var v = bake.eval(t);

					debugData += '<circle cx="$t" cy="$v" r="0.02" fill="red"/>';

					v = prefab.getVal(t);
					debugData += '<circle cx="$t" cy="$v" r="0.015" fill="white"/>';

					v = curve.eval(t);
					debugData += '<circle cx="$t" cy="$v" r="0.01" fill="green"/>';
				}
			}

			var svg = '
				<svg class="cdb-curve" preserveAspectRatio="none" viewBox="${bounds.xMin} ${bounds.yMin} ${bounds.width} ${bounds.height}">
				<path d="M ${bounds.xMin} 0 H ${bounds.xMax}" class="x-axis"/>
				<path d="M 0 ${bounds.yMin} V ${bounds.yMax}" class="y-axis"/>
				<path d="$data" class="curve"/>
				$debugData
				</svg>
			';

			return html(svg);
		}

	}

	#if js
	static function onImageLoad(img : js.html.ImageElement, url) {
		var dims = {width : img.width, height : img.height};
		imageDims.set(url, dims);
		new Element(img).parent().find(".label").text(dims.width+'x'+dims.height);
	}
	#end

	static var KWDS = ["for","if","var","this","while","else","do","break","continue","switch","function","return","new","throw","try","catch","case","default"];
	static var KWD_REG = new EReg([for( k in KWDS ) "(\\b"+k+"\\b)"].join("|"),"g");
	function colorizeScript( c : cdb.Data.Column, ecode : String, objID : String ) {
		var code = ecode;
		code = StringTools.htmlEscape(code);
		code = code.split("\n").join("<br/>");
		code = code.split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
		// typecheck
		var chk = new ScriptEditor.ScriptChecker(editor.config, "cdb."+getDocumentName()+(c == this.column ? "" : "."+ c.name),line.getConstants(objID));
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
		#if js
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
		#else
		return {str : "", containsHtml : false};
		#end
	}

	#if !hl
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
	#end

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

	// replace consecutive spaces to non brekable space + a space
	public function spacesToNBSP(str: String) {
		var buf = new StringBuf();

		for (i in 0...str.length) {
			var c : Int = str.charCodeAt(i);
			if (c == 0x20) {
				var c2 = str.charCodeAt(i+1);
				if (c2 == null || c2 == 0x20) {
					c = 0xa0;
				}
			}
			buf.addChar(c);
		}
		return buf.toString();
	}

	public function nBSPtoSpaces(str: String) {
		return StringTools.replace(str, "\u00A0", " ");
	}

	public function edit() {
		if( !canEdit() )
			return;
		inEdit = true;

		switch( column.type ) {
		case TString if( column.kind == Script ):
			open();
		case TInt, TFloat, TString, TId, TDynamic:
			var val = value;
			if (column.display == Percent) {
				val *= 100;
			}
			var str = value == null ? "" : Std.isOfType(value, String) ? value : editor.base.valToString(column.type, val, false);

			elementHtml.innerHTML = null;
			elementHtml.classList.add("edit");



			var i = new Element("<div contenteditable='true' tabindex='1' class='custom-text-edit'>");
			// replace all spaces with unbreakable spaces (I wanna die)
			str = spacesToNBSP(str);
			i.get(0).innerText = str;
			var textHeight = i.get(0).offsetHeight;
			var longText = textHeight > 25 || str.indexOf("\n") >= 0;

			elementHtml.appendChild(i.get(0));
			#if js
			i.keypress(function(e) {
				e.stopPropagation();
			});

			i.get(0).addEventListener("paste", function(e) {
				e.preventDefault();

				var event : Dynamic = e;
				if (e.originalEvent != null) {
					event = e.originalEvent;
				}
				var text = event.clipboardData.getData('text/plain');
				js.Browser.document.execCommand("insertText", false, text);
			});
			#end
			i.dblclick(function(e) e.stopPropagation());

			i.val(str);
			function closeEdit() {
				i.off();
				this.closeEdit();
			}
			i.keydown(function(e) {
				var t : Element.HTMLElement = cast e.target;
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
							if (c != this && c != null)
								c.edit();
				}
				e.stopPropagation();
			});
			i.keyup(function(e) try {
				var t : Element.HTMLElement = cast e.target;
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
				#if js
				var range = js.Browser.document.createRange();
				range.selectNodeContents(i.get(0));
				var sel = js.Browser.window.getSelection();
				sel.removeAllRanges();
				sel.addRange(range);
				#end
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
			#if js
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
					if( c != this ) c.edit();
					e.preventDefault();
				default:
				}
				e.stopPropagation();
			});
			#end
		case TEnum(values):
			elementHtml.innerHTML = null;
			elementHtml.classList.add("edit");
			#if js
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
					if( c != this ) c.edit();
					e.preventDefault();
				default:
				}
				e.stopPropagation();
			});
			#end
		case TCustom(typeName):
			{
				#if js
				var shouldClose = false;
				if (elementHtml.classList.contains("edit"))
					shouldClose = true;

				if (shouldClose)
					return;

				elementHtml.innerHTML = null;
				elementHtml.classList.add("edit");
				var cellEl = new Element(elementHtml);
				var paddingCell = 4;
				editCustomType(typeName, currentValue, column, cellEl, 0, 0);
				#end
			}
		case TColor:
			var elem = new Element(elementHtml);
			var preview = elem.find(".color");
			if (preview.length < 1) {
				elem.html('<div class="color" style="background-color:#${StringTools.hex(0xFFFFFF,6)}"></div>');
				preview = elem.find(".color");
			}
			#if js
			var cb = new ColorPicker(false, preview);
			cb.value = currentValue;
			cb.onChange = function(drag) {
				preview.css({backgroundColor : '#'+StringTools.hex(cb.value,6) });
			};
			cb.onClose = function() {
				setValue(cb.value);
				cb.remove();
				closeEdit();
			};
			#end
		case TFile:
			#if js
			ide.chooseFile(["*"], function(file) {
				setValue(file);
				closeEdit();
			}, false, (currentValue == '') ? null : currentValue);
			#end
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
					if( e.getThis().is(":checked") ) val |= 1 << i;
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
			elementHtml.appendChild(modal.get(0));
			elementHtml.appendChild(div.get(0));
			modal.click(function(e) {
				setValue(val);
				closeEdit();
			});
		case TTilePos:
			var modal = new hide.comp.Modal.Modal2(new Element(elementHtml), "Tile Picker", "tile-picker");
			//var modal = new hide.comp.Modal(new Element(elementHtml));
			//modal.modalClick = function(_) closeEdit();

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
				#if js
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
				#end
				return;
			}

			#if js
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
				modal.close();
			};

			modal.onClose = function() {
				refresh();
				focus();
			}
			#end
		case TLayer(_), TTileLayer:
			// no edit
		case TImage:
			// deprecated
		case TGradient:
			#if js
			var e = new Element(elementHtml);
			e.addClass("edit");
			var gradientEditor = new GradientEditor(e , false);

			var gradient = hrt.impl.Gradient.getDefaultGradientData();
			if (value != null && value.colors != null && value.colors.length >= 1) {
				gradient.stops.clear();
				for (i in 0...value.colors.length) {
					gradient.stops[i] = {color: value.colors[i], position: value.positions[i]};
				}
			}

			gradientEditor.value = gradient;
			gradientEditor.onClose = function() {
				var grad : cdb.Types.Gradient = {colors: [], positions: []};
				for (i => stop in gradientEditor.value.stops) {
					grad.data.colors[i] = stop.color;
					grad.data.positions[i] = stop.position;
				}

				setValue(grad);
				e.removeClass("edit");
				closeEdit();
				refresh();
				focus();
			}
			#end
		case TCurve:
			var e = new Element(elementHtml);
			e.addClass("edit");
			var curveEditor = new hide.comp.CurveEditor.CurvePopup(e, editor.undo);

			var prefabCurve = new hrt.prefab.Curve(null, null);
			var linear : Float = cast hrt.prefab.Curve.CurveKeyMode.Linear;
			var curve = new cdb.Types.Curve(cast (value ?? [0.0,0.0,cdb.Types.Curve.HandleData,linear,cdb.Types.Curve.HandleData,cdb.Types.Curve.HandleData, 1.0,1.0,cdb.Types.Curve.HandleData,linear,cdb.Types.Curve.HandleData,cdb.Types.Curve.HandleData]));
			prefabCurve.initFromCDB(curve);

			prefabCurve.selected = true;
			curveEditor.editor.curves = [prefabCurve];


			curveEditor.onClose =() -> {
				setValue(prefabCurve.toCDB());
				e.removeClass("edit");
				closeEdit();
				refresh();
				focus();
			};
		}
	}

	public function open( ?immediate : Bool ) {
		#if js
		if( column.type == TString && column.kind == Script ) {

			// prevent opening the script if we are undo/redo-ing as this
			// will get our script windowed focus and prevent further undo/redo action
			if( immediate && !Editor.inRefreshAll ) return;

			var str = value == null ? "" : editor.base.valToString(column.type, value);
			table.toggleList(this, immediate, function() return new ScriptTable(editor, this));
		} else
		#end
			table.toggleList(this, immediate);
	}

	public function setErrorMessage( msg : String ) {
		var prevError = new Element(elementHtml).find("div.error");
		if (prevError != null)
			prevError.remove();
		if( msg == null ) return;
		var div = #if hl ide.createElement("div") #else js.Browser.document.createDivElement() #end;
		div.classList.add("error");
		div.innerText = msg;
		elementHtml.appendChild(div);
	}

	public function isUniqueID(id : String, ignoreSelf:Bool = false) {
		var scope = table.getScope();
		var idWithScope : String = if (column.scope != null) table.makeId(scope, column.scope, id) else id;
		return editor.isUniqueID(table.getRealSheet(), if(ignoreSelf) line.obj else {}, idWithScope);
	}

	function isSpace(c: Int) {
		return (c > 8 && c < 14) || c == 32 || c == 0xA0;
	}

	function trimNonBreakableSpaces(str: String) {
		var pos = 0;
		var endPos = str.length - 1;

		while(pos < str.length && isSpace(str.charCodeAt(pos))) {
			pos ++;
		}

		while (endPos > 0 && isSpace(str.charCodeAt(endPos))) {
			endPos --;
		}
		return str.substr(pos, endPos - pos + 1);
	}

	function setRawValue( str : Dynamic ) {
		var newValue : Dynamic;
		if( Std.isOfType(str,String) ) {
			newValue = try editor.base.parseValue(column.type, str, false) catch( e : Dynamic ) return;
		} else
			newValue = str;

		if (column.display == Percent)
			newValue *= 0.01;

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
			setValue(trimNonBreakableSpaces(newValue));
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

	public function setValue( value : Dynamic ) {
		currentValue = value;
		editor.changeObject(line,column,value);
	}

	public function closeEdit() {
		inEdit = false;
		var input = new Element(elementHtml).find("div[contenteditable]").get(0);
		var text : String = input?.innerText;
		if (text != null) {
			text = nBSPtoSpaces(text);
			setRawValue(text);
		}

		refresh();
		focus();
	}

	public function editCustomType(typeName : String, ctValue : Dynamic, col : cdb.Data.Column, parentEl : Element, rightAnchor: Float, topAnchor : Float, depth : Int = 0) {
		var customType = editor.base.getCustomType(typeName);

		parentEl.empty();
		var rootEl = new Element('<div class="cdb-type-string"></div>').appendTo(parentEl);
		new Element('<p>...</p>').css("margin", "0px").css("text-align","center").appendTo(rootEl);

		var content = new Element('
		<div class="cdb-types">
			<select name="customType" id="dropdown-custom-type">
			<option value="none">None</option>
			${ [for (idx in 0...customType.cases.length) '<option value=${idx}>${customType.cases[idx].name}</option>'].join("") }
			</select>
			<div id="parameters">
			<div>
		</div>');

		content.appendTo(parentEl);

		// Manage keyboard flow
		content.keydown(function(e){
			var focused = content.find(':focus');

			if (e.altKey || e.shiftKey)
				return;

			switch (e.keyCode) {
				case hxd.Key.ENTER:
					if (focused.is('div'))
						focused.trigger('click');

					if (focused.is('input')) {
						if (focused.is('input[type="checkbox"]'))
							focused.prop('checked', !focused.is(':checked'));
						else if (focused.prop('readonly'))
							focused.prop('readonly', false);
						else
							focused.prop('readonly', true);
					}

					if (focused.is('select')) {

					}

					e.stopPropagation();
					e.preventDefault();

				case hxd.Key.ESCAPE:
					if (focused.is('input') && !focused.is('input[type="checkbox"]') && !focused.prop('readonly')) {
						focused.prop('readonly', true);

						e.stopPropagation();
						return;
					}

					rootEl.trigger('click');
					e.stopPropagation();
					e.preventDefault();

				case hxd.Key.RIGHT:
					if (focused.is('input') && !focused.prop('readonly') && !focused.is('input[type="checkbox"]')) {
						e.stopPropagation();
						return;
					}

					var s = content.children('select').first();
					var p = content.find('#parameters').children('.value');

					focused.blur();

					if (focused.is(s))
						p.first().focus();
					else if (focused.is(p.last()))
						s.focus();
					else
						p.eq(p.index(focused) + 1).focus();
					e.stopPropagation();
					e.preventDefault();

				case hxd.Key.LEFT:
					if (focused.is('input') && !focused.prop('readonly') && !focused.is('input[type="checkbox"]')) {
						e.stopPropagation();
						return;
					}

					var s = content.children('select').first();
					var p = content.find('#parameters').children('.value');

					focused.blur();

					if (focused.is(s))
						p.last().focus();
					else if (focused.is(p.first()))
						s.focus();
					else
						p.eq(p.index(focused) - 1).focus();
					e.stopPropagation();
					e.preventDefault();

				case hxd.Key.UP, hxd.Key.DOWN:
					e.stopPropagation();
					e.preventDefault();

				default:
					trace("Not managed");
			}
		});

		function getHtml(value : Dynamic, column : cdb.Data.Column) {
			switch (column.type) {
				case TId, TString, TDynamic:
					var e = new Element('<input type="text" readonly ${value != null ? 'value="${value}"': ''}></input>');
					e.on('click', function(_) {
						e.prop('readonly', false);
					});
					return e;
				case TBool:
					var el =  new Element('<input type="checkbox"></input>');
					if (value != null && value)
						el.attr("checked", "true");
					return el;
				case TInt, TFloat:
					var e = new Element('<input type="number" readonly ${'value="${value != null ? value : 0}"'}></input>');
					e.on('click', function(_) {
						e.prop('readonly', false);
					});
					return e;
				case TRef(name):
					{
						var sdat = editor.base.getSheet(name);
						if( sdat == null ) return new Element("<p>No sheet data found</p>");

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

						elts.unshift({
							id : null,
							ico : null,
							text : "None",
						});

						function makeIcon(c: hide.comp.Dropdown.Choice) {
							if (sdat.props.displayIcon == null)
								return null;
							if (c.ico == null)
								return new Element("<div style='display:inline-block;width:16px'/>");
							return new Element(tileHtml(c.ico, true).str);
						}

						var html = new Element('
						<select name="ref">
							${ [for(idx in 0...elts.length) '<option value="${idx}" ${elts[idx].text == value ? "selected":""}>${elts[idx].text}</option>'].join('') }
						</select>');
						return html;
					}
				case TCustom(name):
					{
						var valueHtml = this.valueHtml(column, value, line.table.getRealSheet(), ctValue, []);
						var display = '<span class="error">#NULL</span>';

						if (valueHtml != null && valueHtml.str != "")
							display = valueHtml.str;

						var html = new Element('<div tabindex="0" class="sub-cdb-type"><p>${display}</p></div>').css("min-width","80px").css("background-color","#222222");
						html.on("click", function(e) {
							// When opening one custom type, close others of the same level
							content.find(".cdb-type-string").trigger("click");

							editCustomType(name, value, column, html, content.width() - html.position().left - html.width(), 25, depth + 1);
						});

						return html;
					}
				default:
					return new Element('<p>Not supported</p>');
			}
		}

		var d = content.find("#dropdown-custom-type");
		d.find("option").eq(ctValue == null || ctValue.length == 0 ? 0 : Std.int(ctValue[0] + 1)).attr("selected", "true");

		var paramsContent = content.find("#parameters");

		function buildParameters() {
			paramsContent.empty();
			var val = d.val();
			var selected = val != null ? customType.cases[content.find("#dropdown-custom-type").val()] : null;

			if (selected != null && selected.args.length > 0) {
				for (idx in 0...selected.args.length) {
					new Element('<p>&nbsp${selected.args[idx].name}&nbsp:</p>').appendTo(paramsContent);
					var v = ctValue != null ? ctValue[idx + 1] : null;
					if (v == null && selected.args[idx].type.match(TCustom(_))) {
						ctValue[idx + 1] = [];
						v = ctValue[idx + 1];
					}

					getHtml(v, selected.args[idx]).addClass("value").appendTo(paramsContent);

					if (idx != selected.args.length - 1)
						new Element('<p>,&nbsp</p>').appendTo(paramsContent);
				}
			}

			if (rightAnchor > 0)
				content.css("right", '${depth == 0 ? rightAnchor - content.width() / 2.0 : rightAnchor}px');
		}

		function closeCdbTypeEdit(applyModifications : Bool = true) {
			// Close children cdb types editor before closing this one
			var children = content.children().find(".cdb-type-string");
			if (children.length > 0)
				children.first().trigger("click");

			var newCtValue : Array<Dynamic> = null;

			var selected = d.val() != null ? customType.cases[d.val()] : null;
			if (selected != null) {
				newCtValue = [];
				newCtValue.push(Std.int(d.val()));

				if (selected.args != null && selected.args.length > 0) {
					var paramsValues = paramsContent.find(".value");
					for (idx in 0...selected.args.length) {
						var paramValue = paramsValues.eq(idx);

						if (paramValue.is("input[type=checkbox]")) {
							var v = paramValue.is(':checked');
							newCtValue.push(v);
						}
						else if (paramValue.is("input[type=number]"))
							newCtValue.push(Std.parseFloat(paramValue.val()));
						else if (paramValue.is("select")) {
							var sel = paramValue.find(":selected");
							if (sel.val() != 0)
								newCtValue.push(sel.text());
							else
								newCtValue.push("");
						}
						else if (paramValue.is("div")) {
							// Case where the param value is another cdbType
							var v = ctValue[idx + 1] != null && ctValue[idx + 1].length > 0 ? ctValue[idx + 1] : null;
							newCtValue.push(v);
						}
						else
							newCtValue.push(paramsValues.eq(idx).val());
					}
				}
			}

			parentEl.empty();

			if (newCtValue != null) {
				if (ctValue == null) ctValue = [];
				for (idx in 0...ctValue.length) ctValue.pop();
				for (idx in 0...newCtValue.length) {
					var u = newCtValue[idx];
					ctValue.push(newCtValue[idx]);
				}
			}

			if (ctValue.length == 0)
				ctValue = null;

			if (depth == 0) {
				this.setValue(ctValue);
				this.closeEdit();
				this.focus();
			}
			else {
				var htmlValue = valueHtml(col, ctValue, line.table.getRealSheet(), currentValue, []);
				new Element('<p>${htmlValue.str}</p>').appendTo(parentEl);
				parentEl.focus();
			}
		}

		buildParameters();

		d.on("change", function(e) {
			if (ctValue == null) ctValue = [];
			for (idx in 0...ctValue.length) ctValue.pop();

			var selected = d.val() == 0 ? null : customType.cases[d.val()];
			if (selected != null) {
				ctValue.push(d.val());
				for (idx in 0...selected.args.length) {
					switch (selected.args[idx].type) {
						case TId, TString, TRef(_):
							ctValue.push('');
						case TBool:
							ctValue.push(false);
						case TInt, TFloat:
							ctValue.push(0);
						case TCustom(_), TList, TEnum(_):
							ctValue.push([]);
						default:
							ctValue.push(null);
					}
				}
			}
			var t = this.currentValue;
			buildParameters();
		});

		d.focus();

		// Prevent missclick to actually close the edit mode and
		// open another one
		rootEl.on("click", function(e, applyModifications) { closeCdbTypeEdit(applyModifications == null); e.stopPropagation(); });
		content.on("click", function(e) { e.stopPropagation(); });
		content.on("dblclick", function(e) { e.stopPropagation(); });

		if (topAnchor > 0)
			content.css("top", '${topAnchor}px');
	}
}
