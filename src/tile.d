module tile;

private {
    import std.string: toStringz, text;
    import std.exception: enforce;
    import std.conv: to;
    import std.math: PI, atan, sinh, pow;

    import gl3n.linalg: vec3;
    
    version(stb)
    {
        static assert(0, "stb support is not realized yet!");
    } 
    else
    version(SDLImage) 
    {
        import derelict.sdl2.sdl: SDL_Surface, SDL_FreeSurface, SDL_CreateRGBSurface, SDL_GetError
                                , SDL_PixelFormat, SDL_ConvertSurface, SDL_PIXELFORMAT_RGBA8888;
        import derelict.sdl2.image: IMG_Load;
        import derelict.opengl3.gl3: GLint, GLsizei, GLenum, GL_RGB, GL_RGBA, GL_UNSIGNED_BYTE;
    }
    else
    {
        static assert(0, "DevIL support is not realized yet!");
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

    static Tile loadFromFile(string filename) {
        Tile tile;

        version(stb) {        
            int x;
            int y;
            int comp;
            ubyte* data = stbi_load(toStringz(filename), &x, &y, &comp, 0);
            scope(exit) stbi_image_free(data);

            if(data is null) {
                throw new TextureException("Unable to load image: " ~ filename);
            }
            
            uint image_format;
            switch(comp) {
                case 3: image_format = GL_RGB; break;
                case 4: image_format = GL_RGBA; break;
                default: throw new TextureException("Unknown/Unsupported stbi image format");
            }

            tile = new Tile((float[]).init, (float[]).init, data, image_format, x, y, image_format, GL_UNSIGNED_BYTE);
        } else version (SDLImage) {
            // make sure the tileture has the right side up
            //thanks to tito http://stackoverflow.com/questions/5862097/sdl-opengl-screenshot-is-black 
            SDL_Surface* flip(SDL_Surface* surface) { 
                SDL_Surface* result = SDL_CreateRGBSurface(surface.flags, surface.w, surface.h, 
                                                           surface.format.BytesPerPixel * 8, surface.format.Rmask, surface.format.Gmask, 
                                                           surface.format.Bmask, surface.format.Amask); 
              
                ubyte* pixels = cast(ubyte*) surface.pixels; 
                ubyte* rpixels = cast(ubyte*) result.pixels; 
                uint pitch = surface.pitch;
                uint pxlength = pitch * surface.h; 
              
                assert(result != null); 

                for(uint line = 0; line < surface.h; ++line) {  
                    uint pos = line * pitch; 
                    rpixels[pos..pos+pitch] = pixels[(pxlength-pos)-pitch..pxlength-pos]; 
                } 

                return result; 
            }
            
            auto original = IMG_Load(filename.toStringz());
            
            enforce(original, new Exception("Error loading image " ~ filename ~ ": " ~ SDL_GetError().text));
            scope(exit) SDL_FreeSurface(original);

            // convert to our format
            auto fmt = SDL_PixelFormat(SDL_PIXELFORMAT_RGBA8888, null, 
                32, // bits per pixel
                4,  // bytes per pixel
                0, 0, 0, 0, // mask
            ); // TODO dirty hack, hardcoded value used

            auto flags = 0;
            auto surface = SDL_ConvertSurface(original, &fmt, flags);
            if(surface is null)
                throw new Exception("Error converting " ~ filename);
            
            enforce(surface.format.BytesPerPixel == 3 || surface.format.BytesPerPixel == 4, "With SDLImage Glamour supports loading images only with 3 or 4 bytes per pixel format.");
            auto image_format = GL_RGB;
            
            if (surface.format.BytesPerPixel == 4) {
              image_format = GL_RGBA;
            }
            
            auto flipped = flip(surface);
            scope(exit) SDL_FreeSurface(flipped);
            size_t size = surface.pitch*surface.h;
            ubyte[] data = new ubyte[](size);
            data[] = (cast(ubyte*)flipped.pixels)[0..size];
            tile = new Tile((float[]).init, (float[]).init, data, image_format, surface.w, surface.h, image_format, GL_UNSIGNED_BYTE);
        } else {
            /// DevIl is default choice
            ILuint id;
            ilGenImages(1, &id);
            scope(exit) ilDeleteImage(1, id);
            
            if(!ilLoadImage(toStringz(filename))) {
                throw new TextureException("Unable to load image: " ~ filename);
            }
            
            tile = new Tile((float[]).init, (float[]).init, ilGetData(), ilGetInteger(IL_IMAGE_FORMAT),
                                      ilGetInteger(IL_IMAGE_WIDTH), ilGetInteger(IL_IMAGE_HEIGHT),
                                      ilGetInteger(IL_IMAGE_FORMAT), ilGetInteger(IL_IMAGE_TYPE));
        }

        return tile;
    }
}
