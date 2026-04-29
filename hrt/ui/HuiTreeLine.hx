package hrt.ui;
import hrt.ui.HuiTree;

#if hui

@:access(hrt.ui.HuiTree)
class HuiTreeLine extends HuiElement {
	static var SRC =
		<hui-tree-line>
			<hui-element id="caret"/>
			<hui-element id="icon"/>
			<hui-text("") id="title"/>
			<hui-input-box id="title-edit"/>
			<hui-element id="drop-indicator"/>
		</hui-tree-line>

	var data : TreeItemData;
	var tree : Any;

	public function new(data: TreeItemData, tree: Any, ?parent) {
		super(parent);
		initComponent();
		this.data = data;
		makeInteractive();
		this.tree = tree;

		caret.onPush = (e) -> {
			if (e.button == 0) {
				onCaretClick();
				e.propagate = false;
			}
		}

		onPush = (e) -> {
			if (e.button == 0 || e.button == 1) {
				onItemSelect(hxd.Key.isDown(hxd.Key.SHIFT), hxd.Key.isDown(hxd.Key.CTRL));

				if (e.button == 1) {
					onContextMenu();
				}
			}
		}

		var tree : HuiTree<Dynamic> = tree;
	}

	public dynamic function onContextMenu() {
	}

	public function rename(callback: (newName: String) -> Void, ?selectionRange: HuiTree.SelectionRange) : Void {
		dom.addClass("edit");
		// force visibility to prevent direct unfocus if the style is not applied before the SceneEvents.checkEvents function is called
		titleEdit.visible = true;
		titleEdit.text = data.name;
		titleEdit.focus();

		if (selectionRange != null) {
			titleEdit.textInput.selectionRange = selectionRange;
			@:privateAccess titleEdit.textInput.onCursorChange();
		}

		function cleanup() {
			dom.removeClass("edit");
		}

		titleEdit.onFocusLost = (e) -> {
			cleanup();
		}

		titleEdit.onChange = (temp) -> {
			if (!temp) {
				callback(titleEdit.text);
			}
		}
	}

	public function getDropOperation(op: HuiDragOp) : hrt.ui.HuiTree.DropOperation {
		var tree : HuiTree<Dynamic> = tree;
		if (tree.dragAndDropInterface == null)
			return null;

		var percentHeight = op.event.relY / calculatedHeight;

		var flags = tree.dragAndDropInterface.getItemDropFlags(data.item, op);
		if (flags == DropFlags.ofInt(0)) {
			return null;
		}

		if (!flags.has(Reorder)) {
			return Inside;
		}

		if (!flags.has(Reparent)) {
			if (percentHeight > 0.5) {
				return After;
			}
			return Before;
		}
		else {
			final split = 1.0 / 3.0;
			if (percentHeight < split) {
				return Before;
			}
			if (percentHeight > (1.0-split) && !tree.isOpen(data)) {
				return After;
			}
			return Inside;
		}
	}

	public function refresh() {
		var tree : HuiTree<Dynamic> = tree;
		if (tree.searchBarContainer.visible && data.searchRanges != null) {
			title.text = hide.Search.splitSearchRanges(data.name, data.searchRanges, "<h>", "</h>");
		} else {
			title.text = data.name;
		}
		icon.backgroundType = "hui";
		icon.huiBg.image = { path: data.icon, mode: Fit };

		paddingLeft = data.depth * 5;

		dom.toggleClass("children", tree.hasChildren(data.item));
		dom.toggleClass("open", tree.isOpen(data));
		dom.toggleClass("selected", tree.isSelected(data));

		if (tree.renamedElement?.item == data.item) {
			rename(tree.renamedElement.callback, tree.renamedElement.selectionRange);
			tree.renamedElement = null;
		}

		@:privateAccess dom.toggleClass("keyboard-selected", tree.keyboardFocus == data);
	}

	override public function draw(ctx) {
		dropIndicator.x = paddingLeft;
		dropIndicator.y = 0;
		dropIndicator.setWidth(Std.int(calculatedWidth - paddingLeft));
		dropIndicator.setHeight(Std.int(calculatedHeight));
		super.draw(ctx);
	}

	dynamic public function onCaretClick() {

	}

	dynamic public function onItemSelect(shift: Bool, ctrl: Bool) {

	}
}

#end