/***

  Sdk to work with datapoints

 ***/

module sdk;

import std.algorithm;
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
    if ((dv.id in descriptions) is null) {
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
    OS_DatapointValue res;
    if (value.type() != JSONType.object) {
      throw new Exception("JSON datapoint value payload is not object.");
    }
    if (("id" in value) is null) {
      throw new Exception("JSON datapoint value should contain id field.");
    }
    if (value["id"].type() != JSONType.integer) {
      throw new Exception("JSON datapoint value id field should be number.");
    }

    auto id = cast(ushort) value["id"].integer;
    if ((id in descriptions) is null) {
      writeln("Datapoint can't be found");
      throw new Exception("Datapoint can't be found");
    }

    auto hasValue = !(("value" in value) is null);
    auto hasRaw = !(("raw" in value) is null);
    if (!(hasValue || hasRaw)) {
      throw new Exception("JSON datapoint value should contain one of value/raw fields.");
    }
    if (hasRaw && value["raw"].type() != JSONType.string) {
      throw new Exception("JSON datapoint value raw field should be string.");
    }

    res.id = id;
    ubyte[] raw;

    auto dpt = descriptions[id].type;
    // raw value encoded in base64
    if (hasRaw) {
      res.value = Base64.decode(value["raw"].str);
    } else {
      switch(dpt) {
        case OS_DatapointType.dpt1:
          // TODO: check type. true/false/int(0-1)/...
          res.value = DPT1.toUbyte(value["value"].boolean);
          break;
        case OS_DatapointType.dpt9:
          res.value = DPT9.toUbyte(value["value"].floating);
          break;
        default:
          writeln("unknown yet dtp");
          break;
      }
    }

    // converted value
    return res;
  }

  private Baos baos;
  // TODO: methods to work with baos
  public JSONValue getDescription(JSONValue payload) {
    JSONValue res;
    if(payload.type() == JSONType.null_) {
      // return all descriptions
      JSONValue allDatapointId = parseJSON("[]");
      allDatapointId.array.length = descriptions.keys.length;

      auto count = 0;
      foreach(id; descriptions.keys) {
        allDatapointId.array[count] = cast(int) descriptions[id].id;
        count += 1;
      }

      res = getDescription(allDatapointId);
    } else if (payload.type() == JSONType.array) {
      foreach(JSONValue id; payload.array) {
        assert(id.type() == JSONType.integer);
      }

      res = parseJSON("[]");
      res.array.length = payload.array.length;

      auto count = 0;
      foreach(JSONValue id; payload.array) {
        res.array[count] = getDescription(id);
        count += 1;
      }
    } else if (payload.type() == JSONType.integer) {
      // return descr for selected datapoint
      ushort id = cast(ushort) payload.integer;
      if ((id in descriptions) is null) {
        writeln("Datapoint can't be found");
        throw new Exception("Datapoint can't be found");
      }

      auto descr = descriptions[id];
      res["id"] = descr.id;
      res["type"] = descr.type;
      res["priority"] = descr.flags.priority;
      res["communication"] = descr.flags.communication;
      res["read"] = descr.flags.read;
      res["write"] = descr.flags.write;
      res["read_on_init"] = descr.flags.read_on_init;
      res["transmit"] = descr.flags.transmit;
      res["update"] = descr.flags.update;
    }

    return res;
  }

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
      ushort[] idUshort;
      idUshort.length = payload.array.length;
      auto count = 0;
      assert(payload.array.length > 0);
      foreach(JSONValue id; payload.array) {
        // assert
        assert(id.type() == JSONType.integer);
        idUshort[count] = cast(ushort) id.integer;
        count += 1;
      }
      idUshort.sort();
      writeln("sorted: ", idUshort);

      // generate array with no dublicated id numbers
      ushort[] idUniq;
      // max length is payload len
      idUniq.length = idUshort.length;
      auto countUniq = 0;
      auto countOrigin = 0;
      idUniq[0] = idUshort[0];
      countUniq = 1;
      foreach(id; idUshort) {
        if (idUniq[countUniq - 1] != idUshort[countOrigin]) {
          idUniq[countUniq] = idUshort[countOrigin];
          countUniq += 1;
          countOrigin += 1;
        } else {
          countOrigin += 1;
        }
      }
      idUniq.length = countUniq;
      writeln("uniq: ", idUniq);

      res = parseJSON("[]");
      res.array.length = idUniq.length;

      count = 0;
      // temporary, refactor
      foreach(id; idUniq) {
        JSONValue jid = cast(int) id;
        res.array[count] = getValue(jid);
        count += 1;
      }
    } else {
      throw new Exception("unknown payload type.");
    }

    return res;
  }

  public JSONValue processInd() {
    JSONValue res = parseJSON("null");
    OS_Message ind = baos.processInd();
    if (ind.service == OS_Services.DatapointValueInd) {
      res = parseJSON("{}");
      res["method"] = "datapoint value";
      res["payload"] = parseJSON("[]");
      res["payload"].array.length = ind.datapoint_values.length;
      // example
      auto count = 0;
      foreach(OS_DatapointValue dv; ind.datapoint_values) {
        // convert to json type
        JSONValue _res;
        _res["id"] = dv.id;
        _res["raw"] = Base64.encode(dv.value);
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
        res["payload"].array[count] = _res;
        count++;
        // TODO: create ind object {id, value, raw} and return
      }
    }
    // TODO: server ind

    return res;
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
