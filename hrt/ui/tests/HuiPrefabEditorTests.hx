package hrt.ui.tests;

#if hui

@:access(hrt.ui.HuiPrefabEditor)
class HuiPrefabEditorTests extends HuiView<{}> {
	static var SRC =
		<hui-prefab-editor-tests>
			<hui-prefab-editor id="prefab-editor"/>
		</hui-prefab-editor-tests>

	static var _ = HuiView.register("hui-prefab-editor-tests", HuiPrefabEditorTests);

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		// Needed so we can handle the errors ourselves
		prefabEditor.rethrowMakeErrors = true;

		// try {
			testTryMake();
			testMakePrefabAction();
		// } catch (e) {
		// 	hide.Ide.showError("Test failed " + e);
		// }
	}

	public function serializeScenes(s3d: h3d.scene.Object, s2d: h2d.Object) {
		var ser2d = {};

		function rec(obj: Dynamic) : Dynamic {
			var children : Array<Dynamic> = [];

			var objChildren : Array<Dynamic> = obj.children;
			if (objChildren != null) {
				for (child in @:privateAccess objChildren) {
					children.push(rec(child));
				}
			}

			return {
				"name": obj.name,
				"type": Type.getClassName(Type.getClass(obj)),
				"children": children,
			};
		}

		return {
			"root3d": rec(s3d),
			"root2d": rec(s2d),
		};
	}

	public function dumpScene() : Dynamic {
		@:privateAccess return serializeScenes(prefabEditor.prefab.shared.root3d, prefabEditor.prefab.shared.root2d);
	}

	public function checkDumpEqual(a: Dynamic, b: Dynamic) {
		var diff = hrt.prefab.Diff.diff(a, b);
		switch(diff) {
			case Skip:
				trace("No Diff");
			case Set(diff):
				trace("Difference found : ");
				trace(haxe.Json.stringify(diff, null, "\t"));
		}
	}

	public function testTryMake() {
		var prefabData = {
			"type": "prefab",
			"children": [
				{
					"type": "Object3D",
					"name": "bob",
				},
				{
					"type": "particle2D",
					"name": "Particle2D",
				}
			]
		};
		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared()));
		var a = dumpScene();
		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared()));
		var b = dumpScene();

		checkDumpEqual(a, b);
	}

	static var skipMakeTest : Array<Class<hrt.prefab.Prefab>>= [
		hrt.shgraph.ShaderGraph, // Should not be created manually
		hrt.texgraph.TexGraph, // Should not be created manually
		hrt.animgraph.AnimGraph, // Should not be created manually
		hrt.prefab.l3d.MeshGenerator, // Crashes on load ???
		hrt.prefab.fx.gpuemitter.MeshSpawn, // crashes on load
		hrt.prefab.l3d.modellibrary.ModelLibrary, // crashes on load
	];


	public function testMakePrefabAction() {
		var prefabData = {
			"type": "prefab",
			"children": [
				{"type": "box", "name": "node"}
			]
		};

		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
		var sceneStateBefore = dumpScene();

		var prefabStateBefore = @:privateAccess prefabEditor.prefab.serialize();

		var node = prefabEditor.prefab.locatePrefab("node");

		for (prefab in @:privateAccess hrt.prefab.Prefab.registry) {
			if (skipMakeTest.contains(prefab.prefabClass))
				continue;

			// add to root
			undo.run(prefabEditor.makePrefabAction(prefabEditor.prefab, 0, prefab.prefabClass), true);

			// add to node
			undo.run(prefabEditor.makePrefabAction(node, 0, prefab.prefabClass), true);


			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			// check if there is any difference in the scene after that
			var sceneStateAfter = dumpScene();
			var prefabStateAfter = @:privateAccess prefabEditor.prefab.serialize();


			var diff = hrt.prefab.Diff.diff(sceneStateBefore, sceneStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(prefab.prefabClass)} had some side effects on the scene', haxe.Json.stringify(diff, null, "\t"));
			}

			var diff = hrt.prefab.Diff.diff(prefabStateBefore, prefabStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(prefab.prefabClass)} had some side effects on the prefab', haxe.Json.stringify(diff, null, "\t"));
			}

			trace('${Type.getClassName(prefab.prefabClass)} ok');
		}
	}
}

class TestError extends haxe.Exception {
	var test: String;
	var reason: String;
	var dump : String;

	public function new(test, reason, dump) {
		super("Test failed :" + test + ":" + reason);
		this.test = test;
		this.reason = reason;
		this.dump = dump;
	}
}


#end