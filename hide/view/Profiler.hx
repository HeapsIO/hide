package hide.view;

typedef LineData = {
	count : Int,
	size : Int,
	tid : Array<Int>,
	name : String,
}

typedef Path = {
	v: Int,
	children: Array<Path>,
	line: LineData,
	total : {count: Int, mem: Int},
};

enum DumpViewerPage {
	None;
	Stats;
	Dump;
}

enum SortType {
	ByMemory;
	ByCount;
}

enum Filter {
	None;
	Unique;			// Blocks only present in current memory
	Difference;		// Blocks only present in other memory
	Intersected; 	// Blocks present in both memories
}

class Profiler extends hide.ui.View<{}> {

	var tabContents : Array<Element>;
	var editor : hide.comp.cdb.Editor;
	var currentSheet : String;
	var tabCache : String;
	var tabs : hide.comp.Tabs;
	var view : cdb.DiffFile.ConfigView;

	public var mainMemory : hide.tools.memory.Memory = null;
	public var currentMemory : hide.tools.memory.Memory = null;
	public var names(default, null) : Array<String> = [];

	public var lines(default, null) : Array<LineData> = [];
	public var locationData(default, null) : Map<String, Array<LineData>> = [];

	var error : String = "";

	// Params
	var sort : SortType = ByCount;
	var sortOrderAscending = true;
	var currentFilter : Filter = None;
	var hlPath = "";
	var dumpPaths : Array<String> = [];

	// Cached values
	var statsObj : Array<Dynamic> = [];
	var fileSelects : Array<hide.comp.FileSelect> = [];

	public function new( ?state ) {
		super(state);
	}

	override function onDisplay() {
		new Element('
		<div class="profiler">
			<div class="left-panel"></div>
			<div class="right-panel">
				<div class="title">Files input</div>
				<div class="files-input">
					<div class="drop-zone hidden">
						<p class="icon">+</p>
						<p class="label">Drop .hl and .dump files here</p>
					</div>
					<div class="inputs">
						<dl>
							<dt>HL file</dt><dd><input class="hl-fileselect" type="fileselect" extensions="hl"/></dd>
							<dt>Dump files</dt><dd><input class="dump-fileselect" type="fileselect" extension="dump"/></dd>
							<dt></dt><dd><input class="dump-fileselect" type="fileselect" extension="dump"/></dd>
						</dl>
						<input type="button" value="Process Files" id="process-btn"/>
					</div>
				</div>
				<div class="filters">
				</div>
			</div>
		</div>'
		).appendTo(element);

		var hlSelect = new hide.comp.FileSelect(["hl"], null, element.find(".hl-fileselect"));
		hlSelect.onChange = function() { hlPath = Ide.inst.getPath(hlSelect.path); };

		for (el in element.find(".dump-fileselect")) {
			var dumpSelect = new hide.comp.FileSelect(["dump"], null, new Element(el));
			fileSelects.push(dumpSelect);

			dumpSelect.onChange = function() {
				dumpPaths = [];
				for (fs in fileSelects) {
					if (fs.path != null && fs.path != "")
						dumpPaths.push(Ide.inst.getPath(fs.path));
				}
			};
		}

		var dropZone = element.find(".drop-zone");
		dropZone.css({display:'none'});

		var inputs = element.find(".inputs");
		inputs.css({display:'block'});

		var isDragging = false;
		var wait = false;
		var fileInput = element.find(".files-input");
		fileInput.on('dragenter', function(e) {
			var dt : js.html.DataTransfer = e.originalEvent.dataTransfer;
			if (!wait && !isDragging && dt.files != null && dt.files.length > 0) {
				dropZone.css({display:'block'});
				inputs.css({display:'none'});
				dropZone.css({animation:'zoomIn .25s'});
				isDragging = true;
				wait = true;
				haxe.Timer.delay(function() wait = false, 500);
			}
		});

		fileInput.on('drop', function(e) {
			var dt : js.html.DataTransfer = e.originalEvent.dataTransfer;
			if (dt.files != null && dt.files.length > 0) {
				dropZone.css({display:'none'});
				inputs.css({display:'block'});
				isDragging = false;

				var tmpDumpPaths = [];
				for (f in dt.files) {
					var arrSplit = Reflect.getProperty(f, "name").split('.');
					var ext = arrSplit[arrSplit.length - 1];
					var p = Reflect.getProperty(f, "path");
					p = StringTools.replace(p, "\\", "/");

					if (ext == "hl") {
						hlPath = p;
						hlSelect.path = p;
						continue;
					}

					if (ext == "dump") {
						tmpDumpPaths.push(p);
						continue;
					}

					Ide.inst.error('File ${p} is not supported, please provide .dump file or .hl file');
				}

				if (tmpDumpPaths.length > 0) dumpPaths = [];
				for (idx => p in tmpDumpPaths) {
					dumpPaths.push(p);

					if (idx < fileSelects.length)
						fileSelects[idx].path = p;
				}
			}
		});

		fileInput.on('dragleave', function(e) {
			if (!wait && isDragging) {
				dropZone.css({display:'none'});
				inputs.css({display:'block'});
				isDragging = false;
				wait = true;
				haxe.Timer.delay(function() wait = false, 500);
			}
		});

		var processBtn = element.find("#process-btn");
		processBtn.on('click', function() {
			if (hlPath == null || hlPath == '' || dumpPaths == null || dumpPaths.length <= 0) {
				Ide.inst.quickMessage('.hl or/and .dump files are missing. Please provide both files before hit the process button');
				return;
			}

			clear();
			load();
			refresh();
		});

		refreshFilters();
	}

	override function getTitle() {
		return "Memory profiler";
	}

	function load() {
		names = dumpPaths;

		var result = loadAll();
		if ( result != null) {
			error = result;
		} else {
			error = "";
			if (names.length > 0) {
				this.currentFilter = None;
				displayTypes(sort, sortOrderAscending);
				statsObj = mainMemory?.getStatsObj();
			}
		}
	}

	function loadAll() @:privateAccess{
		if (names.length < 1) return null;
		for (i in 0...names.length) {
			var newMem = new hide.tools.memory.Memory();
			try {
				if (i == 0) { // setup main Memory
					newMem.loadBytecode(hlPath);
					currentMemory = mainMemory = newMem;
				} else {
					mainMemory.otherMems.push(newMem);
					newMem.code = mainMemory.code;
				}

				newMem.otherMems = [];
				newMem.loadMemory(names[i]);
				newMem.check();
			} catch(e) {
				names.remove(names[i]);
				if (names.length < 1)
					mainMemory = currentMemory = null;

				return e.toString();
			}
		}

		mainMemory.setFilterMode(None);
		for (mem in mainMemory.otherMems)
			mem.setFilterMode(None);

		return null;
	}

	function clear() {
		mainMemory = currentMemory = null;
		lines = [];
		locationData.clear();
		statsObj = null;
	}

	public function displayTypes(sort : SortType = ByCount, asc : Bool = true) @:privateAccess{
		if (currentMemory == null) throw "memory not loaded";

		lines = [];

		var ctx = new hide.tools.memory.Memory.Stats(currentMemory);
		for ( b in currentMemory.filteredBlocks)
			ctx.add(b.type, b.size);

		ctx.sort(sort == ByCount, asc);

		for (i in ctx.allT){
			lines.push({count : i.count, size : i.mem, tid : i.tl, name : getNameString(i.tl)});
		}
	}

	public function getNameString(tid : Array<Int>) {
		var path = hide.tools.memory.Memory.Stats.getPathStrings(mainMemory, tid);
		return path[path.length-1];
	}

	public function getPathString(tid : Array<Int>) {
		return hide.tools.memory.Memory.Stats.getPathStrings(currentMemory, tid).join(" > ");
	}

	public function refresh() {
		refreshStats();
		refreshFilters();
		refreshHierarchicalView();
	}

	public function refreshFilters() {
		var filters = element.find('.filters');
		filters.empty();

		var fileNames = [];
		for (p in dumpPaths) {
			var arr = p.split('/');
			fileNames.push(arr[arr.length - 1]);
		}

		new Element('
			<div class="title">Filters</div>
			<dt>Filter</dt><dd>
				<select class="dd-filters">
					<option value="0">None</option>
					<option value="1">Show ${fileNames[0]}</option>
					<option value="2">Show ${fileNames[1]}</option>
					<option value="3">Intersected</option>
				</select>
			</dd>
		').appendTo(filters);

		var ddFilters = filters.find('.dd-filters');
		ddFilters.on('change', function(e) {
			var enumVal = Filter.None;
			var val : Int = Std.parseInt(ddFilters.val());
			switch (val) {
				case 0: enumVal = Filter.None;
				case 1: enumVal = Filter.Unique;
				case 2: enumVal = Filter.Difference;
				case 3: enumVal = Filter.Intersected;
			}

			this.filterDatas(enumVal);
		});

		if (dumpPaths.length >= 2)
			filters.css({ display:'block' });
		else
			filters.css({ display:'none' });
	}

	public function refreshStats() {
		element.find('.stats').remove();

		var stats = new Element ('<div class="stats"><div class="title">Stats</div></div>').appendTo(element.find('.right-panel'));
		for (idx => s in statsObj) {
			new Element('
			<h4>Memory usage</h4>
			<h5>${s.memFile}</h5>
			<div class="outer-gauge"><div class="inner-gauge" title="${hide.tools.memory.Memory.MB(s.used)} used (${ 100 * s.used / s.totalAllocated}% of total)" style="width:${ 100 * s.used / s.totalAllocated}%;"></div></div>
			<dl>
				<dt>Allocated</dt><dd>${hide.tools.memory.Memory.MB(s.totalAllocated)}</dd>
				<dt>Used</dt><dd>${hide.tools.memory.Memory.MB(s.used)}</dd>
				<dt>Free</dt><dd>${hide.tools.memory.Memory.MB(s.free)}</dd>
				<dt>GC</dt><dd>${hide.tools.memory.Memory.MB(s.gc)}</dd>
				<dt>&nbsp</dt><dd></dd>
				<dt>Pages</dt><dd>${s.pagesCount} (${hide.tools.memory.Memory.MB(s.pagesSize)})</dd>
				<dt>Roots</dt><dd>${s.rootsCount}</dd>
				<dt>Stacks</dt><dd>${s.stackCount}</dd>
				<dt>Types</dt><dd>${s.typesCount}</dd>
				<dt>Closures</dt><dd>${s.closuresCount}</dd>
				<dt>Live blocks</dt><dd>${s.blockCount}</dd>
			</dl>
			${idx < statsObj.length - 1 ? '<hr class="solid"></hr>' : ''}
			').appendTo(stats);
		}
	}

	public function refreshHierarchicalView() {
		element.find('table').parent().remove();
		var tab = new Element('
		<div class="hide-scroll">
			<table rules=none>
				<thead>
					<td class="sort-count">Count<div ${sort.match(SortType.ByCount) ? 'class="icon ico ico-caret-${sortOrderAscending ? 'up' : 'down'}"' : ''}></div></td>
					<td class="sort-size">Size<div ${sort.match(SortType.ByMemory) ? 'class="icon ico ico-caret-${sortOrderAscending ? 'up' : 'down'}"' : ''}></div></td>
					<td>Name</td>
					<td class="sort-size">% Impact<div ${sort.match(SortType.ByMemory) ? 'class="icon ico ico-caret-${sortOrderAscending ? 'up' : 'down'}"' : ''}></div></td>
				</thead>
				<tbody>
				</tbody>
			</table>
		</div>'
		).appendTo(element.find(".left-panel"));

		tab.find('.sort-count').on('click', function(e) { sortDatas(SortType.ByCount, sort.match(SortType.ByCount) ? !sortOrderAscending : false); });
		tab.find('.sort-size').on('click', function(e) { sortDatas(SortType.ByMemory, sort.match(SortType.ByMemory) ? !sortOrderAscending : false); });
		tab.on('keydown', function(e) e.preventDefault());

		var body = tab.find('tbody');
		for (idx => l in lines) {
			var pe = new ProfilerElement(this, l, null, null);
			pe.element.appendTo(body);

			if (idx == 0)
				pe.element.focus();
		}
	}

	public function locate(str : String) @:privateAccess {
		var datas = [];
		if (str == "null" || locationData.exists(str)) return;

		var ctx = currentMemory.getLocate(str, 30);
		ctx.sort();
		for (i in ctx.allT)
			datas.push({count : i.count, size : i.mem, tid : i.tl, name : null, state: Unique});

		locationData.set(str, datas);
	}

	public function getChildren(depth : Int, parent : Int, valid : Array<LineData>) : Array<Path> {
		var valid = valid.filter(p ->  {
			var isCurrentPath = depth <= 0 || p.tid[depth-1] == parent;
			return p.tid.length > depth && isCurrentPath;
		});

		var children : Array<Dynamic> = [];
		for (path in valid) {
			if (parent == -1 || path.tid[depth - 1] == parent) {
				var copy = children.filter((c) -> c.p == path.tid[depth]);
				if (copy.length == 0) {
					children.push({p : path.tid[depth],
						count : path.count, size : path.size,
						line : depth == path.tid.length - 1 ? path : null});
				} else {
					copy[0].count += path.count;
					copy[0].size += path.size;
				}
			}

		}

		children.sort((a, b) -> b.count - a.count);
		return children.map(c -> {v : c.p, children : getChildren(depth+1, c.p, valid), line : c.line, total : {count : c.count, mem : c.size}});
	}

	public function sortDatas(sort: SortType, isAscending : Bool) {
		this.sort = sort;
		this.sortOrderAscending = isAscending;

		if (mainMemory == null) return;

		displayTypes(sort, isAscending);
		refreshHierarchicalView();
	}

	public function filterDatas(filter: Filter) @:privateAccess{
		this.currentFilter = filter;

		switch (currentFilter) {
			case None :
				currentMemory = mainMemory;
				mainMemory.setFilterMode(None);
			case Unique :
				currentMemory = mainMemory;
				mainMemory.setFilterMode(Unique);
			case Difference :
				mainMemory.setFilterMode(None);
				if (mainMemory.otherMems.length > 0){
					var other = mainMemory.otherMems[0];
					other.otherMems = [mainMemory];
					other.setFilterMode(Unique);
					other.otherMems = [];
					currentMemory = other;
				}
			case Intersected :
				var other = mainMemory.otherMems[0];
				other.setFilterMode(None);
				currentMemory = mainMemory;
				mainMemory.setFilterMode(Intersect);
			default:
				currentMemory = mainMemory;
				mainMemory.setFilterMode(None);
		}

		locationData.clear();

		displayTypes(sort, sortOrderAscending);
		statsObj = mainMemory?.getStatsObj();

		refreshHierarchicalView();
	}

	static var _ = hide.ui.View.register(Profiler);

}

class ProfilerElement extends hide.comp.Component{
	public var profiler : Profiler;
	public var line : LineData;
	public var path : Path;
	public var parent : ProfilerElement;
	public var depth : Int = 0;
	public var isOpen = false;

	// Cached values
	var foldBtn : Element;
	var children : Array<ProfilerElement> = null;

	public function new(profiler : Profiler, line: LineData, path : Path, parent : ProfilerElement = null) @:privateAccess {
        super(null, null);

		this.profiler = profiler;
		this.line = line;
		this.path = path;
		this.parent = parent;
		this.depth = parent != null ? parent.depth + 1 : 0;

		var name = path == null ? line.name : hide.tools.memory.Memory.Stats.getTypeString(profiler.currentMemory, path.v);
		var count = path == null ? line.count : path.total.count;
		var mem = path == null ? line.size : path.total.mem;

		this.element = new Element('<tr tabindex="2"><td><div class="folder icon ico ico-caret-right"></div>${count}</td><td>${hide.tools.memory.Memory.MB(mem)}</td><td title="${name}">${name}</td><td><div title="Allocated ${mem} (${100 * mem / Reflect.getProperty(profiler.statsObj[0], "totalAllocated")}% of total)" class="outer-gauge"><div class="inner-gauge" style="width:${100 * mem / Reflect.getProperty(profiler.statsObj[0], "totalAllocated")}%;"></div></div></td></tr>');
		this.element.find('td').first().css({'padding-left':'${10 * depth}px'});

		this.foldBtn = this.element.find('.folder');

		// Build children profiler
		if (this.path != null) {
			for (p in this.path.children??[]) {
				if (children == null)
					children = [];

				var pe = new ProfilerElement(this.profiler, null, p, this);

				if (pe.children == null) {
					pe.foldBtn.css({ opacity : 0 });
					pe.foldBtn.off();
				}

				children.push(pe);
			}
		}

		// Manage line folding / unfolding to show / unshow details
		foldBtn.on('click', function(e) {
			if (!isOpen) {
				this.open();
			}
			else {
				this.close();
			}
		});

		this.element.on('keydown', function(e) {

			function selectUp() {
				if (this.element.prev('tr').length > 0)
					this.element.prev('tr').first().focus();
				else
					this.element.parent('tr').focus();
			}

			function selectDown() {
				if (this.element.children('tr').length > 0)
					this.element.children('tr').first().focus();
				else
					this.element.next('tr').focus();
			}

			switch( e.keyCode ) {
				case hxd.Key.LEFT:
					if (this.isOpen)
						this.close();
				case hxd.Key.RIGHT:
					if (this.isOpen) {
						selectDown();
					}
					else {
						open();
					}
				case hxd.Key.DOWN:
					selectDown();
				case hxd.Key.UP:
					selectUp();
				default:
			}

			e.stopPropagation();
			e.preventDefault();
		});
    }

	public function open() {
		this.isOpen = true;
		this.foldBtn.removeClass('ico-caret-right').addClass('ico-caret-down');

		// Only root nodes without children will generate their children
		if (children == null && parent == null) {
			var d = profiler.locationData.get(line.name);
			if (d == null) {
				profiler.locate(line.name);
				d = profiler.locationData.get(line.name);
			}

			var pathData = profiler.getChildren(depth, path != null ? path.v : -1, d);

			if (this.children == null)
				this.children = [];

			for (p in pathData) {
				var pe = new ProfilerElement(this.profiler, null, p, this);
				this.children.push(pe);
				pe.element.insertAfter(this.element);
			}
		}

		for (c in children??[]) {
			c.element.insertAfter(this.element);
		}
	}

	public function close() {
		this.isOpen = false;
		this.foldBtn.removeClass('ico-caret-down').addClass('ico-caret-right');

		for (c in children??[]) {
			c.close();
			c.element.detach();
		}
	}
}
