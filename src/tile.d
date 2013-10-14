module tile;

private {
    import std.string: toStringz, text, format;
    import std.exception: enforce;
    import std.conv: to;
    import std.math: PI, atan, sinh, pow, log, tan, cos, abs;
    import std.file: exists, mkdirRecurse, dirName, read, write;
    import std.path: buildNormalizedPath, absolutePath;
    import std.typecons: Tuple;
    import etc.c.curl: curl_easy_cleanup, curl_easy_init, curl_easy_perform, curl_easy_setopt, curl_easy_strerror, CurlOption,
                  CurlError, CurlGlobal, curl_global_cleanup, curl_global_init, CURLOPT_WRITEDATA;
    debug import std.stdio: writefln;

    import gl3n.linalg: vec3d;
    import derelict.opengl3.gl3: GLint, GLsizei, GLenum, GL_RGB, GL_BGRA, GL_UNSIGNED_BYTE;
    import derelict.freeimage.freeimage: FreeImage_Load, FreeImage_Unload, FreeImage_GetWidth, FreeImage_GetHeight, FreeImage_GetBits,
                FreeImage_GetPitch, FreeImage_GetFileType, FreeImage_ConvertTo32Bits, FIF_UNKNOWN;

  struct Chunk
  {
    void[] data;
  }

  extern(C) static size_t
  WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
  {
    size_t realsize = size * nmemb;
    auto mem = cast(Chunk *) userp;
    mem.data ~= contents[0..realsize];

    return realsize;
  }

  void download(string url, string filename)
  {
    Chunk chunk;

    /* init the curl session */
    auto curl_handle = curl_easy_init();

    /* specify URL to get */
    curl_easy_setopt(curl_handle, CurlOption.url, url.toStringz);

    /* send all data to this function  */
    curl_easy_setopt(curl_handle, CurlOption.writefunction, &WriteMemoryCallback);

    /* we pass our 'chunk' struct to the callback function */
    curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, cast(void *)&chunk);

    /* some servers don't like requests that are made without a user-agent
       field, so we provide one */
    curl_easy_setopt(curl_handle, CurlOption.useragent, "libcurl-agent/1.0".toStringz);

    /* get it! */
    auto res = curl_easy_perform(curl_handle);

    /* check for errors */
    if(res != CurlError.ok) {
      throw new TileException(format("curl_easy_perform() failed: %s\n",
              curl_easy_strerror(res).text));
    }
    else {
      write(filename, chunk.data);
      debug writefln("%d bytes retrieved", chunk.data.length);
    }

    /* cleanup curl stuff */
    curl_easy_cleanup(curl_handle);
  }
}

class TileException : Exception
{
  this(string msg)
  {
    super(msg);
  }
}

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

    static string download(uint zoom, uint tilex, uint tiley, string url, string local_path)
    {
        // wrap tile x, y
        auto n = pow(2, zoom);
        tilex = tilex % n;
        tiley = tiley % n;

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
            .download(url ~ zoom.text ~ "/" ~ tilex.text ~ "/" ~ filename, full_path);
        }
        import std.stdio;
        writeln(full_path);
        return full_path;
    }

    static Tile loadFromPng(string filename) {

        assert(exists(filename), filename ~ " not exists!");

        auto img_fmt = FreeImage_GetFileType(filename.toStringz, 0);
        assert(img_fmt != FIF_UNKNOWN, "FIF_UNKNOWN: " ~ filename);

        auto original = FreeImage_Load(img_fmt, filename.toStringz, 0);
        assert(original, "original loading failed");

        auto image = FreeImage_ConvertTo32Bits(original);
        FreeImage_Unload(original);
        assert(image, "original converting failed");

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

static this()
{
  auto ret = curl_global_init(CurlGlobal.all);
  assert(!ret);
}

static ~this()
{
  curl_global_cleanup();
}
