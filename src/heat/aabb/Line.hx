package heat.aabb;

import heat.vector.*;

class Line {
    public var x1(default, null):Float;
    public var y1(default, null):Float;
    public var x2(default, null):Float;
    public var y2(default, null):Float;

    public function new(x1=0., y1=0., x2=0., y2=0.) {
        this.x1 = x1;
        this.y1 = y1;
        this.x2 = x2;
        this.y2 = y2;
    }

    public static function fromVectors(v1:Vector2<Float>, v2:Vector2<Float>):Line {
        return new Line(v1.x, v1.y, v2.x, v2.y);
    }
}