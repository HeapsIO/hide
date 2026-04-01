package hrt.ui.tests;

#if hui

@:access(hrt.ui.HuiPrefabEditor)
class HuiPrefabEditorTests extends HuiView<{}> {
	static var SRC =
		<hui-prefab-editor-tests>
			<hui-prefab-editor id="prefab-editor"/>
		</hui-prefab-editor-tests>

	static var _ = HuiView.register("hui-prefab-editor-tests", HuiPrefabEditorTests);

	public var prefab(get, never) : hrt.prefab.Prefab;

	inline function get_prefab() {
		return prefabEditor.prefab;
	}

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

	inline public function locate(path: String) : hrt.prefab.Prefab {
		return prefab.locatePrefab(path);
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
		@:privateAccess return serializeScenes(prefab.shared.root3d, prefab.shared.root2d);
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

		var prefabStateBefore = @:privateAccess prefab.serialize();

		var node = locate("node");

		for (entry in @:privateAccess hrt.prefab.Prefab.registry) {
			if (skipMakeTest.contains(entry.prefabClass))
				continue;

			// add to root
			undo.run(prefabEditor.makePrefabAction(prefab, 0, entry.prefabClass), true);

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			// check if there is any difference in the scene after that
			var sceneStateAfter = dumpScene();
			var prefabStateAfter = @:privateAccess prefab.serialize();

			var diff = hrt.prefab.Diff.diff(sceneStateBefore, sceneStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(entry.prefabClass)} had some side effects on the scene', haxe.Json.stringify(diff, null, "\t"));
			}

			var diff = hrt.prefab.Diff.diff(prefabStateBefore, prefabStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(entry.prefabClass)} had some side effects on the prefab', haxe.Json.stringify(diff, null, "\t"));
			}
		}

		for (entry in @:privateAccess hrt.prefab.Prefab.registry) {
			if (skipMakeTest.contains(entry.prefabClass))
				continue;

			// add to node
			undo.run(prefabEditor.makePrefabAction(node, 0, entry.prefabClass), true);

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			// check if there is any difference in the scene after that
			var sceneStateAfter = dumpScene();
			var prefabStateAfter = @:privateAccess prefab.serialize();


			var diff = hrt.prefab.Diff.diff(sceneStateBefore, sceneStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(entry.prefabClass)} had some side effects on the scene', haxe.Json.stringify(diff, null, "\t"));
			}

			var diff = hrt.prefab.Diff.diff(prefabStateBefore, prefabStateAfter);
			switch(diff) {
				case Skip:
				case Set(diff):
					throw new TestError("Make Prefab Action", 'Creating and removing prefab ${Type.getClassName(entry.prefabClass)} had some side effects on the prefab', haxe.Json.stringify(diff, null, "\t"));
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

			undo.run(prefabEditor.actionReparentPrefabs([locate("a")], locate("b"), 0), true);

			assert(locate("a") == null);
			assert(locate("b.a") != null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"b","children":[{"type":"box","name":"a"}]},{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([locate("a"), locate("b"), locate("c")], prefab, 0), true);

			assert(locate("a") != null);
			assert(locate("b") != null);
			assert(locate("c") != null);
			assert(prefab.children.indexOf(locate("a")) == 0);
			assert(prefab.children.indexOf(locate("b")) == 1);
			assert(prefab.children.indexOf(locate("c")) == 2);

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

			undo.run(prefabEditor.actionReparentPrefabs([locate("a"), locate("c")], locate("b"), 0), true);

			var b = locate("b");
			assert(locate("a") == null);
			assert(locate("c") == null);
			assert(locate("b.a") != null);
			assert(locate("b.c") != null);

			assert(prefab.children.indexOf(locate("b")) == 0);
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

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([locate("a"), locate("c")], prefab, prefab.children.indexOf(locate("b")) + 1), true);

			assert(prefab.children.indexOf(locate("b")) == 0);
			assert(prefab.children.indexOf(locate("a")) == 1);
			assert(prefab.children.indexOf(locate("c")) == 2);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"b"},{"type":"box","name":"a"},{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([locate("a"), locate("b"), locate("d")], prefab, prefab.children.indexOf(locate("c")) + 1), true);

			assert(prefab.children.indexOf(locate("c")) == 0);
			assert(prefab.children.indexOf(locate("a")) == 1);
			assert(prefab.children.indexOf(locate("b")) == 2);
			assert(prefab.children.indexOf(locate("d")) == 3);
			assert(locate("d.e") != null);
			assert(locate("d.f") != null);
			assert(locate("d.g") != null);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"c"},{"type":"box","name":"a"},{"type":"box","name":"b"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			// return to base state
			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			var state = dumpState();

			undo.run(prefabEditor.actionReparentPrefabs([locate("a")], prefab, prefab.children.indexOf(locate("c")) + 1), true);
			var after1 = dumpState();

			assert(prefab.children.indexOf(locate("a")) == prefab.children.indexOf(locate("c")) + 1);

			undo.run(prefabEditor.actionReparentPrefabs([locate("b")], prefab, prefab.children.indexOf(locate("c")) + 1), true);
			var after2 = dumpState();

			assert(prefab.children.indexOf(locate("b")) == prefab.children.indexOf(locate("c")) + 1);
			assert(prefab.children.indexOf(locate("a")) == prefab.children.indexOf(locate("c")) + 2);

			undo.run(prefabEditor.actionReparentPrefabs([locate("d")], prefab, prefab.children.indexOf(locate("c")) + 1), true);

			assert(prefab.children.indexOf(locate("d")) == prefab.children.indexOf(locate("c")) + 1);
			assert(prefab.children.indexOf(locate("b")) == prefab.children.indexOf(locate("c")) + 2);
			assert(prefab.children.indexOf(locate("a")) == prefab.children.indexOf(locate("c")) + 3);

			assertSnapshot(dumpState(), '{"prefab":{"type":"prefab","children":[{"type":"box","name":"c"},{"type":"box","name":"d","children":[{"type":"box","name":"e"},{"type":"box","name":"f"},{"type":"box","name":"g"}]},{"type":"box","name":"b"},{"type":"box","name":"a"}]},"scene":{"root2d":{"children":[],"name":null,"type":"h2d.Object"},"root3d":{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"c","type":"h3d.scene.Mesh"},{"children":[{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"e","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"f","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"g","type":"h3d.scene.Mesh"},{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"d","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"b","type":"h3d.scene.Mesh"},{"children":[{"children":[],"name":null,"type":"h3d.scene.Interactive"}],"name":"a","type":"h3d.scene.Mesh"}],"name":null,"type":"h3d.scene.Object"}}}');

			undo.undo();
			checkState(after2);

			undo.undo();
			checkState(after1);

			undo.undo();

			assert(!undo.canUndo());

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

			undo.run(prefabEditor.actionRemovePrefabs([locate("a")]), true);

			assert(locate("a") == null);
			assert(locate("b") != null);

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

			undo.run(prefabEditor.actionRemovePrefabs([locate("a")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([locate("b")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([locate("c")]), true);
			undo.run(prefabEditor.actionRemovePrefabs([locate("d")]), true);

			assert(locate("a") == null);
			assert(locate("b") == null);
			assert(locate("c") == null);
			assert(locate("d") == null);
			assert(locate("d.e") == null);
			assert(locate("d.f") == null);
			assert(locate("d.g") == null);

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
				locate("a"),
				locate("b"),
				locate("c"),
				locate("d")
			]), true);

			assert(locate("a") == null);
			assert(locate("b") == null);
			assert(locate("c") == null);
			assert(locate("d") == null);

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
				locate("d.e"),
				locate("d.f"),
				locate("d.g"),
			]), true);

			assert(locate("d.e") == null);
			assert(locate("d.f") == null);
			assert(locate("d.g") == null);
			assert(locate("a") != null);
			assert(locate("b") != null);
			assert(locate("c") != null);
			assert(locate("d") != null);

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
			prefab: @:privateAccess prefab.serialize(),
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
			Sys.stdout().writeString('Empty snapshot. Paste the following string into the second argument to set the current state as the valid one : \r\n');
			Sys.stdout().flush();
			Sys.stdout().writeString('\'$ser\'');
			Sys.stdout().flush();
			throw "Set snapshot test";
		}
		if (snapshotTest != ser) {
			Sys.stdout().writeString('Snapshot test failed. Had :\r\n');
			Sys.stdout().writeString(actualState);
			Sys.stdout().writeString('Wanted :\r\n');
			Sys.stdout().writeString(haxe.Json.parse(snapshotTest));
			Sys.stdout().flush();
			throw new TestError("Snapshot test failed", "Snapshot test failed", "");
		}
	}

	function checkState(prevDump: EditorDump) {
		var sceneStateAfter = dumpScene();
		var prefabStateAfter = @:privateAccess prefab.serialize();


		var diff = hrt.prefab.Diff.diff(prevDump.scene, sceneStateAfter);
		switch(diff) {
			case Skip:
			case Set(diff):
				trace("Diff failed");
				trace("had:");
				trace(prevDump.scene);
				trace("wanted:");
				trace(sceneStateAfter);
				trace("diff:");
				trace(diff);
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