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

    /**
        Construct a new Rect from the specified position, dimensions, and offset.
    **/
    public function new(?pos:IVector2<Float>, ?dim:IVector2<Float>, ?offset:IVector2<Float>) {
        this.pos = pos == null ? new VectorFloat2(0, 0) : new VectorFloat2(pos.x, pos.y);
        this.dim = dim == null ? new VectorFloat2(0, 0) : new VectorFloat2(dim.x, dim.y);
        this.offset = offset == null ? new VectorFloat2(0, 0) : new VectorFloat2(offset.x, offset.y);
    }

    /**
        Build a new Rect from the specified components.
    **/
    public static inline function fromComponents(x=0., y=0., w=0., h=0., offsetX=0., offsetY=0.):Rect {
        return new Rect(new VectorFloat2(x, y), new VectorFloat2(w, h), 
            new VectorFloat2(offsetX, offsetY));
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
        return new Rect(pos, dim, offset);
    }

    /**
        Return a vector corresponding to the corner nearest to point.
    **/
    public inline function nearestCornerToPoint(point:IVector2<Float>):VectorFloat2 {
        return new VectorFloat2(Math.nearest(point.x, leftX, rightX), 
            Math.nearest(point.y, topY, bottomY));
    }

    /** 
        Compute the Minkowski sum of two rectangles, resulting in a new rectangle.
    **/
    public static inline function sum(r1:IRect, r2:IRect):Rect {
        return new Rect(new VectorFloat2(r1.leftX+r2.leftX, r1.topY+r2.topY),
            new VectorFloat2(r1.width+r2.width, r1.height+r2.height));
    }

    /**
        Compute the Minkowski difference between two rectangles, resulting in a new rectangle.
    **/
    public static inline function diff(r1:IRect, r2:IRect):Rect {
        return new Rect(new VectorFloat2(r2.leftX-r1.rightX, r2.topY-r1.bottomY),
            new VectorFloat2(r1.width+r2.width, r1.height+r2.height));
    }

    /**
        Compute the Minkowski difference between this rectangle and another rectangle.
    **/
    public inline function diffWith(other:IRect):Rect {
        return diff(this, other);
    }

    /**
        Return a new Rect occupying same area as this Rect but with a different offset position.
    **/
    public inline function offsetTo(offset:IVector2<Float>):Rect {
        return new Rect(new VectorFloat2(leftX+offset.x, topY+offset.y),
            dim, new VectorFloat2(offset.x, offset.y));
    }

    public inline function normalize():Rect {
        return offsetTo(new VectorFloat2(0,0));
    }

    public inline function centerOffset():Rect {
        return offsetTo(new VectorFloat2(width/2, height/2));
    }

    public inline function containsPoint(point:IVector2<Float>):Bool {
        return point.x - leftX >= Math.FP_ERR() 
            && point.y - topY >= Math.FP_ERR()
            && rightX - point.x >= Math.FP_ERR() 
            && bottomY - point.y >= Math.FP_ERR();
    }

    public inline function intersectsWithRect(other:IRect):Bool {
        return leftX < other.rightX && other.leftX < rightX
            && topY < other.bottomY && other.topY < bottomY;
    }

    public inline function toMutable():MRect {
        return new MRect(pos, dim, offset);
    }

    public static inline function fromMutable(mutable:MRect):Rect {
        return new Rect(mutable.pos, mutable.dim, mutable.offset);
    }
}