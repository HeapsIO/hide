package hide.comp.cdb;

typedef LineData = {
	originalObj : Dynamic,
	originalIndex : Dynamic,
	originalId : Dynamic,
	originalArr : Array<Dynamic>
}

class SheetView {

	static var changed : Bool;
	static var skip : Int = 0;
	static var watching : Map<String, Bool> = new Map();

	#if (editor || cdb_datafiles)
	static var base(get,never) : cdb.Database;
	static function get_base() return Ide.inst.database;
	#else
	public static var base : cdb.Database;
	#end

	public static function loadSheet(sheet : cdb.Sheet) @:privateAccess {
		var v = hide.comp.cdb.Editor.getSheetProps(sheet).view;
		var originalSheet = base.getSheet(v.originalSheet);

		loadColumns(originalSheet, sheet);

		if (originalSheet.sheet.lines != null) sheet.sheet.lines = [];
		sheet.sheet.linesData = [];

		// Copy separators that has been picked for the view (and their lines)
		sheet.sheet.separators = [];
		for (sIdx in hide.comp.cdb.Editor.getSheetProps(sheet).view.sepIndexes) {
			var sep = originalSheet.sheet.separators[sIdx];
			var newSep = Reflect.copy(sep);
			newSep.index = sheet.lines.length;
			sheet.sheet.separators.push(newSep);

			// Get the lines that are in this separator
			for (idx in sep.index...(sIdx == originalSheet.separators.length - 1 ? originalSheet.sheet.lines.length : originalSheet.separators[sIdx + 1].index)) {
				var newLine = sheet.newLine();
				var newLineData : LineData = {
					originalObj: originalSheet.sheet.lines[idx],
					originalIndex: idx,
					originalId: getLineId(originalSheet, originalSheet.sheet.lines[idx]),
					originalArr: null
				};

				sheet.sheet.linesData.push(newLineData);
				loadLine(originalSheet.name, newLine, newLineData);
			}
		}
 	}

	public static function unloadSheet(sheet : cdb.Sheet) @:privateAccess {
		while(sheet.lines.length > 0)
			sheet.deleteLine(sheet.lines.length - 1);

		if (sheet.sheet.linesData != null)
			sheet.sheet.linesData = [];

		if (sheet.sheet.separators != null)
			sheet.sheet.separators = [];

		var idx = sheet.columns.length - 1;
		while (idx >= 0) {
			sheet.deleteColumn(sheet.columns[idx].name);
			idx--;
		}
	}

	public static function reloadSheet(sheet : cdb.Sheet) {
		var rootSheet = getRootSheet(sheet);
		if (Editor.getSheetProps(rootSheet).view == null)
			return;

		unloadSheet(rootSheet);
		loadSheet(rootSheet);
	}

	public static function getOriginalSheet(sheet : cdb.Sheet) {
		var rootSheet = getRootSheet(sheet);
		if (Editor.getSheetProps(rootSheet).view == null)
			return sheet;

		return base.getSheet(StringTools.replace(sheet.name, rootSheet.name, Editor.getSheetProps(rootSheet).view.originalSheet));
	}

	public static function isView(sheet : cdb.Sheet) {
		return SheetView.getOriginalSheet(sheet) != sheet;
	}

	/* Lines modifications */
	public static function insertLine(editor : hide.comp.cdb.Editor, ?line : Line, ?table : Table) : Dynamic {
		var newLine = null;
		var table = line != null ? line.table : table;
		if( table == null || !table.canInsert() )
			return null;

		editor.beginChanges();
		var originalSheet = getOriginalSheet(table.sheet);
		var arr : Array<Dynamic> = SheetView.getOriginalArr(line, table);
		if (arr != null) {
			var newLine = {};
			for( c in @:privateAccess originalSheet.sheet.columns ) {
				var d = base.getDefault(c, originalSheet);

				if (d != null)
					Reflect.setField(newLine, c.name, d);
			}

			arr.insert(line != null ? line.index + 1 : 0, newLine);
		}
		else if (line != null) {
			newLine = originalSheet.newLine(getOriginalIndex(line));
		}
		else {
			newLine = originalSheet.newLine(0);
		}

		editor.endChanges();
		editor.refresh();
		table.refresh();
		return newLine;
	}

	public static function deleteLine(editor : hide.comp.cdb.Editor, line : Line) {
		var originalSheet = SheetView.getOriginalSheet(line.table.sheet);
		var id = getOriginalId(line);
		if( id != null && id.length > 0) {
			var refs = editor.getReferences(id, originalSheet);
			if( refs.length > 0 ) {
				var message = [for (r in refs) r.str].join("\n");
				if( !Ide.inst.confirm('$id is referenced elswhere. Are you sure you want to delete?\n$message') )
					return;
			}
		}

		editor.beginChanges();
		// If originalArr is not null, it means that we're deleting a line from a sub sheet
		var arr : Array<Dynamic> = getOriginalArr(line);
		if (arr != null)
			arr.remove(arr[line.index]);
		else
			originalSheet.deleteLine(getOriginalIndex(line));
		editor.endChanges();
		editor.refresh();
	}

	public static function duplicateLine(editor : hide.comp.cdb.Editor, line : Line) {
		if( !line.table.canInsert() || line.table.displayMode != Table )
			return;

		var arr : Array<Dynamic> = getOriginalArr(line);
		var originalSheet = getOriginalSheet(line.table.sheet);
		var srcObj = getOriginalObject(line);
		editor.beginChanges();
		var obj = arr != null ? {} : originalSheet.newLine(getOriginalIndex(line));
		for(colId => c in line.table.columns ) {
			var val = Reflect.field(srcObj, c.name);
			if( val != null ) {
				if( c.type != TId ) {
					// Deep copy
					Reflect.setField(obj, c.name, haxe.Json.parse(haxe.Json.stringify(val)));
				} else {
					// Increment the number at the end of the id if there is one

					var newId = editor.getNewUniqueId(val, line.table, c);
					if (newId != null) {
						Reflect.setField(obj, c.name, newId);
					}
				}
			}
		}

		if (arr != null)
			arr.insert(line.index + 1, obj);

		editor.endChanges();
		editor.refresh();
		line.table.refresh();
		line.table.getRealSheet().sync();
	}

	public static function moveLine(editor : hide.comp.cdb.Editor, line : Line, delta : Int, exact : Bool = false) {
		if( !line.table.canInsert() )
			return;

		editor.beginChanges();
		var originalSheet = SheetView.getOriginalSheet(line.table.sheet);
		var prevIndex = getOriginalIndex(line);

		var index : Null<Int> = null;
		var currIndex : Null<Int> = getOriginalIndex(line);

		var arr : Array<Dynamic> = getOriginalArr(line);
		if (arr != null) {
			var newIndex = currIndex + delta;
			if (newIndex < 0 || newIndex >= arr.length)
				throw "Moving lines into another group isn't supported in views yet.";
		}

		if (!exact) {
			var distance = (delta >= 0 ? delta : -1 * delta);
			for( _ in 0...distance ) {
				if (arr != null) {
					var tmp = arr[currIndex + delta];
					arr[currIndex + delta] = arr[currIndex];
					arr[currIndex] = tmp;
					currIndex = currIndex + delta;

					if (currIndex < 0 || currIndex >= arr.length)
						break;
				}
				else
					currIndex = originalSheet.moveLine( currIndex, delta );
				if( currIndex == null )
					break;
				else
					index = currIndex;
			}
		}
		else {
			while (index != prevIndex + delta) {
				if (arr != null) {
					var tmp = arr[currIndex + delta];
					arr[currIndex + delta] = arr[currIndex];
					arr[currIndex] = tmp;
					currIndex = currIndex + delta;

					if (currIndex < 0 || currIndex >= arr.length)
						break;
				}
				else
					currIndex = originalSheet.moveLine( currIndex, delta );
				if( currIndex == null )
					break;
				else
					index = currIndex;
			}
		}

		if( index != null ) {
			if (index != prevIndex) {
				if ( editor.cursor.y == prevIndex ) editor.cursor.set(editor.cursor.table, editor.cursor.x, index);
				else if ( editor.cursor.y > prevIndex && editor.cursor.y <= index) editor.cursor.set(editor.cursor.table, editor.cursor.x, editor.cursor.y - 1);
				else if ( editor.cursor.y < prevIndex && editor.cursor.y >= index) editor.cursor.set(editor.cursor.table, editor.cursor.x, editor.cursor.y + 1);
			}

			editor.refresh();
		}

		editor.endChanges();
		editor.refresh();
	}


	public static function getOriginalObject(?line : Line, ?table : Table) {
		var sheet = line != null ? line.table.sheet : table.sheet;
		var path = @:privateAccess sheet.path;

		if (path == null)
			return @:privateAccess sheet.sheet.linesData[line.index].originalObj;

		var arrRealPath = path.split('@');
		var originalObj : Dynamic = @:privateAccess SheetView.getRootSheet(sheet).sheet.linesData[getRootLineIndex(line, table)].originalObj;

		for (pIdx => p in arrRealPath) {
			if (pIdx == 0)
				continue;

			var field = p.split(':')[0];
			var index = Std.parseInt(p.split(':')[1]);

			originalObj = Reflect.field(originalObj is Array ? originalObj[index] : originalObj, field);
		}

		return originalObj is Array ? originalObj[line.index] : originalObj;
	}

	public static function getOriginalIndex(line : Line) {
		var sheet = line.table.sheet;
		var path = @:privateAccess sheet.path;

		if (path == null)
			return @:privateAccess sheet.sheet.linesData[line.index].originalIndex;

		return line.index;
	}

	public static function getRootLineIndex(?line : Line, ?table : Table) {
		var sheet = line != null ? line.table.sheet : table.sheet;
		var path = @:privateAccess sheet.path;

		if (path != null) {
			var idx = path.indexOf(':');
			var nextSub = path.indexOf('@', idx + 1);
			var nextSubIdx = path.indexOf(':', idx + 1);
			var next = (nextSub == -1 && nextSubIdx == -1) ? 1000 : (nextSub < nextSubIdx && nextSub != -1) ? nextSub : nextSubIdx;

			return Std.parseInt(path.substr(idx + 1, next));
		}

		return line.index;
	}

	public static function getOriginalId(line : Line) {
		var sheet = line.table.sheet;
		var path = @:privateAccess sheet.path;

		if (path == null)
			return @:privateAccess sheet.sheet.linesData[line.index].originalId;

		var splittedPath = (path.split(':'));
		if (splittedPath.length > 1) {
			var idx = Std.parseInt(splittedPath.pop());
			var originalId : Dynamic = @:privateAccess SheetView.getRootSheet(sheet).sheet.linesData[idx].originalId;

			for (elIdx => el in splittedPath.join("").split('@')) {
				if (elIdx == 0)
					continue;

				originalId = Reflect.field(originalId, el);
			}

			return originalId;
		}

		throw "Not implemented exception";
	}

	public static function getOriginalArr(?line : Line, ?table : Table) {
		var sheet = line != null ? line.table.sheet : table.sheet;
		var path = @:privateAccess sheet.path;

		var arrRealPath = path.split('@');
		var originalObj : Dynamic = @:privateAccess SheetView.getRootSheet(sheet).sheet.linesData[getRootLineIndex(line, table)].originalObj;
		var nextOriginalObj : Dynamic = null;
		for (pIdx => p in arrRealPath) {
			if (pIdx == 0)
				continue;

			var field = p.split(':')[0];
			var index = Std.parseInt(p.split(':')[1]);

			nextOriginalObj = Reflect.field(originalObj is Array ? originalObj[index] : originalObj, field);

			if (nextOriginalObj != null)
				originalObj = nextOriginalObj
			else {
				nextOriginalObj = [];
				Reflect.setField(originalObj is Array ? originalObj[index] : originalObj, field, nextOriginalObj);
				originalObj = nextOriginalObj;
			}
		}

		return originalObj;
	}


	public function moveLines(editor : hide.comp.cdb.Editor, lines : Array<Line>, delta : Int) {
		if( lines.length == 0 || !lines[0].table.canInsert() || delta == 0 )
			return;

		var selDiff: Null<Int> = editor.cursor.select == null ? null : editor.cursor.select.y - editor.cursor.y;
		editor.beginChanges();
		lines.sort((a, b) -> { return (a.index - b.index) * delta * -1; });
		for( l in lines ) {
			moveLine(editor, l, delta);
		}
		if (selDiff != null && hxd.Math.iabs(selDiff) == lines.length - 1)
			editor.cursor.set(editor.cursor.table, editor.cursor.x, editor.cursor.y, {x: editor.cursor.x, y: editor.cursor.y + selDiff});
		editor.endChanges();
	}

	static function getRootSheet(sheet : cdb.Sheet) {
		var rootSheet = sheet;
		while (rootSheet.parent != null)
			rootSheet = rootSheet.parent.sheet;

		return base.getSheet(rootSheet.name.split("@")[0]);
	}

	static function loadColumns(originalSheet : cdb.Sheet, sheet : cdb.Sheet) {
		for (c in originalSheet.columns) {
			var newCol = Reflect.copy(c);
			sheet.addColumn(newCol);

			if (c.type.match(cdb.Data.ColumnType.TProperties) || c.type.match(cdb.Data.ColumnType.TList)) {
				loadColumns(originalSheet.getSub(c), sheet.getSub(c));
			}
		}
	}

	static function loadLine(name : String, object : Dynamic, objectData : Dynamic) @:privateAccess {
		var originalSheet = base.getSheet(name);
		var addedField = false;

		for (c in originalSheet.sheet.columns) {
			var hasField = Reflect.hasField(objectData.originalObj, c.name);
			var v = Reflect.field(objectData.originalObj, c.name);

			var sub = originalSheet.getSub(c);
			if (sub != null && hasField && c.type.match(cdb.Data.ColumnType.TProperties)) {
				var vCopy = {};
				var vData = {
					originalObj: v,
					originalIndex: objectData.originalIndex,
					originalId: objectData.originalId,
					originalArr: null
				};

				loadLine(sub.name, vCopy, vData);

				if (vCopy != null) {
					Reflect.setField(object, c.name, vCopy);
					addedField = true;
				}

				continue;
			}

			if (hasField && sub != null && c.type.match(cdb.Data.ColumnType.TList)) {
				var vCopy = [];

				for (idx in 0...v.length) {
					var elCopy = {};
					var elData = {
						originalObj: v[idx],
						originalIndex: idx,
						originalId: getLineId(sub, v[idx]),
						originalArr: vCopy
					};

					loadLine(sub.name, elCopy, elData);
					vCopy.push(elCopy);
				}

				if (vCopy != null) {
					Reflect.setField(object, c.name, vCopy);
					addedField = true;
				}

				continue;
			}

			if (hasField) {
				Reflect.setField(object, c.name, v);
				addedField = true;
			}
		}

		if (!addedField) {
			object = null;
			objectData = null;
		}
	}

	static function getLineId(sheet : cdb.Sheet, line : Dynamic) {
		for( c in sheet.columns ) {
			if( c.type == TId )
				return Reflect.field(line, c.name);
		}

		return null;
	}
}

class SheetViewModal extends Modal {
	var contentModal : Element;
	var editor : Editor;
	var originalSheet : cdb.Sheet;
	var selectedSeparators : Array<Int>;

	public function new( editor : Editor, originalSheet : cdb.Sheet, viewSheet : cdb.Sheet, ?parent,?el) {
		function findParentSepIdx(sepIdx : Int) : Int {
			var idx = sepIdx - 1;
			while (idx > 0) {
				if (this.originalSheet.separators[idx].level == null || this.originalSheet.separators[idx].level < this.originalSheet.separators[sepIdx].level)
					return idx;

				idx--;
			}

			return -1;
		}

		function findChildrenSepIdx(sepIdx : Int) : Array<Int> {
			var children = [];

			if (sepIdx < 0 || sepIdx >= this.originalSheet.separators.length)
				return children;

			for (idx in (sepIdx + 1)...this.originalSheet.separators.length) {
				var s = this.originalSheet.separators[idx];

				if (findParentSepIdx(idx) == sepIdx)
					children.push(idx);
			}

			return children;
		}

		super(parent,el);

		var editForm = viewSheet != null;
		var base = editor.base;
		this.editor = editor;
		this.selectedSeparators = viewSheet != null ? hide.comp.cdb.Editor.getSheetProps(viewSheet).view.sepIndexes.copy() : [];

		this.originalSheet = originalSheet;
		if (originalSheet == null) {
			for (sheet in base.sheets) {
				if (sheet.name == hide.comp.cdb.Editor.getSheetProps(viewSheet).view.originalSheet) {
					this.originalSheet = sheet;
					break;
				}
			}
		}


		contentModal = new Element("<div tabindex='0'>").addClass("content-modal").appendTo(content);

		if (editForm)
			new Element('<h2> Edit view ${viewSheet.name}</h2>').appendTo(contentModal);
		else
			new Element("<h2> Create view </h2>").appendTo(contentModal);
		new Element("<p id='errorModal'></p>").appendTo(contentModal);

		new Element('
		<div class="sheet-view">
			<div id="name"><p>Name</p><input id="view-name"/></div>
			<div>
				<p>Pick separators to include in the view</p>
				<div id="separators-picker"></div>
			</div>
			<div id="buttons">
				<input id="create-btn" type="button" value="${editForm ? "Apply" : "Create"}"/><input id="cancel-btn" type="button" value="Cancel"/>
			</div>
		</div>').appendTo(contentModal);

		if (viewSheet != null)
			contentModal.find("#name").css({ display:"none" });

		var separators = contentModal.find("#separators-picker");
		for (sIdx => s in this.originalSheet.separators) {
			var sepEl = new Element('
			<div class="sep level-${s.level}">
				<input type="checkbox"/>
				<p>${s.title}</p>
			</div>');

			var cb = sepEl.find("input");
			cb.on("change", function(_) {
				var v = cb.prop("checked");

				function pushSep(sIdx : Int) {
					if (selectedSeparators.contains(sIdx))
						return;

					if (this.originalSheet.separators[sIdx].level > 0)
						pushSep(findParentSepIdx(sIdx));

					selectedSeparators.push(sIdx);
				}

				function removeSep(sIdx : Int) {
					if (!selectedSeparators.contains(sIdx))
						return;

					var childrenSepIdx = findChildrenSepIdx(sIdx);
					for (childSepIdx in childrenSepIdx)
						removeSep(childSepIdx);

					selectedSeparators.remove(sIdx);
				}

				// We do not want an orphan separators, so we want to include parent separators on separator add
				// and remove children separator on separator remove
				if (v)
					pushSep(sIdx)
				else
					removeSep(sIdx);

				updateCheckedSeparators();
			});

			separators.append(sepEl);
		}

		if (editForm)
			updateCheckedSeparators();

		element.find("#cancel-btn").click(function(e) { closeModal(); });
	}

	public function updateCheckedSeparators() {
		var sepPicker = element.find("#separators-picker");
		sepPicker.find("input").prop("checked", false);
		sepPicker.find("input").each(function(idx: Int, el : js.html.Element) {
			if (!selectedSeparators.contains(idx))
				return;

			var jEl = new Element(el);
			jEl.prop("checked", true);
		});
	}

	public function getOriginalSheet() {
		return this.originalSheet;
	}

	public function getSheetName() {
		return '${originalSheet.name}(${element.find("#view-name").val()})';
	}

	public function getCheckedSeparators() {
		return selectedSeparators;
	}

	public function setCallback(callback : (Void -> Void)) {
		element.find("#create-btn").click(function(e) {
			e.preventDefault();
			callback();
		});

		contentModal.find("#edit-btn").click(function(e) {
			e.preventDefault();
			callback();
		});
	}

	public function closeModal() {
		content.empty();
		close();
	}

	public function error(str : String) {
		contentModal.find("#errorModal").html(str);
	}
}