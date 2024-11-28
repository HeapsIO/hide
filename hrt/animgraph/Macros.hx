package hrt.animgraph;

import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.Tools;

class Macros {
    macro static public function build():Array<Field> {
        var fields = Context.getBuildFields();

        #if editor
        var thisClass = Context.getLocalClass().get();
        var classPath = thisClass.pack.copy();
        classPath.push(thisClass.name);

        fields.push({
            name: "_build",
            access: [Access.AStatic],
            kind : FieldType.FVar(macro:Bool, macro hrt.animgraph.Node.register($v{thisClass.name}, ${classPath.toFieldExpr()})),
            pos: Context.currentPos(),
        });
        #end
        return fields;
    }
}