module tile;

private {
    import std.string: toStringz, format;
    import std.conv : text;
    import std.exception: enforce;
    import std.conv: to;
    import std.math: PI, atan, sinh, pow, log, tan, cos, abs;
    import std.file: exists, read, write;
    import std.typecons: Tuple;
    import etc.c.curl: curl_easy_cleanup, curl_easy_init, curl_easy_perform, curl_easy_setopt, curl_easy_strerror, CurlOption,
                  CurlError, CurlGlobal, curl_global_cleanup, curl_global_init, CURLOPT_WRITEDATA;
    debug import std.stdio: writefln;

    import gl3n.linalg: vec3d;
    import derelict.opengl: GLint, GLsizei, GLenum, GL_RGB, GL_BGRA, GL_UNSIGNED_BYTE;
    import imageformats;

  ubyte[] downloadToMemory(string url)
  {
    import requests;
    Request rq = Request();
    Response rs = rq.get(url);
    return rs.responseBody.data;
  }
}

enum tileSize = 256;

class TileException : Exception
{
  this(string msg)
  {
    super(msg);
  }
}

class Tile {

private:

    static ubyte[] downloadToMemorySeveralTimes(string url, int times)
    {
        ubyte[] data;
        auto count = 0;
        // try to download five times
        do
        {
            try
            {
                data = .downloadToMemory(url);
                break;
            }
            catch(Exception e)
            {
                debug writefln("%s. Retrying %d time...", e.msg, count + 1);
                count++;
            }
        } while(count < times - 1);

        // the last time do not ignore exceptions
        if(count >= times-1)
            data = .downloadToMemory(url);

        return data;
    }

    static Tile loadFromMemory(ubyte[] data) {
        auto png = read_png_from_mem(data, ColFmt.RGB);
        return new Tile((float[]).init, (float[]).init, png.pixels, GL_RGB, png.w, png.h, GL_RGB, GL_UNSIGNED_BYTE);
    }

public:
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

    /**
    *   takes tile coordinates, url to tile server and path to local cache
    * If requested tile doesn't exist in cache download it using given url.vertices
    * If tile exists in local cache load it from cache. If tile doesn't exist or url
    * is empty or downloading failed load nodata tile.
    */
    static Tile create(int x, int y, int zoom, string url, string path)
    {
        //assert(x > 0, "x is negative " ~ x.text);
        //assert(y > 0, "y is negative " ~ y.text);
        //assert(zoom > 0, "zoom is negative " ~ zoom.text);
        ubyte[] data;
        // if file exists load it
        if(exists(path))
            data = cast(ubyte[]) read(path);
        // if file doesn't exist but there is no url - load tile with label 'no data' to inform user
        else if(!url)
            data = cast(ubyte[]) read("./cache/nodata.png");
        // if file doesn't exist but there is url - download it
        else {
            //trying to download from openstreet map
            try
            {
                data = downloadToMemorySeveralTimes(url, 2);
            }
            catch(Exception e)
            {
                debug writefln("failed downloading: %s", url);
                data = cast(ubyte[]) read("./cache/nodata.png"); // TODO hardcoded path to nodata tile
            }
        }
        enforce(data, "empty data to be loaded as tile image");

        Tile tile;
        try
        {
            tile =  loadFromMemory(data);

            // save to cache if no error occurred
            write(path, data);
        }
        catch(Exception e)
        {
            debug writefln("failed loading from memory: %s", e.msg);
            debug writefln("\tx: %s, y: %s, zoom: %s, url: %s, path: %s", x, y, zoom, url, path);
            data = cast(ubyte[]) read("./cache/nodata.png");
            tile = loadFromMemory(data);
        }
        with(tile)
        {
            vertices.length = 8;
            auto ww = tile2world(x + 0, y + 0, zoom);
            vertices[0] = ww.x;
            vertices[1] = ww.y;

            ww = tile2world(x + 1, y + 0, zoom);
            vertices[2] = ww.x;
            vertices[3] = ww.y;

            ww = tile2world(x + 0, y + 1, zoom);
            vertices[4] = ww.x;
            vertices[5] = ww.y;

            ww = tile2world(x + 1, y + 1, zoom);
            vertices[6] = ww.x;
            vertices[7] = ww.y;

            tex_coords = [ 0.00, 0.00,  1.00, 0.00,  0.00, 1.00,  1.00, 1.00 ];
        }
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
    auto zoom = xyz.z.to!int;
    auto zoom_factor = pow(2, zoom);

    auto x = xyz.x / zoom_factor;
    auto y = xyz.y / zoom_factor;
    auto z = xyz.z;

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
    auto zoom_factor = pow(2, zoom);

    auto tile_x = xyz.x * zoom_factor;
    auto tile_y = xyz.y * zoom_factor;

    return vec3d(tile_x, tile_y, zoom);
}

auto world2tile(double x, double y, double z)
{
    return world2tile(vec3d(x, y, z));
}

unittest
{
  foreach(uint zoom; 0..18)
  {
    auto w = vec3d(.5, .5, zoom);
    auto t = world2tile(w);
    assert(w == tile2world(t), w.text ~ " " ~ tile2world(t).text);
  }
}
