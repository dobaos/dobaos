module logo;

import std.stdio;
import std.random;

string[] logo;

shared static this() {
  logo.length = 3;
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

}

void print_logo() {
  // prints random logo
  string logo2print = logo.choice();
  writeln(logo2print);
}
