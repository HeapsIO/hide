package hrt.prefab2;


/**
    A ProtoPrefab is a prefab created by loading a file. It contains a ref to the actual prefab that can be used to call make on them. Each spawned prefab can link to a protoprefab through the `proto` field 
**/
class ProtoPrefab {
    public function new(prefab:Prefab, source:String) {
        this.prefab = prefab;
        this.source = source;
    }

    public var prefab : Prefab;
    public var source : String = "";
}