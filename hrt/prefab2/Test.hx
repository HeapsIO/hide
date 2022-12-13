package hrt.prefab2;

@:keep
class Test extends Prefab {
    /** This is a debug doc string **/
    @:s
    @:range(-10,10,1)
    public var a(default, set) : Int = 42;

    function set_a(val : Int) : Int {
        a = val;
        trace("a set to " + a);
        return a;
    }

    static var _ = Prefab.register("Test", Test);
}