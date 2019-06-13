/****
TODO: convert funcs
 ****/

module datapoints;

import std.math;
import std.bitmanip;
import std.range.primitives : empty;


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
