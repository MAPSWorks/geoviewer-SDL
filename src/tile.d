module tile;

private {
    import std.string: toStringz, text;
    import std.exception: enforce;
    import std.conv: to;
    import std.math: PI, atan, sinh, pow;
    import std.file: exists, mkdirRecurse, dirName, read;
    import std.path: buildNormalizedPath, absolutePath;
    import std.net.curl: download;

    import gl3n.linalg: vec3;
    import derelict.opengl3.gl3: GLint, GLsizei, GLenum, GL_RGB, GL_BGRA, GL_UNSIGNED_BYTE;
    import derelict.freeimage.freeimage: FreeImage_Load, FreeImage_Unload, FreeImage_GetWidth, FreeImage_GetHeight, FreeImage_GetBits,
                FreeImage_GetPitch, FreeImage_GetFileType, FreeImage_ConvertTo32Bits;
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

    static vec3 tileToGeodetic(vec3 tile) // lon, lat, zoom
    {
        uint zoom = to!uint(tile.z);
        double n = PI*(1 - 2.0 * tile.y / pow(2, zoom));

        vec3 geo;
        geo.x = to!double(tile.x * 360 / pow(2, zoom) - 180.0);
        geo.y = to!double(180.0 / PI * atan(sinh(n)));
        geo.z = zoom;

        return geo;
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
        ubyte[] pixels = FreeImage_GetBits(image)[0..size];
        auto tile = new Tile((float[]).init, (float[]).init, pixels, GL_RGB, w, h, GL_BGRA, GL_UNSIGNED_BYTE);

        return tile;
    }
}
