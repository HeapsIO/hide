package hide.kit;

#if domkit

#if js
import hide.comp.cdb.DataFiles;
#end

class CDB extends Element {
	#if js
	var cdbCategory : Category;
	var curType : cdb.Sheet;

	override public function new(parent: Element, id: String) {
		super(parent, id);
		var types = DataFiles.getAvailableTypes();
		if (types.length <= 0)
			return;

		var prefab = @:privateAccess root.prefab;

		var typeName = prefab.getCdbType();
		if( typeName == null && prefab.props != null )
			return; // don't allow CDB data with props already used !

		var detached = root.editor.getSetting(Global, "detachedCdbEditor") ?? false;

		var options : Array<hide.kit.Select.SelectEntry> = [{value: null, label: "- No props -"}];
		for (type in types) {
			var id = DataFiles.getTypeName(type);
			options.push({value: id, label: id});
		}
		this.build(
			<category("CDB") id="cdbCategory" single-edit>
				<select(options) id="propTypeSelect" label="Type"/>
				<button("Detach editor") highlight={detached} onClick={() -> {root.editor.saveSetting(Global, "detachedCdbEditor", !detached); root.editor.rebuildInspector();}}/>
			</category>
		);

		this.cdbCategory = cdbCategory;
		propTypeSelect.value = null;
		curType = DataFiles.resolveType(typeName);
		if (curType != null)
			propTypeSelect.value = DataFiles.getTypeName(curType);

		propTypeSelect.onValueChange = (_) -> {
			var typeId = propTypeSelect.value;
			if (typeId == null) {
				prefab.props = null;
			} else {
				if (prefab.shared.currentPath.length == 0)
					throw "hurgh";
				prefab.props = hide.view.Prefab.makeCdbProps(prefab, prefab.shared.currentPath, DataFiles.resolveType(typeId));
			}
			root.editor.rebuildInspector();
		}
	}

	override function make() {
		super.make();

		#if js
		if (curType != null) {
			var prefab = @:privateAccess root.prefab;

			var detachable = new hide.comp.DetachablePanel();
			detachable.saveDisplayKey = "detachedCdb";

			var props = new hide.Element('<div></div>').appendTo(cdbCategory.nativeContent);
			var fileRef = prefab.shared.currentPath;
			detachable.element.appendTo(props);
			var ctx = Std.downcast(@:privateAccess (cast root.editor: hide.prefab.EditContext.HideJsEditContext2).ctx, hide.comp.SceneEditor.SceneEditorContext);

			var detached = root.editor.getSetting(Global, "detachedCdbEditor") ?? false;

			//group.toggleClass("cdb-large", cdbLarge == true);
			detachable.setDetached(detached);


			var editor = new hide.comp.cdb.ObjEditor(curType, ctx.editor.view.config, prefab.props, fileRef, detachable.element);
			editor.onScriptCtrlS = function() {
				ctx.editor.view.save();
			}
			editor.undo = ctx.editor.view.undo;
			editor.fileView = ctx.editor.view;

			editor.onChange = function(pname) {
				ctx.onChange(prefab, 'props.$pname');
				var obj3d = Std.downcast(prefab, hrt.prefab.Object3D);
				if( obj3d != null ) {
					obj3d.addEditorUI();
				}
			}
		}
		#end

	}
	#end
}

#end