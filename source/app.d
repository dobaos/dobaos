module main;
import core.thread;
import std.algorithm: canFind;
import std.conv;
import std.format;
import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;
import std.json;
import std.functional;

import std.datetime.stopwatch;

import std.getopt;

import logo;
import baos;
import datapoints;
import object_server;
import redis_dsm;
import sdk;
import errors;

enum VERSION = "9_nov_2020";

// struct for commandline params

void main(string[] args) {
  print_logo();

  auto dsm = new RedisDsm("127.0.0.1", cast(ushort)6379);
  // parse args
  string dobaos_prefix = "dobaos";
  string config_prefix; 
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

  void setUartDevice(string d) {
    device = d;
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
    if (jstream_ids.type() != JSONType.array) {
      writeln("Key stream_datapoints is not a JSON array");
      return;
    }
    stream_ids.length = jstream_ids.array.length;
    auto i = 0;
    foreach(entry; jstream_ids.array) {
      if (entry.type() != JSONType.integer && 
          entry.type() != JSONType.uinteger &&
          entry.type() != JSONType.string) {
        writeln("Error in stream_ids key value.");
        return;
      }
      if (entry.type() == JSONType.integer) {
        stream_ids[i] = to!int(entry.integer);
      } else if (entry.type() == JSONType.integer) {
        stream_ids[i] = to!int(entry.uinteger);
      } else if (entry.type() == JSONType.string) {
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
      if (_jvalue["value"].type() == JSONType.float_) {
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

  loadRedisConfig();

  StopWatch sw;
  sw.start();

  auto sdk = new DatapointSdk(device, params);

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
      case "get description":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getDescription(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getValue(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get stored":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getStored(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "set value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.setValue(jreq["payload"], OS_DatapointValueCommand.set_and_send);
          sendResponse(res);
          // broadcast values
          auto jcast = parseJSON("{}");
          jcast["method"] = "datapoint value";
          if (res["payload"].type() == JSONType.array) {
            jcast["payload"] = parseJSON("[]");
            jcast["payload"].array.length = res["payload"].array.length;
            auto count = 0;
            foreach(value; res["payload"].array) {
              if (value["success"].type() == JSONType.true_) {
                auto _jvalue = parseJSON("{}");
                _jvalue["id"] = value["id"];
                _jvalue["raw"] = value["raw"];
                _jvalue["value"] = value["value"];
                jcast["payload"].array[count] = _jvalue;
                count += 1;
                // check if datapoint should be saved
                if (stream_ids.length == 0) {
                  continue;
                }

                int id;
                if (value["id"].type() == JSONType.integer) {
                  id = to!int(value["id"].integer);
                } else if (value["id"].type() == JSONType.uinteger) {
                  id = to!int(value["id"].uinteger);
                }
                addToStream(value);
              }
            }
            if (count > 0) {
              dsm.broadcast(jcast);
            }
          } else if (res["payload"].type() == JSONType.object) {
            auto value = res["payload"];
            if (value["success"].type() == JSONType.true_) {
              auto _jvalue = parseJSON("{}");
              _jvalue["id"] = value["id"];
              _jvalue["raw"] = value["raw"];
              _jvalue["value"] = value["value"];
              jcast["payload"] = _jvalue;
              dsm.broadcast(jcast);

              // check if datapoint should be saved
              if (stream_ids.length == 0) {
                return;
              }

              int id;
              if (value["id"].type() == JSONType.integer) {
                id = to!int(value["id"].integer);
              } else if (value["id"].type() == JSONType.uinteger) {
                id = to!int(value["id"].uinteger);
              }
              addToStream(value);
            }
          }
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "put value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.setValue(jreq["payload"], OS_DatapointValueCommand.set);
          sendResponse(res);
          // broadcast values
          auto jcast = parseJSON("{}");
          jcast["method"] = "datapoint value";
          if (res["payload"].type() == JSONType.array) {
            jcast["payload"] = parseJSON("[]");
            jcast["payload"].array.length = res["payload"].array.length;
            auto count = 0; 
            foreach(value; res["payload"].array) {
              if (value["success"].type() == JSONType.true_) {
                auto _jvalue = parseJSON("{}");
                _jvalue["id"] = value["id"];
                _jvalue["raw"] = value["raw"];
                _jvalue["value"] = value["value"];
                jcast["payload"].array[count] = _jvalue;
                count += 1;

                // check if datapoint should be stored
                if (stream_ids.length == 0) {
                  continue;
                }
                int id;
                if (value["id"].type() == JSONType.integer) {
                  id = to!int(value["id"].integer);
                } else if (value["id"].type() == JSONType.uinteger) {
                  id = to!int(value["id"].uinteger);
                }
                addToStream(value);
              }
            }
            if (count > 0) {
              dsm.broadcast(jcast);
            }
          } else if (res["payload"].type() == JSONType.object) {
            auto value = res["payload"];
            if (value["success"].type() == JSONType.true_) {
              auto _jvalue = parseJSON("{}");
              _jvalue["id"] = value["id"];
              _jvalue["raw"] = value["raw"];
              _jvalue["value"] = value["value"];
              jcast["payload"] = _jvalue;
              dsm.broadcast(jcast);

              // check if datapoint should be stored
              if (stream_ids.length == 0) {
                return;
              }
              int id;
              if (value["id"].type() == JSONType.integer) {
                id = to!int(value["id"].integer);
              } else if (value["id"].type() == JSONType.uinteger) {
                id = to!int(value["id"].uinteger);
              }
              addToStream(value);
            }
          }
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "read value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.readValue(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get programming mode":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getProgrammingMode();
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "set programming mode":
        try {
          res["method"] = "success";
          res["payload"] = sdk.setProgrammingMode(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get server items":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getServerItems();
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "version":
        try {
          res["method"] = "success";
          res["payload"] = VERSION;
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "reset":
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
          }
          res["method"] = "success";
          res["payload"] = true;
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      default:
        res["method"] = "error";
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));

  writeln("IPC ready");

  while(true) {
    if (!sdk.resetBaos(device, params)) {
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
      continue;
    }
    if (sdk.init()) break;
  }

  writeln("SDK ready");
  writefln("Started in %dms", sw.peek.total!"msecs");
  sw.stop();

  // process incoming values
  while(true) {
    sdk.processResetInd();

    JSONValue ind = sdk.processInd();
    if (ind.type() != JSONType.null_) {
      dsm.broadcast(ind);

      // now, if we got datapoint value that should be saved
      if (ind["method"].str == "datapoint value" && stream_ids.length > 0) {
        if (ind["payload"].type == JSONType.array) {
          foreach(value; ind["payload"].array) {
            int id;
            if (value["id"].type() == JSONType.integer) {
              id = to!int(value["id"].integer);
            } else if (value["id"].type() == JSONType.uinteger) {
              id = to!int(value["id"].uinteger);
            }
            addToStream(value);
          }
        } else if (ind["payload"].type == JSONType.object) {
          int id;
          auto value = ind["payload"];
          if (value["id"].type() == JSONType.integer) {
            id = to!int(value["id"].integer);
          } else if (value["id"].type() == JSONType.uinteger) {
            id = to!int(value["id"].uinteger);
          }
          addToStream(value);
        }
      }
    }

    dsm.processMessages();

    // calculate approximate sleep time depending on baudrate.
    // assuming default baud 19200 bits per second is used.
    // also that on each iteration app needs to get at least 4 bytes.
    // bytes_per_second = 19200/8 = 2400; bytes_per_ms = 2,4;
    // 4bytes can be received in 4/2.4 = 1.6 ~= 2 ms;
    // same applies to baos.d
    Thread.sleep(2.msecs);
  }
}
