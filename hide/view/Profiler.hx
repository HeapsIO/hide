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

	var hlPath = "";//"C:/Projects/wartales/trunk/wartales.hl";
	var dumpPath = "";//"C:/Projects/wartales/trunk/capture.dump";

	var error : String = "";

	var sort : SortType = ByCount;
	var sortOrderAscending = true;
	var currentFilter : Filter = None;
	var stats : Array<String> = [];
	var statsObj : Dynamic;

	public function new( ?state ) {
		super(state);
	}

	override function onDisplay() {
		new Element('
		<div class="profiler">
			<div class="left-panel">
				<div class="tree-map"></div>
				<div class="hierarchy"></div>
			</div>
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
								<dt>Dump file</dt><dd><input class="dump-fileselect" type="fileselect" extension="dump"/></dd>
							</dl>
						</div>
						<input type="button" value="Process Files" id="process-btn"/>
					</div>
				</div>
			</div>
		</div>'
		).appendTo(element);

		var hlSelect = new hide.comp.FileSelect(["hl"], null, element.find(".hl-fileselect"));
		hlSelect.onChange = function() { hlPath = Ide.inst.getPath(hlSelect.path); };

		var dumpSelect = new hide.comp.FileSelect(["dump"], null, element.find(".dump-fileselect"));
		dumpSelect.onChange = function() { dumpPath = Ide.inst.getPath(dumpSelect.path); };

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
						dumpPath = p;
						dumpSelect.path = p;
						continue;
					}

					Ide.inst.error('File ${p} is not supported, please provide .dump file or .hl file');
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
			if (hlPath == null || hlPath == '' || dumpPath == null || dumpPath == '') {
				Ide.inst.quickMessage('.hl or/and .dump files are missing. Please provide both files before hit the process button');
				return;
			}

			clear();
			load();
			refresh();
		});

		var hierarchyPanel = new hide.comp.ResizablePanel(Vertical, element.find(".hierarchy"));
		hierarchyPanel.saveDisplayKey = "hierarchyPanel";
	}

	override function getTitle() {
		return "Memory profiler";
	}

	function load() {
		names = [ dumpPath ];

		var result = loadAll();
		if ( result != null) {
			error = result;
		} else {
			error = "";
			if (names.length > 0) {
				filter(None);
				displayTypes(sort, sortOrderAscending);
				stats = mainMemory?.getStats();
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
	}

	function filter(f : Filter) {
		switch (f) {
			case None :
				currentMemory = mainMemory;
				mainMemory.setFilterMode(None);
			/*case Unique :
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
				mainMemory.setFilterMode(Intersect);*/
			default:
				currentMemory = mainMemory;
				mainMemory.setFilterMode(None);
		}

		locationData.clear();
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
		// Update memory statistics on the right panel
		element.find('.stats').remove();

		new Element ('
		<div class="stats">
			<div class="title">Stats</div>
			<h4>Memory usage on device</h4>
			<div class="outer-gauge"><div class="inner-gauge" title="${hide.tools.memory.Memory.MB(statsObj?.used)} used (${ 100 * statsObj?.used / statsObj?.totalAllocated}% of total)" style="width:${ 100 * statsObj?.used / statsObj?.totalAllocated}%;"></div></div>
			<dl>
				<dt>Allocated</dt><dd>${hide.tools.memory.Memory.MB(statsObj?.totalAllocated)}</dd>
				<dt>Used</dt><dd>${hide.tools.memory.Memory.MB(statsObj?.used)}</dd>
				<dt>Free</dt><dd>${hide.tools.memory.Memory.MB(statsObj?.free)}</dd>
				<dt>GC</dt><dd>${hide.tools.memory.Memory.MB(statsObj?.gc)}</dd>
				<dt>&nbsp</dt><dd></dd>
				<dt>Pages</dt><dd>${statsObj?.pagesCount} (${hide.tools.memory.Memory.MB(statsObj?.pagesSize)})</dd>
				<dt>Roots</dt><dd>${statsObj?.rootsCount}</dd>
				<dt>Stacks</dt><dd>${statsObj?.stackCount}</dd>
				<dt>Types</dt><dd>${statsObj?.typesCount}</dd>
				<dt>Closures</dt><dd>${statsObj?.closuresCount}</dd>
				<dt>Live blocks</dt><dd>${statsObj?.blockCount}</dd>
			</dl>
		</div>
		').appendTo(element.find('.right-panel'));

		// Update memory hierarchical view
		element.find('table').parent().remove();
		var tab = new Element('
		<div class="hide-scroll">
			<table rules=none>
				<thead>
					<td>Count</td>
					<td>Size</td>
					<td>Name</td>
					<td>% Impact</td>
				</thead>
				<tbody>
				</tbody>
			</table>
		</div>'
		).appendTo(element.find(".hierarchy"));

		var body = tab.find('tbody');
		for (l in lines)
			new ProfilerElement(this, l, null, null).element.appendTo(body);
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

		this.element = new Element('<tr><td><div class="folder icon ico ico-caret-right"></div>${count}</td><td>${hide.tools.memory.Memory.MB(mem)}</td><td title="${name}">${name}</td><td><div title="Allocated ${mem} (${100 * mem / Reflect.getProperty(profiler.statsObj, "totalAllocated")}% of total)" class="outer-gauge"><div class="inner-gauge" style="width:${100 * mem / Reflect.getProperty(profiler.statsObj, "totalAllocated")}%;"></div></div></td></tr>');
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
