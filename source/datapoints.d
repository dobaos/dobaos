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

class DPT2 {
  static public bool[string] toDecoded(ubyte[] raw) {
    bool[string] result;

    result["control"] = (raw[0] & 0x02) > 0;
    result["value"] = (raw[0] & 0x01) > 0;

    return result;
  }
  static public ubyte[] toUBytes(bool[string] value) {
    ubyte[] result;

    result.length = 1;
    result[0] = 0x00;
    if (value["control"]) {
      result[0] = result[0] | 0x02;
    }
    if (value["value"]) {
      result[0] = result[0] | 0x01;
    }

    return result;
  }
}

class DPT3 {
  static public ubyte[string] toDecoded(ubyte[] raw) {
    ubyte[string] result;

    result["direction"] = (raw[0] & 0x08) >> 3;
    result["step"] = raw[0] | 0x07;

    return result;
  }
  static public ubyte[] toUBytes(ubyte[string] value) {
    ubyte[] result;

    result.length = 1;
    result[0] = 0x00;
    result[0] = result[0] | ((value["direction"] << 3) & 0xff);
    result[0] = result[0] | value["step"];

    return result;
  }
}

class DPT4 {
  static public char toChar(ubyte[] raw) {
    char result;

    result = cast(char) raw[0] & 0x7f;

    return result;
  }
  static public ubyte[] toUBytes(char value) {
    ubyte[] result;

    result.length = 1;
    result[0] = cast(ubyte) value;

    return result;
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

class DPT6 {
  static public byte toByte(ubyte[] raw) {
    byte result;

    result = raw.read!byte();

    return result;
  }
  static public ubyte[] toUBytes(byte value) {
    ubyte[] result;

    result.length = 1;
    result.write!byte(value, 0);

    return result;
  }
}

class DPT7 {
  static public ushort toUShort(ubyte[] raw) {
    ushort result;

    result = raw.read!ushort();

    return result;
  }
  static public ubyte[] toUBytes(ushort value) {
    ubyte[] result;

    result.length = 2;
    result.write!ushort(value, 0);

    return result;
  }
}

class DPT8 {
  static public short toShort(ubyte[] raw) {
    short result;

    result = raw.read!short();

    return result;
  }
  static public ubyte[] toUBytes(short value) {
    ubyte[] result;

    result.length = 2;
    result.write!short(value, 0);

    return result;
  }
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
    int exp = cast(int) (floor(fmax((log(abs(value) * 100) / log(2)) - 10, 0)));
    int mant = cast(int) (floor(value * 100) / (1 << exp));

    if (value < 0) {
      sign = 0x01;
      mant = (~(mant*-1) + 1) & 0x07FF;
    }

    ushort val = ((sign << 15) | (exp << 11) | mant) & 0xFFFF;

    ubyte[] res;
    res.length = 2;
    res[0] = cast(ubyte) (val >> 8);
    res[1] = cast(ubyte) (val & 0xFF);

    return res;
  }
}

class DPT10 {
  static public ubyte[string] toTime(ubyte[] raw) {
    ubyte[string] result;

    result["day"] = cast(ubyte) ((raw[0] & 0xe0) >> 5);
    result["hour"] = cast(ubyte) (raw[0] & 0x1f);
    result["munutes"] = cast(ubyte) (raw[1] & 0x3f);
    result["seconds"] = cast(ubyte) (raw[2] & 0x3f);

    return result;
  }
  static public ubyte[] toUBytes(ubyte[string] value) {
    ubyte[] result;

    result.length = 3;
    result[0] = cast(ubyte)(result[0] | (value["day"] << 5));
    result[0] = cast(ubyte)(result[0] | (value["hour"] & 0x1f));
    result[1] = cast(ubyte)(result[1] | (value["minutes"] & 0x3f));
    result[2] = cast(ubyte)(result[2] | (value["seconds"] & 0x3f));

    return result;
  }
}

class DPT11 {
  static public ushort[string] toDate(ubyte[] raw) {
    ushort[string] result;

    result["day"] = cast(ushort) (raw[0] & 0x1f);
    result["month"] = cast(ushort) (raw[1] & 0x0f);
    result["year"] = cast(ushort) (raw[2] & 0x7f);
    if (result["year"] >= 90) {
      result["year"] += 1900;
    } else {
      result["year"] += 2000;
    }

    return result;
  }
  static public ubyte[] toUBytes(ushort[string] value) {
    ubyte[] result;

    result.length = 3;
    result[0] = cast(ubyte)(result[0] | (value["day"] & 0x1f));
    result[1] = cast(ubyte)(result[1] | (value["month"] & 0x0f));
    ushort year = value["year"];
    if (year >= 2000) {
      year -= 2000;
    } else {
      year -= 1990;
    }
    result[2] = cast(ubyte)(result[2] | (year& 0x7f));

    return result;
  }
}

class DPT12 {
  static public uint toUInt(ubyte[] raw) {
    uint result;

    result = raw.read!uint();

    return result;
  }
  static public ubyte[] toUBytes(uint value) {
    ubyte[] result;

    result.length = 4;
    result.write!uint(value, 0);

    return result;
  }
}

class DPT13 {
  static public int toInt(ubyte[] raw) {
    uint result;

    result = raw.read!int();

    return result;
  }
  static public ubyte[] toUBytes(int value) {
    ubyte[] result;

    result.length = 4;
    result.write!int(value, 0);

    return result;
  }
}

class DPT14 {
  static public float toFloat(ubyte[] raw) {
    float result;

    result = raw.read!float();

    return result;
  }
  static public ubyte[] toUBytes(float value) {
    ubyte[] result;

    result.length = 4;
    result.write!float(value, 0);

    return result;
  }
}

class DPT16 {
  static public char[] toString(ubyte[] raw) {
    char[] result;

    auto maxLen = max(raw.length, 14);
    result.length = maxLen;

    for (auto i = 0; i < raw.length; i+= 1) {
      result[i] = cast(char) raw[i] & 0x7f;
    }

    return result;
  }
  static public ubyte[] toUBytes(char[] value) {
    ubyte[] result;

    auto maxLen = max(value.length, 14);

    result.length = maxLen;

    for (auto i = 0; i < maxLen; i+= 1) {
      result[i] = cast(ubyte) value[i];
    }

    return result;
  }
}

class DPT18 {
  static public ubyte[string] toDecoded(ubyte[] raw) {
    ubyte[string] result;

    result["learn"] = (raw[0] & 0x80) >> 7;
    result["number"] = raw[0] | 0x7f;

    return result;
  }
  static public ubyte[] toUBytes(ubyte[string] value) {
    ubyte[] result;

    result.length = 1;
    result[0] = 0x00;
    result[0] = cast(ubyte) (result[0] | (value["learn"] << 8));
    result[0] = cast(ubyte) (result[0] | (value["number"] & 0x7f));

    return result;
  }
}
