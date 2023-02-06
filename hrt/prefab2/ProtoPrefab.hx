package hrt.prefab2;


/**
    A ProtoPrefab is a prefab created by loading a file. It contains a ref to the actual prefab that can be used to call make on them. Each spawned prefab can link to a protoprefab through the `proto` field 
**/
typedef ProtoPrefab = {
    prefab : Prefab,
    cache : h3d.prim.ModelCache,
    ?source : String
}