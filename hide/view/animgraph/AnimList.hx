package hide.view.animgraph;

class AnimList extends hide.comp.Component {
	public static final dragEventKey = "animlist.path";

	var paths : Array<String> = [];
	var filter = "";

	public function new(parent, el, paths: Array<String>) {
		super(parent, el);
		this.paths = paths;
		element.addClass("anim-list");
		element.html('
			<h1>Animations</h1>
			<div class="fancy-search-bar">
				<input type="text"/>
			</div>
			<ul>
			</ul>
		');

		var filterElem = element.find("input");

		filterElem.get(0).onkeyup = (e) -> {
			filter = filterElem.val();
			refreshList();
		};

		refreshList();
	}

	public function refreshList() {
		var list = element.find("ul");
		list.html("");
		var lowFilter = filter.toLowerCase();
		for (path in paths) {
			var rel = ide.makeRelative(path);
			if (filter.length > 0 && !StringTools.contains(rel.toLowerCase(), lowFilter))
				continue;

			var item = new Element('<li draggable="true">$rel</li>').appendTo(list);

            item.get(0).ondragstart = (e: js.html.DragEvent) -> {
                e.dataTransfer.setDragImage(item.get(0), Std.int(item.width()), 0);

                e.dataTransfer.setData(dragEventKey, rel);
                e.dataTransfer.dropEffect = "link";
            }
		}
	}
}