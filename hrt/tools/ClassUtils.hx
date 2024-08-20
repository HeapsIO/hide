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

    public static function getCommonClass<T>(instances:Array<T>, baseClass: Class<T>) : Class<T> {
        if (instances.length == 0)
            return baseClass;
        var commonDenominator : Array<Class<T>> = getInheritance(Type.getClass(instances[0]), baseClass);
        for (instance in instances) {
            var inheritance = getInheritance(Type.getClass(instance), baseClass);
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