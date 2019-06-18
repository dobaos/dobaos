/***

  Sdk to work with datapoints

 ***/

module sdk;

import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;
import std.json;
import std.base64;

import object_server;
import datapoints;
import baos;

// TODO: structs for converted datapoint value

const ushort MAX_DATAPOINT_NUM = 1000;

class DatapointSdk {
  private ushort SI_currentBufferSize;
  private OS_DatapointDescription[ushort] descriptions;
  private JSONValue convert2JSONValue(OS_DatapointValue dv) {
    // TODO: get dpt type from descriptions
    // TODO: convert
    JSONValue res;
    res["id"] = dv.id;
    // assert that description can be found
    OS_DatapointDescription *p;
    p = (dv.id in descriptions);
    if (p is null) {
      writeln("Datapoint can't be found");
      throw new Exception("Datapoint can't be found");
    }

    auto dpt = descriptions[dv.id].type;
    // raw value encoded in base64
    res["raw"] = Base64.encode(dv.value);
    // converted value
    switch(dpt) {
      case OS_DatapointType.dpt1:
        res["value"] = DPT1.toBoolean(dv.value);
        break;
      case OS_DatapointType.dpt9:
        res["value"] = DPT9.toFloat(dv.value);
        break;
      default:
        writeln("unknown yet dtp");
        break;
    }
    return res;

  }
  private OS_DatapointValue convert2OSValue(JSONValue value) {
    // TODO: get dpt type from descriptions
    // TODO: convert
    OS_DatapointValue res;
    // TODO: check type. array=> set multiple; object=>set one valu; default => err
    // TODO: assert that "value" or "raw" field is present value object
    return res;
  }
  private Baos baos;
  // TODO: methods to work with baos
  public JSONValue getValue(JSONValue payload) {
    JSONValue res;
    if (payload.type() == JSONType.integer) {
      writeln("is integer");
      ushort id = cast(ushort) payload.integer;
      auto val = baos.GetDatapointValueReq(id);
      writeln(val);
      if (val.success) {
        assert(val.datapoint_values.length == 1);
        res = convert2JSONValue(val.datapoint_values[0]);
      } else {
        writeln("values: bad:: ", val.error.message);
        // TODO: throw error
        throw new Exception(cast(string) val.error.message);
      }
    } else if (payload.type() == JSONType.array) {
      // TODO: check every element if it is integer
      // TODO: then calculate getValue map [{id, number}...]
      // TODO: get values, convert and return
      writeln("is array");
      // assert
      foreach(JSONValue id; payload.array) {
        assert(id.type() == JSONType.integer);
      }

      res = parseJSON("[]");
      res.array.length = payload.array.length;

      auto count = 0;
      // temporary, refactor
      foreach(JSONValue id; payload.array) {
        res.array[count] = getValue(id);
        count += 1;
      }
    } else {
      throw new Exception("unknown payload type.");
    }

    return res;
  }

  public void processInd() {
    OS_Message ind = baos.processInd();
    if (ind.service == OS_Services.DatapointValueInd) {
      JSONValue[] result;
      result.length = ind.datapoint_values.length;
      // example
      auto count = 0;
      foreach(OS_DatapointValue dv; ind.datapoint_values) {
        /****
          if (dv.id == 10) {
          OS_DatapointValue[] newVal;
          newVal.length = 1;
          newVal[0].id = 11;
          newVal[0].value.length = 1;
          newVal[0].value[0] = dv.value[0] == 0? 32: 8;
          writeln("new val: ", newVal[0].value[0]);
          Thread.sleep(1.msecs);
          baos.SetDatapointValueReq(cast(ushort) 10, newVal);
          } ****/

        // convert to base type
        JSONValue _res;
        _res["id"] = dv.id;
        switch(descriptions[dv.id].type) {
          case OS_DatapointType.dpt1:
            _res["value"] = DPT1.toBoolean(dv.value);
            writeln("boo: ", _res["id"], "=", _res["value"]);
            break;
          case OS_DatapointType.dpt9:
            _res["value"] = DPT9.toFloat(dv.value);
            writeln("float: ", _res["id"], "=", _res["value"]);
            break;
          default:
            writeln("unknown yet dtp");
            break;
        }
        result[count] = _res;
        count++;
        // TODO: create ind object {id, value, raw} and return
      }
      result.length = count;
    }
  }
  this(string device = "/dev/ttyS1", string params = "19200:8E1") {

    baos = new Baos(device, params);

    auto serverItemMessage = baos.GetServerItemReq(1, 17);

    // maximum buffer size
    SI_currentBufferSize = 0;
    writeln("Loading server items");
    if (serverItemMessage.service == OS_Services.GetServerItemRes) {
      foreach(OS_ServerItem si; serverItemMessage.server_items) {
        //writeln(si);
        // maximum buffer size
        if (si.id == 14) {
          SI_currentBufferSize = si.value.read!ushort();
          writefln("Current buffer size: %d bytes", SI_currentBufferSize);
        }
      }
    }
    writeln("Server items loaded");
    writeln("Loading datapoints");
    /***
      if (datapointValueMessage.service == OS_Services.GetDatapointValueRes) {
      writeln("values: good");
      foreach(OS_DatapointValue dv; datapointValueMessage.datapoint_values) {
      writeln(dv);
      }
      }
     ***/
    // TODO: calculate max num of dps

    // count for loaded datapoints
    auto count = 0;
    // GetDatapointDescriptionRes has a header(6b) and 5bytes each dp
    ushort number = cast(ushort)(SI_currentBufferSize - 6)/5;
    ushort start = 1;
    while(start < MAX_DATAPOINT_NUM ) {
      if (MAX_DATAPOINT_NUM - start <= number) {
        number = cast(ushort) (MAX_DATAPOINT_NUM - start + 1);
      }
      //writeln("start-number: ", start, "-", number);
      auto descr = baos.GetDatapointDescriptionReq(start, number);
      if (descr.success) {
        foreach(OS_DatapointDescription dd; descr.datapoint_descriptions) {
          //writeln("here comes description #", dd.id, "[", dd.type, "] ");
          // TODO: save in hash?
          descriptions[dd.id] = dd;
          count++;
        }
      } else {
        //writeln("here comes error:", start, "-", number,": ", descr.error.message);
      }
      start += number;
    }
    writefln("Datapoints[%d] loaded.", count);
  }
}
