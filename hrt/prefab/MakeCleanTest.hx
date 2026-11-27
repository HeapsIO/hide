package hrt.prefab;

#if !release

typedef MakeCleanFailure = {
	/** Type of the prefab owning the failing value, null if unknown **/
	prefabType : Null<String>,
	path : String,
	message : String,
}

typedef MakeCleanResult = {
	file : String,
	/** Types of all the prefabs made from the file, references included **/
	types : Array<String>,
	/** Types without a registered class, not tested **/
	unknownTypes : Array<String>,
	/** Heaps tree values differing between two clones made once each, not compared between make 1 and make 2 **/
	unstableTreePaths : Array<String>,
	/** Prefab tree values differing between two clones made once each, not compared between make 1 and make 2 **/
	unstableStatePaths : Array<String>,
	failures : Array<MakeCleanFailure>,
}

private typedef DumpEntry = {
	repr : String,
	ref : Dynamic,
	owner : Null<String>,
	/** Inside a field reset by clean() : only compared by value **/
	reset : Bool,
	sceneObject : Bool,
}

private class Dump {
	public var entries : Map<String, DumpEntry> = [];
	public var order : Array<String> = [];

	public function new() {
	}

	function add(path : String, repr : String, ref : Dynamic, owner : Null<String>, reset = false, sceneObject = false) {
		entries.set(path, { repr : repr, ref : ref, owner : owner, reset : reset, sceneObject : sceneObject });
		order.push(path);
	}
}

/**
	Deep snapshot of the variables of a prefab tree. Prefabs and ContextShared reachable from it are dumped once each.
**/
private class StateDump extends Dump {
	static var fieldListCache : Map<String, Array<String>> = [];

	var visited = new haxe.ds.ObjectMap<Dynamic, String>();
	var queue : Array<{ node : Dynamic, name : String, owner : String }> = [];
	var owner : String;

	public function new(root : Prefab) {
		super();
		discover(root, "");
		while (queue.length > 0) {
			var n = queue.shift();
			if (Std.isOfType(n.node, Unknown))
				continue;
			owner = n.owner;
			dumpFields(n.node, n.name, false);
		}
	}

	function prefabName(p : Prefab, discoveryPath : String) : String {
		var parent = p.parent;
		var prefix = parent != null ? visited.get(parent) ?? prefabName(parent, discoveryPath) : (discoveryPath == "" ? "" : "{" + discoveryPath + "}");
		var index = parent != null ? parent.children.indexOf(p) : 0;
		return prefix + "/" + p.type + ":" + p.name + "#" + index;
	}

	/** Returns the name of the node `v`, queuing it for dump on its first discovery **/
	function discover(v : Dynamic, path : String) : String {
		var name = visited.get(v);
		if (name != null)
			return name;

		var isPrefab = Std.isOfType(v, Prefab);
		name = isPrefab ? prefabName(v, path) : "shared{" + path + "}";
		visited.set(v, name);
		queue.push({ node : v, name : name, owner : isPrefab ? (v : Prefab).type : owner });
		return name;
	}

	function getFieldList(cl : Class<Dynamic>, listName : String) : Array<String> {
		if (cl == null)
			return [];

		var key = Type.getClassName(cl) + ":" + listName;
		var list = fieldListCache.get(key);
		if (list != null)
			return list;

		var own : Array<String> = Reflect.field(cl, listName);
		list = getFieldList(Type.getSuperClass(cl), listName).concat(own ?? []);
		fieldListCache.set(key, list);
		return list;
	}

	function dumpFields(obj : Dynamic, path : String, reset : Bool) {
		var cl = Type.getClass(obj);
		var resetFields = getFieldList(cl, "__resetFields");
		var isShared = Std.isOfType(obj, ContextShared);

		var fields = Reflect.fields(obj);
		fields.sort(Reflect.compare);
		for (f in fields) {
			if (f == "__id__" || StringTools.startsWith(f, "hx__"))
				continue;
			if (isShared && (f == "editor" || f == "scene"))
				continue;
			dumpValue(Reflect.field(obj, f), path + "." + f, reset || resetFields.contains(f));
		}
	}

	function dumpValue(v : Dynamic, path : String, reset : Bool) {
		function addValue(repr : String, ?ref : Dynamic, sceneObject = false)
			add(path, repr, ref, owner, reset, sceneObject);

		// Returns false if `v` was already dumped
		function visit(repr : String) : Bool {
			var first = visited.get(v);
			if (first != null) {
				addValue("-> " + first, v);
				return false;
			}
			visited.set(v, path);
			addValue(repr, v);
			return true;
		}

		if (v == null) {
			addValue("null");
			return;
		}

		switch (Type.typeof(v)) {
			case TInt, TFloat, TBool:
				addValue(Std.string(v));
			case TFunction:
				addValue("function", v);
			case TEnum(e):
				addValue(e.getName() + "." + Type.enumConstructor(v));
				for (i => param in Type.enumParameters(v))
					dumpValue(param, path + "(" + i + ")", reset);
			case TObject:
				if (Std.isOfType(v, Class) || Std.isOfType(v, Enum)) {
					addValue("type", v);
				}
				else if (visit("{}")) {
					dumpFields(v, path, reset);
				}
			case TClass(c):
				var className = Type.getClassName(c);
				if (c == String) {
					addValue('"' + v + '"');
				}
				else if (Std.isOfType(v, Prefab) || Std.isOfType(v, ContextShared)) {
					// Trees only referenced by fields reset by clean() are not part of the prefab state
					if (reset)
						addValue(Std.isOfType(v, Prefab) ? "prefab " + (v : Prefab).type + ":" + (v : Prefab).name : className, v);
					else
						addValue("node " + discover(v, path), v);
				}
				else if (Std.isOfType(v, h3d.scene.Object) || Std.isOfType(v, h2d.Object)) {
					addValue(className, v, true);
				}
				else if (Std.isOfType(v, Array)) {
					var a : Array<Dynamic> = v;
					if (visit("Array(" + a.length + ")"))
						for (i => e in a)
							dumpValue(e, path + "[" + i + "]", reset);
				}
				else if (Std.isOfType(v, haxe.Constraints.IMap)) {
					var map : haxe.Constraints.IMap<Dynamic, Dynamic> = v;
					var keys = [for (k in map.keys()) k];
					var primitiveKeys = keys.length == 0 || Std.isOfType(keys[0], String) || Std.isOfType(keys[0], Int);
					if (primitiveKeys)
						keys.sort((a, b) -> Reflect.compare(Std.string(a), Std.string(b)));
					if (visit(className + "(" + keys.length + ")"))
						for (i => k in keys)
							dumpValue(map.get(k), path + "[" + (primitiveKeys ? Std.string(k) : "#" + i) + "]", reset);
				}
				else if (Std.isOfType(v, haxe.io.Bytes)) {
					addValue("Bytes(" + (v : haxe.io.Bytes).length + ")", v);
				}
				else if (className == null || ~/^(h3d|h2d|hxd|hxsl|js)\./.match(className)) {
					addValue(className, v);
				}
				else if (visit(className)) {
					dumpFields(v, path, reset);
				}
			default:
				// Native handles (HL abstracts) are boxed anew on each read : their pointers can't be compared
				addValue(Std.string(Type.typeof(v)));
		}
	}
}

/**
	Structural snapshot of a heaps tree
**/
private class TreeDump extends Dump {
	public var objects : Array<Dynamic> = [];
	public var objectPaths : Array<String> = [];
	public var objectOwners : Array<String> = [];

	/** `owners` maps the local3d/local2d of the made prefabs to their type **/
	public function new(root : Dynamic, owners : haxe.ds.ObjectMap<Dynamic, String>) {
		super();

		function round(f : Float) {
			return Std.string(Math.round(f * 10000) / 10000);
		}

		// Name based paths : an added or removed object doesn't shift the paths of its siblings
		function childKey(o : Dynamic, name : String, keyCounts : Map<String, Int>) {
			var key = name ?? Type.getClassName(Type.getClass(o)).split(".").pop();
			var n = keyCounts.get(key) ?? 0;
			keyCounts.set(key, n + 1);
			return key + "#" + n;
		}

		function addObject(o : Dynamic, path : String, owner : String) {
			objects.push(o);
			objectPaths.push(path);
			objectOwners.push(owner);
		}

		function dump3d(o : h3d.scene.Object, path : String, owner : String) {
			owner = owners.get(o) ?? owner;
			addObject(o, path, owner);

			var q = o.getRotationQuat();
			add(path, Type.getClassName(Type.getClass(o)), null, owner);
			add(path + ".name", o.name, null, owner);
			add(path + ".visible", Std.string(o.visible), null, owner);
			add(path + ".pos", [o.x, o.y, o.z].map(round).toString(), null, owner);
			add(path + ".scale", [o.scaleX, o.scaleY, o.scaleZ].map(round).toString(), null, owner);
			add(path + ".rot", [q.x, q.y, q.z, q.w].map(round).toString(), null, owner);

			var mesh = Std.downcast(o, h3d.scene.Mesh);
			if (mesh != null) {
				var prim = mesh.primitive;
				var primitive = prim == null ? "null" : Type.getClassName(Type.getClass(prim)) + " triangles=" + prim.triCount() + " vertices=" + prim.vertexCount();
				add(path + ".primitive", primitive, null, owner);
				for (i => m in mesh.getMaterials(false)) {
					var passes = [for (p in m.getPasses()) p.name + [for (s in p.getShaders()) Type.getClassName(Type.getClass(s))].toString()];
					add(path + ".material" + i, m.name + " blend=" + m.blendMode + " " + passes.join(" "), null, owner);
				}
			}

			var keyCounts = new Map<String, Int>();
			for (i in 0...o.numChildren) {
				var c = o.getChildAt(i);
				dump3d(c, path + "/" + childKey(c, c.name, keyCounts), owner);
			}
		}

		function dump2d(o : h2d.Object, path : String, owner : String) {
			owner = owners.get(o) ?? owner;
			addObject(o, path, owner);

			add(path, Type.getClassName(Type.getClass(o)), null, owner);
			add(path + ".name", o.name, null, owner);
			add(path + ".visible", Std.string(o.visible), null, owner);
			add(path + ".pos", [o.x, o.y].map(round).toString(), null, owner);
			add(path + ".scale", [o.scaleX, o.scaleY].map(round).toString(), null, owner);
			add(path + ".rot", round(o.rotation), null, owner);

			var keyCounts = new Map<String, Int>();
			for (i in 0...o.numChildren) {
				var c = o.getChildAt(i);
				dump2d(c, path + "/" + childKey(c, c.name, keyCounts), owner);
			}
		}

		if (Std.isOfType(root, h3d.scene.Object))
			dump3d(root, "", null);
		else if (Std.isOfType(root, h2d.Object))
			dump2d(root, "", null);
	}
}

/**
	Checks the make/clean contract on a prefab file :
	- the prefab tree variables after make() are the same after clean() + make()
	- clean() doesn't keep any scene object alive
	- a second make() builds an heaps tree equivalent to the first one, made of new objects, without modifying the first one
	- the cached prefab of the resource is not modified by clean() + make()
**/
class MakeCleanTest {

	var result : MakeCleanResult;
	var phase = "load";

	function new(file : String) {
		result = { file : file, types : [], unknownTypes : [], unstableTreePaths : [], unstableStatePaths : [], failures : [] };
	}

	/**
		Tests every .fx file of the current resource loader.
		`initShared` initializes the context of the tested instances before each make (e.g. the scene used to load resources in editor, or a root attached to a scene).
	**/
	public static function runAll(?initShared : ContextShared -> Void) : Array<MakeCleanResult> {
		var results = [];
		function rec(entry : hxd.fs.FileEntry) {
			if (entry.isDirectory) {
				for (e in entry)
					rec(e);
			}
			else if (entry.extension == "fx") {
				results.push(run(entry.path, initShared));
			}
		}
		rec(hxd.res.Loader.currentInstance.fs.getRoot());
		return results;
	}

	public static function run(file : String, ?initShared : ContextShared -> Void) : MakeCleanResult {
		var test = new MakeCleanTest(file);
		try {
			test.test(initShared);
		} catch (e : haxe.Exception) {
			test.fail(null, "", "exception in " + test.phase + " : " + e.details());
		}
		restoreRandom();
		return test.result;
	}

	function fail(prefabType : Null<String>, path : String, message : String) {
		result.failures.push({ prefabType : prefabType, path : path, message : message });
	}

	function test(initShared : ContextShared -> Void) {
		var template = hxd.res.Loader.currentInstance.load(result.file).to(hrt.prefab.Resource).load();

		// clean() resets the roots of the context : it is initialized before each make
		function makeTree(p : Prefab) {
			if (initShared != null)
				initShared(p.shared);
			return this.makeTree(p);
		}

		// Values differing between the trees of two clones don't depend on clean() : they are not compared between make 1 and make 2
		phase = "baseline";
		var cloneA = template.clone(), cloneB = template.clone();
		var unstableTreePaths = [for (d in diff(makeTree(cloneA).dump, makeTree(cloneB).dump, false)) d.path];
		var unstableStatePaths = [for (d in diff(new StateDump(cloneA), new StateDump(cloneB), false, null, false)) d.path];
		result.unstableTreePaths = unstableTreePaths;
		result.unstableStatePaths = unstableStatePaths;

		phase = "clone";
		var p = template.clone();

		phase = "make 1";
		var tree1 = makeTree(p);
		var state1 = new StateDump(p);
		var templateState1 = new StateDump(template);

		for (c in p.findAll(Prefab, null, true)) {
			var list = Std.isOfType(c, Unknown) ? result.unknownTypes : result.types;
			if (!list.contains(c.type))
				list.push(c.type);
		}

		phase = "clean 1";
		p.clean();
		var cleanState1 = new StateDump(p);
		phase = "make 2";
		var tree2 = makeTree(p);
		var tree1After = new TreeDump(tree1.objects[0], tree1.owners);
		var state2 = new StateDump(p);
		phase = "clean 2";
		p.clean();
		var cleanState2 = new StateDump(p);
		phase = "compare";
		var templateState2 = new StateDump(template);

		checkSceneObjects(cleanState1, "clean 1");
		checkSceneObjects(cleanState2, "clean 2");
		compare(state1, state2, "clean + make 2", false, unstableStatePaths);
		compare(templateState1, templateState2, "template", true);

		compare(tree1.dump, tree2.dump, "make 2 tree", false, unstableTreePaths);
		compare(tree1.dump, tree1After, "make 1 tree after make 2", false);

		var tree1Objects = new haxe.ds.ObjectMap<Dynamic, Bool>();
		for (o in tree1.dump.objects)
			tree1Objects.set(o, true);
		for (i => o in tree2.dump.objects)
			if (tree1Objects.exists(o))
				fail(tree2.dump.objectOwners[i], tree2.dump.objectPaths[i], "make 2 tree : object of make 1 reused");
	}

	function makeTree(p : Prefab) : { dump : TreeDump, owners : haxe.ds.ObjectMap<Dynamic, String>, objects : Array<Dynamic> } {
		seedRandom();
		p.make();
		restoreRandom();

		var owners = new haxe.ds.ObjectMap<Dynamic, String>();
		for (o in p.findAll(Object3D, null, true))
			if (o.local3d != null && !owners.exists(o.local3d))
				owners.set(o.local3d, o.type);
		for (o in p.findAll(Object2D, null, true))
			if (o.local2d != null && !owners.exists(o.local2d))
				owners.set(o.local2d, o.type);

		var root : Dynamic = p.shared.root3d ?? p.shared.root2d;
		return { dump : new TreeDump(root, owners), owners : owners, objects : [root] };
	}

	function checkSceneObjects(state : StateDump, step : String) {
		for (path in state.order) {
			var e = state.entries.get(path);
			if (e.sceneObject)
				fail(e.owner, path, step + " : scene object kept (" + e.repr + ")");
		}
	}

	/**
		`strict` also compares the pointers of the scene objects and of the values reset by clean()
	**/
	function compare(a : Dump, b : Dump, step : String, strict : Bool, ?ignoredPaths : Array<String>) {
		for (d in diff(a, b, strict, ignoredPaths))
			fail(d.prefabType, d.path, step + " : " + d.message);
	}

	/**
		The differences between two dumps, ignoring the values in `ignoredPaths` and under them.
		`strict` also compares the pointers of the scene objects and of the values reset by clean(), `pointers` false compares only the values
	**/
	static function diff(a : Dump, b : Dump, strict : Bool, ?ignoredPaths : Array<String>, pointers = true) : Array<MakeCleanFailure> {
		var diffs : Array<MakeCleanFailure> = [];

		function isUnder(path : String, parent : String) {
			if (!StringTools.startsWith(path, parent))
				return false;
			return path.length == parent.length || ".[(/".indexOf(path.charAt(parent.length)) >= 0;
		}

		// Paths are listed depth first : the values under an ignored path follow it
		var ignored = [for (p in ignoredPaths ?? []) p => true];
		var ignoredPath : String = null;
		function isIgnored(path : String) {
			if (ignoredPath != null && isUnder(path, ignoredPath))
				return true;
			if (!ignored.exists(path))
				return false;
			ignoredPath = path;
			return true;
		}

		// The values under a failing path are not reported
		var failedPath : String = null;
		function add(owner : String, path : String, message : String) {
			diffs.push({ prefabType : owner, path : path, message : message });
			failedPath = path;
		}

		for (path in a.order) {
			var ea = a.entries.get(path);
			var eb = b.entries.get(path);
			if ((failedPath != null && isUnder(path, failedPath)) || isIgnored(path))
				continue;

			if (eb == null)
				add(ea.owner, path, "removed (" + ea.repr + ")");
			else if (ea.repr != eb.repr)
				add(ea.owner, path, ea.repr + " -> " + eb.repr);
			else if (pointers && (strict || (!ea.reset && !ea.sceneObject)) && ea.ref != eb.ref)
				add(ea.owner, path, "pointer changed (" + ea.repr + ")");
		}

		failedPath = null;
		ignoredPath = null;
		for (path in b.order) {
			var eb = b.entries.get(path);
			if (isIgnored(path) || a.entries.exists(path) || (failedPath != null && isUnder(path, failedPath)))
				continue;
			add(eb.owner, path, "added (" + eb.repr + ")");
		}

		return diffs;
	}

	// Math.random (Std.random on HL) is replaced by a seeded generator during make() so that both makes get the same random values
	static var originalRandom : Dynamic;

	#if hl
	@:hlNative("std", "rnd_alloc") static function rndAlloc() : hl.Abstract<"hl_random"> {
		return null;
	}

	@:hlNative("std", "rnd_set_seed") static function rndSetSeed(r : hl.Abstract<"hl_random">, seed : Int) : Void {
	}
	#end

	static function seedRandom() {
		#if js
		if (originalRandom == null)
			originalRandom = js.Syntax.code("Math.random");
		var seed = 1.0;
		js.Syntax.code("Math.random = {0}", () -> {
			seed = (seed * 16807.0) % 2147483647.0;
			return seed / 2147483647;
		});
		#elseif hl
		if (originalRandom == null)
			originalRandom = @:privateAccess Std.rnd;
		var rnd = rndAlloc();
		rndSetSeed(rnd, 1);
		@:privateAccess Std.rnd = rnd;
		#end
	}

	static function restoreRandom() {
		#if js
		if (originalRandom != null)
			js.Syntax.code("Math.random = {0}", originalRandom);
		#elseif hl
		if (originalRandom != null)
			@:privateAccess Std.rnd = originalRandom;
		#end
	}
}

#end
