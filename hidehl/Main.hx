package hidehl;

class Main extends hxd.App {
	override function init() {
		new h3d.scene.CameraController(s3d);

		editorRoot = new hidehl.ui.HuiEditorRoot(s2d);

		editorStyle = new h2d.domkit.Style();
		editorStyle.load(hxd.Res.style.editor);
		editorStyle.addObject(editorRoot);
		editorStyle.allowInspect = true;
		editorStyle.inspectKeyCode = hxd.Key.CTRL;
		editorStyle.useSmartCache = true;

		var testPrefab = hxd.Res.test.testObject.load();
		var prefab = testPrefab.make(s3d);

		var g = new h3d.scene.Graphics(prefab.children[0].findFirstLocal3d());
		g.lineStyle(5, 0xFFFFFF, 1.0);
		g.moveTo(0,0,-1.0);
		g.lineTo(0,0,1.0);
		g.moveTo(0,-1.0,0);
		g.lineTo(0,1.0,0);
		g.moveTo(-1.0,0,0);
		g.lineTo(1.0,0,0);

		@:privateAccess
		{
			var selectedPrefabs = [prefab.children[0]];
			var commonClass = hrt.tools.ClassUtils.getCommonClass(selectedPrefabs, hrt.prefab.Prefab);
			var editContext = new hide.prefab.EditContext();
			{
				var proxyPrefab = Type.createInstance(commonClass, [null, new hrt.prefab.ContextShared()]);
				proxyPrefab.load(haxe.Json.parse(haxe.Json.stringify(selectedPrefabs[0].save())));
				var rootProperties = new hide.kit.KitRoot(null, null, proxyPrefab, editContext);
				editContext.kitRoot = rootProperties;
				proxyPrefab.edit2(editContext);
				for (i => select in selectedPrefabs) {
					var childProperties = new hide.kit.KitRoot(null, null, select, editContext);
					rootProperties.editedPrefabsProperties.push(childProperties);
					editContext.kitRoot = childProperties;
					select.edit2(editContext);
				}

				editContext.kitRoot = rootProperties;
				editContext.kitRoot.make();

				@:privateAccess editorRoot.panelRight.addChild(editContext.properties2.nativeContent);
			}
		}
	}

	override function update(dt: Float) {
		try {
			editorStyle.sync(dt);
		} catch (e) {
			trace(e);
		}
	}

	static function main() {
		hxd.res.Resource.LIVE_UPDATE = true;
		//hxd.Res.initLocal();
		new Main();
	}

	var editorRoot : hidehl.ui.HuiEditorRoot;
	var editorStyle : h2d.domkit.Style;
}
