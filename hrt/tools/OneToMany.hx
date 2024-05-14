package hrt.tools;

typedef Left = Int;
typedef Right = Int;

/**
    Represent a collection of One -> Many relationship, i.e Multiple `Right` elements can point to an unique `Left` element.
    For example, a Parent -> Children relationship can be modeled with this, or a Output -> Input in a shadergraph.
**/
class OneToMany {
    var left : Map<Left, Map<Right, Bool>>;
    var right : Map<Right, Left>;

    public function new() {
        left = new Map<Left, Map<Right, Bool>>();
        right = new Map<Right, Left>();
    }

    /**
        Add a relation in the collection.
        If the right element already has a relation, it will be removed and replaced by this one.
    **/
    public function insert(l: Left, r: Right) {
        removeRight(r);
        var rights : Map<Right, Bool> = left.get(l);
        if (rights == null) {
            rights = [];
            left.set(l, rights);
        }
        rights.set(r, true);
        right.set(r, l);
    }

    public function removeRight(r: Right) : Null<Left> {
        var prevL = right.get(r);
        right.remove(r);
        if (prevL != null) {
            left.get(prevL).remove(r);
        }
        return prevL;
    }

    public function removeLeft(l: Left) {
        var prevRs = left.get(l);
        left.remove(l);
        if (prevRs != null) {
            for(r => _ in prevRs) {
                right.remove(r);
            }
        }
    }

    public function iterAll() : KeyValueIterator<Int, Iterator<Right>> {
        var iter = left.keyValueIterator();
        return {
            next: () -> {
                var n = iter.next();
                return {key: n.key, value: n.value.keys()};
            },
            hasNext: () -> {
                return iter.hasNext();
            }
        };
    }

    public function iterRights(l: Left) : Iterator<Right> {
        var rights = left.get(l);
        if (rights != null) {
            return rights.keys();
        }
        return {
            next: () -> {
                return -1;
            },
            hasNext: () -> {
                return false;
            }
        };
    }

    public function getLeft(r: Right) {
        return right.get(r);
    }

    public function clear() {
        right.clear();
        left.clear();
    }
}