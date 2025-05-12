package hide.view;

#if (hashlink >= "1.15.0")
class MemProfiler extends hide.ui.View<{}> {
	public var analyzer : hlmem.Analyzer = null;
	public var hlPath(default, set) : String = null;
	public var dumpPaths(default, set) : Array<String> = [];
	var currentFilter : hlmem.Memory.FilterMode = None;
	public var defaultTableLines : Int = 5;
	public var defaultLocateRoot : Bool = false;
	public var showTid : Bool = false;

	var hlSelect : hide.comp.FileSelect;
	var fileSelects : Array<hide.comp.FileSelect>;
	var statsView : Element;
	var tabsView : Element;
	var searchBar : MemProfilerSearchBar;
	var summaryView : MemProfilerSummaryView;
	var inspectView : MemProfilerInspectView;

	public function new( ?state ) {
		super(state);
	}

	override function onDisplay() {
		new Element('
		<div class="profiler">
			<div class="left-panel">
			</div>
			<div class="right-panel hide-scroll">
				<div class="title">Files input</div>
				<div class="files-input">
					<div class="drop-zone hidden">
						<p class="label">Drop .hl and .dump files here</p>
					</div>
					<div class="inputs">
						<dl>
							<dt>HL file</dt><dd><input class="hl-fileselect" type="fileselect" extensions="hl"/></dd>
							<dt>Dump files</dt><dd>
								<input class="dump-fileselect" type="fileselect" extension="dump"/>
								<input class="dump-fileselect" type="fileselect" extension="dump"/>
							</dd>
						</dl>
						<input type="button" value="Process Files" id="process-btn"/>
					</div>
				</div>
				<div class="info">
				</div>
				<div class="options">
					<dl>
						<dt><label for="mem-filter">Filter</label></dt><dd>
							<select id="mem-filter">
								<option value="0">None</option>
								<option value="1">Unique</option>
								<option value="2">Intersected</option>
							</select>
						</dd>
						<dt><label for="mem-table-size">Display size</label></dt><dd>
							<input type="number" id="mem-table-size" min="0" max="100" value="5"
								title="Default table display size for inspect. 0 for display all lines."
							/>
						</dd>
						<dt><label for="mem-locate-root">Locate root</label></dt><dd>
							<input type="checkbox" id="mem-locate-root"
								title="Auto locate root when inspect, at cost of performance."
							/>
						</dd>
						<dt><label for="mem-show-tid">Show tid</label></dt><dd>
							<input type="checkbox" id="mem-show-tid"
								title="Display tid with type when inspect."
							/>
						</dd>
					</dl>
				</div>
			</div>
		</div>'
		).appendTo(element);

		hlSelect = new hide.comp.FileSelect(["hl"], null, element.find(".hl-fileselect"));
		hlSelect.onChange = function() { hlPath = Ide.inst.getPath(hlSelect.path); };

		fileSelects = [];
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
		processBtn.on('click', function(e) {
			process();
		});

		var filterOpt = element.find("#mem-filter");
		filterOpt.on('change', function(e) {
			var val : Int = Std.parseInt(filterOpt.val());
			var enumVal : hlmem.Memory.FilterMode = switch (val) {
				case 0: None;
				case 1: Unique;
				case 2: Intersect;
				case _:
					trace("Unknown filter mode " + val);
					None;
			}
			this.onFilterChange(enumVal);
		});

		var tableSizeOpt = element.find("#mem-table-size");
		tableSizeOpt.on('change', function(e) {
			var val : Int = Std.parseInt(tableSizeOpt.val());
			if( val < 0 ) val = 0;
			if( val > 100 ) val = 100;
			tableSizeOpt.val(val);
			defaultTableLines = val;
		});

		var locateRootOpt = element.find("#mem-locate-root");
		locateRootOpt.on('change', function(e) {
			defaultLocateRoot = locateRootOpt.is(":checked");
		});

		var showTidOpt = element.find("#mem-show-tid");
		showTidOpt.on('change', function(e) {
			showTid = showTidOpt.is(":checked");
		});

	}

	override function onBeforeClose():Bool {
		clear();
		return super.onBeforeClose();
	}

	override function getTitle() {
		return "Memory profiler";
	}

	public function process() {
		if( hlPath == null || hlPath == '' || dumpPaths == null || dumpPaths.length <= 0 ) {
			Ide.inst.quickMessage('.hl or/and .dump files are missing. Please provide both files before hit the process button');
			return;
		}
		clear();
		load( function(b) {
			if( b )
				refresh();
		});
	}

	function set_hlPath( p : String ) {
		if( hlSelect != null ) {
			hlSelect.path = p;
		}
		return hlPath = p;
	}

	function set_dumpPaths( arr : Array<String> ) {
		if( fileSelects != null ) {
			for( i in 0...fileSelects.length ) {
				fileSelects[i].path = arr[i];
			}
		}
		return dumpPaths = arr;
	}

	function onFilterChange( f : hlmem.Memory.FilterMode ) {
		if( currentFilter == f )
			return;
		currentFilter = f;
		if( analyzer == null || analyzer.getMainMemory() == null )
			return;
		showInfo('Setting filter to ${currentFilter.getName()}...', true);
		haxe.Timer.delay(() -> {
			var mainMemory = analyzer.getMainMemory();
			mainMemory.filterMode = currentFilter;
			mainMemory.buildFilteredBlocks();
			refresh();
			showInfo('Filter set to ${currentFilter.getName()}.');
		}, 1);
	}

	function showInfo( msg : String, loading : Bool = false ) {
		var info = element.find(".info");
		info.html(loading ? '<p>${msg}<i class="ico ico-spinner fa-spin"></i></p>' : '<p>${msg}</p>');
	}

	function clear() {
		analyzer = null;
		if( statsView != null )
			statsView.remove();
		statsView = null;
		if( tabsView != null )
			tabsView.remove();
		tabsView = null;
		searchBar = null;
		summaryView = null;
		inspectView = null;
	}

	function load( onDone : Bool -> Void ) {
		try {
			hlmem.Analyzer.useColor = false;
			analyzer = new hlmem.Analyzer();
			showInfo("Loading bytecode...", true);
			haxe.Timer.delay(() -> {
				analyzer.loadBytecode(hlPath);
				showInfo("Bytecode loaded, loading dump...", true);
				haxe.Timer.delay(() -> {
					for (i in 0...dumpPaths.length) {
						analyzer.loadMemoryDump(dumpPaths[i]);
					}
					showInfo("Memory dump loaded, building hierarchy...", true);
					haxe.Timer.delay(() -> {
						analyzer.build(currentFilter);
						showInfo("Hierarchy built.");
						haxe.Timer.delay(() -> {
							onDone(true);
						}, 0);
					}, 0);
				}, 0);
			}, 1);
		} catch(e) {
			Ide.inst.quickError(e);
			analyzer = null;
			onDone(false);
		}
	}

	function refresh() {
		refreshStats();
		refreshTabsView();
	}

	function refreshStats() {
		if( statsView != null )
			statsView.remove();
		var statsObj = analyzer != null ? analyzer.getMemStats() : [];
		statsView = new Element('<div class="stats"><div class="title">Stats</div></div>').appendTo(element.find('.right-panel'));
		for (idx => s in statsObj) {
			new Element('
			<h4>Memory usage</h4>
			<h5>${s.memFile}</h5>
			<div class="outer-gauge"><div class="inner-gauge" title="${hlmem.Analyzer.mb(s.used)} used (${ 100 * s.used / s.totalAllocated}% of total)" style="width:${ 100 * s.used / s.totalAllocated}%;"></div></div>
			<dl>
				<dt>Allocated</dt><dd>${hlmem.Analyzer.mb(s.totalAllocated)}</dd>
				<dt>Used</dt><dd>${hlmem.Analyzer.mb(s.used)}</dd>
				<dt>Free</dt><dd>${hlmem.Analyzer.mb(s.free)}</dd>
				<dt>GC</dt><dd>${hlmem.Analyzer.mb(s.gc)}</dd>
				<dt>Pages</dt><dd>${s.pagesCount} (${hlmem.Analyzer.mb(s.pagesSize)})</dd>
				<dt>Roots</dt><dd>${s.rootsCount}</dd>
				<dt>Stacks</dt><dd>${s.stackCount}</dd>
				<dt>Types</dt><dd>${s.typesCount}</dd>
				<dt>Closures</dt><dd>${s.closuresCount}</dd>
				<dt>Live blocks</dt><dd>${s.blockCount}</dd>
				<dt>Filtered blocks</dt><dd>${s.filteredBlockCount}</dd>
			</dl>
			').appendTo(statsView);
		}
	}

	function refreshTabsView() {
		if( tabsView != null )
			tabsView.remove();
		tabsView = new Element('
		<div class="hide-tabs">
			<div id="search-bar"></div>
			<div class="tabs-header"></div>
			<div class="tab-content"></div>
		</div>
		').appendTo(element.find(".left-panel"));
		var header = tabsView.find(".tabs-header");
		var summaryBtn = new Element('<div name="summary" class="active">Summary</button>').appendTo(header);
		summaryBtn.on('click', (e) -> openSummaryTab());
		var inspectBtn = new Element('<div name="inspect">Inspect</button>').appendTo(header);
		inspectBtn.on('click', (e) -> openInspectTab());
		searchBar = new MemProfilerSearchBar(this);
		searchBar.element.appendTo(tabsView.find("#search-bar"));
		var content = tabsView.find(".tab-content");
		summaryView = new MemProfilerSummaryView(this);
		summaryView.element.appendTo(content);
		inspectView = new MemProfilerInspectView(this);
		inspectView.element.appendTo(content);
	}

	public function addHistory(str) {
		searchBar.addHistory(str);
	}

	public function openSummaryTab() {
		var header = tabsView.find(".tabs-header");
		header.find("[name=inspect]").removeClass("active");
		header.find("[name=summary]").addClass("active");
		inspectView.element.toggle(false);
		summaryView.element.toggle(true);
	}

	public function getTypeStat( ttype : hlmem.TType ) {
		return summaryView.typeStats.get(ttype);
	}

	public function openInspectTab( ?tstr : String ) {
		var header = tabsView.find(".tabs-header");
		header.find("[name=summary]").removeClass("active");
		header.find("[name=inspect]").addClass("active");
		summaryView.element.toggle(false);
		inspectView.element.toggle(true);
		inspectView.open(tstr);
	}

	public function inspectRemoveParent( pstr : String ) {
		var mainMemory = analyzer.getMainMemory();
		var ptype = mainMemory.resolveType(pstr);
		if( inspectView.ttype != null && ptype != null ) {
			mainMemory.removeParent(inspectView.ttype, ptype);
			showInfo('Removed parents ${StringTools.htmlEscape(ptype.toString())} for blocks ${inspectView.ttypeName}.');
		}
	}

	static var _ = hide.ui.View.register(MemProfiler);
}

class MemProfilerSearchBar extends hide.comp.Component {
	var profiler : MemProfiler;
	public var searchHistory : Array<String> = [];
	public var searchHistoryIndex : Int = 0;
	var searchInput : Element;
	var searchBtn : Element;
	var searchPrev : Element;
	var searchNext : Element;
	public function new( profiler : MemProfiler ) {
		super(null, null);
		this.profiler = profiler;
		searchPrev = new Element('<i class="ico ico-arrow-left disable"></i>').appendTo(element);
		searchNext = new Element('<i class="ico ico-arrow-right disable"></i>').appendTo(element);
		searchInput = new Element('<input type="text" placeholder="Search..."
			title="Enter class full path or #+tid, e.g. sys.FileSystem, #0"
		/>').appendTo(element);
		searchBtn = new Element('<i class="ico ico-search"></i>').appendTo(element);
		searchInput.keydown(function(e) {
			if (e.key == 'Enter') searchBtn.click();
			if (e.key == 'ArrowUp') goto(searchHistoryIndex + 1, false);
			if (e.key == 'ArrowDown') goto(searchHistoryIndex - 1, false);
		});
		searchBtn.on('click', function(e) {
			profiler.openInspectTab(searchInput.val());
		});
		searchPrev.on('click', function(e) {
			goto(searchHistoryIndex + 1, true);
		});
		searchNext.on('click', function(e) {
			goto(searchHistoryIndex - 1, true);
		});
		searchPrev.contextmenu(function(e) {
			e.preventDefault();
			var menu = buildHistoryMenu(searchHistoryIndex, searchHistory.length);
			if( menu.length > 0 )
				hide.comp.ContextMenu.createDropdown(searchPrev.get(0), menu);
		});
		searchNext.contextmenu(function(e) {
			e.preventDefault();
			var menu = buildHistoryMenu(0, searchHistoryIndex);
			menu.reverse();
			if( menu.length > 0 )
				hide.comp.ContextMenu.createDropdown(searchNext.get(0), menu);
		});
		profiler.keys.register("memprof.inspectPrev", () -> searchPrev.click());
		profiler.keys.register("memprof.inspectNext", () -> searchNext.click());
	}
	public function refreshSearchBar() {
		if( searchHistory[searchHistoryIndex] != null )
			searchInput.val(searchHistory[searchHistoryIndex]);
		searchPrev.toggleClass("disable", searchHistoryIndex >= searchHistory.length - 1);
		searchNext.toggleClass("disable", searchHistoryIndex <= 0);
	}
	public function addHistory( str : String ) {
		if( str != null && str.length > 0 && searchHistory[searchHistoryIndex] != str ) {
			searchHistory.unshift(str);
			searchHistoryIndex = 0;
			refreshSearchBar();
		}
	}
	function goto( index : Int, open : Bool ) {
		if( index >= searchHistory.length )
			index = searchHistory.length - 1;
		if( index < 0 )
			index = 0;
		searchHistoryIndex = index;
		refreshSearchBar();
		haxe.Timer.delay(() -> searchBtn.click(), 1);
	}
	function buildHistoryMenu( begin : Int, end : Int ) : Array<hide.comp.ContextMenu.MenuItem> {
		var items = [];
		for( i in begin...end ) {
			if( searchHistory[i] != null ) {
				var item = {
					label : StringTools.htmlEscape(searchHistory[i]),
					click : () -> goto(i, true),
				};
				items.push(item);
			}
		}
		return items;
	}
}

class MemProfilerSummaryView extends hide.comp.Component {
	var profiler : MemProfiler;
	public var typeStats : hlmem.Result.BlockStats = null;
	public function new( profiler : MemProfiler ) {
		super(null, null);
		this.profiler = profiler;
		element = new Element('<div class="hide-scroll"></div>');
		var mainMemory = profiler.analyzer.getMainMemory();
		typeStats = mainMemory.getBlockStatsByType();
		typeStats.sort(true, false);
		var sumTypeStateByCount = typeStats.slice(0, 10);
		var tabCount = new MemProfilerTable(profiler, "Top 10 type on count", sumTypeStateByCount, 0);
		tabCount.element.appendTo(element);
		typeStats.sort(false, false);
		var sumTypeStateBySize = typeStats.slice(0, 10);
		var tabSize = new MemProfilerTable(profiler, "Top 10 type on size", sumTypeStateBySize, 0);
		tabSize.element.appendTo(element);
		var sumUnknown = mainMemory.getUnknown();
		var tabUnknown = new MemProfilerTable(profiler, "Unknown blocks", sumUnknown, 0);
		tabUnknown.element.appendTo(element);
	}
}

class MemProfilerInspectView extends hide.comp.Component {
	var profiler : MemProfiler;
	public var ttype : hlmem.TType;
	public var ttypeName : String;
	var locateRootBtn : Element;
	var locateRootTable : MemProfilerTable;
	public function new( profiler : MemProfiler ) {
		super(null, null);
		this.profiler = profiler;
		element = new Element('<div class="hide-scroll"></div>');
	}
	public function open( ?tstr : String ) {
		if( tstr == null || tstr.length <= 0 ) return;
		var mainMemory = profiler.analyzer.getMainMemory();
		ttype = mainMemory.resolveType(tstr);
		element.empty();
		if( ttype == null ) {
			new Element('<div><p>Cannot open type ${StringTools.htmlEscape(tstr)}</p></div>').appendTo(element);
			return;
		}
		var tstr = ttype.toString() ?? "";
		profiler.addHistory(tstr.length <= 20 ? tstr : "#" + ttype.tid);
		ttypeName = StringTools.htmlEscape(tstr) + "#" + ttype.tid;
		var ttypeStat = profiler.getTypeStat(ttype);
		new Element('
			<table>
				<tr><td>Type</td><td>${ttypeName}</td></tr>
				<tr><td>Blocks count</td><td>${ttypeStat == null ? 0 : ttypeStat.count}</td></tr>
				<tr><td>Blocks size</td><td>${ttypeStat == null ? "0" : hlmem.Analyzer.mb(ttypeStat.size)}</td></tr>
			</table>
		').appendTo(element);
		var data = mainMemory.locate(ttype);
		var locateTable = new MemProfilerTable(profiler, "Locate", data, profiler.defaultTableLines);
		locateTable.element.appendTo(element);
		var data = mainMemory.parents(ttype);
		var parentsTable = new MemProfilerTable(profiler, "Parents", data, profiler.defaultTableLines, true);
		parentsTable.element.appendTo(element);
		var data = mainMemory.subs(ttype);
		var subsTable = new MemProfilerTable(profiler, "Subs", data, profiler.defaultTableLines);
		subsTable.element.appendTo(element);
		locateRootTable = null;
		locateRootBtn = new Element('<input type="button" value="Locate Root"/>').appendTo(element);
		locateRootBtn.on('click', function(e) {
			if( locateRootTable != null ) return;
			locateRootBtn.remove();
			var data = mainMemory.locate(ttype, 10);
			locateRootTable = new MemProfilerTable(profiler, "Locate 10", data, profiler.defaultTableLines);
			locateRootTable.element.appendTo(element);
		});
		if( profiler.defaultLocateRoot ) {
			haxe.Timer.delay(() -> locateRootBtn.click(), 0);
		}
	}
}

class MemProfilerTable extends hide.comp.Component {
	var profiler : MemProfiler;
	var title : String;
	var data : hlmem.Result.BlockStats;
	var allowRemoveParent : Bool;
	var currentLine : Int;
	var expandBtn : Element;
	public function new( profiler : MemProfiler, title : String, data : hlmem.Result.BlockStats, maxLine : Int, allowRemoveParent : Bool = false ) {
		super(null, null);
		this.profiler = profiler;
		this.title = title;
		this.data = data;
		this.currentLine = 0;
		this.allowRemoveParent = allowRemoveParent;
		element = new Element('
		<table rules=none>
			<caption>${title} (${data.allT.length})</caption>
			<thead>
				<td></td>
				<td>Count</td>
				<td>Size</td>
				<td>Name</td>
			</thead>
			<tbody>
			</tbody>
		</table>'
		);
		var size = (maxLine > 0 && maxLine < data.allT.length) ? maxLine : data.allT.length;
		expand(size);
	}
	public function expand( size : Int ) {
		if( expandBtn != null )
			expandBtn.remove();
		var delta = data.allT.length - currentLine;
		if( delta <= 0 || size <= 0 )
			return;
		if( size < delta )
			delta = size;
		var maxLine = currentLine + delta;
		var body = element.find('tbody');
		for ( i in currentLine...maxLine ) {
			var l = data.allT[i];
			var child = new MemProfilerTableLine(profiler, l);
			child.element.appendTo(body);
			child.addAction("ico-map-marker", "locate", element -> profiler.openInspectTab("#" + element.tl[0]));
			if( allowRemoveParent )
				child.addAction("ico-remove", "remove parent", element -> profiler.inspectRemoveParent("#" + element.tl[0]));
		}
		currentLine = maxLine;
		var delta = data.allT.length - currentLine;
		if( delta > 0 ) {
			expandBtn = new Element('<input type="button" value="Expand"/>').appendTo(body);
			expandBtn.on('click', (e) -> expand(5));
		}
	}
}

class MemProfilerTableLine extends hide.comp.Component {
	var profiler : MemProfiler;
	var data : hlmem.Result.BlockStatsElement;
	var actions : Element;
	public function new( profiler : MemProfiler, el : hlmem.Result.BlockStatsElement ) {
		super(null, null);
		this.profiler = profiler;
		this.data = el;
		var names = el.getNames(true, false, false).map(s -> StringTools.htmlEscape(s));
		var tids = el.getNames(false, true, false).map(s -> profiler.showTid ? '<span class="tid">$s</span>' : "");
		var fields = el.getNames(false, false, true);
		if( names[0] == "roots" || names[0] == "stack" )
			names[0] = '<span class="roots">${names[0]}</span>';
		for( i in 0...names.length )
			names[i] = names[i] + tids[i] + fields[i];
		var name = names.join(' <span class="arrow">&#10148;</span> ');
		var title = el.getNames(false).join(' > ');
		element = new Element('
		<tr tabindex="2">
			<td id="actions"></td>
			<td>${el.count}</td>
			<td>${hlmem.Analyzer.mb(el.size)}</td>
			<td title="${title}">
				${name}
			</td>
		</tr>'
		);
		actions = element.find("#actions");
	}
	public function addAction( icon : String, description : String, onClick : hlmem.Result.BlockStatsElement -> Void ) {
		var btn = new Element('<i class="ico ${icon}" title="${description}"></i>').appendTo(actions);
		btn.on('click', (e) -> onClick(data));
	}
}

#end
