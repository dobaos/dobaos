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
import errors;

const ushort MIN_DATAPOINT_NUM = 1;
const ushort MAX_DATAPOINT_NUM = 1000;

class DatapointSdk {
  private ushort SI_currentBufferSize;
  private OS_DatapointDescription[ushort] descriptions;

  // stored values
  private JSONValue[ushort] values;

  private JSONValue convert2JSONValue(OS_DatapointValue dv) {
    // get dpt type from descriptions
    // then convert
    JSONValue res;
    res["id"] = dv.id;

    // assert that description can be found
    if ((dv.id in descriptions) is null) {
      throw Errors.datapoint_not_found;
    }

    auto dpt = descriptions[dv.id].type;
    // raw value encoded in base64
    res["raw"] = Base64.encode(dv.value);
    // converted value
    switch(dpt) {
      case OS_DatapointType.dpt1:
        res["value"] = DPT1.toBoolean(dv.value);
        break;
      case OS_DatapointType.dpt5:
        res["value"] = DPT5.toUByte(dv.value);
        break;
      case OS_DatapointType.dpt9:
        res["value"] = DPT9.toFloat(dv.value);
        break;
      default:
        break;
    }

    return res;
  }

  private OS_DatapointValue convert2OSValue(JSONValue value) {
    OS_DatapointValue res;
    if (value.type() != JSONType.object) {
      throw Errors.wrong_payload_type;
    }
    if (("id" in value) is null) {
      throw Errors.wrong_payload;
    }
    if (value["id"].type() != JSONType.integer) {
      throw Errors.wrong_payload_type;
    }

    auto id = cast(ushort) value["id"].integer;
    if ((id in descriptions) is null) {
      throw Errors.datapoint_not_found;
    }

    auto hasValue = !(("value" in value) is null);
    auto hasRaw = !(("raw" in value) is null);
    if (!(hasValue || hasRaw)) {
      throw Errors.wrong_value_payload;
    }
    if (hasRaw && value["raw"].type() != JSONType.string) {
      throw Errors.wrong_value_payload;
    }

    res.id = id;
    ubyte[] raw;

    auto dpt = descriptions[id].type;
    // raw value encoded in base64
    if (hasRaw) {
      res.value = Base64.decode(value["raw"].str);
      res.length = cast(ubyte)res.value.length;
    } else {
      auto _value = value["value"];
      switch(dpt) {
        case OS_DatapointType.dpt1:
          // TODO: check type. true/false/int(0-1)/...
          bool _val = true;
          if (_value.type() == JSONType.false_) {
            _val = false;
          } else if (_value.type() == JSONType.integer) {
            _val = _value.integer != 0;
          } else if (_value.type() == JSONType.uinteger) {
            _val = _value.uinteger != 0;
          } else if (_value.type() == JSONType.float_) {
            _val = _value.floating != 0;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT1.toUBytes(_val);
          res.length = cast(ubyte)res.value.length;
          break;
        case OS_DatapointType.dpt5:
          // TODO: check type. true/false/int(0-1)/...
          ubyte _val;
          if (_value.type() == JSONType.integer) {
            if (_value.integer < 0 || _value.integer > 255) {
              throw Errors.wrong_value;
            }
            _val = cast(ubyte) _value.integer;
          } else if (_value.type() == JSONType.uinteger) {
            if (_value.uinteger > 255) {
              throw Errors.wrong_value;
            }
            _val = cast(ubyte) _value.uinteger;
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT5.toUBytes(_val);
          res.length = cast(ubyte)res.value.length;
          break;
        case OS_DatapointType.dpt9:
          float _val;
          if (_value.type() == JSONType.float_) {
            _val = _value.floating;
          } else if (_value.type() == JSONType.integer) {
            _val = cast(float) _value.integer;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT9.toUBytes(_val);
          res.length = cast(ubyte)res.value.length;
          break;
        default:
          throw Errors.dpt_not_supported;
      }
    }

    // converted value
    return res;
  }

  private Baos baos;

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
      foreach(JSONValue jid; payload.array) {
        if (jid.type() != JSONType.integer) {
          throw Errors.wrong_payload;
        }
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
        throw Errors.datapoint_not_found;
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
    } else {
      throw Errors.wrong_payload_type;
    }

    return res;
  }

  public JSONValue getValue(JSONValue payload) {
    JSONValue res = parseJSON("{}");
    if (payload.type() == JSONType.integer) {
      ushort id = cast(ushort) payload.integer;
      auto val = baos.GetDatapointValueReq(id);
      if (val.service == OS_Services.GetDatapointValueRes && val.success) {
        //assert(val.datapoint_values.length == 1);
        res = convert2JSONValue(val.datapoint_values[0]);
      } else {
        // TODO: BaosErros(val.error);
        throw val.error;
      }
    } else if (payload.type() == JSONType.array) {
      // sort array, create new with uniq numbers
      // then calculate length to cover maximum possible values
      ushort[] idUshort;
      idUshort.length = payload.array.length;
      auto count = 0;
      if(payload.array.length == 0) {
        throw Errors.wrong_payload;
      }
      foreach(JSONValue jid; payload.array) {
        // assert
        if(jid.type() != JSONType.integer) {
          throw Errors.wrong_payload;
        }
        ushort id = cast(ushort) jid.integer;
        if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
          throw Errors.datapoint_out_of_bounds;
        }
        if((id in descriptions) == null) {
          throw Errors.datapoint_not_found;
        }
        idUshort[count] = id;
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
    } else if(payload.type() == JSONType.null_) {
      JSONValue allDatapoints = parseJSON("[]");
      allDatapoints.array.length = descriptions.keys.length;
      auto count = 0;
      foreach(id; descriptions.keys) {
        // cast to int, so, it is JSONType.integer, not uinteger
        allDatapoints.array[count] = cast(int) id;
        count += 1;
      }

      return getValue(allDatapoints);
    } else {
      throw Errors.wrong_payload_type;
    }

    return res;
  }

  public JSONValue setValue(JSONValue payload) {
    JSONValue res;
    if (payload.type() == JSONType.object) {
      if(("id" in payload) == null) {
        throw Errors.wrong_payload;
      }
      if(payload["id"].type() != JSONType.integer) {
        throw Errors.wrong_payload;
      }
      ushort id = cast(ushort) payload["id"].integer;
      if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
        throw Errors.datapoint_out_of_bounds;
      }
      if((id in descriptions) == null) {
        throw Errors.datapoint_not_found;
      }
      res = parseJSON("{}");
      auto rawValue = convert2OSValue(payload);
      rawValue.command = OS_DatapointValueCommand.set_and_send;
      auto setValResult = baos.SetDatapointValueReq([rawValue]);
      // for each datapoint add item to response
      if (setValResult.success) {
        res = convert2JSONValue(rawValue);
        res["success"] = true;
      } else {
        res["id"] = rawValue.id;
        res["success"] = false;
        res["error"] = setValResult.error.message;
      }
    } else if (payload.type() == JSONType.array) {
      if(payload.array.length == 0) {
        throw Errors.wrong_payload;
      }
      // array for converted values
      OS_DatapointValue[] rawValues;
      rawValues.length = payload.array.length;
      auto count = 0;
      foreach(JSONValue value; payload.array) {
        // assert
        if(value.type() != JSONType.object) {
          throw Errors.wrong_payload_type;
        }
        if(("id" in value) == null) {
          throw Errors.wrong_payload;
        }
        if(value["id"].type() != JSONType.integer) {
          throw Errors.wrong_payload_type;
        }
        ushort id = cast(ushort) value["id"].integer;
        if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
          throw Errors.datapoint_out_of_bounds;
        }
        if((id in descriptions) == null) {
          throw Errors.datapoint_not_found;
        }
        // TODO: handle errors on this stage
        auto rawValue = convert2OSValue(value);
        rawValue.command = OS_DatapointValueCommand.set_and_send;
        rawValues[count] = rawValue;
        count += 1;
      }

      res = parseJSON("[]");
      res.array.length = rawValues.length;

      // now calculate max length of response
      auto headerSize = 6;
      // default 250 - 6 = 244
      auto maxResLen = SI_currentBufferSize - headerSize;
      //maxResLen = 6;

      // current index in array
      auto currentIndex = 0;
      // expected response len
      auto expectedLen = 0;

      // temp array for raw values to fill 
      // when expected len exceeded, send req and clear
      OS_DatapointValue[] currentValues;
      currentValues.length = rawValues.length;
      count = 0;
      // for response
      auto resCount = 0;

      void _setValues() {
        currentValues.length = count;
        auto setValResult = baos.SetDatapointValueReq(currentValues);
        // for each datapoint add item to response
        if (setValResult.success) {
          for(auto i = currentIndex - count; i < currentIndex; i += 1) {
            // convert back to JSON value and return
            res.array[resCount] = convert2JSONValue(rawValues[i]);
            res.array[resCount]["success"] = true;
            resCount += 1;
          }
        } else {
          for(auto i = currentIndex - count; i < currentIndex; i += 1) {
            auto _res = parseJSON("{}");
            _res["id"] = rawValues[i].id;
            _res["success"] = false;
            _res["error"] = setValResult.error.message;
            res.array[resCount] = _res;
            resCount += 1;
          }
        }
      }

      // moving in rawValues array
      while (currentIndex < rawValues.length) {
        expectedLen += 4;
        expectedLen += rawValues[currentIndex].length;
        if (expectedLen > maxResLen) {
          // send req if len is exeeded
          // clear len values
          _setValues();
          count = 0;
          currentValues.length = 0;
          currentValues.length = rawValues.length;
          expectedLen = 0;
        } else {
          // if we still can add values
          currentValues[count] = rawValues[currentIndex];
          count += 1;
          currentIndex += 1;

          // if it was last element
          if (currentIndex == rawValues.length) {
            _setValues();
          }
        }
      }
    } else {
      throw Errors.wrong_payload_type;
    }

    return res;
  }
  public JSONValue readValue(JSONValue payload) {
    JSONValue res;
    if (payload.type() == JSONType.integer) {
      ushort id = cast(ushort) payload.integer;
      if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
        throw Errors.datapoint_out_of_bounds;
      }
      if((id in descriptions) == null) {
        throw Errors.datapoint_not_found;
      }
      // read request is basically SetDatapointValueReq
      // with command "read [0x04]" and zero value
      OS_DatapointValue raw;
      raw.id = id;
      raw.length = descriptions[id].length;
      raw.value.length = raw.length;
      for(auto i = 0; i < raw.length; i += 1) {
        raw.value[i] = 0;
      }
      raw.command = OS_DatapointValueCommand.read;

      auto val = baos.SetDatapointValueReq([raw]);
      if (val.service == OS_Services.SetDatapointValueRes && val.success) {
        res = true;
      } else {
        throw val.error;
      }
    } else if (payload.type() == JSONType.array) {
      // sort array, create new with uniq numbers
      // then calculate length to cover maximum possible values
      OS_DatapointValue[] rawValues;
      rawValues.length = payload.array.length;
      auto count = 0;
      if(payload.array.length == 0) {
        throw Errors.wrong_payload;
      }
      foreach(JSONValue jid; payload.array) {
        // assert
        if(jid.type() != JSONType.integer) {
          throw Errors.wrong_payload_type;
        }
        ushort id = cast(ushort) jid.integer;
        if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
          throw Errors.datapoint_out_of_bounds;
        }
        if((id in descriptions) == null) {
          throw Errors.datapoint_not_found;
        }
        OS_DatapointValue raw;
        raw.id = id;
        raw.length = descriptions[id].length;
        raw.value.length = raw.length;
        for(auto i = 0; i < raw.length; i += 1) {
          raw.value[i] = 0;
        }
        raw.command = OS_DatapointValueCommand.read;
        rawValues[count] = raw;
        count += 1;
      }

      res = parseJSON("[]");
      res.array.length = rawValues.length;

      // now calculate reqs
      auto headerSize = 6;
      // default 250 - 6 = 244
      auto maxResLen = SI_currentBufferSize - headerSize;

      // current index in array
      auto currentIndex = 0;
      // expected response len
      auto expectedLen = 0;

      // temp array for raw values to fill 
      // when expected len exceeded, send req and clear
      OS_DatapointValue[] currentValues;
      currentValues.length = rawValues.length;
      count = 0;
      // for response
      auto resCount = 0;

      void _readValues() {
        currentValues.length = count;
        auto setValResult = baos.SetDatapointValueReq(currentValues);
        // for each datapoint add item to response
        if (setValResult.success) {
          for(auto i = currentIndex - count; i < currentIndex; i += 1) {
            auto _res = parseJSON("{}");
            _res["id"] = rawValues[i].id;
            _res["success"] = true;
            res.array[resCount] = _res;
            resCount += 1;
          }
        } else {
          for(auto i = currentIndex - count; i < currentIndex; i += 1) {
            auto _res = parseJSON("{}");
            _res["id"] = rawValues[i].id;
            _res["success"] = false;
            _res["error"] = setValResult.error.message;
            res.array[resCount] = _res;
            resCount += 1;
          }
        }
      }

      // moving in rawValues array
      while (currentIndex < rawValues.length) {
        expectedLen += 4;
        expectedLen += rawValues[currentIndex].length;
        if (expectedLen > maxResLen) {
          // send req if len is exeeded
          // clear len values
          _readValues();
          count = 0;
          currentValues.length = 0;
          currentValues.length = rawValues.length;
          expectedLen = 0;
        } else {
          // if we still can add values
          currentValues[count] = rawValues[currentIndex];
          count += 1;
          currentIndex += 1;

          // if it was last element
          if (currentIndex == rawValues.length) {
            _readValues();
          }
        }
      }
    } else {
      throw Errors.wrong_payload_type;
    }

    return res;
  }

  public JSONValue getProgrammingMode() {
    JSONValue res;
    auto serverItemMessage = baos.GetServerItemReq(15);
    if (!serverItemMessage.success) {
      throw serverItemMessage.error;
    }

    foreach(si; serverItemMessage.server_items) {
      if (si.id == 15) {
        res = si.value.read!bool();

        return res;
      }
    }

    return res;
  }
  public JSONValue setProgrammingMode(JSONValue payload) {
    JSONValue res;
    ubyte[] uvalue = [0];
    if (payload.type() == JSONType.true_) {
      uvalue[0] = 1;
    } else if (payload.type == JSONType.false_) {
      uvalue[0] = 0;
    } else if (payload.type == JSONType.integer) {
      if (payload.integer != 0) {
        uvalue[0] = 1;
      } else {
        uvalue[0] = 0;
      }
    } else if (payload.type == JSONType.uinteger) {
      if (payload.uinteger != 0) {
        uvalue[0] = 1;
      } else {
        uvalue[0] = 0;
      }
    } else {
      throw Errors.wrong_payload_type;
    }
    OS_ServerItem mode;
    mode.id = 15;
    mode.length = 1;
    mode.value = uvalue;
    res = parseJSON("{}");
    auto setValResult = baos.SetServerItemReq([mode]);
    res = setValResult.success;

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
            break;
          case OS_DatapointType.dpt5:
            _res["value"] = DPT5.toUByte(dv.value);
            break;
          case OS_DatapointType.dpt9:
            _res["value"] = DPT9.toFloat(dv.value);
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

  // on reset 
  void _onReset() {
    auto serverItemMessage = baos.GetServerItemReq(14, 1);

    // maximum buffer size
    SI_currentBufferSize = 0;
    writeln("Loading server items");
    if (serverItemMessage.service == OS_Services.GetServerItemRes) {
      foreach(OS_ServerItem si; serverItemMessage.server_items) {
        // maximum buffer size
        if (si.id == 14) {
          SI_currentBufferSize = si.value.read!ushort();
          writefln("Current buffer size: %d bytes", SI_currentBufferSize);
        }
      }
    }
    writeln("Server items loaded");
    writeln("Loading datapoints");

    // count for loaded datapoints number
    auto count = 0;

    // calculate max num of dps in one response
    // GetDatapointDescriptionRes has a header(6b) and 5bytes each dp
    // so, incoming message can contain descr for following num of dpts:
    ushort number = cast(ushort)(SI_currentBufferSize - 6)/5;
    ushort start = 1;
    while(start < MAX_DATAPOINT_NUM ) {
      if (MAX_DATAPOINT_NUM - start <= number) {
        number = cast(ushort) (MAX_DATAPOINT_NUM - start + 1);
      }
      auto descr = baos.GetDatapointDescriptionReq(start, number);
      if (descr.success) {
        foreach(OS_DatapointDescription dd; descr.datapoint_descriptions) {
          descriptions[dd.id] = dd;
          count++;
        }
      } else {
        // there will be a lot of baos erros, 
        // if there is datapoints no configured
        // and so ignore them
      }
      start += number;
    }
    writefln("Datapoints[%d] loaded.", count);
  }

  // on incoming reset req. ETS download/bus dis and then -connected
  public void processResetInd() {
    if (baos.processResetInd()) {
      writeln("Reset indication was received");
      _onReset();
    }
  }

  this(string device = "/dev/ttyS1", string params = "19200:8E1") {
    baos = new Baos(device, params);

    // load datapoints at very start
    _onReset();
  }
}
