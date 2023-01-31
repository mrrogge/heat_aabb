package heat.aabb;

using heat.AllCore;

interface IRect {
    public var pos(default, null):IVector2<Float>; 
    public var x(get, never):Float;
    public var y(get, never):Float;   
    public var leftX(get, never):Float;
    public var rightX(get, never):Float;
    public var topY(get, never):Float;
    public var bottomY(get, never):Float;
    public var dim(default, null):IVector2<Float>;
    public var width(get, never):Float;
    public var height(get, never):Float;
    public var offset(default, null):IVector2<Float>;
    public var offsetX(get, never):Float;
    public var offsetY(get, never):Float;
}