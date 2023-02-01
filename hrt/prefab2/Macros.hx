package hrt.prefab2;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;



class Macros {

    public static macro function getSerializableProps() : Expr {

        var serializableProps = [];
        var clRef = Context.getLocalClass();
        if (clRef == null)
            throw 'no class';
        var cl : ClassType = clRef.get();

        while (cl != null) {
            var fields = cl.fields.get();
            for (f in fields) {
                if (f.meta.has(":s")) {
                    serializableProps.push(f);
                }
            }
            if (cl.superClass != null) {
                cl = cl.superClass.t.get();
            } else {
                break;
            }
        }

        var serArrayExprs = [
            for (f in serializableProps) {
                var props : Array<ObjectField> = [];
                props.push({
                    field: "name",
                    expr: macro $v{f.name},
                });

                var meta : Array<ObjectField> = [];

                if (f.doc != null) {
                    meta.push({
                        field: "doc",
                        expr: macro $v{f.doc},
                    });
                }

                var ranges = f.meta.extract(":range");
                if (ranges.length > 0) {
                    var range = ranges[0];
                    if (range.params.length > 0) {
                        meta.push({
                            field: "range_min",
                            expr: range.params[0],
                        });
                    }
                    if (range.params.length > 1 ) {
                        meta.push({
                            field: "range_max",
                            expr: range.params[1],
                        });
                    }
                    if (range.params.length > 2 ) {
                        meta.push({
                            field: "range_step",
                            expr: range.params[2],
                        });
                    }
                }

                props.push({
                    field: "meta",
                    expr: {
                        expr: EObjectDecl(meta),
                        pos: Context.currentPos(),
                    }
                });


                var hasSetter = false;
                switch(f.kind) {
                    case FVar(_, AccCall):
                        hasSetter = true;
                    default:
                };

                props.push({
                    field: "hasSetter",
                    expr: macro $v{hasSetter},
                });

                var e : Expr = macro @:pos(f.pos) null;
                if (f.expr() != null) {
                    e = Context.getTypedExpr(f.expr());
                }
                var defVal = e.expr.match(EConst(_) | EBinop(_) | EUnop(_)) ? e : macro @:pos(f.pos) null;

                props.push({
                    field: "defaultValue",
                    expr: macro ($defVal:Dynamic),
                });

                {
                    expr: EObjectDecl(props),
                    pos: Context.currentPos(),
                }
            }
        ];

        return macro $a{serArrayExprs};
    }

    public static macro function Cast(e : Expr, typeToCast : String) : Expr {
        return macro Std.downcast(${e}, $i{typeToCast});
    }

    #if macro
    public static function buildPrefab():Array<Field> {
        var buildFields = Context.getBuildFields();

        var getSerFunc : Function = {
            args: [],
            expr: macro {
                if (serializablePropsFields == null)
                    serializablePropsFields = hrt.prefab2.Macros.getSerializableProps();
                return serializablePropsFields;
            },
        };

        buildFields.push({
            name: "serializablePropsFields",
            access: [AStatic],
            kind: FVar(macro : Array<hrt.prefab2.Prefab.PrefabField>, macro null),
            pos: Context.currentPos(),
        });

        var serFieldField : Field = {
            name: "getSerializablePropsStatic",
            doc: "Returns the list of props that have the @:s meta tag associated to them in this prefab type",
            access: [AStatic, APublic],
            kind: FFun(getSerFunc),
            pos: Context.currentPos(),
        }

        buildFields.push(serFieldField);

        var typeName = Context.getLocalClass().get().name;

        // Experiment for a typed createFromDynamic from the subclasses
        /*if (typeName != "Prefab") {
            var createFromDynamic : Function = {
                args: [
                    { name : "data", type : macro : Dynamic},
                    { name : "parent", type : macro : prefab.Prefab, value: macro null}
                ],
                expr: macro {
                    return prefab.Macros.Cast(${macro prefab.Prefab.createFromDynamic(data, parent)}, $v{typeName});
                }
            }

            buildFields.push({
                name: "createFromDynamic",
                access : [AStatic, APublic],
                pos : Context.currentPos(),
                kind: FFun(createFromDynamic)
            });
        }*/


        // allow child classes to return an object of their type when using make
        var make : Function = {
            args: [
                { name : "root", type : macro : hrt.prefab2.Prefab, value: macro null},
                { name : "o2d", type : macro :  h2d.Object, value: macro null},
                { name : "o3d", type : macro :  h3d.scene.Object, value: macro null}
            ],
            expr: macro {
                return hrt.prefab2.Macros.Cast(${macro makeInternal(root, o2d, o3d)}, $v{typeName});
            }
        }


        var access = [APublic];
        if (typeName != "Prefab")
            access.push(AOverride);


        
        buildFields.push({
            name: "make",
            access : access,
            pos : Context.currentPos(),
            kind: FFun(make)
        });

        return buildFields;
    }
    #end
}