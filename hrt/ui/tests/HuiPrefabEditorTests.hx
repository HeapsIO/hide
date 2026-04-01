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
			actionRemovePrefabs();
			actionReparentPrefabs();
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

		for (prefab in @:privateAccess hrt.prefab.Prefab.registry) {
			if (skipMakeTest.contains(prefab.prefabClass))
				continue;

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
		}
	}


	public function actionReparentPrefabs() {
		var prefabData = {
			"type": "prefab",
			"children": [
				{"type": "box", "name": "a"},
				{"type": "box", "name": "b"},
				{"type": "box", "name": "c"},
				{"type": "box", "name": "d", "children": [
					{"type": "box", "name": "e"},
					{"type": "box", "name": "f"},
					{"type": "box", "name": "g"},
				]}
			]
		};

		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([prefabEditor.prefab.locatePrefab("a")], prefabEditor.prefab.locatePrefab("b"), 0), true);

			assert(prefabEditor.prefab.locatePrefab("a") == null);
			assert(prefabEditor.prefab.locatePrefab("b.a") != null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"b","children":[{"type":"box","name":"a"}]},{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([prefabEditor.prefab.locatePrefab("a"), prefabEditor.prefab.locatePrefab("b"), prefabEditor.prefab.locatePrefab("c")], prefabEditor.prefab, 0), true);

			assert(prefabEditor.prefab.locatePrefab("a") != null);
			assert(prefabEditor.prefab.locatePrefab("b") != null);
			assert(prefabEditor.prefab.locatePrefab("c") != null);
			assert(prefabEditor.prefab.children.indexOf(prefabEditor.prefab.locatePrefab("a")) == 0);
			assert(prefabEditor.prefab.children.indexOf(prefabEditor.prefab.locatePrefab("b")) == 1);
			assert(prefabEditor.prefab.children.indexOf(prefabEditor.prefab.locatePrefab("c")) == 2);

			checkState(state);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"a"},{"type":"box","name":"b"},{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([prefabEditor.prefab.locatePrefab("a"), prefabEditor.prefab.locatePrefab("c")], prefabEditor.prefab.locatePrefab("b"), 0), true);

			var b = prefabEditor.prefab.locatePrefab("b");
			assert(prefabEditor.prefab.locatePrefab("a") == null);
			assert(prefabEditor.prefab.locatePrefab("c") == null);
			assert(prefabEditor.prefab.locatePrefab("b.a") != null);
			assert(prefabEditor.prefab.locatePrefab("b.c") != null);

			assert(prefabEditor.prefab.children.indexOf(prefabEditor.prefab.locatePrefab("b")) == 0);
			assert(b.children.indexOf(b.locatePrefab("a")) == 0);
			assert(b.children.indexOf(b.locatePrefab("c")) == 1);
			assert(b.children.length == 2);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"b","children":[{"type":"box","name":"a"},{"type":"box","name":"c"}]},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

	}


	public function actionRemovePrefabs() {
		var prefabData = {
			"type": "prefab",
			"children": [
				{"type": "box", "name": "a"},
				{"type": "box", "name": "b"},
				{"type": "box", "name": "c"},
				{"type": "box", "name": "d", "children": [
					{"type": "box", "name": "e"},
					{"type": "box", "name": "f"},
					{"type": "box", "name": "g"},
				]}
			]
		};

		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));

		// remove one
		{
			var state = dumpState();

			undo.run(prefabEditor.actionRemovePrefabs([prefabEditor.prefab.locatePrefab("a")]), true);

			assert(prefabEditor.prefab.locatePrefab("a") == null);
			assert(prefabEditor.prefab.locatePrefab("b") != null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"b"},{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}



		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
		// sequentially remove
		{
			var state = dumpState();

			undo.run(prefabEditor.actionRemovePrefabs([prefabEditor.prefab.locatePrefab("a")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([prefabEditor.prefab.locatePrefab("b")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([prefabEditor.prefab.locatePrefab("c")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([prefabEditor.prefab.locatePrefab("d")]), true);

			assert(prefabEditor.prefab.locatePrefab("a") == null);
			assert(prefabEditor.prefab.locatePrefab("b") == null);
			assert(prefabEditor.prefab.locatePrefab("c") == null);
			assert(prefabEditor.prefab.locatePrefab("d") == null);
			assert(prefabEditor.prefab.locatePrefab("d.e") == null);
			assert(prefabEditor.prefab.locatePrefab("d.f") == null);
			assert(prefabEditor.prefab.locatePrefab("d.g") == null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab"},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		// Remove many at the same time
		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
		{
			var state = dumpState();

			undo.run(prefabEditor.actionRemovePrefabs([
				prefabEditor.prefab.locatePrefab("a"),
				prefabEditor.prefab.locatePrefab("b"),
				prefabEditor.prefab.locatePrefab("c"),
				prefabEditor.prefab.locatePrefab("d")
			]), true);

			assert(prefabEditor.prefab.locatePrefab("a") == null);
			assert(prefabEditor.prefab.locatePrefab("b") == null);
			assert(prefabEditor.prefab.locatePrefab("c") == null);
			assert(prefabEditor.prefab.locatePrefab("d") == null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab"},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
		{
			var state = dumpState();

			undo.run(prefabEditor.actionRemovePrefabs([
				prefabEditor.prefab.locatePrefab("d.e"),
				prefabEditor.prefab.locatePrefab("d.f"),
				prefabEditor.prefab.locatePrefab("d.g"),
			]), true);

			assert(prefabEditor.prefab.locatePrefab("d.e") == null);
			assert(prefabEditor.prefab.locatePrefab("d.f") == null);
			assert(prefabEditor.prefab.locatePrefab("d.g") == null);
			assert(prefabEditor.prefab.locatePrefab("a") != null);
			assert(prefabEditor.prefab.locatePrefab("b") != null);
			assert(prefabEditor.prefab.locatePrefab("c") != null);
			assert(prefabEditor.prefab.locatePrefab("d") != null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"a"},{"type":"box","name":"b"},{"type":"box","name":"c"},{"type":"box","name":"d"}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}
	}

	function dumpState() {
		return {
			scene: dumpScene(),
			prefab: @:privateAccess prefabEditor.prefab.serialize(),
		};
	}

	function assert(condition: Bool) {
		if (!condition)
			throw "assert";
	}

	/**
		Check if actualState matches a previous known correct state.
		To setup this, first call `assertSnapshot(yourKnownValidState, "")`, then run your code.
		The function will assert and print into the console a string to replace the "" with that is a serialisation of `yourKnownValidState`.
	**/
	function assertSnapshot(actualState: Dynamic, snapshotTest: String) {
		var ser = haxe.Json.stringify(actualState);
		if (snapshotTest == "") {
			Sys.stdout().writeString('Empty snapshot. Paste the following string into the second argument to set the current state as the valid one : \n');
			Sys.stdout().writeString('\'$ser\'');
			Sys.stdout().flush();
			throw "Set snapshot test";
		}
		if (snapshotTest != ser) {
			Sys.stdout().writeString('Snapshot test failed. Had :\n');
			Sys.stdout().writeString(actualState);
			Sys.stdout().writeString('Wanted :\n');
			Sys.stdout().writeString(haxe.Json.parse(snapshotTest));
			Sys.stdout().flush();
			throw new TestError("Snapshot test failed", "Snapshot test failed", "");
		}
	}

	function checkState(prevDump: EditorDump) {
		var sceneStateAfter = dumpScene();
		var prefabStateAfter = @:privateAccess prefabEditor.prefab.serialize();


		var diff = hrt.prefab.Diff.diff(prevDump.scene, sceneStateAfter);
		switch(diff) {
			case Skip:
			case Set(diff):
				throw new TestError("Remove Prefab Action", '', haxe.Json.stringify(diff, null, "\t"));
		}

		var diff = hrt.prefab.Diff.diff(prevDump.prefab, prefabStateAfter);
		switch(diff) {
			case Skip:
			case Set(diff):
				throw new TestError("Make Prefab Action", '', haxe.Json.stringify(diff, null, "\t"));
		}
	}
}

typedef EditorDump = {
	scene: Dynamic,
	prefab: Dynamic,
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