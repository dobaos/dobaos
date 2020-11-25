/***
  Sdk to work with datapoints
 ***/

module sdk;

import core.thread;
import std.algorithm;
import std.base64;
import std.bitmanip;
import std.conv;
import std.json;
import std.range.primitives : empty;
import std.stdio;

import logo;
import object_server;
import datapoints;
import baos;
import errors;

const ushort MIN_DATAPOINT_NUM = 1;
const ushort MAX_DATAPOINT_NUM = 1000;

class DatapointSdk {
  private ushort SI_currentBufferSize;
  private OS_DatapointDescription[ushort] descriptions;
  private ushort[string] name2id;
  private string[ushort] id2name;

  public bool loadDatapointNames(string[string] table) {
    // input format: table[name] = id; { "datapoint1": 1 }
    name2id.clear();
    id2name.clear();
    foreach(k, v; table) {
      try{ 
        ushort id = parse!ushort(v);
        name2id[k] = id;
        id2name[id] = k;
      } catch(Exception e) {
        name2id.clear();
        id2name.clear();
        return false;
      }
    }

    return true;
  }

  // stored values
  private JSONValue[ushort] values;

  private JSONValue convert2JSONValue(OS_DatapointValue dv) {
    // get dpt type from descriptions
    // then convert
    JSONValue res;
    res["id"] = to!int(dv.id);

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
      case OS_DatapointType.dpt2:
        res["value"] = DPT2.toDecoded(dv.value);
        break;
      case OS_DatapointType.dpt3:
        res["value"] = DPT3.toDecoded(dv.value);
        break;
      case OS_DatapointType.dpt4:
        res["value"] = DPT4.toChar(dv.value);
        break;
      case OS_DatapointType.dpt5:
        res["value"] = DPT5.toUByte(dv.value);
        break;
      case OS_DatapointType.dpt6:
        res["value"] = DPT6.toByte(dv.value);
        break;
      case OS_DatapointType.dpt7:
        res["value"] = DPT7.toUShort(dv.value);
        break;
      case OS_DatapointType.dpt8:
        res["value"] = DPT8.toShort(dv.value);
        break;
      case OS_DatapointType.dpt9:
        res["value"] = DPT9.toFloat(dv.value);
        break;
      case OS_DatapointType.dpt10:
        res["value"] = DPT10.toTime(dv.value);
        break;
      case OS_DatapointType.dpt11:
        res["value"] = DPT11.toDate(dv.value);
        break;
      case OS_DatapointType.dpt12:
        res["value"] = DPT12.toUInt(dv.value);
        break;
      case OS_DatapointType.dpt13:
        res["value"] = DPT13.toInt(dv.value);
        break;
      case OS_DatapointType.dpt14:
        res["value"] = DPT14.toFloat(dv.value);
        break;
      case OS_DatapointType.dpt16:
        res["value"] = DPT16.toString(dv.value);
        break;
      case OS_DatapointType.dpt18:
        res["value"] = DPT18.toDecoded(dv.value);
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
    if (value["id"].type() != JSONType.integer && 
        value["id"].type() != JSONType.uinteger) {
      throw Errors.wrong_payload_type;
    }

    ushort id;
    if (value["id"].type() == JSONType.uinteger) {
      id = to!ushort(value["id"].uinteger);
    } else if (value["id"].type() == JSONType.integer) {
      id = to!ushort(value["id"].integer);
    }
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
      try {
        res.value = Base64.decode(value["raw"].str);
      } catch(Exception e) {
        throw Errors.wrong_raw_value;
      }
      res.length = to!ubyte(res.value.length);
    } else {

      void assertLongBounds(long val, long low, long high) {
        if (val < low || val > high) {
          throw Errors.wrong_value;
        }
      }
      void assertULongBounds(ulong val, ulong low, ulong high) {
        if (val < low || val > high) {
          throw Errors.wrong_value;
        }
      }
      void assertFloatBounds(float val, float low, float high) {
        if (val < low || val > high) {
          throw Errors.wrong_value;
        }
      }

      auto _value = value["value"];
      switch(dpt) {
        case OS_DatapointType.dpt1:
          bool _val;
          if (_value.type() == JSONType.false_) {
            _val = false;
          } else if (_value.type() == JSONType.true_) {
            _val = true;
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
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt2:
          bool _val = true;
          bool _ctrl = true;
          bool[string] _val_ctrl;
          if (_value.type() == JSONType.object) {
            bool _fieldsInvalid = false;
            _fieldsInvalid = _fieldsInvalid || ("control" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("value" in _value) is null;
            if (_fieldsInvalid) {
              throw Errors.wrong_value;
            }
            if (_value["control"].type() == JSONType.false_) {
              _ctrl = false;
            } else if (_value["control"].type() == JSONType.true_) {
              _ctrl = true;
            } else if (_value["control"].type() == JSONType.integer) {
              _ctrl = _value["control"].integer != 0;
            } else if (_value["control"].type() == JSONType.uinteger) {
              _ctrl = _value["control"].uinteger != 0;
            } else if (_value["control"].type() == JSONType.float_) {
              _ctrl = _value["control"].floating != 0;
            } else {
              throw Errors.wrong_value;
            }
            if (_value["value"].type() == JSONType.false_) {
              _val = false;
            } else if (_value["value"].type() == JSONType.true_) {
              _val = true;
            } else if (_value["value"].type() == JSONType.integer) {
              _val = _value["value"].integer != 0;
            } else if (_value["value"].type() == JSONType.uinteger) {
              _val = _value["value"].uinteger != 0;
            } else if (_value["value"].type() == JSONType.float_) {
              _val = _value["value"].floating != 0;
            } else {
              throw Errors.wrong_value;
            }

            _val_ctrl["control"] = _ctrl;
            _val_ctrl["value"] = _val;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT2.toUBytes(_val_ctrl);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt3:
          ubyte _dir = 1;
          ubyte _step = 1;
          ubyte[string] _dir_step;
          if (_value.type() == JSONType.object) {
            bool _fieldsInvalid = false;
            _fieldsInvalid = _fieldsInvalid || ("direction" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("step" in _value) is null;
            if (_fieldsInvalid) {
              throw Errors.wrong_value;
            }
            if (_value["direction"].type() == JSONType.integer) {
              _dir = (_value["direction"].integer != 0) ? 1: 0;
            } else if (_value["direction"].type() == JSONType.uinteger) {
              _dir = (_value["direction"].uinteger != 0)? 1: 0;
            } else {
              throw Errors.wrong_value;
            }

            if (_value["step"].type() == JSONType.integer) {
              assertLongBounds(_value.integer, 0, 7);
              _step = to!ubyte(_value["step"].integer);
            } else if (_value["step"].type() == JSONType.uinteger) {
              assertULongBounds(_value.uinteger, 0, 7);
              _step = to!ubyte(_value["step"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            _dir_step["direction"] = _dir;
            _dir_step["step"] = _step;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT3.toUBytes(_dir_step);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt4:
          char _char;
          if (_value.type() == JSONType.string) {
            if (_value.str.length != 1) {
              throw Errors.wrong_value_type;
            }
            _char = to!char(_value.str[0]);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT4.toUBytes(_char);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt5:
          ubyte _val;
          if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, 0, 255);
            _val = to!ubyte(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, 0, 255);
            _val = to!ubyte(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT5.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt6:
          byte _val;
          if (_value.type() == JSONType.integer) {
            assertULongBounds(_value.integer, -127, 127);
            _val = to!byte(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, -127, 127);
            _val = to!byte(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT6.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt7:
          ushort _val;
          if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, 0, 65535);
            _val = to!ushort(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, 0, 65535);
            _val = to!ushort(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT7.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt8:
          short _val;
          if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, -32768, 32768);
            _val = to!short(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, -32768, 32768);
            _val = to!short(_value.uinteger);
          }  else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT8.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt9:
          float _val;
          if (_value.type() == JSONType.float_) {
            assertFloatBounds(_value.floating, -671088.65, 650761.97);
            _val = _value.floating;
          } else if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, -671088, 650761);
            _val = to!float(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, -671088, 650761);
            if (_value.uinteger < -671088.64 || _value.uinteger > 670761.96) {
              throw Errors.wrong_value;
            }
            _val = to!float(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT9.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt10:
          ubyte _day = 0;
          ubyte _hour = 0;
          ubyte _minutes = 0;
          ubyte _seconds = 0;
          ubyte[string] _time;
          if (_value.type() == JSONType.object) {
            bool _fieldsInvalid = false;
            _fieldsInvalid = _fieldsInvalid || ("day" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("hour" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("minutes" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("seconds" in _value) is null;
            if (_fieldsInvalid) {
              throw Errors.wrong_value;
            }
            if (_value["day"].type() == JSONType.integer) {
              assertLongBounds(_value["day"].integer, 0, 7);
              _day = to!ubyte(_value["day"].integer);
            } else if (_value["day"].type() == JSONType.uinteger) {
              assertLongBounds(_value["day"].uinteger, 0, 7);
              _day = to!ubyte(_value["day"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            if (_value["hour"].type() == JSONType.integer) {
              assertLongBounds(_value["hour"].integer, 0, 23);
              _hour = to!ubyte(_value["hour"].integer);
            } else if (_value["hour"].type() == JSONType.uinteger) {
              assertULongBounds(_value["hour"].uinteger, 0, 23);
              _hour = to!ubyte(_value["hour"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            if (_value["minutes"].type() == JSONType.integer) {
              assertLongBounds(_value["minutes"].integer, 0, 59);
              _minutes = to!ubyte(_value["minutes"].integer);
            } else if (_value["minutes"].type() == JSONType.uinteger) {
              assertULongBounds(_value["minutes"].uinteger, 0, 59);
              _minutes = to!ubyte(_value["minutes"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            if (_value["seconds"].type() == JSONType.integer) {
              assertLongBounds(_value["seconds"].integer, 0, 59);
              _seconds = to!ubyte(_value["seconds"].integer);
            } else if (_value["seconds"].type() == JSONType.uinteger) {
              assertULongBounds(_value["seconds"].uinteger, 0, 59);
              _seconds = to!ubyte(_value["seconds"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            _time["day"] = _day;
            _time["hour"] = _hour;
            _time["minutes"] = _minutes;
            _time["seconds"] = _seconds;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT10.toUBytes(_time);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt11:
          ushort _day = 0;
          ushort _month = 0;
          ushort _year = 0;
          ushort[string] _date;
          if (_value.type() == JSONType.object) {
            bool _fieldsInvalid = false;
            _fieldsInvalid = _fieldsInvalid || ("day" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("month" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("year" in _value) is null;
            if (_fieldsInvalid) {
              throw Errors.wrong_value;
            }

            if (_value["day"].type() == JSONType.integer) {
              assertLongBounds(_value["day"].integer, 1, 31);
              _day = to!ushort(_value["day"].integer);
            } else if (_value["day"].type() == JSONType.uinteger) {
              assertULongBounds(_value["day"].uinteger, 1, 31);
              _day = to!ushort(_value["day"].uinteger != 0);
            } else {
              throw Errors.wrong_value;
            }

            if (_value["month"].type() == JSONType.integer) {
              assertLongBounds(_value["month"].integer, 1, 12);
              _month = to!ushort(_value["month"].integer);
            } else if (_value["month"].type() == JSONType.uinteger) {
              assertULongBounds(_value["month"].uinteger, 1, 12);
              _month = to!ushort(_value["month"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            if (_value["year"].type() == JSONType.integer) {
              assertLongBounds(_value["year"].integer, 1990, 2089);
              _year = to!ushort(_value["year"].integer);
            } else if (_value["year"].type() == JSONType.uinteger) {
              assertULongBounds(_value["year"].uinteger, 1990, 2089);
              _year = to!ushort(_value["year"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            _date["day"] = _day;
            _date["month"] = _month;
            _date["year"] = _year;
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT11.toUBytes(_date);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt12:
          uint _val;
          if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, 0, 4294967295);
            _val = to!uint(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, 0, 4294967295);
            _val = to!uint(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT12.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt13:
          int _val;
          if (_value.type() == JSONType.integer) {
            assertLongBounds(_value.integer, -2147483648, 2147483647);
            _val = to!uint(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            assertULongBounds(_value.uinteger, -2147483648, 2147483647);
            _val = to!uint(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT13.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt14:
          float _val;
          if (_value.type() == JSONType.float_) {
            _val = _value.floating;
          } else if (_value.type() == JSONType.integer) {
            _val = to!float(_value.integer);
          } else if (_value.type() == JSONType.uinteger) {
            _val = to!float(_value.uinteger);
          } else {
            throw Errors.wrong_value_type;
          }

          // what is a range? not in specs.

          res.value = DPT14.toUBytes(_val);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt16:
          char[] _char;
          if (_value.type() == JSONType.string) {
            _char = to!(char[])(_value.str);
          } else {
            throw Errors.wrong_value_type;
          }

          res.value = DPT16.toUBytes(_char);
          res.length = to!ubyte(res.value.length);
          break;
        case OS_DatapointType.dpt18:
          ubyte _learn = 1;
          ubyte _num = 1;
          ubyte[string] _learn_num;
          if (_value.type() == JSONType.object) {
            bool _fieldsInvalid = false;
            _fieldsInvalid = _fieldsInvalid || ("learn" in _value) is null;
            _fieldsInvalid = _fieldsInvalid || ("number" in _value) is null;
            if (_fieldsInvalid) {
              throw Errors.wrong_value;
            }

            if (_value["learn"].type() == JSONType.false_) {
              _learn = 0;
            } else if (_value["learn"].type() == JSONType.true_) {
              _learn = 1;
            } else if (_value["learn"].type() == JSONType.integer) {
              _learn = (_value["learn"].integer != 0)? 1: 0;
            } else if (_value["learn"].type() == JSONType.uinteger) {
              _learn = (_value["learn"].uinteger != 0)? 1: 0;
            } else {
              throw Errors.wrong_value;
            }

            if (_value["number"].type() == JSONType.integer) {
              _num = to!ubyte(_value["step"].integer);
            } else if (_value["number"].type() == JSONType.uinteger) {
              _num = to!ubyte(_value["number"].uinteger);
            } else {
              throw Errors.wrong_value;
            }

            _learn_num["learn"] = _learn;
            _learn_num["number"] = _num;
          } else {
            throw Errors.wrong_value_type;
          }
          res.value = DPT18.toUBytes(_learn_num);
          res.length = to!ubyte(res.value.length);
          break;
        default:
          throw Errors.dpt_not_supported;
      }
    }

    // converted value
    return res;
  }

  private Baos baos;

  private ushort getIdFromJson(JSONValue payload) {
    ushort id;
    if (payload.type() == JSONType.integer) {
      id = to!ushort(payload.integer);
    } else if (payload.type() == JSONType.uinteger) {
      id = to!ushort(payload.uinteger);
    } else if (payload.type() == JSONType.string) {
      if ((payload.str in name2id) is null) {
        throw Errors.datapoint_not_found;
      }
      id = name2id[payload.str];
    }

    return id;
  }

  public JSONValue getDescription(JSONValue payload) {
    JSONValue res;
    if (payload.type() == JSONType.null_) {
      return getDescription(JSONValue("*"));
    } else if(payload.type() == JSONType.string) {
      // return all descriptions
      if (payload.str == "*") {
        JSONValue allDatapointId = parseJSON("[]");
        allDatapointId.array.length = descriptions.keys.length;

        auto count = 0;
        foreach(id; descriptions.keys) {
          allDatapointId.array[count] = JSONValue(id);
          count += 1;
        }

        res = getDescription(allDatapointId);
      } else {
        if ((payload.str in name2id) is null) {
          throw Errors.datapoint_not_found;
        }
        ushort id = name2id[payload.str];
        return getDescription(JSONValue(id));
      }
    } else if (payload.type() == JSONType.array) {
      foreach(JSONValue jid; payload.array) {
        if (jid.type() != JSONType.integer &&
            jid.type() != JSONType.uinteger &&
            jid.type() != JSONType.string) {
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
    } else if (payload.type() == JSONType.integer ||
        payload.type() == JSONType.uinteger) {
      // return descr for selected datapoint
      ushort id = getIdFromJson(payload);
      if ((id in descriptions) is null) {
        throw Errors.datapoint_not_found;
      }

      auto descr = descriptions[id];
      if ((id in id2name) !is null) {
        res["name"] = id2name[id];
      }
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
    if (payload.type() == JSONType.integer ||
        payload.type() == JSONType.uinteger ||
        payload.type() == JSONType.string) {
      if (payload.type() == JSONType.string) {
        if (payload.str == "*") {
          return getValue(JSONValue(null));
        }
      }

      ushort id = getIdFromJson(payload);

      if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
        throw Errors.datapoint_out_of_bounds;
      }
      if((id in descriptions) == null) {
        throw Errors.datapoint_not_found;
      }
      auto val = baos.GetDatapointValueReq(id);
      if (val.service == OS_Services.GetDatapointValueRes && val.success) {
        //assert(val.datapoint_values.length == 1);
        res = convert2JSONValue(val.datapoint_values[0]);
        values[id] = res;
      } else {
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
        if(jid.type() != JSONType.integer &&
            jid.type() != JSONType.uinteger &&
            jid.type() != JSONType.string) {
          throw Errors.wrong_payload;
        }
        ushort id = getIdFromJson(jid);
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
        if (!val.success) {
          throw val.error;
        }
        foreach(_val; val.datapoint_values) {
          if ((_val.id in descriptions) != null) {
            // store in any case
            values[_val.id] = convert2JSONValue(_val);
            // but return in response only if id presented in request payload
            if (canFind(idUniq, _val.id)) {
              res.array ~= values[_val.id];
            }
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
            number = to!ushort(id - start);
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
    } else if(payload.type() == JSONType.null_) {
      JSONValue allDatapoints = parseJSON("[]");
      allDatapoints.array.length = descriptions.keys.length;
      auto count = 0;
      foreach(id; descriptions.keys) {
        allDatapoints.array[count] = JSONValue(id);
        count += 1;
      }

      return getValue(allDatapoints);
    } else {
      throw Errors.wrong_payload_type;
    }

    return res;
  }
  public JSONValue getStored(JSONValue payload) {
    JSONValue res = parseJSON("{}");
    if (payload.type() == JSONType.integer ||
        payload.type() == JSONType.uinteger ||
        payload.type() == JSONType.string) {

      if (payload.type() == JSONType.string) {
        if (payload.str == "*") {
          return getStored(JSONValue(null));
        }
      }
      ushort id = getIdFromJson(payload);

      if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
        throw Errors.datapoint_out_of_bounds;
      }
      if((id in descriptions) == null) {
        throw Errors.datapoint_not_found;
      }
      if((id in values) == null) {
        values[id] = getValue(JSONValue(to!int(id)));
      }
      return values[id];
    } else if (payload.type() == JSONType.array) {
      // sort array, create new with uniq numbers
      // then calculate length to cover maximum possible values
      ushort[] idArray;
      idArray.length = payload.array.length;
      auto count = 0;
      if(payload.array.length == 0) {
        throw Errors.wrong_payload;
      }
      foreach(JSONValue jid; payload.array) {
        // assert
        if(jid.type() != JSONType.integer &&
            jid.type() != JSONType.uinteger &&
            jid.type() != JSONType.string) {
          throw Errors.wrong_payload;
        }
        ushort id = getIdFromJson(payload);

        if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
          throw Errors.datapoint_out_of_bounds;
        }
        if((id in descriptions) == null) {
          throw Errors.datapoint_not_found;
        }
        idArray[count] = id;
        count += 1;
      }

      ushort[] id2get;

      res = parseJSON("[]");
      foreach(id; idArray) {
        if((to!ushort(id) in values) == null) {
          id2get ~= id;
        } else {
          res.array ~= values[to!ushort(id)];
        }
      }
      if (id2get.length > 0) {
        auto getRes = getValue(JSONValue(id2get));
        foreach(v; getRes.array) {
          ushort id;
          if (v["id"].type() == JSONType.integer) {
            id = to!ushort(v["id"].integer);
          } else if (v["id"].type() == JSONType.uinteger) {
            id = to!ushort(v["id"].uinteger);
          }
          values[id] = v;
          res.array ~= v;
        }
      }
      return res;
    } else if(payload.type() == JSONType.null_) {
      JSONValue allDatapoints = parseJSON("[]");
      allDatapoints.array.length = descriptions.keys.length;
      auto count = 0;
      foreach(id; descriptions.keys) {
        allDatapoints.array[count] = JSONValue(to!int(id));
        count += 1;
      }

      return getStored(allDatapoints);
    } else {
      throw Errors.wrong_payload_type;
    }
  }

  public JSONValue setValue(JSONValue payload,
      OS_DatapointValueCommand command = OS_DatapointValueCommand.set_and_send) {
    JSONValue res;
    if (payload.type() == JSONType.object) {
      if(("id" in payload) == null) {
        throw Errors.wrong_payload;
      }
      if(payload["id"].type() != JSONType.integer &&
          payload["id"].type() != JSONType.uinteger &&
          payload["id"].type() != JSONType.string) {
        throw Errors.wrong_payload;
      }

      ushort id = getIdFromJson(payload["id"]);
      payload["id"] = JSONValue(id);

      if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
        throw Errors.datapoint_out_of_bounds;
      }
      if((id in descriptions) == null) {
        throw Errors.datapoint_not_found;
      }
      res = parseJSON("{}");
      auto rawValue = convert2OSValue(payload);
      rawValue.command = command;
      auto setValResult = baos.SetDatapointValueReq([rawValue]);
      // for each datapoint add item to response
      if (setValResult.success) {
        res = convert2JSONValue(rawValue);
        values[id] = res;
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
        if(value["id"].type() != JSONType.integer &&
            value["id"].type() != JSONType.uinteger &&
            value["id"].type() != JSONType.string) {
          throw Errors.wrong_payload;
        }

        ushort id = getIdFromJson(value["id"]);
        value["id"] = JSONValue(id);

        if(id < MIN_DATAPOINT_NUM || id > MAX_DATAPOINT_NUM) {
          throw Errors.datapoint_out_of_bounds;
        }
        if((id in descriptions) == null) {
          throw Errors.datapoint_not_found;
        }
        auto rawValue = convert2OSValue(value);
        rawValue.command = command;
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
            values[rawValues[i].id] = res.array[resCount];
            res.array[resCount]["success"] = true;
            resCount += 1;
          }
        } else {
          throw setValResult.error;
        }
      }

      // moving in rawValues array
      while (currentIndex < rawValues.length) {
        expectedLen += 4;
        expectedLen += rawValues[currentIndex].length;
        if (expectedLen > maxResLen - 1) {
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
    if (payload.type() == JSONType.integer ||
        payload.type() == JSONType.uinteger ||
        payload.type() == JSONType.string) {

      ushort id = getIdFromJson(payload);

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
        if(jid.type() != JSONType.integer &&
            jid.type() != JSONType.uinteger &&
            jid.type() != JSONType.string) {
          throw Errors.wrong_payload_type;
        }

        ushort id = getIdFromJson(jid);

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
          throw setValResult.error;
        }
      }

      // moving in rawValues array
      while (currentIndex < rawValues.length) {
        expectedLen += 4;
        expectedLen += rawValues[currentIndex].length;
        if (expectedLen > maxResLen - 1) {
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
    } else if (payload.type() == JSONType.false_) {
      uvalue[0] = 0;
    } else if (payload.type() == JSONType.integer) {
      if (payload.integer != 0) {
        uvalue[0] = 1;
      } else {
        uvalue[0] = 0;
      }
    } else if (payload.type() == JSONType.uinteger) {
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

  public JSONValue getServerItems() {
    JSONValue res = parseJSON("[]");

    res.array.length = 17;
    auto serverItemMessage = baos.GetServerItemReq(1, 17);
    if (!serverItemMessage.success) {
      throw serverItemMessage.error;
    }

    auto count = 0;
    foreach(si; serverItemMessage.server_items) {
      res.array[count] = parseJSON("{}");
      res.array[count]["id"] = si.id;
      res.array[count]["value"] = si.value;
      res.array[count]["raw"] = Base64.encode(si.value);
      count += 1;
    }

    res.array.length = count;

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
      auto count = 0;
      foreach(OS_DatapointValue dv; ind.datapoint_values) {
        // convert to json type
        try {
          res["payload"].array[count] = convert2JSONValue(dv);
          values[dv.id] = res["payload"].array[count];
          count++;
        } catch(Exception e) {
          writeln(e);
          if (e == Errors.datapoint_not_found) {
            print_logo();
            writeln(" ==== Unknown datapoint indication was received ==== ");

            bool initialized = false;
            while(!initialized) {
              // set flags to false.
              // if bus was connected/disconnected few times
              // or there was "reset" request
              // while initializing sdk
              baos.processResetInd();
              // and init
              initialized = init();
            }
            res["method"] = "sdk reset";
            res["payload"] = true;

            return res;
          }
        }
      }
      if (count > 0) {
        res["payload"].array.length = count;
      } else {
        res = parseJSON("null");
      }
    }
    if (ind.service == OS_Services.ServerItemInd) {
      res = parseJSON("{}");
      res["method"] = "server item";
      res["payload"] = parseJSON("[]");
      res["payload"].array.length = ind.server_items.length;
      auto count = 0;
      foreach(OS_ServerItem si; ind.server_items) {
        try {
          res["payload"].array[count] = parseJSON("{}");
          res["payload"].array[count]["id"] = si.id;
          res["payload"].array[count]["value"] = si.value;
          res["payload"].array[count]["raw"] = Base64.encode(si.value);
          count++;
        } catch(Exception e) {
          writeln(e);
        }
      }
      if (count > 0) {
        res["payload"].array.length = count;
      } else {
        res = parseJSON("null");
      }
    }

    return res;
  }

  // entry point
  // load datapoints at very start and reset
  public bool init() {
    auto serverItemMessage = baos.GetServerItemReq(14, 1);
    // maximum buffer size
    SI_currentBufferSize = 0;
    writeln("Loading server items");
    if (serverItemMessage.service == OS_Services.GetServerItemRes && serverItemMessage.success) {
      foreach(OS_ServerItem si; serverItemMessage.server_items) {
        // maximum buffer size
        if (si.id == 14) {
          SI_currentBufferSize = si.value.read!ushort();
          writefln("Current buffer size: %d bytes", SI_currentBufferSize);
        }
      }
    } else {
      //writeln("Unknown response to GetServerItemReq");

      return false;
    }
    writeln("Server items loaded");
    writeln("Loading datapoints");

    // clear old datapoint descr if preset
    descriptions.clear();
    // count for loaded datapoints number
    auto count = 0;

    // calculate max num of dps in one response
    // GetDatapointDescriptionRes has a header(6b) and 5bytes each dp
    // so, incoming message can contain descr for following num of dpts:
    ushort number = to!ushort(SI_currentBufferSize - 6)/5;
    ushort start = 1;
    while(start < MAX_DATAPOINT_NUM ) {
      if (MAX_DATAPOINT_NUM - start <= number) {
        number = to!ushort(MAX_DATAPOINT_NUM - start + 1);
      }
      auto descr = baos.GetDatapointDescriptionReq(start, number);
      if (descr.success && descr.service == OS_Services.GetDatapointDescriptionRes) {
        foreach(OS_DatapointDescription dd; descr.datapoint_descriptions) {
          descriptions[dd.id] = dd;
          count++;
        }
      } else  if (!descr.success && descr.service == OS_Services.GetDatapointDescriptionRes) {
        // there will be a lot of baos erros, 
        // if there is datapoints no configured
        // and so ignore them
      } else if (descr.service == OS_Services.unknown) {
        //writeln("Unknown response to GetDatapointDescriptionReq");

        return false;
      }
      start += number;
    }
    writefln("Datapoints[%d] loaded.", count);
    values.clear();

    return true;
  }

  public bool resetBaos() {
    return baos.reset();
  }
  public bool resetBaos(string device, string params) {
    return baos.reset(device, params);
  }

  // on incoming reset req. ETS download/bus dis and then -connected
  public JSONValue processResetInd() {
    JSONValue res = parseJSON("null");
    if (baos.processResetInd()) {
      print_logo();
      writeln(" ==== Reset indication was received ==== ");

      bool initialized = false;
      while(!initialized) {
        // set flags to false.
        // if bus was connected/disconnected few times
        // or there was second "reset" request
        // while initializing sdk
        baos.processResetInd();
        // and init
        initialized = init();
      }
      res = parseJSON("{}");
      res["method"] = "sdk reset";
      res["payload"] = true;

      return res;
    }

    return res;
  }

  this(string device = "/dev/ttyS1", string params = "19200:8E1") {
    baos = new Baos(device, params);
  }
}
