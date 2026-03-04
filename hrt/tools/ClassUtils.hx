package hrt.tools;

class ClassUtils {
    public static function getInheritance<T>(startClass:Class<T>, baseClass: Class<T>) : Array<Class<T>> {
        var classes : Array<Class<T>> = [];
        var cl : Class<Dynamic> = startClass;
        while(true) {
            classes.unshift(cast cl);
            if (cl == baseClass)
                break;
            cl = Type.getSuperClass(cl);

        }
        return classes;
    }

	/**
		Returns the first common root for all classes instances in their class inheritance tree. See getCommonClass for more info
	**/
    public static function getCommonClassInstance<T>(instances:Array<T>, baseClass: Class<T>) : Class<T> {
		return getCommonClass([for (i in instances) Type.getClass(i)], baseClass);
    }

	/**
		Return the first common root for all classes in their inheritance tree (which should start at baseClass).
		For example if B extends A and C extends A, `getCommonClass([B,C], A)` returns A
		If D extends B, `getCommonClass([B,D], A)` returns B, and `getCommonClass([C,D], A)` returns A
	**/
	public static function getCommonClass<T>(classes: Array<Class<T>>, baseClass: Class<T>) : Class<T> {
        if (classes.length == 0)
            return baseClass;
        var commonDenominator : Array<Class<T>> = getInheritance(classes[0], baseClass);
        for (cl in classes) {
            var inheritance = getInheritance(cl, baseClass);
            var min = commonDenominator.length > inheritance.length ? inheritance.length : commonDenominator.length;
            var lastCommon = min-1;
            for (index in 0...min) {
                if (commonDenominator[index] != inheritance[index]) {
                    lastCommon = index-1;
                    break;
                }
            }
            commonDenominator = commonDenominator.slice(0, lastCommon+1);
        }
        return commonDenominator.pop();
	}
}