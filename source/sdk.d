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

  // stored values
  private JSONValue[ushort] values;

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
      res.length = cast(ubyte)res.value.length;
    } else {
      switch(dpt) {
        case OS_DatapointType.dpt1:
          // TODO: check type. true/false/int(0-1)/...
          res.value = DPT1.toUbyte(value["value"].boolean);
          res.length = cast(ubyte)res.value.length;
          break;
        case OS_DatapointType.dpt9:
          res.value = DPT9.toUbyte(value["value"].floating);
          res.length = cast(ubyte)res.value.length;
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
      // sort array, create new with uniq numbers
      // then calculate length to cover maximum possible values
      ushort[] idUshort;
      idUshort.length = payload.array.length;
      auto count = 0;
      assert(payload.array.length > 0);
      foreach(JSONValue id; payload.array) {
        // assert
        assert(id.type() == JSONType.integer);
        assert(id.integer > 0 && id.integer <= MAX_DATAPOINT_NUM);
        assert((cast(ushort) id.integer in descriptions) != null);
        idUshort[count] = cast(ushort) id.integer;
        count += 1;
      }
      idUshort.sort();

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

      res = parseJSON("[]");
      res.array.length = 1000;

      // now calculate max length of response
      auto headerSize = 6;
      // default 250 - 6 = 244
      auto maxResLen = SI_currentBufferSize - headerSize;

      // current index in array
      auto currentIndex = 0;
      // expected response len
      auto currentLen = 0;

      // current id. 
      // GetDatapointValueReq(start, number, filter.all) returns all datapoints
      // even if they are not configured in ETS
      // and for them length is 1
      // so, 
      ushort id = idUniq[currentIndex];

      // params for ObjectServer request
      ushort start = id;
      ushort number = 0;

      // response count to fill array
      auto resCount = 0;
      // get values with current params
      void _getValues() {
        auto val = baos.GetDatapointValueReq(start, number);
        //writeln(val.datapoint_values);
        // TODO: error check
        foreach(_val; val.datapoint_values) {
          if ((_val.id in descriptions) != null) {
            res.array[resCount] = convert2JSONValue(_val);
            resCount += 1;
          }
        }
      }
      while(currentIndex < idUniq.length) {
        ushort dpLen = 1;
        if ((id in descriptions) != null) {
          // if is configured
          dpLen = descriptions[id].length;
        } else {
          // otherwise value is [0]
          dpLen = 1;
        }
        // header len for every value is 4
        currentLen += 4 + dpLen;
        // moving next
        if (currentLen < maxResLen + 1) {
          if (idUniq[currentIndex] == id) {
            number = cast(ushort) (id - start);
            if (currentIndex == idUniq.length - 1) {
              number += 1;
              _getValues();
              currentIndex += 2;
            } else {
              currentIndex += 1;
            }
          }
          id += 1;
        } else {
          // if exceeded length
          number += 1;
          _getValues();

          // start again from id under cursor
          id = idUniq[currentIndex];
          start = id;
          number = 0;
          currentLen = 0;
        }
      }
      res.array.length = resCount;
    } else {
      throw new Exception("unknown payload type.");
    }

    return res;
  }

  public JSONValue setValue(JSONValue payload) {
    // TODO: 
    JSONValue res;
    if (payload.type() == JSONType.object) {
      writeln("is object");
    } else if (payload.type() == JSONType.array) {
      assert(payload.array.length > 0);
      // array for converted values
      OS_DatapointValue[] rawValues;
      rawValues.length = payload.array.length;
      auto count = 0;
      foreach(JSONValue value; payload.array) {
        // assert
        assert(value.type() == JSONType.object);
        assert(("id" in value) != null);
        assert(value["id"].type() == JSONType.integer);
        ushort id = cast(ushort) value["id"].integer;
        assert(id > 0 && id <= MAX_DATAPOINT_NUM);
        assert((id in descriptions) != null);
        rawValues[count] = convert2OSValue(value);
        count += 1;
      }

      res = parseJSON("[]");
      res.array.length = 1000;

      // now calculate max length of response
      auto headerSize = 6;
      // default 250 - 6 = 244
      auto maxResLen = SI_currentBufferSize - headerSize;

      // current index in array
      auto currentIndex = 0;
      // expected response len
      auto expectedLen = 0;
      // TODO: calculate, send
      // temp array for raw values
      // when expected len exceeded, send req and fill
      count = 0;
      OS_DatapointValue[] currentValues;
      currentValues.length = rawValues.length;

      while (currentIndex < rawValues.length) {
        expectedLen += 4;
        expectedLen += rawValues[currentIndex].length;
        if (expectedLen > maxResLen) {
          // TODO: send req,
          // TODO: clear len values
          currentValues.length = count;
          auto setValResult = baos.SetDatapointValueReq(currentValues);
          writeln(setValResult);
          count = 0;
        } else {
          // last element
          currentValues[count] = rawValues[currentIndex];
          // proceed next
          count += 1;
          if (currentIndex == rawValues.length - 1) {
            currentValues.length = count;
            auto setValResult = baos.SetDatapointValueReq(currentValues);
            writeln(setValResult);
          }
          currentIndex += 1;
        }
      }

      // TODO: process response, error handling
      // TODO: intelligent error handling: 
      // TODO: error/success for each datapoint in array

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
