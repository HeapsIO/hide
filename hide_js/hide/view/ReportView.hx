package hide.view;

import js.html.Element as DomElement;
import hide.tools.Report.ReportData;
import hide.tools.Report.ReportBlock;
import hide.tools.Report.ReportTable;

typedef ReportViewState = { kind : String, ?params : Dynamic };

private typedef TableRow = { tr : DomElement, values : Array<Dynamic>, text : String };

class ReportView extends hide.ui.View<ReportViewState> {

	var root : DomElement;
	var content : DomElement;
	var filterInput : js.html.InputElement;
	var generating = false;
	var tables : Array<{ section : DomElement, rows : Array<TableRow> }> = [];
	var kind : hide.tools.Report.ReportKind;

	public function new( ?state : ReportViewState ) {
		super(state);
		kind = hide.tools.Report.get(this.state.kind);
		if( this.state.params == null )
			this.state.params = {};
	}

	override function getTitle() {
		return kind?.title ?? "Report";
	}

	override function onDisplay() {
		root = element.get(0);
		root.classList.add("report-view");
		root.innerHTML = "";
		if( kind == null ) {
			root.innerHTML = '<p class="warn">Unknown report ${hide.tools.Report.esc(state.kind)}</p>';
			return;
		}

		var bar = el("div", "toolbar", root);
		kind.editParams(bar, state.params, saveState);
		var run = el("button", "run", bar);
		run.textContent = "Generate";
		run.onclick = () -> generate();
		filterInput = cast el("input", "filter", bar);
		filterInput.type = "search";
		filterInput.placeholder = "Filter rows...";
		filterInput.oninput = () -> applyFilter();

		content = el("div", "content hide-scroll", root);
		content.innerHTML = '<p class="note">Click <b>Generate</b> to make the report.</p>';
		content.addEventListener("click", onClick);
	}

	inline function el( tag : String, cls : String, parent : DomElement ) {
		return hide.tools.Report.el(tag, cls, parent);
	}

	function generate() {
		if( generating )
			return;
		generating = true;
		var t0 = haxe.Timer.stamp();
		function progress( text : String ) {
			content.innerHTML = '<p class="note">${hide.tools.Report.esc(text)}</p>';
		}
		function done( data : ReportData ) {
			generating = false;
			render(data);
			ide.quickMessage('${data.title} generated in ${Math.round((haxe.Timer.stamp() - t0) * 10) / 10}s');
		}
		function error( e : haxe.Exception ) {
			generating = false;
			content.innerHTML = '<p class="warn">${hide.tools.Report.esc(e.message)}</p><pre>${hide.tools.Report.esc(e.stack.toString())}</pre>';
		}
		progress("Generating...");
		haxe.Timer.delay(() -> {
			kind.generate(state.params, progress, done, error);
		}, 30);
	}

	function render( data : ReportData ) {
		tables = [];
		content.innerHTML = "";
		el("h1", null, content).textContent = data.title;
		el("p", null, content).innerHTML = data.subtitle;

		var nav = el("div", "nav", content);
		for( s in data.sections ) {
			var a = el("a", "r-goto", nav);
			a.dataset.goto = s.id;
			a.innerHTML = hide.tools.Report.esc(s.title) + (s.count == null ? "" : ' <small>${s.count}</small>');
		}

		var box = el("div", "box", content);
		for( b in data.summary )
			addBlock(box, b, null);

		for( s in data.sections ) {
			var d : js.html.DetailsElement = cast el("details", "section", content);
			d.dataset.id = s.id;
			d.open = s.open ?? false;
			var sum = el("summary", null, d);
			sum.innerHTML = hide.tools.Report.esc(s.title) + (s.count == null ? "" : ' <small class="count">(${s.count})</small>');
			for( b in s.blocks )
				addBlock(d, b, d);
		}
		applyFilter();
	}

	function addBlock( parent : DomElement, b : ReportBlock, section : DomElement ) {
		switch( b ) {
		case Html(html):
			el("div", "desc", parent).innerHTML = html;
		case Table(t):
			addTable(parent, t, section);
		}
	}

	function addTable( parent : DomElement, t : ReportTable, section : DomElement ) {
		var table = el("table", null, parent);
		var fixed = Lambda.exists(t.columns, c -> c.width != null);
		if( fixed )
			table.classList.add("fixed");
		var head = el("tr", null, el("thead", null, table));
		var body = el("tbody", null, table);
		var rows : Array<TableRow> = [];
		for( r in t.rows ) {
			var tr = el("tr", null, body);
			if( r.id != null )
				tr.dataset.id = r.id;
			for( i => c in r.cells ) {
				var td = el("td", t.columns[i]?.num ? "n" : null, tr);
				td.innerHTML = c;
			}
			rows.push({ tr : tr, values : r.values, text : tr.textContent.toLowerCase() });
		}
		for( i => c in t.columns ) {
			var th = el("th", c.num ? "n" : null, head);
			th.textContent = c.name;
			if( c.width != null )
				th.style.width = c.width + "%";
			th.title = "Sort";
			var dir = 0;
			th.onclick = () -> {
				dir = dir == 1 ? -1 : 1;
				for( h in head.children )
					h.classList.remove("asc", "desc");
				th.classList.add(dir == 1 ? "desc" : "asc");
				function key( r : TableRow ) : Dynamic {
					var v = r.values == null ? null : r.values[i];
					if( v != null )
						return v;
					var text = (cast r.tr.children[i] : DomElement).textContent;
					var f = Std.parseFloat(text);
					return c.num && !Math.isNaN(f) ? f : text;
				}
				var sorted = rows.copy();
				sorted.sort((a, b) -> {
					var x = key(a), y = key(b);
					var cmp = Std.isOfType(x, Float) && Std.isOfType(y, Float) ? Reflect.compare(y, x) : Reflect.compare(Std.string(x).toLowerCase(), Std.string(y).toLowerCase());
					return cmp * dir;
				});
				for( r in sorted )
					body.appendChild(r.tr);
			};
		}
		if( section != null )
			tables.push({ section : section, rows : rows });
	}

	function applyFilter() {
		if( filterInput == null )
			return;
		var q = StringTools.trim(filterInput.value).toLowerCase();
		var counts = new Map<DomElement, { shown : Int, total : Int }>();
		for( t in tables ) {
			var c = counts.get(t.section);
			if( c == null ) {
				c = { shown : 0, total : 0 };
				counts.set(t.section, c);
			}
			for( r in t.rows ) {
				var show = q == "" || r.text.indexOf(q) >= 0;
				r.tr.style.display = show ? "" : "none";
				c.total++;
				if( show )
					c.shown++;
			}
		}
		for( s => c in counts ) {
			var count = s.querySelector("summary .filtered");
			if( count == null )
				count = el("small", "filtered", s.querySelector("summary"));
			count.textContent = q == "" ? "" : ' ${c.shown} match${c.shown == 1 ? "" : "es"}';
			s.classList.toggle("nomatch", q != "" && c.shown == 0);
			if( q != "" && c.shown > 0 )
				(cast s : js.html.DetailsElement).open = true;
		}
	}

	function reveal( id : String ) {
		var target : DomElement = content.querySelector('[data-id="${untyped CSS.escape(id)}"]');
		if( target == null ) {
			ide.quickError('$id is not in the report');
			return;
		}
		var p = target;
		while( p != null && p != content ) {
			if( p.tagName == "DETAILS" )
				(cast p : js.html.DetailsElement).open = true;
			if( p.style.display == "none" ) {
				filterInput.value = "";
				applyFilter();
			}
			p = p.parentElement;
		}
		target.scrollIntoView({ block : target.tagName == "TR" ? CENTER : START });
		target.classList.remove("flash");
		untyped target.offsetWidth;
		target.classList.add("flash");
	}

	function onClick( e : js.html.MouseEvent ) {
		var t : DomElement = cast e.target;
		var link = t.closest(".r-file, .r-code, .r-goto, .r-shader");
		if( link == null )
			return;
		e.preventDefault();
		var d = link.dataset;
		if( d.file != null )
			ide.openFile(d.file);
		else if( d.code != null )
			js.node.ChildProcess.exec((Sys.systemName() == "Windows" ? 'start ""' : Sys.systemName() == "Mac" ? "open" : "xdg-open") + ' "vscode://file/${d.code}"', (_, _, _) -> {});
		else if( d.goto != null )
			reveal(d.goto);
		else if( d.shader != null )
			reveal("sh-" + d.shader);
	}

	static var _ = hide.ui.View.register(ReportView);
}
