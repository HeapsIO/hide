package hrt.prefab;

enum DiffResult {
	Skip;
	Set(value: Dynamic);
}

class Diff {
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

			switch(diffValue(originalValue, modifiedValue)) {
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

	public static function diffArray(original: Array<Dynamic>, modified: Dynamic) : DiffResult {
		if (original.length != modified.length) {
			return Set(deepCopy(modified));
		}

		for (index in 0...original.length) {
			var originalValue = original[index];
			var modifiedValue = modified[index];

			switch(diffValue(originalValue, modifiedValue)) {
				case Set(_):
					// return the whole modified object when any field is different than the original
					return Set(deepCopy(modified));
				case Skip:
			}
		}
		return Skip;
	}

	public static function diffValue(originalValue: Dynamic, modifiedValue: Dynamic) : DiffResult {
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
		Modifies `target` dynamic so `apply(a, diff(a, b)) == b`
	**/
	public static function apply(target: Dynamic, diff: Dynamic) {
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

				var finalChildren = [];

				for (index => child in targetChildren) {
					finalChildren[index] = child;
				}

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
					var finalIndex = 0;
					for (index => child in targetChildren) {
						if (name == child.name) {
							if (nthChild == 0) {
								targetChild = child;
								finalIndex = index;
								break;
							} else {
								nthChild --;
							}
						}
					}

					// Remove child if null
					if (diffChild == null) {
						finalChildren.splice(finalIndex, 1);
						continue;
					}

					var modifiedChild = apply(targetChild, diffChild);
					finalIndex = Reflect.field(diffChild, "@index") ?? finalIndex;

					finalChildren[finalIndex] = modifiedChild;
				}

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

			if (field.charAt(0) == "@") {
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