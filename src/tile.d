module tile;

private {
    import std.string: toStringz, text;
    import std.exception: enforce;
    import std.conv: to;
    import std.math: PI, atan, sinh, pow, log, tan, cos;
    import std.file: exists, mkdirRecurse, dirName, read;
    import std.path: buildNormalizedPath, absolutePath;
    import std.net.curl: download;
    import std.typecons: Tuple;

    import gl3n.linalg: vec3d;
    import derelict.opengl3.gl3: GLint, GLsizei, GLenum, GL_RGB, GL_BGRA, GL_UNSIGNED_BYTE;
    import derelict.freeimage.freeimage: FreeImage_Load, FreeImage_Unload, FreeImage_GetWidth, FreeImage_GetHeight, FreeImage_GetBits,
                FreeImage_GetPitch, FreeImage_GetFileType, FreeImage_ConvertTo32Bits;
}

immutable tileSize = 256;

class Tile {
	float[] tex_coords;
	float[] vertices;
	GLint internal_format; 
	GLsizei width; 
	GLsizei height;
    GLenum format; 
    GLenum type;
    ubyte[] data;

    this(float[] tex_coords, float[] vertices, ubyte[] data, GLint internal_format, GLsizei width, GLsizei height,
                     GLenum format, GLenum type) {
    	this.tex_coords = tex_coords;
    	this.vertices = vertices;
    	this.data = data;
    	this.internal_format = internal_format;
    	this.width = width;
    	this.height = height;
    	this.format = format;
    	this.type = type;
    }

    static string downloadTile(uint zoom, uint tilex, uint tiley, string url, string local_path)
    {
        string absolute_path = absolutePath(local_path);
        auto filename = tiley.text ~ ".png";
        auto full_path = buildNormalizedPath(absolute_path, zoom.text, tilex.text, filename);

        if(!exists(full_path) && url) {
            //trying to download from openstreet map
            auto dir = dirName(full_path);
            if(!exists(dir))
                mkdirRecurse(dir); // creating directories may be thread unsafe if different threads try to create the same dir or different dirs that belong 
                                   // to the single parent dir that also is created by these threads. it's better to create dirs in one parent thread or you
                                   // should ensure there won't be collisions.
            download(url ~ zoom.text ~ "/" ~ tilex.text ~ "/" ~ filename, full_path);
        }

        return full_path;
    }

    static Tile loadFromPng(string filename) {
        
        auto img_fmt = FreeImage_GetFileType(filename.toStringz, 0);
        auto original = FreeImage_Load(img_fmt, filename.toStringz, 0);
     
        auto image = FreeImage_ConvertTo32Bits(original);
        FreeImage_Unload(original);
     
        int w = FreeImage_GetWidth(image);
        int h = FreeImage_GetHeight(image);
     
        size_t size = FreeImage_GetPitch(image) * h;
        ubyte[] pixels;
        pixels.length = size;
        // copy data to our own buffer and free buffer that is owned by FreeImage
        pixels[] = FreeImage_GetBits(image)[0..size];
        FreeImage_Unload(image);
        auto tile = new Tile((float[]).init, (float[]).init, pixels, GL_RGB, w, h, GL_BGRA, GL_UNSIGNED_BYTE);

        return tile;
    }
}

/**
 * geo.x - tile longitude
 * geo.y - tile latitude
 * geo.z - tile zoom
 */
auto geodetic2tile(vec3d geo) {
    vec3d t;
    int zoom = to!int(geo.z);
    t.x = to!double((geo.x + 180.0) / 360.0 * (1 << zoom));
    t.y = to!double((1.0 - log(tan(geo.y * PI / 180.0) + 
                                       1.0 / cos(geo.y * PI / 180.0)) / PI) / 2.0 * (1 << zoom));
    t.z = zoom;
    
    return t;
}

auto geodetic2tile(double lon, double lat, double zoom)
{
    auto geo = vec3d(lon, lat, zoom);
    return geodetic2tile(geo);
}

unittest {
    auto right_answer = vec3d(15, 4, 4);
    auto test_value = geodetic2tile(177, 65, 4); // Анадырь
    test_value.x = test_value.x.to!uint;
    test_value.y = test_value.y.to!uint;
    assert(right_answer == test_value, test_value.text);

    right_answer = vec3d(1, 4, 4);
    test_value = geodetic2tile(-150, 61, 4); // Anchorage
    test_value.x = test_value.x.to!uint;
    test_value.y = test_value.y.to!uint;
    assert(right_answer == test_value, test_value.text);
}

/**
 * tile.x - tile x
 * tile.y - tile y
 * tile.z - tile zoom
 */
auto tile2geodetic(vec3d tile) // lon, lat, zoom
{
    auto zoom = to!int(tile.z);
    double n = PI*(1 - 2.0 * tile.y / pow(2, zoom));

    vec3d geo;
    geo.x = to!double(tile.x * 360 / pow(2, zoom) - 180.0);
    geo.y = to!double(180.0 / PI * atan(sinh(n)));
    geo.z = zoom;

    return geo;
}

auto tile2geodetic(double tile_x, double tile_y, double zoom) 
{
    auto tile = vec3d(tile_x, tile_y, zoom);
    return tile2geodetic(tile);
}

/**
* Преобразует координаты тайла в мировые координаты (2D)
*
*/
auto tile2world(vec3d xyz)
{
    auto n = pow(2, xyz.z.to!int);
    
    auto x = xyz.x * tileSize;
    auto y = (/*n - */xyz.y) * tileSize;  // invert y
    auto z = 0; // 2D

    return vec3d(x, y, z);
}

auto tile2world(double tile_x, double tile_y, double zoom)
{
    return tile2world(vec3d(tile_x, tile_y, zoom));
}

/**
* Преобразует мировые координаты в тайловые с зумом zoom
* (zoom не участвует в преобразовании и напрямую передается
* в результат)
*/
auto world2tile(vec3d xyz)
{
    auto zoom = xyz.z.to!int;
    auto n = pow(2, zoom);
    
    auto tile_x = xyz.x / tileSize;
    auto tile_y = xyz.y / tileSize;

    return vec3d(tile_x, /*n - */tile_y, zoom); // invert y
}

auto world2tile(double x, double y, double z)
{
    return world2tile(vec3d(x, y, z));
}

class TileStorage
{
    /// using camera creates list of tiles that 
    /// are viewable from the camera at the moment
    Tuple!(int, "x", int, "y", int, "zoom")[] getViewableTiles(Camera)(Camera cam)
    {
        int zoom = 3;
        int n = pow(2, zoom);
        
        Tuple!(int, "x", int, "y", int, "zoom")[] result;
        result.length = n * n;
        foreach(uint y; 0..n)
            foreach(uint x; 0..n)
                result[y*n + x] = Tuple!(int, "x", int, "y", int, "zoom")(x, y, zoom);

        return result;
    }
}
