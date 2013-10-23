module backend;

import std.concurrency: spawn, send, prioritySend, Tid, thisTid, receiveTimeout, receiveOnly, spawnLinked, OwnerTerminated, LinkTerminated, Variant;
import std.datetime: dur;
import std.stdio: stderr, writeln, writefln;
import std.exception: enforce;
import std.conv: text;
import std.math: pow;
import std.container: DList;
import std.typecons: Tuple;
import std.file: exists, mkdirRecurse, dirName, read, write;
import std.path: buildNormalizedPath, absolutePath;

import derelict.freeimage.freeimage: DerelictFI;

import tile: Tile, tile2world;

// backend получает от фронтенда пользовательский ввод, обрабатывает данные
// в соотвествии с бизнес-логикой и отправляет их фронтенду
class BackEnd
{
private:

	enum childFailed = "child failed";
	enum tileLoadingFailed = "tile loading failed";

	string url_, cache_path_;

    static Tuple!(string, "path", string, "url") makeFullPathAndUrl(int x, int y, int zoom, string url, string local_path)
    {
        // wrap tile x, y
        auto n = pow(2, zoom);
        x = x % n;
        y = y % n;

        string absolute_path = absolutePath(local_path);
        auto filename = y.text ~ ".png";

        auto full_path = buildNormalizedPath(absolute_path, zoom.text, x.text, filename);
        auto full_url = url ? url ~ "/" ~ zoom.text ~ "/" ~ x.text ~ "/" ~ filename : "";
        return Tuple!(string, "path", string, "url")(full_path, full_url);
    }

    // parent is Tid of parent, worker_id is unique identificator of child
    static void downloading(Tid parent, int worker_id)
    {
        int zoom, x, y;
        x = y = zoom = -1;
        auto running = true; // define it to let delegates below stop thread executing if needed
        size_t current_batch_id;  // current batch tile shows id of the last batch processed

        // let to set specific tile batch id to skip tile batch is being processed before
        // processing will be complete
        void handleTileBatchId(size_t batch_id)
        {
            current_batch_id = batch_id;
        }

        // get tile description to download
        void handleTileRequest(size_t batch_id, int local_x, int local_y, int local_zoom, string url, string path)
        {
            // ignore tile of previous requests
            if(batch_id < current_batch_id) return;

            // use outer variable, see below catch construction
            current_batch_id = batch_id;
            x = local_x;
            y = local_y;
            zoom = local_zoom;
            version(none)
            {
                import std.random;
                auto i = uniform(0, 15);
                if(i == 10)
                    throw new Error("error imitation");
            }

            auto tile = Tile.create(x, y, zoom, url, path);
            parent.send(batch_id, cast(shared) tile, x, y, zoom);
            x = y = zoom = -1;
        }

        try
        {
            DerelictFI.load();
            scope(exit) DerelictFI.unload();

            while(running)
            {
                auto msg = receiveTimeout(dur!"msecs"(100), // because this function is single in loop set delay big enough to lower processor loading
                    &handleTileBatchId,
                    &handleTileRequest,
                    (OwnerTerminated ot)
                    {
                        // normal exit
                        running = false;
                    },
                    (Variant any)
                    {
                        stderr.writeln("Unknown message received by worker thread: " ~ any.type.text);
                    }
                );
            }
        }
        catch(Throwable t)
        {
            debug writefln("worker id %s, throwable: %s", worker_id, t.msg);
            debug writefln("on throwing batch id: %s, x: %s, y: %s, zoom: %s", current_batch_id, x, y, zoom);
            // complain to parent that something gone wrong
            parent.send(worker_id, current_batch_id, x, y, zoom);
        }
    }

	static run(string url, string cache_path)
	{
		enum maxWorkers = 8;
	    Tid[maxWorkers] workers;
	    uint current_worker;
	    size_t current_batch_id;
	    shared(Tile)[int][int][int] tile_cache;  // x, y, zoom
        int[int][int][int] failed_tile_cache; // x, y, zoom - stores count of attempts of tile downloading to avoid infinite fail

	    alias Tuple!(int, "x", int, "y", int, "zoom") TileDescription;
		DList!TileDescription tile_cache_content; // list of tile that cache contains
		size_t tile_cache_size; // current size of tile cache
		enum maxTileCacheSize = 256;

		auto frontend = receiveOnly!Tid();
		enforce(frontend != Tid.init, "Wrong frontend tid.");
		enforce(frontend != thisTid, "frontend and backend shall be running in different threads!");

        // if x, y and zoom don't equal to -1 it means tile loading failed, child thread crashes
        // and parent can relaunch thread with the same zoom, x and y values to try loading once again.
        // If x, y or zoom equals to -1 it means that thread has crashed before valid x, y or zoom
        // recieving and parent can only restart thread without relaunching tile downloading
        void respawnWorker(int worker_id, size_t batch_id, int x, int y, int zoom)
        {
            enum maxDownloadingAttempt = 2;

            enforce(worker_id >= 0 && worker_id < maxWorkers);
            workers[worker_id] = spawnLinked(&downloading, thisTid, worker_id);
            debug writefln("worker respawned, id: %s", worker_id);

            // if batch is old or there is no valid info skip relaunching failed task
            if(batch_id < current_batch_id || x != -1 || y != -1 || zoom != -1)
                return;

            // check how many time we tried to download this tile
            int count;
            auto layerx = failed_tile_cache.get(x, null);
            if(layerx !is null)
            {
                auto layerxy = layerx.get(y, null);
                if(layerxy !is null)
                    count = layerxy.get(zoom, 0);
            }
            failed_tile_cache[x][y][zoom]++;

            // if count is above threshold give up downloading the tile
            if(count > maxDownloadingAttempt)
                return;

            string local_url, local_cache_path; // presents url and cache path for the current tile
            // if count is equal to threshold try to use nodata tile
            if(count == maxDownloadingAttempt)
            {
                // empty url and path to force downloading nodata tile
                local_url = "";
                local_cache_path = "";
            }
            else
            {
                local_url = url;
                local_cache_path = cache_path;
            }

            workers[worker_id].send(batch_id, x, y, zoom, local_url, local_cache_path);
            debug writefln("tile downloading restarted, x: %s, y: %s, zoom: %s", x, y, zoom);
        }

        // set new tile batch with batch_id
        void setNewTileBatch(size_t batch_id)
        {
            current_batch_id = batch_id;
            foreach(w; workers)
            {
                w.prioritySend(batch_id);
            }
        }

        /// handle request to (down)load tile image
        void startTileDownloading(size_t batch_id, int x, int y, int zoom)
        {
            if(batch_id < current_batch_id)  // ignore tile of previous requests
            {
                return;
            }

            // check cache for given tile
            shared(Tile) shared_tile;
            auto layerx = tile_cache.get(x, null);
            if(layerx !is null)
            {
                auto layerxy = layerx.get(y, null);
                if(layerxy !is null)
                    shared_tile = layerxy.get(zoom, null);
            }
            // if given tile found send it and quit
            if(shared_tile !is null)
            {
                frontend.send(batch_id, shared_tile);
                return;
            }

            // if tile not found readress the request to one of workers
            auto current_tid = workers[current_worker];
            auto full = makeFullPathAndUrl(x, y, zoom, url, cache_path);
            auto dir = dirName(full.path);
            if(!exists(dir))
                mkdirRecurse(dir); // it's better to create dirs in one parent thread instead of each of workers
            current_tid.send(batch_id, x, y, zoom, full.url, full.path);
            current_worker++;
            if(current_worker == maxWorkers)
                current_worker = 0;
        }

        // collect results from workers
        void getDownloadedTile(size_t batch_id, shared(Tile) shared_tile, int x, int y, int zoom) {
            if(batch_id != current_batch_id)  // ignore tile of other requests
                return;

            // store given tile into cache
            if(x !in tile_cache)
                tile_cache[x] = (shared(Tile)[int][int]).init;
            if(y !in tile_cache[x])
                tile_cache[x][y] = (shared(Tile)[int]).init;
            tile_cache[x][y][zoom] = shared_tile;

            tile_cache_content.insertFront(TileDescription(x, y, zoom));
            tile_cache_size++;
            if(tile_cache_size > maxTileCacheSize)
            {
                enum tileAmountToFree = 64;
                foreach(i; 0..tileAmountToFree)
                {
                    auto description = tile_cache_content.back;
                    tile_cache[description.x][description.y][description.zoom] = null;
                    tile_cache_content.removeBack();
                }
                tile_cache_size -= tileAmountToFree;
            }

            // translate tile to frontend
            frontend.send(batch_id, shared_tile);
        }

		try
		{
			// prepare workers
	        foreach(int id; 0..maxWorkers)
                workers[id] = spawnLinked(&downloading, thisTid, id);

            writeln("Backend launched");
			// talk to child threads
	        bool msg;
	        bool running = true;
	        do{
	            msg = receiveTimeout(dur!"msecs"(10),
                    &respawnWorker,
					&setNewTileBatch,
					&startTileDownloading,
		            &getDownloadedTile,
	                (LinkTerminated lt)
	            	{
	            		debug writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Link terminated");
	            	},
	            	(OwnerTerminated ot)
	                {
	                    writeln("Backend exited");
	                    running = false;
	                },
	                (Variant any)
	                {
	                    stderr.writeln("Unknown message received by BackEnd running thread: " ~ any.type.text);
	                }
	            );
	        } while(running);
		}
		catch(Throwable t)
		{
			writefln("Backend premature finished its execution because of:\n%s\n", t.msg);
            // complain to parent that something gone wrong
            frontend.send(Status.backendCrashed);
		}
	}

public:

	enum Status { backendCrashed };

	this(string url, string cache_path)
	{
		url_ = url;
		cache_path_ = cache_path;
	}

	// run backend in other thread
	Tid runAsync()
	{
		return spawn(&run, url_, cache_path_);
	}

	void close()
	{

	}
}
