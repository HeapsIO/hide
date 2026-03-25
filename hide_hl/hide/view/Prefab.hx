package hide.view;
import hrt.ui.*;

#if hui

class Prefab extends HuiView<{path: String}> {
	static var SRC =
		<prefab>
			<hui-prefab-editor id="prefab-editor"/>
		</prefab>

	static var _ = HuiView.register("prefab", Prefab);

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);

		try {
			var prefabData = hxd.res.Loader.currentInstance.load(path).toPrefab().load().clone();
			prefabEditor.setPrefab(prefabData);
		} catch(e) {
			prefabEditor.remove();
			var error = 'Couldn\'t load $path : $e';
			hide.Ide.showError(error);
			new HuiText(error, this);
		}

		undo.onAfterChange = () -> {
			hasUnsavedChanges = prefabEditor.hasUnsavedChanges();
		}

		registerCommand(HuiCommands.save, View, () -> {@:privateAccess prefabEditor.save(); hasUnsavedChanges = prefabEditor.hasUnsavedChanges();});
	}

	override function sync(ctx) {
		super.sync(ctx);
	}

	override function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {
		content.push({label: "Save", click: () -> execCommand(HuiCommands.save)});
		content.push({label: "Rebuild", click: () -> @:privateAccess prefabEditor.tryMake(prefabEditor.prefab)});
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}
}

#end