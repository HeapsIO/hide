package hrt.prefab;

enum DiffResult {
	/**The two object are identical, don't save anything**/
	Skip;

	/**The two objects are different, save the result as diff**/
	Set(diff: Dynamic);
}

/**
	Utility class to get the difference between two dynamics

	There are two main functions : diff and apply, and they are reciprocal
	diff(A,B) = D
	apply(A,D) = B

	the diff has a special support for prefab if the diffPrefab function is used :
	the children array is handled as a special case, and prefabs that change type are
	fully serialized in the diff instead of just the delta

	Special fields prefixed by an @ can appear in the diff, they are as follow :

	@removed : an array of keys name that are present in A but were removed in B
	@index : in the prefab children data, indicate that this child has changed index between the A.children and B.children array

**/
class Diff {

	/**
		Add or Set a key/value pair to a DiffResult. If "diff" was a Skip, it will become a Set({key: value})
	**/
	public static function addToDiff(diff: DiffResult, key: String, value: Dynamic) : DiffResult{
		var v = switch(diff) {
			case Skip:
				var v = {};
				Reflect.setField(v, key, value);
				return Set(v);
			case Set(v):
				Reflect.setField(v, key, value);
				return diff;
		}
	}

	public static function deepCopy(v:Dynamic) : Dynamic {
		return haxe.Json.parse(haxe.Json.stringify(v));
	}

	/**
		Returns the difference of two values together
	**/
	public static function diff(originalValue: Dynamic, modifiedValue: Dynamic) : DiffResult {
		var originalType = Type.typeof(originalValue);
		var modifiedType = Type.typeof(modifiedValue);

		if (!originalType.equals(modifiedType)) {
			return Set(modifiedValue);
		}

		switch (modifiedType) {
			case TNull:
				// The only way we get here is if both types are null, so by definition they are both null and so there is no diff
				return Skip;
			case TInt | TFloat | TBool:
				if (originalValue == modifiedValue) {
					return Skip;
				}
			case TObject:
				return diffObject(originalValue, modifiedValue);
			case TClass(subClass): {
				switch (subClass) {
					case String:
						if (originalValue == modifiedValue) {
							return Skip;
						}
					case Array:
						return diffArray(originalValue, modifiedValue);
					default:
						throw "Can't diff class " + subClass;
				}
			}
			default:
				throw "Unhandled type " + modifiedType;
		}
		return Set(modifiedValue);
	}


	/**
		Same as diffObject, but handles `type` and `children` fields as a special case :
		children is serialized as an object with prefabName: diffPrefab(prefab)
		and if original.type != modified.type, the whole modified object is copied as is
		(because we consider that changing the type of a prefab in a diff means the prefab was destroyed then re-created)
	**/
	public static function diffPrefab(original: Dynamic, modified: Dynamic) : DiffResult {
		if (original == null || modified == null) {
			if (original == modified)
				return Skip;
			return Set(deepCopy(modified));
		}

		if (original.type != modified.type)
			return Set(deepCopy(modified));

		var result = diffObject(original, modified, ["children"]); // we could skip "type" but because we are sure that the type are equals they will never be serialised

		var resultChildren = {};

		var originalChildren = original.children ?? [];
		var modifiedChildren = modified.children ?? [];

		var childrenMap : Map<String, {originals: Array<Dynamic>, modifieds: Array<Dynamic>}> = [];

		for (index => child in originalChildren) {
			hrt.tools.MapUtils.getOrPut(childrenMap, child.name ?? "", {originals: [], modifieds: []}).originals.push({index: index, child: child});
		}

		for (index => child in modifiedChildren) {
			hrt.tools.MapUtils.getOrPut(childrenMap, child.name ?? "", {originals: [], modifieds: []}).modifieds.push({index: index, child: child});
		}

		for (name => data in childrenMap) {
			for (index in 0...hxd.Math.imax(data.originals.length, data.modifieds.length)) {
				var originalChild = data.originals[index];
				var modifiedChild = data.modifieds[index];
				var key = name;

				#if editor
				if ((originalChild?.child != null && originalChild.child.type == null) || (modifiedChild?.child != null && modifiedChild.child.type == null)) {
					throw "can't diff child that have a missing `type`";
				}
				#end
				if (index > 0)
					key += '@$index';

				var diff = diffPrefab(originalChild?.child, modifiedChild?.child);

				if (originalChild?.index != modifiedChild?.index) {
					if (modifiedChild?.index != null) {
						diff = addToDiff(diff, "@index", modifiedChild.index);
					}
				}

				switch(diff) {
					case Skip:
					case Set(value):
						Reflect.setField(resultChildren, key, value);
				}
			}
		}

		if (Reflect.fields(resultChildren).length > 0) {
			result = addToDiff(result, "children", resultChildren);
		}

		return result;
	}

	/**
		Returns the difference between two dynamic objects
	**/
	public static function diffObject(original: Dynamic, modified: Dynamic, skipFields: Array<String> = null) : DiffResult {
		skipFields ??= [];
		var result = {};
		var removedFields : Array<String> = [];

		if (original == null || modified == null) {
			if (original == modified)
				return Skip;
			return Set(deepCopy(modified));
		}

		// Mark fields as removed
		for (originalField in Reflect.fields(original)) {
			if (skipFields.contains(originalField))
				continue;

			if (!Reflect.hasField(modified, originalField)) {
				removedFields.push(originalField);
				continue;
			}
		}

		for (modifiedField in Reflect.fields(modified)) {
			if (skipFields.contains(modifiedField))
				continue;

			var originalValue = Reflect.getProperty(original, modifiedField);
			var modifiedValue = Reflect.getProperty(modified, modifiedField);

			switch(diff(originalValue, modifiedValue)) {
				case Skip:
				case Set(v):
					Reflect.setField(result, modifiedField, v);
			}
		}

		if (removedFields.length > 0) {
			Reflect.setField(result, "@removed", removedFields);
		}

		if (Reflect.fields(result).length == 0)
			return Skip;
		return Set(result);
	}

	/**
		Returns the difference between two arrays. If the arrays are found to be different, a full copy of
		modified will be returned as a Set()
	**/
	public static function diffArray(original: Array<Dynamic>, modified: Dynamic) : DiffResult {
		if (original.length != modified.length) {
			return Set(deepCopy(modified));
		}

		for (index in 0...original.length) {
			var originalValue = original[index];
			var modifiedValue = modified[index];

			switch(diff(originalValue, modifiedValue)) {
				case Set(_):
					// return the whole modified object when any field is different than the original
					return Set(deepCopy(modified));
				case Skip:
			}
		}
		return Skip;
	}

	/**
		Modifies `target` dynamic so `apply(a, diffObject(a, b)) == b`
	**/
	public static function apply(target: Dynamic, diff: Dynamic) : Dynamic {
		if (diff == null)
			return null;

		if (target == null)
			target = {};

		if (diff.type != null && diff.type != target.type) {
			return diff;
		}

		for (field in Reflect.fields(diff)) {
			if (field == "children")
			{
				var targetChildren = Reflect.field(target, "children") ?? [];
				var diffChildren = Reflect.field(diff, "children");

				for (fields in Reflect.fields(diffChildren)) {
					var diffChild = Reflect.field(diffChildren, fields);
					var name = fields;
					var split = name.split("@");
					var nthChild = 0;
					if (split.length == 2) {
						name = split[0];
						nthChild = Std.parseInt(split[1]);
					}

					var targetChild = null;
					var originalIndex = targetChildren.length; // if we don't found any children with the right name in the array, this will make sure we add the newly created children at the end of the array
					for (index => child in targetChildren) {
						// Can happen if a child get deleted, it is nulled and removed at the end
						if (child == null)
							continue;
						if (name == child.name) {
							if (nthChild == 0) {
								targetChild = child;
								originalIndex = index;
								break;
							} else {
								nthChild --;
							}
						}
					}

					// Remove child if null
					if (diffChild == null) {
						targetChildren[originalIndex] = null;
						continue;
					}

					// Skip diff children that don't have type if they don't
					// modify a prefab from target object (because we can't create a prefab without a type)
					if (targetChild == null && diffChild.type == null) {
							continue;
					}

					targetChildren[originalIndex] = apply(targetChild, diffChild);
				}

				// Reorder the targetChildren array based on @indexes.
				// if the @index point to a slot already taken, find the next free slot
				// This should ensure that arrays are somewhat coherent in bad situation like
				// the target children array has been modified since the last diff
				var finalChildren : Array<Dynamic> = [];
				for (index => child in targetChildren) {
					if (child == null) continue;
					var changedIndex = Reflect.field(child, "@index");
					var targetIndex = if (changedIndex != null) {
						Reflect.deleteField(child, "@index");
						changedIndex;
					} else {
						index;
					}
					while (finalChildren[targetIndex] != null) {
						targetIndex ++;
					}
					finalChildren[targetIndex] = child;
				}
				// If a prefab has been removed, it get inserted as a null in the childrenArray
				// we fix that here
				finalChildren = finalChildren.filter((f) -> f != null);

				Reflect.setField(target, "children", finalChildren);
				continue;
			}

			if (field == "@removed") {
				var removed = Reflect.field(diff, "@removed");
				for (field in (removed:Array<String>)) {
					Reflect.deleteField(target, field);
				}
				continue;
			}

			var targetValue = Reflect.getProperty(target, field);
			var diffValue = Reflect.getProperty(diff, field);

			var targetType = Type.typeof(targetValue);
			var diffType = Type.typeof(diffValue);

			switch (targetType) {
				case TNull | TInt | TFloat | TBool | TClass(Array) | TClass(String):
					Reflect.setField(target, field, diffValue);
				case TObject:
					apply(targetValue, diffValue);
				default:
					throw "unhandeld type " + targetType;
			}
		}
		return target;
	}
}