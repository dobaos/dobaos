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


module dsm;
import std.stdio;
import std.json;
import std.functional;

import tinyredis;
import tinyredis.subscriber;

class Dsm {
  private Redis pub;
  private Subscriber sub;
  private string redis_host, req_channel, bcast_channel;
  private ushort redis_port;
  this(string redis_host, ushort redis_port, string req_channel, string bcast_channel) {
    // init publisher

    this.redis_host = redis_host;
    this.redis_port = redis_port;
    this.req_channel = req_channel;
    this.bcast_channel = bcast_channel;
  }

  public void subscribe(void delegate(JSONValue, void delegate(JSONValue)) req_handler) {

    // init publisher
    pub = new Redis(redis_host, redis_port);
    // delegate for incoming messages
    void handleMessage(string channel, string message)
    {
      writefln("Redis channel '%s': %s", channel, message);
      try {
        JSONValue jreq = parseJSON(message);

        // check if request is object
        if (!jreq.type == JSONType.object) {
          return;
        }
        // check if request has response_channel field
        auto jresponse_channel = ("response_channel" in jreq);
        if (jresponse_channel is null) {
          writeln("no response_channel field in json request");
          return;
        }
        auto response_channel = ("response_channel" in jreq).str;
        writeln("response_channel", response_channel);

        void sendResponse(JSONValue res) {
          writeln("trying to send response to ", response_channel);
          pub.send("PUBLISH", response_channel, res.toJSON());
        }
        req_handler(jreq, &sendResponse);
      } catch(Exception e) {
        writeln("error parsing json: %s ", e.msg);
      } finally {
        writeln("finally..");
      }
    }
    sub = new Subscriber(redis_host, redis_port);
    writeln("subscribing to ", req_channel);
    sub.subscribe(req_channel, toDelegate(&handleMessage));
  }
  public void broadcast(JSONValue data) {
    writeln("broadcasting net yet here");
  }
  public void processMessages() {
    sub.processMessages();
  }
}
