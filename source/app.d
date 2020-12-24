module main;
import core.thread;
import std.algorithm: canFind;
import std.base64;
import std.conv;
import std.format;
import std.stdio;
import std.bitmanip;
import std.json;
import std.digest: toHexString;
import std.getopt;
import std.functional;
import std.range.primitives : empty;
import std.datetime.stopwatch;
import std.socket: Socket;

import logo;
import baos;
import datapoints;
import object_server;
import redis_dsm;
import datapoint_sdk;
import errors;
import socket_server;

enum VERSION = "24_dec_2020";

// struct for commandline params

void main(string[] args) {
  print_logo();

  RedisDsm dsm;
  DatapointSdk sdk;
  SocketServer knxnet_server;
  bool knxnet_enabled = false;
  ushort knxnet_port = 0;

  dsm = new RedisDsm("127.0.0.1", cast(ushort)6379);
  // parse args
  string dobaos_prefix = "dobaos";
  string config_prefix = dobaos_prefix ~ ":config";
  string stream_prefix;
  string device;
  string params;
  string req_channel;
  string cast_channel;
  string stream_maxlen;
  bool stream_raw;
  string stream_ids_cfg;
  int[] stream_ids; 
  string[string] datapoint_names;
  string[string] default_names;
  default_names["first"] = "1";
  default_names["last"] = "1000";

  void setUartDevice(string d, string v) {
    config_prefix = dobaos_prefix ~ ":config";
    device = v;
    // save to redis
    dsm.setKey(config_prefix ~ ":uart_device", device);
  }
  auto getoptResult = getopt(args,
      "prefix|p", 
      "Prefix for redis config and stream keys. Default: dobaos",
      &dobaos_prefix,

      "device|d", 
      "UART device. Will be persisted in redis key. Default: /dev/ttyAMA0", 
      &setUartDevice);

  if (getoptResult.helpWanted) {
    defaultGetoptPrinter("SDK for Weinzierl BAOS 83x application layer.",
        getoptResult.options);
    return;
  }
  config_prefix = dobaos_prefix ~ ":config";
  stream_prefix = dobaos_prefix ~ ":stream";

  void loadRedisConfig() {
    device = dsm.getKey(config_prefix ~ ":uart_device", "/dev/ttyAMA0", true);
    // if device parameter was given in commandline arguments
    params = dsm.getKey(config_prefix ~ ":uart_params", "19200:8E1", true);

    req_channel = dsm.getKey(config_prefix ~ ":req_channel", "dobaos_req", true);
    cast_channel = dsm.getKey(config_prefix ~ ":bcast_channel", "dobaos_cast", true);
    dsm.setChannels(req_channel, cast_channel);

    stream_maxlen = dsm.getKey(config_prefix ~ ":stream_maxlen", "1000", true);
    stream_raw = (dsm.getKey(config_prefix ~ ":stream_raw", "false", true)) == "true";

    // array of datapoints to stream in redis
    stream_ids_cfg = dsm.getKey(config_prefix ~ ":stream_datapoints", "[]", true);
    datapoint_names.clear();
    datapoint_names = dsm.getHash(config_prefix ~ ":names", default_names, true);

    string knxnet_port_cfg = dsm.getKey(config_prefix ~ ":knxnet_port", "0", true);
    int knxnet_port_int = parse!int(knxnet_port_cfg);
    knxnet_enabled = knxnet_port_int > 0;
    if (knxnet_enabled) {
      knxnet_port = to!ushort(knxnet_port_int);
    }
  }
  void loadStreamDatapoints() {
    stream_ids = [];
    JSONValue jstream_ids;
    try {
      jstream_ids = parseJSON(stream_ids_cfg); 
    } catch(Exception e) {
      writeln("Error in stream_datapoints key. Streams disabled");
      return;
    }
    if (jstream_ids.type != JSONType.array) {
      writeln("Key stream_datapoints is not a JSON array");
      return;
    }
    stream_ids.length = jstream_ids.array.length;
    auto i = 0;
    foreach(entry; jstream_ids.array) {
      if (entry.type != JSONType.integer && 
          entry.type != JSONType.uinteger &&
          entry.type != JSONType.string) {
        writeln("Error in stream_ids key value.");
        return;
      }
      if (entry.type == JSONType.integer) {
        stream_ids[i] = to!int(entry.integer);
      } else if (entry.type == JSONType.integer) {
        stream_ids[i] = to!int(entry.uinteger);
      } else if (entry.type == JSONType.string) {
        if(datapoint_names.keys.canFind(entry.str)) {
          string v = datapoint_names[entry.str];
          try {
            stream_ids[i] = parse!int(v);
          } catch (Exception e) {
            // do nothing.
            // Datapoint names will be disabled later
            stream_ids.length = stream_ids.length - 1;
            continue;
          }
        } else {
          stream_ids.length = stream_ids.length - 1;
          continue;
        }
      }
      i += 1;
    }
  }
  void addToStream(JSONValue _jvalue) {
    int id = to!int(_jvalue["id"].integer);
    // add only if this datapoint is selected
    if (stream_ids.canFind(id)) {
      if (_jvalue["value"].type == JSONType.float_) {
        _jvalue["value"] = format!"%0.2f"(_jvalue["value"].floating);
      }
      string[string] entry;
      entry["value"] = _jvalue["value"].toJSON();
      if (stream_raw) {
        entry["raw"] = _jvalue["raw"].toJSON();
      }
      dsm.addToStream(stream_prefix ~ ":" ~ to!string(id), stream_maxlen, entry);
    }
  }
  void initKnxNetServer() {
    writeln("KNXNetServer enabled: ", knxnet_enabled);
    if (!knxnet_enabled) return;
    if (knxnet_server !is null) {
      knxnet_server.stop();
    }
    knxnet_server = new SocketServer(knxnet_port);
    knxnet_server.onOpen = (Socket sock, string addr) {
      writeln("KNXNet Connection open: ", addr);
    };
    knxnet_server.onClose = (Socket sock, string addr) {
      writeln("KNXNet Connection closed: ", addr);
    };
    knxnet_server.onMessage = (Socket sock, string addr, ubyte[] msg) {
      if (msg.toHexString == "0620F080001004000000F001000A0001") {
        // little hack to avoid UART flooding
        // iRidium lite is asking twice in a sec for bus connection state
        // say it's okay - bus connected
        ubyte[] hackResponse = Base64.decode("BiDwgAAUBAAAAPCBAAoAAQAKAQE=");
        sock.send(hackResponse);
        return;
      }

      // decode
      // knxnet header
      ubyte headerSize = msg.read!ubyte();
      ubyte version_ = msg.read!ubyte();
      ushort reqType = msg.read!ushort(); // 0xf080 OBJSERV
      ushort frameSize = msg.read!ushort();
      // conn header 
      ubyte connHeaderSize = msg.read!ubyte();
      msg = msg[connHeaderSize-1..$];

      // objserver message
      ubyte[] res = sdk.binRequest(msg);

      // compose response
      ubyte[] response = [];
      response.length = 10;
      response.write!ubyte(headerSize, 0);
      response.write!ubyte(version_, 1);
      response.write!ushort(reqType, 2);
      auto resLen = res.length + headerSize + connHeaderSize;
      response.write!ushort(to!ushort(resLen), 4);

      response.write!ubyte(4, 6);
      response.write!ubyte(0, 7);
      response.write!ubyte(0, 8);
      response.write!ubyte(0, 9);

      response ~= res;

      sock.send(response);
    };

    writeln("KNXNetServer is listening on port: ", knxnet_port);
  }

  loadRedisConfig();

  StopWatch sw;
  sw.start();

  sdk = new DatapointSdk(device, params);

  // load datapoint names to sdk. if error, then disable feature
  if (!sdk.loadDatapointNames(datapoint_names)) {
    writeln("Error parsing datapoint names table");
    writeln("Datapoint names are disabled");
    datapoint_names.clear();
  }
  loadStreamDatapoints();

  void handleRequest(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    JSONValue res;

    auto jmethod = ("method" in jreq);
    if (jmethod is null) {
      res["success"] = false;
      res["payload"] = Errors.no_method_field.message;
      sendResponse(res);
      return;
    }
    auto jpayload = ("payload" in jreq);
    if (jpayload is null) {
      res["success"] = false;
      res["payload"] = Errors.no_payload_field.message;
      sendResponse(res);
      return;
    }

    string method = ("method" in jreq).str;
    switch(method) {
      case SdkMethods.get_description:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.getDescription(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.get_value:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.getValue(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.get_stored:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.getStored(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.set_value:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.setValue(jreq["payload"],
              OS_DatapointValueCommand.set_and_send);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.put_value:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.setValue(jreq["payload"], 
              OS_DatapointValueCommand.set);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.read_value:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.readValue(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.get_programming_mode:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.getProgrammingMode();
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.set_programming_mode:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.setProgrammingMode(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.get_server_items:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.getServerItems();
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.get_version:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = VERSION;
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.binary_request:
        try {
          res["method"] = SdkMethods.success;
          res["payload"] = sdk.jbinaryRequest(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case SdkMethods.reset:
        try {
          print_logo();
          writeln("==== Reset request received ====");
          while (true) {
            loadRedisConfig();
            if (!sdk.loadDatapointNames(datapoint_names)) {
              writeln("Error parsing datapoint names table");
              writeln("Datapoint names are disabled");
              datapoint_names.clear();
            }
            loadStreamDatapoints();
            dsm.unsubscribe();
            dsm.setChannels(req_channel, cast_channel);
            dsm.subscribe(toDelegate(&handleRequest));
            if (!sdk.resetBaos(device, params)) continue;
            if (sdk.init()) break;
            initKnxNetServer();
          }
          JSONValue jcast = parseJSON("{}");
          jcast["method"] = "sdk reset";
          jcast["payload"] = true;
          dsm.broadcast(jcast);

          res["method"] = SdkMethods.success;
          res["payload"] = true;
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = SdkMethods.error;
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      default:
        res["method"] = SdkMethods.error;
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));

  writeln("IPC ready");

  while(true) {
    if (!sdk.resetBaos()) {
      loadRedisConfig();
      if (!sdk.loadDatapointNames(datapoint_names)) {
        writeln("Error parsing datapoint names table");
        writeln("Datapoint names are disabled");
        datapoint_names.clear();
      }
      loadStreamDatapoints();
      dsm.unsubscribe();
      dsm.setChannels(req_channel, cast_channel);
      dsm.subscribe(toDelegate(&handleRequest));
      initKnxNetServer();
      continue;
    }
    if (sdk.init()) break;
  }
  JSONValue jcast = parseJSON("{}");
  jcast["method"] = "sdk init";
  jcast["payload"] = true;
  dsm.broadcast(jcast);

  writeln("SDK ready");
  writefln("Started in %dms", sw.peek.total!"msecs");
  sw.stop();

  initKnxNetServer();

  // process incoming values
  while(true) {
    JSONValue resetInd = sdk.processResetInd();
    if (resetInd.type != JSONType.null_) {
      dsm.broadcast(resetInd);
    }

    JSONValue[] indications = sdk.processInd();

    foreach(ind; indications) {
      dsm.broadcast(ind);
      // add to stream if present in array
      if (ind["method"].str == SdkMethods.cast_datapoint_value &&
          stream_ids.length > 0) {
        if (ind["payload"].type == JSONType.array) {
          foreach(value; ind["payload"].array) {
            int id;
            if (value["id"].type == JSONType.integer) {
              id = to!int(value["id"].integer);
            } else if (value["id"].type == JSONType.uinteger) {
              id = to!int(value["id"].uinteger);
            }
            addToStream(value);
          }
        } else if (ind["payload"].type == JSONType.object) {
          int id;
          auto value = ind["payload"];
          if (value["id"].type == JSONType.integer) {
            id = to!int(value["id"].integer);
          } else if (value["id"].type == JSONType.uinteger) {
            id = to!int(value["id"].uinteger);
          }
          addToStream(value);
        }
      }
    }

    ubyte[] binInd = sdk.getBinaryIndications();
    if (binInd.length > 0) {
      if (knxnet_enabled) {
        ubyte[] bcast = [];
        bcast.length = 10;
        bcast.write!ubyte(0x06, 0);
        bcast.write!ubyte(0x20, 1);
        bcast.write!ushort(0xf080, 2);
        auto len = binInd.length + 6 + 4;
        bcast.write!ushort(to!ushort(len), 4);

        bcast.write!ubyte(4, 6);
        bcast.write!ubyte(0, 7);
        bcast.write!ubyte(0, 8);
        bcast.write!ubyte(0, 9);

        bcast ~= binInd;
        //writeln("Broadcasting: ", bcast.toHexString);

        knxnet_server.broadcast(bcast);
      }
    }

    dsm.processMessages();

    if(knxnet_enabled && knxnet_server !is null) {
      knxnet_server.loop();
    }

    // calculate approximate sleep time depending on baudrate.
    // assuming default baud 19200 bits per second is used.
    // also that on each iteration app needs to get at least 4 bytes.
    // bytes_per_second = 19200/8 = 2400; bytes_per_ms = 2,4;
    // 4bytes can be received in 4/2.4 = 1.6 ~= 2 ms;
    // same applies to baos.d
    Thread.sleep(2.msecs);
  }
}
