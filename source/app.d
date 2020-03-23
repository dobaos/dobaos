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

import clid;
import clid.validate;

import logo;
import baos;
import datapoints;
import object_server;
import redis_dsm;
import sdk;
import errors;

enum VERSION = "23_mar_2020";

// struct for commandline params
private struct Config {
  @Parameter("config_prefix", 'c')
    @Description("Prefix for config key names. dobaos_config_uart_device, etc.. Default: dobaos_config_")
    string config_prefix;

  @Parameter("device", 'd')
    @Description("UART device. Setting this argument will overwrite redis key value. Default: /dev/ttyAMA0")
    string device;
}

void main() {
  print_logo();

  auto dsm = new RedisDsm("127.0.0.1", cast(ushort)6379);
  // parse args
  auto config = parseArguments!Config();
  string config_prefix = config.config_prefix.length > 1 ? config.config_prefix: "dobaos_config_";

  auto device = dsm.getKey(config_prefix ~ "uart_device", "/dev/ttyAMA0", true);
  // if device parameter was given in commandline arguments
  if (config.device.length > 1) {
    device = config.device;
    dsm.setKey(config_prefix ~ "uart_device", device);
  }
  auto params = dsm.getKey(config_prefix ~ "uart_params", "19200:8E1", true);

  auto req_channel = dsm.getKey(config_prefix ~ "req_channel", "dobaos_req", true);
  auto cast_channel = dsm.getKey(config_prefix ~ "bcast_channel", "dobaos_cast", true);
  dsm.setChannels(req_channel, cast_channel);

  auto service_channel = dsm.getKey(config_prefix ~ "service_channel", "dobaos_service", true);
  auto service_cast = dsm.getKey(config_prefix ~ "scast_channel", "dobaos_cast", true);
  auto stream_prefix = dsm.getKey(config_prefix ~ "stream_prefix", "dobaos_datapoint_", true);
  auto stream_maxlen = dsm.getKey(config_prefix ~ "stream_maxlen", "1000", true);

  // array of datapoints to stream in redis
  auto stream_ids_cfg = dsm.getKey(config_prefix ~ "stream_ids", "[]", true);

  int[] stream_ids; 
  try {
    auto jstream_ids = parseJSON(stream_ids_cfg);
    if (jstream_ids.type() != JSONType.array) {
      writeln("Store datapoint key value is not an array");
      return;
    }
    stream_ids.length = jstream_ids.array.length;
    auto i = 0;
    foreach(entry; jstream_ids.array) {
      if (entry.type() != JSONType.integer) {
        writeln("Datapoint id in stream_ids key value is not an integer");
        return;
      }
      stream_ids[i] = to!int(entry.integer);
      i += 1;
    }
  } catch(Exception e) {
    writeln(e);
    return;
  } catch(Error e) {
    writeln(e);
    return;
  }


  StopWatch sw;
  sw.start();

  auto sdk = new DatapointSdk(device, params);

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
            auto jstream = parseJSON("[]");
            auto count = 0; auto stream_count = 0;
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

                if (stream_ids.canFind(id)) {
                  if (_jvalue["value"].type() == JSONType.float_) {
                    _jvalue["value"] = format!"%0.2f"(_jvalue["value"].floating);
                  }
                  jstream.array ~= _jvalue;
                  stream_count += 1;
                }
              }
            }
            if (count > 0) {
              dsm.broadcast(jcast);
            }
            if (stream_count > 0) {
              dsm.addToStream(stream_prefix, stream_maxlen, jstream);
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
              if (stream_ids.canFind(id)) {
                if (_jvalue["value"].type() == JSONType.float_) {
                  _jvalue["value"] = format!"%0.2f"(_jvalue["value"].floating);
                }
                dsm.addToStream(stream_prefix, stream_maxlen, _jvalue);
              }
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
            auto jstream = parseJSON("[]");
            auto count = 0; auto stream_count = 0;
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
                if (stream_ids.canFind(id)) {
                  if (_jvalue["value"].type() == JSONType.float_) {
                    _jvalue["value"] = format!"%0.2f"(_jvalue["value"].floating);
                  }
                  jstream.array ~= _jvalue;
                  stream_count += 1;
                }
              }
            }
            if (count > 0) {
              dsm.broadcast(jcast);
            }
            if (stream_count > 0) {
              dsm.addToStream(stream_prefix, stream_maxlen, jstream);
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
              if (stream_ids.canFind(id)) {
                if (_jvalue["value"].type() == JSONType.float_) {
                  _jvalue["value"] = format!"%0.2f"(_jvalue["value"].floating);
                }
                dsm.addToStream(stream_prefix, stream_maxlen, _jvalue);
              }
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
      default:
        res["method"] = "error";
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));

  // service messages
  auto ssm = new RedisDsm("127.0.0.1", cast(ushort)6379, service_channel, service_cast);
  void handleService(JSONValue jreq, void delegate(JSONValue) sendResponse) {
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
      case "reset":
        try {
          sdk.interrupt();
          res["method"] = "success";
          res["payload"] = null;
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
      default:
        res["method"] = "error";
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  ssm.subscribe(toDelegate(&handleService));

  writeln("IPC ready");

  sdk.setInterruptsDelegate(toDelegate(&ssm.processMessages));
  sdk.resetBaos();
  sdk.init();

  writeln("SDK ready");
  writefln("Started in %dms", sw.peek.total!"msecs");
  sw.stop();

  // process incoming values
  while(true) {
    sdk.processResetInd();
    sdk.processInterrupts();

    JSONValue ind = sdk.processInd();
    if (ind.type() != JSONType.null_) {
      dsm.broadcast(ind);

      // now, if we got datapoint value that should be saved
      if (ind["method"].str == "datapoint value" && stream_ids.length > 0) {
        if (ind["payload"].type == JSONType.array) {
          auto jstream = parseJSON("[]");
          auto stream_count = 0;
          foreach(value; ind["payload"].array) {
            int id;
            if (value["id"].type() == JSONType.integer) {
              id = to!int(value["id"].integer);
            } else if (value["id"].type() == JSONType.uinteger) {
              id = to!int(value["id"].uinteger);
            }
            if (stream_ids.canFind(id)) {
              if (value["value"].type() == JSONType.float_) {
                value["value"] = format!"%0.2f"(value["value"].floating);
              }
              jstream.array ~= value;
              stream_count += 1;
            }
          }
          if (stream_count > 0) {
            dsm.addToStream(stream_prefix, stream_maxlen, jstream);
          }
        } else if (ind["payload"].type == JSONType.object) {
          int id;
          auto value = ind["payload"];
          if (value["id"].type() == JSONType.integer) {
            id = to!int(value["id"].integer);
          } else if (value["id"].type() == JSONType.uinteger) {
            id = to!int(value["id"].uinteger);
          }
          if (stream_ids.canFind(ind["payload"]["id"].integer)) {
              if (ind["payload"]["value"].type() == JSONType.float_) {
                ind["payload"]["value"] = format!"%0.2f"(ind["payload"]["value"].floating);
              }
            dsm.addToStream(stream_prefix, stream_maxlen, ind["payload"]);
          }
        }
      }
    }

    dsm.processMessages();
    ssm.processMessages();

    // calculate approximate sleep time depending on baudrate.
    // assuming default baud 19200 bits per second is used.
    // also that on each iteration app needs to get at least 4 bytes.
    // bytes_per_second = 19200/8 = 2400; bytes_per_ms = 2,4;
    // 4bytes can be received in 4/2.4 = 1.6 ~= 2 ms;
    // same applies to baos.d
    Thread.sleep(2.msecs);
  }
}
