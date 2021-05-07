import vibe.vibe;

import std.utf : validate;
import std.file;
import std.conv;
import std.datetime;
import std.digest.sha;
import std.digest.digest;
import std.random;

version = Public;

version (Public)
{
}
else
{
	private enum SecretHash = "insert sha512 string (uppercase) of your upload password in here, you can use rdmd --eval='import std.digest.sha; import std.digest.digest; writeln(sha512Of(`My Password Here`).toHexString));' to generate it";
	static assert(SecretHash.length == sha512Of("").length, "Please set your SecretHash in app.d");
}

/// Generates an ID from a number, you might want to change this function up a bit to prevent looking up IDs
string hash(long number, immutable int length = 5)
{
	import std.base64 : Base64URL;

	auto result = Base64URL.encode(sha512Of((cast(ubyte*)&number)[0 .. 8]));

	while (result.length < length)
		result ~= result;

	return cast(string) result[0 .. length].idup;
}

enum EntryType : int
{
	File = 0,
	Url,
	Code,
	Text,
	Graph
}

/// Entry for Database
struct UploadEntry
{
	/// id
	string id;
	/// File, Url, Poll Options, etc.
	string data;
	/// Type how data should be interpreted
	EntryType type;
	/// When file got uploaded
	BsonDate uploadDate;
	/// How many times it got called
	long clicks = 0;

	/// Fills variables with bson
	void fromBson(Bson bson)
	{
		id = bson["id"].get!string;
		data = bson["data"].get!string;
		type = cast(EntryType) bson["type"].get!int;
		uploadDate = bson["uploadDate"].get!BsonDate;
		clicks = bson["clicks"].get!long;
	}

	/// Returns Json containing only statistics
	Json toJson()
	{
		return Json(["uploadDate" : Json(uploadDate.toString()), "clicks" : Json(clicks)]);
	}

	/// Returns db entry
	Bson toBson()
	{
		return Bson(["id" : Bson(id), "data" : Bson(data), "type"
				: Bson(cast(int) type), "uploadDate" : Bson(uploadDate), "clicks" : Bson(clicks)]);
	}
}

///
class UploadManager
{
private:
	MongoCollection collection;
	HTTPFileServerSettings fileServerSettings;

	auto getID()
	{
		return collection.count(Bson.emptyObject) + 1;
	}

public:
	///
	this(MongoCollection collection)
	{
		import core.time;

		this.collection = collection;
		fileServerSettings = new HTTPFileServerSettings();
		fileServerSettings.maxAge = 365.days;
		fileServerSettings.preWriteCallback = (scope req, scope res, ref str) {
			res.headers["Content-Disposition"] = "inline";
		};
	}

	/// GET /
	void index(HTTPServerRequest req, HTTPServerResponse res)
	{
		version (Public)
		{
			string url = req.fullURL.toString;
			res.writeBody("public custom image uploader\n\nto upload: " ~ `echo "` ~ url ~ `"(curl -F "file=@path.png" "` ~ url
					~ `upload" -o -)` ~ "\n\nYou can also use /redirect (with url), /code (with code as file), /text (with text)"
					~ "\n\nAppend /stats to any upload to check upload date & clicks",
					"text/plain; charset=utf-8");
		}
		else
			res.writeBody("custom image uploader", "text/plain; charset=utf-8");
	}

	///
	void postUpload(HTTPServerRequest req, HTTPServerResponse res)
	{
		import std.path : extension;

		string secret = req.form.get("secret", "invalid");
		version (Public)
		{
		}
		else
		{
			if (toHexString(sha512Of(secret)) != SecretHash)
			{
				logInfo("Invalid Secret!");
				return;
			}
		}
		auto file = "file" in req.files;
		if (file is null)
		{
			logInfo("File not present");
			res.writeBody("File not present", 404);
			return;
		}
		string id = "f" ~ hash(getID());
		string path = "./uploads/" ~ id ~ file.filename.name.extension;
		try
		{
			copy(file.tempPath.toString(), NativePath(path).toString());
			remove(file.tempPath.toString());
		}
		catch (Exception e)
		{
			res.writeBody(e.toString(), 500);
			return;
		}

		UploadEntry entry;
		entry.id = id;
		entry.data = path;
		entry.type = EntryType.File;
		entry.uploadDate = BsonDate.fromStdTime(Clock.currStdTime());

		collection.insert(entry.toBson());

		res.writeBody(id, 200);
	}

	///
	void postRedirect(HTTPServerRequest req, HTTPServerResponse res)
	{
		string secret = req.form.get("secret", "invalid");
		string url = req.form.get("url", "");
		version (Public)
		{
		}
		else
		{
			if (toHexString(sha512Of(secret)) != SecretHash)
			{
				logInfo("Invalid Secret!");
				return;
			}
		}
		if (url == "")
		{
			logInfo("Missing Url!");
			return;
		}
		string id = "r" ~ hash(getID());

		UploadEntry entry;
		entry.id = id;
		entry.data = url;
		entry.type = EntryType.Url;
		entry.uploadDate = BsonDate.fromStdTime(Clock.currStdTime());

		collection.insert(entry.toBson());

		res.writeBody(id, 200);
	}

	///
	void postCode(HTTPServerRequest req, HTTPServerResponse res)
	{
		string secret = req.form.get("secret", "invalid");
		version (Public)
		{
		}
		else
		{
			if (toHexString(sha512Of(secret)) != SecretHash)
			{
				logInfo("Invalid Secret! " ~ secret);
				return;
			}
		}
		auto file = "code" in req.files;
		if (file is null)
		{
			logInfo("File not present");
			return;
		}
		string id = "c" ~ hash(getID());
		string path = "./uploads/" ~ id ~ ".txt";
		try
		{
			copy(file.tempPath.toString(), NativePath(path).toString());
			remove(file.tempPath.toString());
		}
		catch (Exception e)
		{
			res.writeBody(e.toString(), 500);
			return;
		}

		UploadEntry entry;
		entry.id = id;
		entry.data = path;
		entry.type = EntryType.Code;
		entry.uploadDate = BsonDate.fromStdTime(Clock.currStdTime());

		collection.insert(entry.toBson());

		res.writeBody(id, 200);
	}

	///
	void postText(HTTPServerRequest req, HTTPServerResponse res)
	{
		string secret = req.form.get("secret", "invalid");
		string text = req.form.get("text", "").stripRight;
		version (Public)
		{
		}
		else
		{
			if (toHexString(sha512Of(secret)) != SecretHash)
			{
				logInfo("Invalid Secret!");
				return;
			}
		}
		if (text == "")
		{
			logInfo("Missing text!");
			return;
		}
		validate(text);
		string id = "t" ~ hash(getID());

		UploadEntry entry;
		entry.id = id;
		entry.data = text;
		entry.type = EntryType.Text;
		entry.uploadDate = BsonDate.fromStdTime(Clock.currStdTime());

		collection.insert(entry.toBson());

		res.writeBody(id, 200);
	}

	version (Public)
	{
		// people can use this to eval js
	}
	else
	{
		///
		void postGraph(HTTPServerRequest req, HTTPServerResponse res)
		{
			string secret = req.form.get("secret", "invalid");
			string equation = req.form.get("equation", "");
			if (toHexString(sha512Of(secret)) != SecretHash)
			{
				logInfo("Invalid Secret!");
				return;
			}
			if (equation == "")
			{
				logInfo("Missing math functions!");
				return;
			}
			string id = "m" ~ hash(getID());

			UploadEntry entry;
			entry.id = id;
			entry.data = equation;
			entry.type = EntryType.Graph;
			entry.uploadDate = BsonDate.fromStdTime(Clock.currStdTime());

			collection.insert(entry.toBson());

			res.writeBody(id, 200);
		}
	}

	@path("*")
	void getFile(HTTPServerRequest req, HTTPServerResponse res)
	{
		string id = req.path[1 .. $];
		if (id.length < 6)
		{
			return;
		}
		Bson query = Bson(["id" : Bson(id[0 .. 6])]);
		UploadEntry result;
		auto bsonResult = collection.findOne(query);
		if (bsonResult.type == Bson.Type.null_)
		{
			return;
		}
		result.fromBson(bsonResult);

		if (id[$ - 6 .. $] == "/stats")
		{
			res.writeJsonBody(result.toJson());
		}
		else
		{
			collection.update(["_id" : bsonResult["_id"]], ["$inc" : ["clicks" : 1]]);

			if (result.type == EntryType.File)
				sendFile(req, res, NativePath(result.data), fileServerSettings);
			else if (result.type == EntryType.Url)
				res.redirect(result.data);
			else if (result.type == EntryType.Code)
			{
				res.renderCode(req, readText(result.data));
			}
			else if (result.type == EntryType.Text)
			{
				res.renderCode(req, result.data);
			}
			else if (result.type == EntryType.Graph)
			{
				string func = result.data;
				res.render!("func.dt", func);
			}
			else
				res.writeBody("Not implemented type " ~ to!string(result.type));
		}
	}
}

void renderCode(HTTPServerResponse res, HTTPServerRequest req, string content)
{
	import std.algorithm : canFind;

	if (req.headers.get("Accept", "").canFind("text/html"))
		res.render!("code.dt", content);
	else
		res.writeBody(content, "text/plain");
}

shared static this()
{
	auto db = connectMongoDB("mongodb://127.0.0.1").getDatabase("files");

	if (!existsFile("public"))
		createDirectory("public");
	if (!existsFile("uploads"))
		createDirectory("uploads");

	auto settings = new HTTPServerSettings;
	settings.port = 3000;
	settings.maxRequestSize = 100 * 1024 * 1024;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto router = new URLRouter;
	router.get("*", serveStaticFiles("public/"));
	router.registerWebInterface(new UploadManager(db["uploads"]));
	listenHTTP(settings, router);
}
