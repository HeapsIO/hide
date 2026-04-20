package hide.view.animgraph;



class AnimPicker extends hide.comp.Component {
	var button : hide.comp.Button;

	public function new(parent = null, undo: hide.ui.UndoHistory, get: () -> String, set: (string: String) -> Void, ?animations: Array<String> ) {
		button = new hide.comp.Button(parent, null, "", {hasDropdown: true});
		super(parent, button.element);

		button.label = get();

		var items : Array<hide.comp.ContextMenu.MenuItem> = [];

		function setPointPath(path: String) {
			var old = get();
			function exec(isUndo: Bool) {
				var toSet = !isUndo ? path : old;
				set(toSet);
				setAnim(toSet);
			};
			exec(false);
			undo.change(Custom(exec));
		}

		items.push({
			label: "Choose File ...",
			click: () -> {
			ide.chooseFile(["fbx"], setPointPath, true);
			}
		});

		if (hrt.animgraph.AnimGraph.customAnimNameLister != null) {
			items.push({isSeparator: true});

			var anims = hrt.animgraph.AnimGraph.customAnimNameLister(null);
			for (anim in anims) {
				items.push({
					label: anim,
					click: setPointPath.bind(anim),
				});
			}
		}

		if (animations != null && animations.length > 0) {
			items.push({isSeparator: true});

			for (animation in animations) {
				items.push({
					label: ide.makeRelative(animation),
					click: setPointPath.bind(ide.makeRelative(animation)),
				});
			}
		}

		button.onClick = () -> {
			hide.comp.ContextMenu.createDropdown(button.element.get(0), items, {search: Visible, widthOverride: 500});
		};

		button.element.get(0).ondragover = (e:js.html.DragEvent) -> {
			if (e.dataTransfer.types.contains(AnimList.dragEventKey))
				e.preventDefault();
		};

		button.element.get(0).ondrop = (e:js.html.DragEvent) -> {
			var data = e.dataTransfer.getData(AnimList.dragEventKey);
			if (data.length == 0)
				return;
			e.preventDefault();

			setPointPath(data);
		};
	}

	public function setAnim(string: String) {
		button.label = string;
	}
}