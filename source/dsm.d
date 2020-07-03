//  Datapoint Sdk Messaging
//  module provides with class to access 
//  redis pub/sub layer for interprocess communication
//  requests are sent to req_channel in stringified JSON
//    response_channel: "client_listener",
//    method: "get value",
//    payload: 1/[1, 2, 3]/null
//  }
//  response then is sent to "client_listener"
//  {
//    method: "error/success",
//    payload: {id: 1, value: 1, raw: "AZAz=" }/[{], ]/"string"
//  }

module redis_dsm;
import std.conv;
import std.stdio;
import std.json;
import std.functional;

import tinyredis;
import tinyredis.subscriber;

class RedisDsm {
  private Redis pub, redis;
  private Subscriber sub;
  private string redis_host, req_channel, bcast_channel;
  private string redis_stream;
  private ushort redis_port;

  this(string redis_host, ushort redis_port, string req_channel,
      string bcast_channel) {
    // init publisher

    this.redis_host = redis_host;
    this.redis_port = redis_port;
    this.req_channel = req_channel;
    this.bcast_channel = bcast_channel;
    redis = new Redis(redis_host, redis_port);
  }
  this(string redis_host, ushort redis_port) {
    // init publisher

    this.redis_host = redis_host;
    this.redis_port = redis_port;
    redis = new Redis(redis_host, redis_port);
  }
  public void setChannels(string req_channel, string bcast_channel) {
    this.req_channel = req_channel;
    this.bcast_channel = bcast_channel;
  }


  public void unsubscribe() {
    if (req_channel.length > 0) {
      writeln("Unsubscribing from ", req_channel);
      sub.unsubscribe(req_channel);
    }
  }
  public void subscribe(void delegate(JSONValue, void delegate(JSONValue)) req_handler) {
    // init publisher
    pub = new Redis(redis_host, redis_port);
    // delegate for incoming messages
    void handleMessage(string channel, string message)
    {
      try {
        JSONValue jreq = parseJSON(message);

        // check if request is object
        if (!jreq.type == JSONType.object) {
          return;
        }
        // check if request has response_channel field
        auto jresponse_channel = ("response_channel" in jreq);
        if (jresponse_channel is null) {
          return;
        }
        auto response_channel = ("response_channel" in jreq).str;

        void sendResponse(JSONValue res) {
          pub.send("PUBLISH", response_channel, res.toJSON());
        }
        req_handler(jreq, &sendResponse);
      } catch(Exception e) {
        //writeln("error parsing json: %s ", e.msg);
      } 
    }
    sub = new Subscriber(redis_host, redis_port);
    writeln("Subscribing to ", req_channel);
    sub.subscribe(req_channel, toDelegate(&handleMessage));
  }
  public void broadcast(JSONValue data) {
    pub.send("PUBLISH", bcast_channel, data.toJSON());
  }
  public void processMessages() {
    sub.processMessages();
  }
  public string[string] getHash(string key) {
    string[string] result;
    auto kv = redis.send("HGETALL", key);
    if (kv.type == ResponseType.MultiBulk) {
      for (int i = 1; i < kv.values.length; i += 2) {
        result[kv.values[i-1].toString()] = kv.values[i].toString();
      }
    }

    return result;
  }
  public string getKey(string key) {
    return redis.send("GET " ~ key).toString();
  }
  public string getKey(string key, string default_value, bool set_if_null = false) {
    auto keyValue = redis.send("GET " ~ key).toString();

    if (keyValue.length > 0) {
      return keyValue;
    } else if (set_if_null) {
      redis.send("SET " ~ key ~ " " ~ default_value);
      return default_value;
    } else {
      return default_value;
    }
  }
  public string setKey(string key, string value) {
    return redis.send("SET " ~ key ~ " " ~ value).toString();
  }
  public void addToStream(string key_prefix, string maxlen, string[string] data) {
    auto command = "XADD ";
    command ~= key_prefix ~ " ";
    command ~= "MAXLEN ~ " ~ to!string(maxlen) ~ " ";
    command ~= "* "; // id
    foreach(k, v; data) {
      command ~= k ~ " ";
      command ~= v;
    }
    redis.send(command);
  }
}
