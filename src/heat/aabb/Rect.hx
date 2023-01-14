package heat.aabb;

using heat.AllCore;

class Rect implements IRect {
    public var x(get, never):Float;
    inline function get_x():Float return pos.x;

    public var y(get, never):Float;
    inline function get_y():Float return pos.y;
    
    public var width(get, never):Float;
    inline function get_width():Float return dim.x;
    
    public var height(get, never):Float;
    inline function get_height():Float return dim.y;
    
    public var offsetX(get, never):Float;
    inline function get_offsetX():Float return offset.x;
    
    public var offsetY(get, never):Float;
    inline function get_offsetY():Float return offset.y;

    public var leftX(get, never):Float;
    inline function get_leftX():Float return x - offsetX;
    
    public var topY(get, never):Float;
    inline function get_topY():Float return y - offsetY;

    public var rightX(get, never):Float;
    inline function get_rightX():Float return leftX + width;

    public var bottomY(get, never):Float;
    inline function get_bottomY():Float return topY + height;

    public inline function topLeft():VectorFloat2 {
        return new VectorFloat2(leftX, topY);
    }

    public inline function topRight():VectorFloat2 {
        return new VectorFloat2(rightX, topY);
    }

    public inline function bottomLeft():VectorFloat2 {
        return new VectorFloat2(leftX, bottomY);
    }

    public inline function bottomRight():VectorFloat2 {
        return new VectorFloat2(rightX, bottomY);
    }
    
    public final pos:VectorFloat2;
    public final dim:VectorFloat2;
    public final offset:VectorFloat2;

    public function new(x=0., y=0., width=0., height=0., offsetX=0., offsetY=0.) {
        pos = new VectorFloat2(x, y);
        dim = new VectorFloat2(width, height);
        offset = new VectorFloat2(offsetX, offsetY);
    }

    public static inline function fromXYWH(x=0., y=0., w=0., h=0.):Rect {
        return new Rect(x, y, w, h, 0, 0);
    }

    public static inline function areSame(r1:IRect, r2:IRect):Bool {
        return r1.x == r2.x && r1.y == r2.y
            && r1.width == r2.width && r1.height == r2.height
            && r1.offsetX == r2.offsetX && r1.offsetY == r2.offsetY;
    }

    public static inline function areClose(r1:IRect, r2:IRect):Bool {
        return r1.x - r2.x <= Math.FP_ERR()
            && r1.y - r2.y <= Math.FP_ERR()
            && r1.width - r2.width <= Math.FP_ERR()
            && r1.height - r2.height <= Math.FP_ERR()
            && r1.offsetX - r2.offsetX <= Math.FP_ERR()
            && r1.offsetY - r2.offsetY <= Math.FP_ERR();
    }

    public static inline function areCloseToSameSpace(r1:IRect, r2:IRect):Bool {
        return r1.leftX - r2.leftX <= Math.FP_ERR()
            && r1.topY - r2.topY <= Math.FP_ERR()
            && r1.width - r2.width <= Math.FP_ERR()
            && r1.height - r2.height <= Math.FP_ERR();
    }
    
    public inline function clone():Rect {
        return new Rect(x, y, width, height, offsetX, offsetY);
    }

    public inline function nearestCornerTo(x:Float, y:Float):VectorFloat2 {
        return new VectorFloat2(Math.nearest(x, leftX, rightX), 
            Math.nearest(y, topY, bottomY));
    }

    /// Compute the Minkowski sum of two rectangles, resulting in a new rectangle.
    public static inline function sum(r1:IRect, r2:IRect):Rect {
        return new Rect(r1.leftX + r2.leftX,
            r1.topY + r2.topY,
            r1.width + r2.width,
            r1.height + r2.height,
            0, 0);
    }

    public static inline function diff(r1:IRect, r2:IRect):Rect {
        return new Rect(r2.leftX - r1.rightX,
            r2.topY - r1.bottomY,
            r1.width + r2.width,
            r1.height + r2.height,
            0, 0);
    }

    public inline function diffWith(other:IRect):Rect {
        return diff(this, other);
    }

    public inline function offsetTo(offsetX:Float, offsetY:Float):Rect {
        return new Rect(leftX + offsetX, topY + offsetY, width, height, offsetX, offsetY);
    }

    public inline function normalize():Rect {
        return offsetTo(0, 0);
    }

    public inline function centerOffset():Rect {
        return offsetTo(width/2, height/2);
    }

    public inline function containsPoint(x:Float, y:Float):Bool {
        return x - leftX >= Math.FP_ERR() && y - topY >= Math.FP_ERR()
            && rightX - x >= Math.FP_ERR() && bottomY - y >= Math.FP_ERR();
    }

    public inline function intersectsWithRect(other:IRect):Bool {
        return leftX < other.rightX && other.leftX < rightX
            && topY < other.bottomY && other.topY < bottomY;
    }
}