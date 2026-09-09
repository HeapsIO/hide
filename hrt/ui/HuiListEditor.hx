package hrt.ui;

#if hui

class HuiListEditor<ListItem> extends HuiElement {
	static var SRC =
		<hui-list-editor>
			<hui-line id="header">
				<hui-element class="kit-label first"><hui-element id="caret"/><hui-text("label") id="label" public/></hui-element>
				<hui-element id="info-container"><hui-text("") id="infos"/></hui-element>
				<hui-button id="add-button" class="medium-square" tip={"Add one line to the list"}><hui-icon(HuiRes.ui.icons.add)/></hui-button>
				<hui-button id="clear-button" class="medium-square" tip={"Remove all the lines from the list"}><hui-icon(HuiRes.ui.icons.clear)/></hui-button>
			</hui-line>
			<hui-element id="content"/>
		</hui-list-editor>


	public var items: Array<ListItem>;

	/**
		Generate an item to display in the list. Header allows to customise the content of the header part of the list
		and content the part that is folded after the header
	**/
	public dynamic function makeLine(line:HuiListEditorLine, item: ListItem, index: Int) : Void {

	}

	/**
		Called every time the editor directly modifies items (add/remove/clear... operations).
		You must call the effects function when overriding this function in order for the editor to
		properly function. Allow for custom undo/redo operations
	**/
	public dynamic function change(effects: () -> Void) {
		effects();
	}

	/**
		Called to get a new ListItem object to add to items.
		You can override this function to override the default values
	**/
	public dynamic function newItem() : ListItem {
		return cast {}
	}

	override public function new(items: Array<ListItem>, makeLine: (line: HuiListEditorLine, item: ListItem, index: Int) -> Void, ?parent) {
		this.items = items;
		this.makeLine = makeLine;
		super(parent);
		initComponent();

		header.onClick = (e) -> {
			saveDisplayState("open", !getDisplayState("open", false));
			refreshOpen();
		}

		addButton.onClick = (e) -> {
			if (e.button == 0)
				addLine();
		}

		clearButton.onClick = (e) -> {
			if (e.button == 0)
				clear();
		}

		refreshLines();
	}

	override function onLoadState() {
		super.onLoadState();
		refreshOpen();
	}

	public function refreshOpen() {
		dom.toggleClass("open", getDisplayState("open", false));
	}

	public function refreshLines() {
		content.removeChildElements();

		var count = items?.length ?? 0;
		infos.text = '($count element${count >2 ? "s" : ""})';
		if (items == null)
			return;

		for (i => item in items) {
			var line = new HuiListEditorLine(content);
			line.remButton.onClick = (e) -> {
				if (e.button == 0)
					removeLine(i);
			}

			line.header.onClick = (e) -> {
				if (e.button == 0) {
					line.dom.toggleClass("open");
				}
			}

			line.saveDisplayKey = '$i';
			var count = line.bodyContent.numChildren;
			line.label.text = '$i';
			makeLine(line, item, i);
			if (line.bodyContent.numChildren == count) {
				line.dom.addClass("no-body");
			}
		}
	}

	function addLine() {
		change(() -> {
			items.push(newItem());
		});

		refreshLines();
	}

	function clear() {
		change(() -> {
			items.resize(0);
		});

		refreshLines();
	}

	function removeLine(index) {
		change(() -> {
			items.splice(index, 1);
		});

		refreshLines();
	}
}

class HuiListEditorLine extends HuiElement {
	static var SRC =
		<hui-list-editor-line>
			<hui-line id="header" public>
				<hui-element class="kit-label first" id="label-container" public>
					<hui-element id="caret"/>
					<hui-element id="drag-handle"/>
					<hui-text("") id="label" public/>
				</hui-element>
				<hui-line id="header-content" class="kit-line" public/>
				<hui-button id="rem-button" class="medium-square" tip={"Remove this line from the list"} public><hui-icon(HuiRes.ui.icons.remove)/></hui-button>
			</hui-line>
			<hui-element id="body-content" public/>
		</hui-list-editor-line>;
}

#end