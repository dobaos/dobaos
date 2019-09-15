module logo;

import std.stdio;
import std.random;

string[] logo;

shared static this() {
  logo.length = 6;
  logo[0] = "\n".dup;
  logo[0] ~= "  ()-()     hello, friend\n";
  logo[0] ~= "   \\\"/_     here comes dobaos again\n";
  logo[0] ~= "    '  )    with the liquor and drugs\n";

  logo[1] = "\n".dup;
  logo[1] ~= "  ()-()     hello, friend\n";
  logo[1] ~= "   \\\"/_     this whole world has just begun\n";
  logo[1] ~= "    '  )    and it's so nice to meet me\n";

  logo[2] = "\n".dup;
  logo[2] ~= "  ()-()     hello, friend\n";
  logo[2] ~= "   \\\"/_     this is what you want\n";
  logo[2] ~= "    '  )    this is what you get\n";

  logo[3] = "\n".dup;
  logo[3] ~= "  ()-()     я кричу - не слышу крика\n";
  logo[3] ~= "   \\\"/_     не вяжу от страха лыка,\n";
  logo[3] ~= "    '  )                вижу плохо я\n";

  logo[4] = "\n".dup;
  logo[4] ~= "  ()-()     they say\n";
  logo[4] ~= "   \\\"/_     everything is beautiful when it begins\n";
  logo[4] ~= "    '  )    but I was too busy being selfish\n";

  logo[5] = "\n".dup;
  logo[5] ~= "  ()-()     I was a dam builder\n";
  logo[5] ~= "   \\\"/_     across the river deep and wide\n";
  logo[5] ~= "    '  )    where still and water did collide\n";
}

void print_logo() {
  // prints random logo
  string logo2print = logo.choice();
  writeln(logo2print);
}
