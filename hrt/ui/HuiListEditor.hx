package hrt.ui;

#if hui

class HuiListEditor<ListItem> extends HuiElement {
	static var SRC =
		<hui-list-editor>
			<hui-line id="header">
				<hui-element class="kit-label first"><hui-element id="caret"/><hui-text("label") id="label" public/></hui-element>
				<hui-element id="info-container"><hui-text("") id="infos"/></hui-element>
				<hui-button id="add-button" class="medium-square"><hui-icon(HuiRes.ui.icons.add)/></hui-button>
				<hui-button id="clear-button" class="medium-square"><hui-icon(HuiRes.ui.icons.clear)/></hui-button>
			</hui-line>
			<hui-element id="content"/>
		</hui-list-editor>


	public var items: Array<ListItem>;

	/**
		Generate an item to display in the list. Header allows to customise the content of the header part of the list
		and content the part that is folded after the header
	**/
	public dynamic function makeLine(header: HuiElement, content: HuiElement, item: ListItem, index: Int) : Void {

	}

	override public function new(items: Array<ListItem>, makeLine: (header: HuiElement, content: HuiElement, item: ListItem, index: Int) -> Void, ?parent) {
		this.items = items;
		this.makeLine = makeLine;
		super(parent);
		initComponent();

		header.onClick = (e) -> {
			saveDisplayState("open", !getDisplayState("open", false));
			refreshOpen();
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
			line.saveDisplayKey = '$i';
			var count = line.bodyContent.numChildren;
			line.label.text = '$i';
			makeLine(line.headerContent, line.bodyContent, item, i);
			if (line.bodyContent.numChildren == count) {
				line.dom.addClass("no-body");
			}
		}
	}
}

class HuiListEditorLine extends HuiElement {
	static var SRC =
		<hui-list-editor-line>
			<hui-line id="header">
				<hui-element class="kit-label first">
					<hui-element id="caret"/>
					<hui-element id="drag-handle"/>
					<hui-text("") id="label" public/>
				</hui-element>
				<hui-line id="header-content" class="kit-line" public/>
				<hui-button id="rem-button" class="medium-square"><hui-icon(HuiRes.ui.icons.remove)/></hui-button>
			</hui-line>
			<hui-line id="body-content" class="kit-line" public/>
		</hui-list-editor-line>;
}

#end