package hrt.ui;

#if hui
@:access(hrt.prefab.Prefab)
class HuiInspector extends HuiElement {
	static var SRC =
		<hui-inspector>
		</hui-inspector>

	public function inspect(prefabs: Array<hrt.prefab.Prefab>, makeEditContext: (parent: hrt.prefab.EditContext2) -> hrt.prefab.EditContext2) {
		removeChildElements();

		if (prefabs.length == 0)
			return;

		var commonClass = hrt.tools.ClassUtils.getCommonClass(prefabs, hrt.prefab.Prefab);

		var isMultiEdit = prefabs.length > 1;
		var editPrefab : hrt.prefab.Prefab = if (isMultiEdit) {
			var p = Type.createInstance(commonClass, [null, new hrt.prefab.ContextShared(prefabs[0].shared.currentPath)]);
			p.load(haxe.Json.parse(haxe.Json.stringify(prefabs[0].save())));
			p;
		} else {
			prefabs[0];
		}

		var editContext = makeEditContext(null);
		var baseRoot = new hide.kit.KitRoot(null, null, editPrefab, editContext);
		@:privateAccess baseRoot.isMultiEdit = isMultiEdit;

		//@:privateAccess editContext.saveKey = Type.getClassName(commonClass);
		editContext.root = baseRoot;

		editPrefab.edit2(editContext);
		baseRoot.postEditStep();

		if (isMultiEdit) {
			for (i => prefab in prefabs) {
				var childEditContext = makeEditContext(editContext);
				//@:privateAccess childEditContext.saveKey = Type.getClassName(commonClass);
				var childRoot = new hide.kit.KitRoot(null, null, prefab, childEditContext);
				@:privateAccess childRoot.isMultiEdit = true;
				childEditContext.root = childRoot;
				prefab.edit2(childEditContext);
				childRoot.postEditStep();
			}
		}

		baseRoot.make();

		addChild(@:privateAccess baseRoot.native);
	}
}

#end