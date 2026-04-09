package hrt.ui.tests;

#if hui

import hrt.ui.tests.Macros;

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
			Macros.init();

			testTryMake();
			testMakePrefabAction();
			actionRemovePrefabs();
			actionReparentPrefabs();
			actionReparentPrefabKeepTransform();

			Macros.writeSnapshotModifs();

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

			var data : Dynamic = {
				"name": obj.name,
				"type": Type.getClassName(Type.getClass(obj)),
				"children": children,
			};

			inline function round(f:Float) {
				return hxd.Math.round(f * 1000.0) / 1000.0;
			}

			var o3d = Std.downcast(obj, h3d.scene.Object);

			if (o3d != null) {
				data.x  = round(o3d.x);
				data.y  = round(o3d.y);
				data.z  = round(o3d.z);
				data.sx = round(o3d.scaleX);
				data.sy = round(o3d.scaleY);
				data.sz = round(o3d.scaleZ);
				var euler = o3d.getTransform().getEulerAngles();
				data.rx = round(euler.x);
				data.ry = round(euler.y);
				data.rz = round(euler.z);
			}

			var o2d = Std.downcast(obj, h2d.Object);

			if (o2d != null) {
				data.x = round(o2d.x);
				data.y = round(o2d.y);
				data.sx = round(o2d.scaleX);
				data.sy = round(o2d.scaleY);
				data.r = round(o2d.rotation);
			}
			return data;
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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:bR2aoR1R3R4y1:aghgoR1R3R4y1:cgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4R6R1R22R2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:agoR1R3R4y1:bgoR1R3R4y1:cgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R6R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:bR2aoR1R3R4y1:agoR1R3R4y1:cghgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4R6R1R22R2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:bgoR1R3R4y1:agoR1R3R4y1:cgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R6R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:cgoR1R3R4y1:agoR1R3R4y1:bgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R6R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:cgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghgoR1R3R4y1:bgoR1R3R4y1:aghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR15zR16zy1:zzR17i1R18i1y2:szi1y2:rxzy2:ryzy2:rzzghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R6R1R22R2aoR4R7R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R8R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R9R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R10R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zgoR4R11R1R22R2aoR4nR1R23R2ahR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zghR15zR16zR24zR17i1R18i1R25i1R26zR27zR28zggg');

			undo.undo();
			checkState(after2);

			undo.undo();
			checkState(after1);

			undo.undo();

			assert(!undo.canUndo());

			checkState(state);
		}
	}

	function dumpAbsTransform(prefab: hrt.prefab.Prefab) {
		var transform = prefab.findFirstLocal3d()?.getAbsPos();
		if (transform == null)
			return "";
		return haxe.Json.stringify(dumpMat(transform));
	}

	function dumpMat(m: h3d.Matrix) {
		inline function round(f:Float) {
			return hxd.Math.round(f * 1000.0) / 1000.0;
		}

		var scale = m.getScale();
		var euler = m.getEulerAngles();

		return {
			"x": round(m.tx),
			"y": round(m.ty),
			"z": round(m.tz),
			"rx": round(euler.x),
			"ry": round(euler.y),
			"rz": round(euler.z),
			"sx": round(scale.x),
			"sy": round(scale.y),
			"sz": round(scale.z)
		};
	}

	public function actionReparentPrefabKeepTransform() {
		var prefabData = {
			"children": [
				{"type": "box", "name": "a", "x": 1, "y":2, "z":3, "rotationX": 0.4, "rotationY": 0.6, "rotationZ": 0.8, "scaleX": 1.2, "scaleY": 1.2, "scaleZ": 1.2},
				{"type": "box", "name": "same", "x": 1, "y":2, "z":3, "rotationX": 0.4, "rotationY": 0.6, "rotationZ": 0.8, "scaleX": 1.2, "scaleY": 1.2, "scaleZ": 1.2},
				{"type": "box", "name": "identity"},
				{"type": "box", "name": "trans", "x": -1, "y":5, "z":10, "rotationX": 0.8, "rotationY": 0.2, "rotationZ": 0.1, "scaleX": 1.1, "scaleY": 1.1, "scaleZ": 1.1},

				{"type": "box", "name": "sub", "x": -2, "y":5, "z":3, "rotationX": 0.1, "rotationY": 0.3, "rotationZ": 0.7, "scaleX": 0.9, "scaleY": 0.9, "scaleZ": 0.9,
					 "children": [
					{"type": "box", "name": "subsub", "x": 1, "y":2, "z":3, "rotationX": 0.4, "rotationY": 0.6, "rotationZ": 0.8, "scaleX": 1.2, "scaleY": 1.2, "scaleZ": 1.2},
				]}
			]
		};

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("a");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([locate("a")], locate("same"), 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey4:samey1:xi1y1:yi2y1:zi3y6:scaleXd1.2y6:scaleYd1.2y6:scaleZd1.2y9:rotationXd0.4y9:rotationYd0.6y9:rotationZd0.8R1aoR2R3R4y1:aghgoR2R3R4y8:identitygoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1goR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7R1aoR2R3R4y6:subsubR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8ghghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4R15R2R28R1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R16R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R17R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R18R2R28R1aoR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("a");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([locate("a")], locate("identity"), 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey4:samey1:xi1y1:yi2y1:zi3y6:scaleXd1.2y6:scaleYd1.2y6:scaleZd1.2y9:rotationXd0.4y9:rotationYd0.6y9:rotationZd0.8goR2R3R4y8:identityR1aoR2R3R4y1:aR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8ghgoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1goR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7R1aoR2R3R4y6:subsubR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8ghghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R15R2R28R1aoR4R16R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R17R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R18R2R28R1aoR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("a");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([locate("a")], locate("trans"), 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey4:samey1:xi1y1:yi2y1:zi3y6:scaleXd1.2y6:scaleYd1.2y6:scaleZd1.2y9:rotationXd0.4y9:rotationYd0.6y9:rotationZd0.8goR2R3R4y8:identitygoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1R1aoR2R3R4y1:aR6d1.8356R7d-2.8189R8d-6.3185R9d1.0909R10d1.0909R11d1.0909R12d-0.4024R13d0.4097R14d0.6943ghgoR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7R1aoR2R3R4y6:subsubR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8ghghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R15R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R16R2R28R1aoR4R17R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6d1.836R7d-2.819R8d-6.318R23d1.091R24d1.091R30d1.091R31d-0.007R32d0.007R33d0.012goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R18R2R28R1aoR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("sub.subsub");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([a], prefab, 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey6:subsuby1:xd-1.1079y1:yd6.8063y1:zd5.6984y6:scaleXd1.08y6:scaleYd1.08y6:scaleZd1.08y9:rotationXd0.5042y9:rotationYd0.8986y9:rotationZd1.5011goR2R3R4y1:aR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8goR2R3R4y4:sameR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8goR2R3R4y8:identitygoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1goR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7ghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6d-1.108R7d6.806R8d5.698R23d1.08R24d1.08R30d1.08R31d0.009R32d0.016R33d0.026goR4R15R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R16R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R17R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R18R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("sub.subsub");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([a], locate("a"), 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey1:ay1:xi1y1:yi2y1:zi3y6:scaleXd1.2y6:scaleYd1.2y6:scaleZd1.2y9:rotationXd0.4y9:rotationYd0.6y9:rotationZd0.8R1aoR2R3R4y6:subsubR6d-1.7239R7d4.0449R8d2.2025R9d0.9R10d0.9R11d0.9R12d0.0969R13d0.3035R14d0.6989ghgoR2R3R4y4:sameR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8goR2R3R4y8:identitygoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1goR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7ghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4R15R2R28R1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6d-1.724R7d4.045R8d2.203R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R16R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R17R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R18R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

			while(undo.canUndo()) {
				undo.undo();
			}

			checkState(state);
		}

		{
			@:privateAccess prefabEditor.setPrefab(hrt.prefab.Prefab.createFromDynamic(prefabData, new hrt.prefab.ContextShared("huiPrefabEditorTests.prefab")));
			var state = dumpState();
			var a = locate("a");
			var aAbs = dumpAbsTransform(a);

			undo.run(prefabEditor.actionReparentPrefabs([a], locate("sub.subsub"), 0), true);
			// Check that the abs pos hasn't changed
			assert(aAbs == dumpAbsTransform(a));

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy8:childrenaoy4:typey3:boxy4:namey4:samey1:xi1y1:yi2y1:zi3y6:scaleXd1.2y6:scaleYd1.2y6:scaleZd1.2y9:rotationXd0.4y9:rotationYd0.6y9:rotationZd0.8goR2R3R4y8:identitygoR2R3R4y5:transR6i-1R7i5R8i10R9d1.1R10d1.1R11d1.1R12d0.8R13d0.2R14d0.1goR2R3R4y3:subR6i-2R7i5R8i3R9d0.9R10d0.9R11d0.9R12d0.1R13d0.3R14d0.7R1aoR2R3R4y6:subsubR6i1R7i2R8i3R9d1.2R10d1.2R11d1.2R12d0.4R13d0.6R14d0.8R1aoR2R3R4y1:aR6d1.8734R7d-4.5215R8d-2.4297R9d1.1111R10d1.1111R11d1.1111R12d-0.0932R13d-0.3047R14d-0.6984ghghghgy5:sceneoy6:root2doR4nR2y10:h2d.ObjectR1ahR6zR7zy2:sxi1y2:syi1y1:rzgy6:root3doR4nR2y16:h3d.scene.ObjectR1aoR4R5R2y14:h3d.scene.MeshR1aoR4nR2y21:h3d.scene.InteractiveR1ahR6zR7zR8zR23i1R24i1y2:szi1y2:rxzy2:ryzy2:rzzghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4R15R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zgoR4R16R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-1R7i5R8i10R23d1.1R24d1.1R30d1.1R31d0.014R32d0.003R33d0.002goR4R17R2R28R1aoR4R18R2R28R1aoR4R19R2R28R1aoR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6d1.873R7d-4.521R8d-2.43R23d1.111R24d1.111R30d1.111R31d-0.002R32d-0.005R33d-0.012goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i1R7i2R8i3R23d1.2R24d1.2R30d1.2R31d0.007R32d0.01R33d0.014goR4nR2R29R1ahR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zghR6i-2R7i5R8i3R23d0.9R24d0.9R30d0.9R31d0.002R32d0.005R33d0.012ghR6zR7zR8zR23i1R24i1R30i1R31zR32zR33zggg');

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

			undo.run(prefabEditor.actionRemovePrefabs([locate("a")]), true);

			assert(locate("a") == null);
			assert(locate("b") != null);

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:bgoR1R3R4y1:cgoR1R3R4y1:dR2aoR1R3R4y1:egoR1R3R4y1:fgoR1R3R4y1:gghghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR14zR15zy1:zzR16i1R17i1y2:szi1y2:rxzy2:ryzy2:rzzghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zgoR4R6R1R21R2aoR4nR1R22R2ahR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zgoR4R7R1R21R2aoR4R8R1R21R2aoR4nR1R22R2ahR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zgoR4R9R1R21R2aoR4nR1R22R2ahR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zgoR4R10R1R21R2aoR4nR1R22R2ahR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zgoR4nR1R22R2ahR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zghR14zR15zR23zR16i1R17i1R24i1R25zR26zR27zggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0gy5:sceneoy6:root2doy4:namenR1y10:h2d.Objecty8:childrenahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR6ahR7zR8zy1:zzR9i1R10i1y2:szi1y2:rxzy2:ryzy2:rzzggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0gy5:sceneoy6:root2doy4:namenR1y10:h2d.Objecty8:childrenahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR6ahR7zR8zy1:zzR9i1R10i1y2:szi1y2:rxzy2:ryzy2:rzzggg');

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

			Macros.assertSnapshot(dumpState(), 'oy6:prefaboy4:typeR0y8:childrenaoR1y3:boxy4:namey1:agoR1R3R4y1:bgoR1R3R4y1:cgoR1R3R4y1:dghgy5:sceneoy6:root2doR4nR1y10:h2d.ObjectR2ahy1:xzy1:yzy2:sxi1y2:syi1y1:rzgy6:root3doR4nR1y16:h3d.scene.ObjectR2aoR4R5R1y14:h3d.scene.MeshR2aoR4nR1y21:h3d.scene.InteractiveR2ahR12zR13zy1:zzR14i1R15i1y2:szi1y2:rxzy2:ryzy2:rzzghR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zgoR4R6R1R19R2aoR4nR1R20R2ahR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zghR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zgoR4R7R1R19R2aoR4nR1R20R2ahR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zghR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zgoR4R8R1R19R2aoR4nR1R20R2ahR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zghR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zghR12zR13zR21zR14i1R15i1R22i1R23zR24zR25zggg');

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