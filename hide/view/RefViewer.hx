package hide.view;

typedef Reference = {
	file : String,
	path : String,
	results : Array<Result>
};

typedef Result =  {
	text: String,
	goto : () -> Void
}

class RefViewer extends hide.ui.View<{}> {
	public function new(state: Dynamic) {
		super(state);
	}

	override public function onDisplay() {
	}

	override function getTitle() {
		return "References Viewer";
	}

	public function showRefs(references: Array<Reference>, original: String, gotoOriginal: Void -> Void) {
		element.html("");
		var div = new Element('<div class="ref-viewer hide-scroll">').appendTo(element);

		var refCount = 0;
		for (r in references)
			refCount += r.results.length;

		var headerEl = new Element('<div class="header">
			<span class="title" title="${original}">References to : <em>${original}</em></span>
			<span class="infos">${refCount} results in ${references.length} files</span>
		</div>');
		headerEl.appendTo(div);
		headerEl.find(".title").on("click", (e) -> gotoOriginal());

		for (r in references) {
			var el = new Element('<div class="reference">
				<div class="header">
					<span class="icon ico ico-angle-down"></span>
					<span title="${r.file}" class="file">${r.file}</span>
					<span title="${r.path}" class="path">${r.path}</span>
					<span class="ref-count">${r.results.length}</span>
				</div>
				<div class="content">
				</div>
			</div>');
			el.appendTo(div);

			for (result in r.results) {
				var resultEl = new Element('<div class="result">
					<span class="entry"><a>${original != null ? StringTools.replace(result.text, original, '<em>${original}</em>') : result.text}<a/></span>
				</div>');
				resultEl.appendTo(el.find(".content"));
				resultEl.on("click", function(e) {
					result.goto();
				});
			}

			var headerEl = el.find(".header");
			var contentEl = el.find(".content");
			headerEl.on('click', function(e) {
				var icon = headerEl.find(".icon");
				var folded = icon.hasClass("folded");
				folded = !folded;
				icon.toggleClass("folded", folded);
				if (folded)
					contentEl.hide();
				else
					contentEl.show();
			});
		}
	}

	public function showUnreferenced(unreferenceds: Array<Result>) {
		element.html("");
		var div = new Element('<div class="ref-viewer hide-scroll">').appendTo(element);
		var headerEl = new Element('<div class="header">
			<span class="title">Unreferenced IDs :</span>
			<span class="infos">${unreferenceds.length} results</span>
		</div>');
		headerEl.appendTo(div);

		var content = new Element('<div class="reference">
			<div class="content">
			</div>
		</div>');
		content.appendTo(div);

		for (u in unreferenceds) {
			var resultEl = new Element('<div class="result">
				<span class="entry"><a>${u.text}<a/></span>
			</div>');
			resultEl.appendTo(content.find(".content"));
			resultEl.on("click", function(e) {
				u.goto();
			});
		}
	}


	static var _ = hide.ui.View.register(RefViewer, {position: Left, width: 400});
}