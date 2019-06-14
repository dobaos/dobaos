/****
TODO: convert funcs
 ****/

module datapoints;

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
}
class DPT1 {
  static public bool toBoolean(ubyte[] raw) {
    assert(raw.length == 1);
    auto value = raw.read!bool();
    return value;
  }
}
