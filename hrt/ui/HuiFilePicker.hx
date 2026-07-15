
package hrt.ui;

#if hui
class HuiFilePicker extends HuiElement {
	static var SRC = <hui-file-picker>
		<hui-text id="path"/>
		<hui-drop-overlay id="drop-overlay"/>
	</hui-file-picker>

	public var value(default, set) : String;

	/** Path relative to the res directory **/
	public var relative : Bool = true;
	public var allowedExtensions : Array<String> = [];

	public function new(?parent) {
		super(parent);
		initComponent();

		this.onClick = (e: hxd.Event) -> {
			if (e.button == 0) {
				hxd.File.browse((select) -> {
					value = validatePath(select.fileName);
					onValueChanged();
				}, {fileTypes: [{ name: [for (e in allowedExtensions) e].join(", "), extensions: allowedExtensions }]});
			} else if (e.button == 1) {
				var clipboard = hide.Ide.inst.getClipboardText();
				var validClipboard = true;
				var pathToPaste = validatePath(hide.Ide.inst.getClipboardText());
				if (pathToPaste == null && clipboard != "") {
					validClipboard = false;
				}

				uiBase.contextMenu([
					{label: "View File", click: () -> hide.Ide.inst.openFile(value), enabled: value != null},
					{label: "Copy", click: () -> hide.Ide.inst.setClipboard(value ?? "", null)},
					{label: "Paste", click: () -> {value = pathToPaste; onValueChanged();}, enabled: validClipboard},
					{label: "Clear", click: () -> {value = null; onValueChanged();}, enabled: value != null},
				]);
			}
		}

		bindDragOperations(this, dropOverlay);

		onOver = (e) -> {
			trace("aaa");
		}
	}

	public function bindDragOperations(element: HuiElement, overlay: HuiDropOverlay) {
		this.onAnyDragStart = HuiElement.emptyFuncDragVoid;
		this.onAnyDragEnd = HuiElement.emptyFuncDragVoid;
		this.onDragOver = HuiElement.emptyFuncDragVoid;
		this.onDragOut = HuiElement.emptyFuncDragVoid;
		this.onDrop = HuiElement.emptyFuncDragVoid;

		element.onAnyDragStart = (op: HuiDragOp) -> {
			if (validateDrop(op) != null) {
				overlay.acceptAny = true;
			}
		}

		element.onAnyDragEnd = (op: HuiDragOp) -> {
			overlay.reset();
		}

		element.onDragOver = (op:HuiDragOp) -> {
			if (validateDrop(op) != null) {
				overlay.accept = true;
				op.acceptDrop = true;
			}
		}

		element.onDragOut = (op:HuiDragOp) -> {
			overlay.accept = false;
		}

		element.onDrop = (op:HuiDragOp) -> {
			var path = validateDrop(op);
			if (path == null)
				return;
			this.value = path;
			onValueChanged();
		}
	}

	public function validateDrop(op: HuiDragOp) : Null<String> {
		if (op.type == HuiFileBrowser.fileDragOp) {
			var files : Array<String> = op.data;
			if (files.length != 1)
				return null;
			return validatePath(files[0]);
		}
		return null;
	}

	public function validatePath(v: String) : Null<String> {
		if (v == null)
			return null;
		if (v == "")
			return null;
		var absPath = StringTools.replace(v, "\\", "/");
		if (!haxe.io.Path.isAbsolute(v))
			absPath = hide.Ide.inst.getPath(v);
		try {
			if (!sys.FileSystem.exists(absPath))
				return null;
		} catch(e) {
			return null;
		}

		var ext = haxe.io.Path.extension(v);
		if (!allowedExtensions.contains(ext))
			return null;

		if (relative) {
			return hide.Ide.inst.getRelPath(absPath);
		}
		return absPath;
	}

	public function set_value(v: String) {
		dom.toggleClass("unset", v == null);
		if (v == null) {
			path.text = "--- Choose file ---";
		} else {
			path.text = v;
		}
		return value = v;
	}

	public dynamic function onValueChanged() {}
}

#end