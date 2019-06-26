/****
TODO: convert funcs
 ****/

module datapoints;

import std.algorithm;
import std.math;
import std.bitmanip;
import std.range.primitives : empty;

enum DatapointType {
  unknown,
  dpt1,
  dpt2,
  dpt3,
  dpt4,
  dpt5,
  dpt6,
  dpt7,
  dpt8,
  dpt9,
  dpt10,
  dpt11,
  dpt12,
  dpt13,
  dpt14,
  dpt15,
  dpt16,
  dpt17,
  dpt18
}

class DPT9 {
  static public float toFloat(ubyte[] raw) {
    assert(raw.length == 2);
    ushort int_value = raw.read!ushort();
    auto sign = !!(int_value & 0x8000);
    auto exp = (int_value & 0x7800) >> 11;
    auto mant = int_value & 0x7FF;

    if (sign) {
      mant = -(~(mant - 1) & 0x07FF);
    }

    float value = (0.01 * mant) * pow(2, exp);
    return value;
  }
  static public ubyte[] toUBytes(float value) {
    auto sign = 0x00;
    /***
    float exp = floor(max((log(abs(value) * 100) / log(2)) - 10, 0));
    float mant = (value * 100) / (1 << cast(int)exp);

    if (value < 0) {
      sign = 0x01;
      mant = (~(mant*-1) + 1) & 0x07FF;
    }

    value = round((sign << 15) | (exp << 11) | mant) & 0xFFFF;
    **/

    ubyte[] res;
    res.length = 2;
    // temporary
    res.write!ushort(42, 0);

    return res;
  }
}
class DPT1 {
  static public bool toBoolean(ubyte[] raw) {
    assert(raw.length == 1);
    auto value = raw.read!bool();
    return value;
  }
  static public ubyte[] toUBytes(bool value) {
    ubyte[] res;
    res.length = 1;
    res.write!bool(value, 0);
    return res;
  }
}

class DPT5 {
  static public ubyte toUByte(ubyte[] raw) {
    assert(raw.length == 1);
    auto value = raw.read!ubyte();
    return value;
  }
  static public ubyte[] toUBytes(ubyte value) {
    ubyte[] res;
    res.length = 1;
    res.write!ubyte(value, 0);
    return res;
  }
}
