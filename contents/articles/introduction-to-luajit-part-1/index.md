---
title: Introduction to LuaJIT [1/2]
author: cellux
date: 2013-01-19 20:38
template: article.jade
---

Now that we have [our own Linux system][prev] to work on, we can start writing programs for the Pi.

[prev]: /articles/diy-linux-with-buildroot-part-1/

After much investigation, I decided to write these programs in [Lua][] - more exactly [LuaJIT][], a highly optimized implementation of the original Lua 5.1 VM developed by a single person, Mike Pall, who - based on his work - seems to be nothing short of a genius. This guy implemented a just-in-time compiler for Lua which can compile Lua bytecode straight into optimized machine code on the x86/x64, PPC, MIPS *and ARM* architectures. Furthermore, he added an excellent foreign function interface which makes it a breeze to interface Lua code with C libraries.

[Lua]: http://www.lua.org/
[LuaJIT]: http://www.luajit.org/

As LuaJIT is already included in the Buildroot distribution, it takes just the flip of a switch to install it into our root fs (see my [Buildroot article][br-article] for details). There is one catch though: Buildroot 2012.11.1 contains a late beta version of LuaJIT, not the final 2.0.0. If you want the final version, you should clone the [Buildroot GitHub repository] and replace the `buildroot-2012.11.1/package/luajit` folder with the version from the master branch before running `make`.

[br-article]: /articles/diy-linux-with-buildroot-part-1/
[Buildroot GitHub repository]: git://git.buildroot.net/buildroot

The LuaJIT package installs the following files to the root fs:

```
/usr/bin/luajit
/usr/lib/libluajit-5.1.so
/usr/share/luajit-2.0.0/jit/bc.lua
/usr/share/luajit-2.0.0/jit/bcsave.lua
/usr/share/luajit-2.0.0/jit/dis_arm.lua
/usr/share/luajit-2.0.0/jit/dis_mipsel.lua
/usr/share/luajit-2.0.0/jit/dis_mips.lua
/usr/share/luajit-2.0.0/jit/dis_ppc.lua
/usr/share/luajit-2.0.0/jit/dis_x64.lua
/usr/share/luajit-2.0.0/jit/dis_x86.lua
/usr/share/luajit-2.0.0/jit/dump.lua
/usr/share/luajit-2.0.0/jit/v.lua
/usr/share/luajit-2.0.0/jit/vmdef.lua
```

From these, `libluajit-5.1.so` plays the central role: this ~500kb library contains the complete Lua interpreter, compiler, standard library and foreign function interface. If we had the necessary header files, we could use this library from C like this:

```C
#include <stdio.h>
#include <luajit-2.0/lua.h>
#include <luajit-2.0/lauxlib.h>

int main (int argc, char **argv) {
  if (argc > 1) {
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    luaL_dostring(L, argv[1]);
    lua_close(L);
  }
  else {
    fprintf(stderr, "Usage: %s [lua-code]\n", argv[0]);
  }
}
```

`luaL_newstate` creates a new Lua VM instance, `luaL_openlibs` makes the standard library available to code running in this VM, `luaL_dostring` compiles the program given in its second parameter (a C string) to Lua bytecode - probably machine code in the case of LuaJIT! - and then executes it. `lua_close` destroys the VM instance and takes care of cleanup.

Variables defined in Lua may be accessed from C through an easy-to-use API. The programmer can also make C functions and data structures available in Lua. A frequently used pattern is to separate the codebase into two parts: a C/C++ part provides a set of low-level components (like objects of a 3D engine), while the Lua part glues these components together into the desired app.

The application's startup code may look like this:

1. Load and initialize low-level C/C++ components, bind them into the Lua VM
2. Load and execute a `main()` function implemented in Lua

In sophisticated systems, the Lua side may open a network socket and listen for connections from the developer. Through this socket the programmer can send in Lua code which is instantly compiled and executed in the context of the running app. Functions of the app thus may be replaced in real-time - while the app is running - which provides a great environment for experimentation.

The `/usr/bin/luajit` binary is a simple C frontend to `libluajit-5.1.so`: it provides a REPL (read-eval-print loop) and can also run a Lua script file if we pass one as an argument.

The files under `/usr/share/luajit-2.0.0/jit` are part of LuaJIT's `jit` library, which provides a Lua API to the JIT compiler. Through this lib we can control the JIT, disassemble Lua bytecode (and the machine code generated from it) or get a human-readable dump of the code in its various stages as it progresses through the JIT compiler.

##### A tour of the language

In the rest of this article I will attempt to give a concise introduction to Lua. For further details - and a description of the C API which I won't discuss here -, I highly recommend reading the [Lua 5.1 manual][] (a work of art in itself - on par with the [R5RS standard][] if you know what I mean).

[Lua 5.1 manual]: http://www.lua.org/manual/5.1/manual.html
[R5RS standard]: http://schemers.org/Documents/Standards/R5RS/

Lua is a "polyglot" language: you can write Lua programs in procedural, object oriented or functional style - most likely mixing and matching these approaches as you go. It has all the usual control structures: *if..then..elseif..end*, *while..do..end*, *repeat..until* and two variants of the *for* loop. It has *booleans* - `true` and `false`, *numbers* - which correspond to C doubles, *strings* - 8-bit clean, counted byte arrays and *tables* - used to implement arrays, maps, records, trees, objects and modules. There is also the special value *nil* - a singleton value serving the same role as *None* in Python or *NULL* in Java (meaning "no value").

*Functions* in Lua are first-class values: they can be created with literals, stored in variables and passed to functions as arguments. *Threads* (aka coroutines) allow several independent threads of execution inside a single Lua VM. These are not OS-level threads: there is no built-in scheduler to pre-empt them, so from time to time they must voluntarily give up control using the `coroutine.yield()` function. (The same model was used in [Windows 3.1][] to implement multitasking.)

[Windows 3.1]: http://en.wikipedia.org/wiki/Scheduling_%28computing%29#Windows

The last two types - *userdata* and *lightuserdata* - are used to represent C data structures and plain pointers on the Lua side.

Lua has the four standard arithmetic operators (`+`, `-`, `*`, `/`), a modulo operator (`%`), exponentiation (`^`) and a prefix "length-of" operator (`#`). Comparison can be done using `==`, `<`, `>`, `<=` and `>=`. The "not-equal" operator is `~=` (not <span style="font-family: monospace">!=</span>). Booleans and numbers are compared by value. Tables, functions, threads and userdata are considered equal if they reference the same object on the Lua heap. Strings are special: they are interned in a string table (a hash map) which [guarantees][luaS_newlstr] that any given string encountered during execution gets stored in memory only once. This means that after

[luaS_newlstr]: http://www.lua.org/source/5.1/lstring.c.html#luaS_newlstr

```Lua
a = "hello, world"
b = "hello, world"
```

both `a` and `b` reference the same string value. Comparison of two strings thus boils down to a [simple pointer comparison][luaV_equalval]. As a result, we can use strings for the same purpose we would use enums in C or C++ without causing speed loss or significant memory bloat.

[luaV_equalval]: http://www.lua.org/source/5.1/lvm.c.html#luaV_equalval

In the following sections I will illustrate various areas (and idioms) of the language using small code snippets mostly originating from Steve Donovan's [Penlight][], a comprehensive library of Lua utility functions. The code has been simplified a bit: I removed error handling and any extra features which would decrease the clarity - and therefore education value - of the examples.

[Penlight]: http://github.com/stevedonovan/Penlight/

Let's start with a simple function which converts its single numeric argument to a string, with thousands separated by commas (`12345678` => `"12,345,678"`):

```Lua
function comma(val)
   local thou = math.floor(val/1000)
   if thou > 0 then return comma(thou)..','..string.format('%03d', val % 1000)
   else return tostring(val) end
end
```

The first line of the function declares the local variable `thou`. Local variables can be only accessed inside the lexical scope that defined them - in this case the body of the function. We initialize `thou` with the value of `math.floor(val/1000)`, using the `floor` function from the built-in `math` module. If `math.floor(val/1000)` is positive, then the original `val` was greater than 1000, therefore we'll need a comma before the last three digits. Here the function goes recursive: it calls itself to return a properly comma-separated string representation of `math.floor(val/1000)`, then concatenates a comma and the last three digits to the result (`..` is the string concatenation operator, `%` is modulo, `string.format` works like `printf` in C). If the `val` we got was less than 1000, then we just return `val` converted to a string.

(Note: the `tostring` function has its brother `tonumber` which can be used to convert a string to a number.)

Let's see a slightly more complicated example, a function which expands tab characters to spaces in a string:

```Lua
function expand_tabs(s,n)
   n = n or 8
   return s:gsub('([^\t]*)\t',
                 function(s)
                    return s..(' '):rep(n - #s % n)
                 end)
end
```

The first argument of expand_tabs (`s`) is the string with the tabs in it, the second arg (`n`) specifies the width of one tab in character units.

The `n = n or 8` idiom takes advantage of the short-circuiting nature of Lua's `or` operator: if the value of `n` is logically true - which in Lua means it is neither `nil` nor `false` - then the value of `n` stays as it is, otherwise it's replaced by eight. This idiom is widely used to assign default values to function arguments.

The `s:gsub()` invocation calls a *method* on string object `s` - the exact meaning of this will be revealed later. The `gsub` method searches the string for the pattern given in the first argument (`([^\t]*)\t`), calls the function passed as the second arg for every match it finds and substitutes the match with the function's result. If the search pattern contains parenthesized subpatterns (captures), then the function is called with a list of the corresponding matches (as separate arguments), otherwise the entire match gets passed (in a single argument).

This particular `gsub` invocation looks for groups of non-tab characters followed by a single tab, and replaces every match with the group of non-tab characters (unchanged) plus the right amount of spaces for the last tab. As `#s` returns the length of the string (the group of non-tab chars), `n - #s % n` gives the number of spaces which must be appended to make up for a single tab.

The `(' '):rep()` call invokes the `rep(n)` string method which returns the string repeated `n` times.

Strings in Lua may contain the following embedded escape sequences:

```Lua
\a bell
\b backspace
\f form feed
\n newline
\r carriage return
\t horizontal tab
\v vertical tab
\\ backslash
\" quotation mark [double quote]
\' apostrophe [single quote]
```

It doesn't matter if a string is enclosed in single (`'`) or double (`"`) quotes, the semantics are the same.

If you want to include a character with any byte value between 0-255, use `\nnn` where `nnn` is the byte value in decimal:

```Lua
assert("\a\b\f\n\r\t\v\\\"\'" == "\007\008\012\010\013\009\011\092\034\039")
```

Embedded zeroes are ok.

(`assert` checks that its argument evaluates to true and throws an error if it doesn't.)

###### Logical operators

Lua has three logical operators: `or`, `and` and `not`.

Their precedence order: `not` > `and` > `or`.

Both `and` and `or` have short-circuiting behavior.

The following examples illustrate their use:

```Lua
so_ext = os == "Windows" and 'dll' or 'so'
```

This example checks whether `os` equals the string `"Windows"`, if it does, the value of `so_ext` will be `'dll'`, otherwise, it will be `'so'`. The `'so'` part will be evaluated only if the `os == "Windows" and 'dll'` part evaluates to false - which is only possible if `os` was not `"Windows"`.

```Lua
year = Y + (Y < 35 and 2000 or 1900)
```

This line might be familiar to any maintenance programmer who spent the last years of the twentieth century removing Y2K bugs.

```Lua
step = finish > start and 1 or -1
```

A way to decide whether we should increment or decrement our index variable in the upcoming loop if we want to get from `start` to `finish`.

```Lua
if not year and not month and not day then
   error "at least the year, the month or the day must be specified"
end
```

`error` is the way to signal an error in Lua. This is similar to *throw* in other languages. The error that is thrown (which may be any object, not just a string) can be caught using `pcall` (protected call):

```Lua
function main(arg1,arg2,arg3)
  if arg1 > 5 then
    error("no")
  else
    return arg3,arg2,arg1
  end
end

status,res1,res2,res3 = pcall(main,1,2,3)
assert(status==true)
assert(res1==3)
assert(res2==2)
assert(res3==1)

status,res1,res2,res3 = pcall(main,9,8,7)
assert(status==false)
assert(type(res1)=="string")
assert(res2==nil)
assert(res3==nil)
```

If the protected function (`main` in this case) didn't call `error` anywhere in its call graph, `pcall` returns with a `true` status plus the values returned by the function. (Here you can see how functions can return multiple values in Lua.)

In the other case, `pcall` returns `false` and the error message (or object) which was thrown. As there are only two results, `res2` and `res3` are set to `nil`.

The `type` function returns the type of its argument as a string.

You may wonder why I used parentheses around `error`'s argument in one case, and no parentheses in the other: in Lua, you are free to leave out the parentheses if you call a function with a single argument which is either a *string* or a *table constructor*.

###### Tables

Tables are associative arrays mapping unique keys to values. Both keys and values may be of an arbitrary type (but not `nil`).

Tables are created with a table constructor:

```Lua
months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
```

This table can be used to map abbreviated month names to month numbers:

```Lua
assert(months["jan"]==1)
assert(months["oct"]==10)
```

For keys which are valid Lua identifiers - meaning a string of letters, digits, and underscores not beginning with a digit - the following notation is also accepted:

```Lua
assert(months.jan==1)
assert(months.oct==10)
```

Here is a function which converts accented characters in a string to their non-accented counterparts:

```Lua
local accent_maps = {
   hu = {
     ['á'] = 'a',
     ['é'] = 'e',
     ['í'] = 'i',
     ['ó'] = 'o',
     ['ú'] = 'u',
     ['ö'] = 'o',
     ['ü'] = 'u',
     ['ő'] = 'o',
     ['ű'] = 'u',
   },
}

function remove_accents(s,lang)
   for from,to in pairs(accent_maps[lang]) do
      s = s:gsub(from,to)
   end
   return s
end

assert(remove_accents("árvíztűrő tükörfúrógép",'hu')=="arvizturo tukorfurogep")
```

The function is not particularly efficient, but it works. It uses a `for..in` loop to iterate over the key-value pairs in a particular accent map (identified by `accent_maps[lang]`) and substitutes one kind of accented character on each iteration of the loop. The code assumes that the strings we process and the string literals in the code are encoded with the same character encoding. Lua doesn't know anything about accented characters: the keys in the `accent_maps.hu` table are seen as simple byte strings.

As you probably noticed from the code, the list of items in a table constructor may end with a single comma - this feature helps us avoid a common error we get in other, more strict languages when we try to add new elements to a table - or change the order of elements - but forget to tidy up the separating commas.

The `gsub` method is used in a slightly different manner than previously: if its second arg is a string, `gsub` uses that directly as the replacement value.

###### Arrays

In Lua, traditional arrays (with integer indices) are also implemented with tables:

```Lua
arr = { 1,5,10,20 }
```

This table constructor is short-hand for the following, more verbose one:

```Lua
arr = { [1]=1,[2]=5,[3]=10,[4]=20 }
```

In other words, if we list a value without a key, it gets an auto-incremented index starting from 1:

```Lua
arr = { 1,2,fire="water","leaves",[1]=8,nil,function() return 42 end }
assert(arr[1]==8)
assert(arr[2]==2)
assert(arr.fire=="water")
assert(arr[3]=="leaves")
assert(arr[4]==nil)
assert(type(arr[5])=="function")
assert(arr[5]()==42)
```

As the example shows, an element which belongs to an already assigned index (`1`) may be later overwritten by explicit specification of the same integer key (`[1]=8`).

Internally, table elements indexed by integers are kept separately (in an *array part*) from elements indexed by other types (the *hash part*). This ensures optimal efficiency for both use cases.

###### Control structures: the for..in loop

The `for..in` loop can be used to iterate over a series of values provided by an *iterator function* (the semantics will be explained later).

It's typically used like this:

```Lua
for <var1>,<var2>,... in <iterator> do
  <block>
end
```

On each pass of the loop, `<iterator>` returns a fixed number of values which get assigned to the `<var1>`, `<var2>`, ... local variables visible inside `<block>`.

A common use case is iteration over the key-value pairs of a table:

```Lua
function table_copy(t)
   local res = {}
   for k,v in pairs(t) do
      res[k] = v
   end
   return res
end
```

The iterator created by `pairs(t)` returns two values on each iteration: the key and value of the next element in `t`.

Here is a function to count the number of elements:

```Lua
function table_size(t)
   local i = 0
   for k in pairs(t) do i = i + 1 end
   return i
end
```

As you see, you don't have to take all values provided by the iterator: here we only take the key. (This is generally true: if you call a function which returns N values but you assign less than N variables on the calling side, the rest of the values are silently dropped. On the contrary, if you assign more values than returned from the function, the remaining variables will be set to `nil`.)

```Lua
function table_foreach(t,fun)
   for k,v in pairs(t) do
      fun(k,v)
   end
end
```

Here we take the function `fun` and apply it to each key-value pair in the table.

Let's see how we could write a function which gets an array of daily maximum temperatures, a limit, and prints the first day when the daily temperature exceeded the limit.

First we define a table with the temperatures and print it out using `table_foreach`:

```Lua
daily_max_temperatures = {30, 35, 32, 34, 38};

table_foreach(daily_max_temperatures,
  function(day,temp)
    print(string.format("the temperature on day #%d was %d degrees", day, temp))
  end)
```

The result:

```
the temperature on day #1 was 30 degrees
the temperature on day #2 was 35 degrees
the temperature on day #3 was 32 degrees
the temperature on day #4 was 34 degrees
the temperature on day #5 was 38 degrees
```

Now let's build a function which takes a table `t` and a function `pred`, then finds the first value `v` in table `t` for which `pred(v)` returns a logically true value (neither `nil` nor `false`):

```Lua
function table_find_if(t,pred)
   for k,v in pairs(t) do
      if pred(v) then return k,v end
   end
   return nil
end
```

If a table has both integer and non-integer keys, `pairs` first iterates over the elements keyed with integer indices (in ascending key order) and then over the rest (in unspecified order). <small>([source])</small>

[source]: http://www.lua.org/source/5.1/ltable.c.html#luaH_next

```Lua
function table_find_if_exceeds(t,limit)
   return table_find_if(t, function(v) return v > limit end)
end
```

This one finds the first value in `t` which exceeds `limit`. Returns both the key and the value.

Utilizing these helper functions, we could build a solution to the original problem like this:

```Lua
function print_first_day_when_temp_exceeded(limit, templist)
   day,degrees = table_find_if_exceeds(templist, limit)
   if day then
      print(string.format("The temperature on day #%d exceeded the limit of %d by %d degrees.", day, limit, degrees-limit))
   end
end

print_first_day_when_temp_exceeded(36, daily_max_temperatures)
```

###### Understanding the for..in loop

The [Lua manual][] gives the following definition for the `for..in` loop:

[Lua manual]: http://www.lua.org/manual/5.1/manual.html#2.4.5

A `for` statement like

```Lua
for <var_1>, ···, <var_n> in <explist> do
  <block>
end
```

is equivalent to the following code:

```Lua
do
  local f, s, var = <explist>
  while true do
    local <var_1>, ···, <var_n> = f(s, var)
    var = <var_1>
    if var == nil then break end
    <block>
  end
end
```

(`do...end` creates a new lexical scope for a block of statements. `break` can be used to exit the innermost `while`, `repeat` or `for` loop.)

To help you decipher this definition, I offer the following code example:

```Lua
function range(from,to)
  local function f(s,var)
    if var == nil then return from
    elseif var >= to then return nil
    else return var+1 end
  end
  return f,nil,nil
end

local s = ""
for i in range(1,10) do s = s..tostring(i) end
assert(s=="12345678910")
```

The `f` *iterator function* created and returned by `range(1,10)` will be called with the following arguments during the `for..in` loop (pseudo-code):

```Lua
f(s=nil,var=nil) => 1
f(s=nil,var=1) => 2
f(s=nil,var=2) => 3
...
f(s=nil,var=9) => 10
f(s=nil,var=10) => nil
```

Upon the first call, `f` gets `var`=`nil`, which corresponds to the initial `var` value returned by `range`. This special "warm-up" case is handled by returning the first value in the series (`from`).

From here on, `f` will be called with the same `var` which it returned in the previous iteration, and it continues to return `var+1` until `var` has reached the higher limit of `to`. At that point, `f` returns `nil`, which signals the `for..in` mechanism that the loop is over.

In this example, we haven't made use of the `s` state variable, so I'll try to show you another - somewhat contrived and hypothetical (although possible) - example where `s` could be put to good use:

```Lua
function mysql_query(sql,params)
  local stmt = mysql_prepare(sql)
  local resultset = stmt:execute(params)
  local f(res)
    return res:fetch_row()
  end
  return f,resultset
end

for row in mysql_query("SELECT * FROM users WHERE year_of_birth<?", {1975}) do
  print(string.format("user %s was born in %d", row.name, row.year_of_birth))
end
```

The example is contrived because we don't really need the state parameter - the following definition of `mysql_query` would also suffice:

```Lua
function mysql_query(sql,params)
  local stmt = mysql_prepare(sql)
  local resultset = stmt:execute(params)
  return function() return resultset:fetch_row() end
end
```

This version would work because Lua functions are actually *closures*: they can hold references to the local variables that were in scope at the point of their definition, even after the block of code which created them (`mysql_query` in this case) has returned.

###### Closures

(This section may be a bit hard-core, feel free to skip it if you don't understand what is going on.)

Formally, each closure (= function) is a `<proto,upvalues,env>` triple, where `proto` is a compiled function skeleton (prototype), `upvalues` is an array of references (pointers) to external local variables used by the closure and `env` is a table used to look up the value of global variables.

When the `mysql_query` function gets compiled - which happens only once, at parse time - the following prototype is created for the iterator function it returns on each call:

```Lua
function()
  return <uv1>:fetch_row()
end
```

The compiler detects that each iterator function created by `mysql_query` will reference one external local variable (labeled `resultset` in the code). In the compiled prototype, `<uv1>` becomes a placeholder for the first element of the closure's `<upvalues>` array, which at this point does not exist yet.

When we actually call `mysql_query` and the argument of the final `return` statement needs to be constructed, the already compiled function prototype is *instantiated*: a new closure is created with its `proto` set to the compiled prototype, `upvalues` set to a newly allocated array of one element (filled with a reference to the `resultset` variable created *during this particular execution of* `mysql_query`) and `env` set to the environment associated with the `mysql_query` function.

Functions (= closures) inherit their environment from the closure that created them. Functions defined at the top level inherit the environment of the top-level closure, which is initially the *global environment*, a singleton table created at VM initialization. The standard library functions are also registered in the global environment.

The `env` of a closure can be retrieved and changed using the `getfenv(f)` and `setfenv(f,table)` functions, respectively. The global environment can be acquired by calling `getfenv(0)`. Using these functions, it's relatively easy to set up a sandboxed Lua environment for execution of potentially dangerous Lua code:

```Lua
local safe_env = { print = print, math = math }
local f = loadfile("user-provided-script.lua")
setfenv(f, safe_env)
f()
```

With this setup, the only things `f()` will have access to are the language keywords (`if`, `while`, `for`, `function`, etc.), the `print` function and all functions in the `math` module. In particular, `f()` cannot access the global environment because `getfenv` is not available to it.

Warning: if you do a `setfenv(0,{})`, you will be most likely doomed.

###### Arithmetic progressions

For this type of iteration, we use another variant of the `for` loop:

```Lua
local tablex = {}

function tablex.range (start,finish,step)
   if start == finish then return {start}
   elseif start > finish then return {}
   end
   local res = {}
   local k = 1
   if not step then
      step = finish > start and 1 or -1
   end
   for i=start,finish,step do res[k]=i; k=k+1 end
   return res
end

local t = tablex.range(1,10,3)
assert(#t==4 and t[1]==1 and t[2]==4 and t[3]==7 and t[4]==10)
```

What you are seeing here is probably the simplest approach to the creation of namespaces: just make a table and place functions into it.

`function tablex.range() ... end` is shorthand for `tablex.range = function() ... end`: we create a function and assign it to a table element.

The following function returns the *tail* of its list argument - a new list consisting of every element in the original list except the first:

```Lua
local append = table.insert

function tail(ls)
   local res = {}
   for i = 2,#ls do
      append(res,ls[i])
   end
   return res
end
```

The `step` argument of a counted `for` loop defaults to 1.

The `table.insert` function comes from the standard library. The reason why the code creates a local proxy for it may be interesting: `tail` - as a closure - has access to both external local variables in its enclosing scopes (via `upvalues`) and global variables (through its `environment`). When `tail`'s function prototype gets compiled, the compiler analyzes the function's variable references and assigns them into three groups: stack, upvalue and env references. References to stack variables - function arguments and local variables defined inside the function - will become simple pointers to a known element on the stack. References to upvalues - external locals in any of the enclosing scopes - will become pointers to elements of the `upvalues` array, while global references will be compiled into a table lookup (the name of the variable will be looked up - at runtime - in the closure's `env`).

As stack and upvalue lookups need only a pointer dereference, and the position of a given item in the respective array is hard-coded into the function's bytecode, these can be significantly faster than the hash table lookup implied by a global reference.

On the other hand, statically hard-coded upvalues cannot be (easily) replaced after the function has been compiled, so if we want dynamic code updates (live coding), the use of global references may be preferred.

###### While..do..end

The following function joins a list of path components into a complete pathstring, using the path separator passed as the first argument:

```Lua
function path_join(sep, ...)
   local parts = {...}
   for i,part in ipairs(parts) do
      -- Strip leading slashes on all but first item
      if i > 1 then
         while part:sub(1,1) == sep do
            part = part:sub(2)
         end
      end
      -- Strip trailing slashes on all but last item
      if i < #parts then
         while part:sub(#part) == sep do
            part = part:sub(1,#part-1)
         end
      end
      parts[i] = part
   end
   return table.concat(parts,sep)
end

assert(path_join('/', '/usr', 'bin', 'luajit') == '/usr/bin/luajit')
```

The major new element introduced here is the *vararg expression* (`...`) used to collect the arguments following `sep`.

This is a special construct with only a handful of uses:

1. you may use it inside a table constructor (if used in the middle, it expands to the first item, if used as the last value, it expands to all items)
2. you may use it on the right side of a multiple assignment (with the same rules)
3. you can return it from a function (it gets unpacked to multiple return values)
4. you can pass it to another function (if passed as the last argument, the callee gets the contained items as extra arguments, if passed as a middle arg, the callee gets the first item)

`local parts = {...}` places the extra arguments into a local table for easy access.

The `ipairs(t)` function creates an iterator which returns a series of `(1,t[1])`, `(2,t[2])`, `(3,t[3])`, ... pairs. This function was invented for iterating integer-indexed arrays. A possible Lua implementation:

```Lua
function ipairs(t)
   local function f(t,var)
      var = var + 1
      local next = t[var]
      if next then
         return var, next
      else
         return nil
      end
   end
   return f,t,0
end
```

The `s:sub(start[,end])` method returns a substring of `s` starting at (1-based) index `start` and ending at `end` (inclusive). If `end` is not supplied, it defaults to `#s`. Both `start` and `end` may be negative, in which case they count from the end of the string (`-1` corresponds to the last character).

Comments begin with `--` and extend to the end of line.

`table.concat(t,sep)` joins the elements of `t` into a string, with the elements separated by `sep`.

###### Repeat..until

```Lua
function fs.readfile(path)
   local fd = fs.open(path, "r")
   local parts = {}
   local length = 0
   local offset = 0
   repeat
      local chunk, len = fs.read(fd, offset, 4096)
      if len > 0 then
         offset = offset + len
         length = length + 1
         parts[length] = chunk
      end
   until len == 0
   fs.close(fd)
   return table.concat(parts)
end
```

This should be trivial to understand by now. The loop exits when the expression following `until` becomes logically true.

As you see, the local variable `len` - defined inside the repeat..until block - can be also accessed in the expression after `until`. In other words, the scope of the repeat..until block extends to the expression after `until`.

###### Metatables

A *metatable* is an ordinary Lua table with VM-defined, special keys. These metatables can be associated with any Lua value (usually a table) to change the behavior of the following VM operations:

<table>
  <tr>
    <th>Operator symbol</th>
    <th>Name of operation</th>
    <th>Corresponding metatable key</th>
  </tr>
  <tr>
    <td>`+`</th>
    <td>addition</th>
    <td>`__add`</th>
  </tr>
  <tr>
    <td>`-`</th>
    <td>subtraction</th>
    <td>`__sub`</th>
  </tr>
  <tr>
    <td>`*`</th>
    <td>multiplication</th>
    <td>`__mul`</th>
  </tr>
  <tr>
    <td>`/`</th>
    <td>division</th>
    <td>`__div`</th>
  </tr>
  <tr>
    <td>`%`</th>
    <td>modulo</th>
    <td>`__mod`</th>
  </tr>
  <tr>
    <td>`^`</th>
    <td>exponentiation</th>
    <td>`__pow`</th>
  </tr>
  <tr>
    <td>`-`</th>
    <td>unary minus</th>
    <td>`__unm`</th>
  </tr>
  <tr>
    <td>`..`</th>
    <td>concatenation</th>
    <td>`__concat`</th>
  </tr>
  <tr>
    <td>`#`</th>
    <td>length</th>
    <td>`__len`</th>
  </tr>
  <tr>
    <td>`==`</th>
    <td>equality test</th>
    <td>`__eq`</th>
  </tr>
  <tr>
    <td>`<`</th>
    <td>less than</th>
    <td>`__lt`</th>
  </tr>
  <tr>
    <td>`<=`</th>
    <td>less than or equal</th>
    <td>`__le`</th>
  </tr>
  <tr>
    <td>`[]`</th>
    <td>get element</th>
    <td>`__index`</th>
  </tr>
  <tr>
    <td>`[]=`</th>
    <td>set element</th>
    <td>`__newindex`</th>
  </tr>
  <tr>
    <td>`()`</th>
    <td>call</th>
    <td>`__call`</th>
  </tr>
</table>

For instance, if you implemented complex numbers as a table of two elements (real and imaginary components), and arrange it so that every such table gets an associated metatable which overrides the standard arithmetic operations in the right way, you could use these operators on your complex tables in the same way you would use them on ordinary numbers.

Instead of discussing all the minutae regarding metatables - which you can find in the [Lua manual][] -, I'll show you how to define a custom `List` datatype using them.

[Lua manual]: http://www.lua.org/manual/5.1/manual.html#2.8

Our new `List` datatype will behave like a class: it will have a "constructor" and "methods" which can be invoked on its "objects".

The class methods will be stored as functions inside a `List` table (the "class" itself):

```Lua
List = {}
List.__index = List

function List.new(t)
   t = t or {}
   return setmetatable(t, List)
end
```

`List.new()` creates a new List object, which is nothing more than a plain table with `List` as its metatable. `setmetatable(t,mt)` sets `mt` as the metatable of `t` and then returns `t`.

Before trying to understand the `List.__index = List` line, let's define some methods:

```Lua
function List:append(i)
   table.insert(self,i)
   return self
end

List.push = List.append

function List:extend(L)
   for i = 1,#L do table.insert(self,L[i]) end
   return self
end
```

`function List:append(i) ... end` is syntactic sugar for `function List.append(self,i) ... end`. Similarly, calling `obj:method(...)` is the same as calling `obj.method(obj, ...)` (but `obj` is evaluated only once).

`List.push` is defined as an alias for `List.append`.

Now let's discuss what happens when you do this:

```Lua
local ls = List.new()
ls:push(1)
```

After the assignment, `ls` is a plain (and empty) table, with its metatable set to `List`. When the VM tries to find `ls.push`, it doesn't find it in `ls` itself, so it checks whether `ls` has a metatable (it has) and whether this metatable has an `__index` key (it has). If the value under the `__index` key is a table (it is), then the VM checks this table for a `push` key as well. If `push` exists there, its value is returned as the lookup result.

Now you can understand why `List.__index` has been set to `List` itself: to let List objects find their methods.

```Lua
function List:insert(i, x)
   table.insert(self,i,x)
   return self
end

function List:remove (i)
   table.remove(self,i)
   return self
end
```

The three-argument version of `table.insert(t,i,x)` inserts `x` at position `i`, `table.remove(t,i)` removes the `i`th element.

```Lua
function List:remove_value(x)
   for i=1,#self do
      if self[i]==x then table.remove(self,i) return self end
   end
   return self
end

function List:pop(i)
   if not i then i = #self end
   return table.remove(self,i)
end

function List:count(x)
   local cnt=0
   for i=1,#self do
      if self[i]==x then cnt=cnt+1 end
   end
   return cnt
end
```

These are all pretty straight-forward.

```Lua
function List:reverse()
   local t = self
   local n = #t
   local n2 = n/2
   for i = 1,n2 do
      local k = n-i+1
      t[i],t[k] = t[k],t[i]
   end
   return self
end
```

Here we can see an important feature of multiple assignment: in `t[i],t[k] = t[k],t[i]` Lua does the assignment only after all expressions on the right side have been evaluated.

```Lua
function List:minmax()
   local vmin,vmax = 1e70,-1e70
   for i = 1,#self do
      local v = self[i]
      if v < vmin then vmin = v end
      if v > vmax then vmax = v end
   end
   return vmin,vmax
end

function List:len()
   return #self
end

function List:clone()
   local ls = List.new({})
   ls:extend(self)
   return ls
end

function List:__concat(L)
   local ls = self:clone()
   ls:extend(L)
   return ls
end
```

Here we defined a `__concat` metamethod to concatenate two `List` values.

Let's define the equality operation as well:

```Lua
function List:equals(L)
   if #self ~= #L then return false end
   for i = 1,#self do
      if self[i] ~= L[i] then return false end
   end
   return true
end

List.__eq = List.equals
```

The reason for the indirection (`__eq` => `equals`): the equality metamethod is invoked only if the compared values have the same metatable (both are `List`s). It is *not* invoked if we try to compare a List with a plain table, so we provide a separate `equals` method for that.

```Lua
local function tostring_q(val)
   local s = tostring(val)
   if type(val) == 'string' then
      s = '"'..s..'"'
   end
   return s
end
```

This is a helper function for the `List.join` method defined below: if `val` is a string, it returns it between double quotes, otherwise returns it stringified with `tostring`.

```Lua
function List:map(f)
   local ls = List.new()
   for i=1,#self do
      ls:append(f(self[i]))
   end
   return ls
end

function List:join(delim,tostrfn)
   delim = delim or ''
   tostrfn = tostrfn or tostring_q
   return table.concat(self:map(tostrfn), delim)
end

function List:__tostring()
   return '{'..self:join(',')..'}'
end
```

Finally, we set a metatable on `List` itself, to enable the use of `List` as a constructor:

```Lua
setmetatable(List,{
    __call = function (tbl,arg)
       return List.new(arg)
    end,
})
```

Here are some test cases to verify that everything works as expected:

```Lua
local ls = List()
assert(getmetatable(ls)==List)
ls:push(1)
ls:append("fire")
ls:push(3.14)
assert(ls:equals {1,"fire",3.14})
ls:extend(ls)
assert(ls:equals {1,"fire",3.14,1,"fire",3.14})
ls:insert(3,"water")
assert(ls:equals {1,"fire","water",3.14,1,"fire",3.14})
ls:remove(1)
ls:remove(4)
assert(ls:equals {"fire","water",3.14,"fire",3.14})
assert(tostring(ls)=='{"fire","water",3.14,"fire",3.14}')
ls:remove_value(3.14)
assert(ls:equals {"fire","water","fire",3.14})
assert(ls:pop()==3.14)
assert(ls:pop(2)=="water")
assert(ls:equals {"fire","fire"})
assert(ls:count("fire")==2)
assert(ls:count("water")==0)
ls = List({1,6,3,8,10})
ls:reverse()
assert(ls:equals {10,8,3,6,1})
local min,max = ls:minmax()
assert(min==1 and max==10)
assert(ls:len()==5)
clone = ls:clone()
assert(clone==ls)
clone[1]=20
assert(clone~=ls)
assert(ls:equals {10,8,3,6,1})
assert(clone:equals {20,8,3,6,1})
```

###### Coroutines

Coroutines are independent threads of execution inside a single Lua VM.

The coroutine API consists of the following functions:

<style>
  #coroutine-api td, #coroutine-api th {
    vertical-align: top;
  }
</style>

<table id="coroutine-api">
  <tr>
    <th>API function</th>
    <th>Purpose</th>
  </tr>
  <tr>
    <td>`coroutine.create(f)`</td>
    <td>create a new coroutine (`f` will be its main function)</td>
  </tr>
  <tr>
    <td>`coroutine.resume(co,...)`</td>
    <td>start/resume a coroutine</td>
  </tr>
  <tr>
    <td>`coroutine.running()`</td>
    <td>returns the currently running coroutine (`nil` when called by the main thread)</td>
  </tr>
  <tr>
    <td>`coroutine.status(co)`</td>
    <td>`"running"` / `"suspended"` / `"normal"` / `"dead"`</td>
  </tr>
  <tr>
    <td>`coroutine.wrap(f)`</td>
    <td>create a coroutine and wrap it inside a function which resumes it when called</td>
  </tr>
  <tr>
    <td>`coroutine.yield(...)`</td>
    <td>suspends execution of the current coroutine</td>
  </tr>
</table>

A coroutine created with `coroutine.create(f)` is initially in the `"suspended"` state. You can start it with `coroutine.resume(co,...)`, which is similar to a simple call of its main function `f`. The difference is that normal functions can only return by invoking `return` or `error` (implicitly or explicitly), while coroutines can also return with `coroutine.yield(...)` and do that from any location in `f`'s call graph.

Upon the execution of `coroutine.yield(...)`, the state of the current coroutine gets "frozen" and control gets back to the code which executed `coroutine.resume`. The arguments passed to `coroutine.yield(...)` are returned by `coroutine.resume` in the same way as values passed to a simple `return` statement are returned by the corresponding function call.

Coroutines that have yielded can be continued exactly at the point where they yielded by calling `coroutine.resume` again. The extra arguments passed to `coroutine.resume(co,...)` become return values of the corresponding `coroutine.yield(...)` call inside the coroutine.

A coroutine that has been resumed can call `coroutine.resume` itself. A coroutine that is waiting for its own `coroutine.resume` call to return (or yield) is in the `"normal"` state (= active but not `"running"`). A `"dead"` coroutine is one which finished execution, either normally (main function returned) or because of an error.

The purpose - ok, one possible purpose - of `coroutine.wrap` is to create a function suitable for use as an iterator in a `for..in` loop. Using `coroutine.yield`, the iterator function doesn't have to adapt to the idiosyncrasies of the `for..in` loop: it can just gather the values and yield them one by one as they arrive.

Hopefully all of this will become reasonably clear after studying the following - rather elaborate - code example:

```Lua
local function _dirfiles(dir)
   local dirs = {}
   local files = {}
   local append = table.insert
   for f in ldir(dir) do
      if f ~= '.' and f ~= '..' then
         local p = path.join(dir,f)
         local mode = path.attrib(p,'mode')
         if mode=='directory' then
            append(dirs,f)
         else
            append(files,f)
         end
      end
   end
   return dirs,files
end
```

This helper function takes the path of a  directory, scans this directory and returns the names of directories and files it finds as a pair of tables.

The `ldir`, `path.join` and `path.attrib` functions are not standard Lua: `ldir(dir)` returns an iterator for directory entries in `dir`, `path.join` joins its arguments (path components) using the default path separator, and `path.attrib(p,'mode')` returns `'directory'` or `'file'` depending on the type of `p`.

```Lua
local function _walker(root)
   local dirs,files = _dirfiles(root)
   for i,d in ipairs(dirs) do
      _walker(path.join(root,d))
   end
   coroutine.yield(root,dirs,files)
end

function walk(root)
   return coroutine.wrap(function () _walker(root) end)
end
```

The `walk` function takes a directory path and returns an iterator (actually a wrapped coroutine) which can be used to go over all files and directories under this path, recursively.

Let's see how we could use `walk` in practice:

```Lua
function rmtree(fullpath)
   for root,dirs,files in walk(fullpath) do
      for i,f in ipairs(files) do
         remove(path.join(root,f))
      end
      rmdir(root)
   end
end
```

The `rmtree` function does the same as what `rm -rf` would do in a shell. `remove` removes a file, `rmdir` removes a non-empty directory (these are not standard Lua).

The iterator `walk(fullpath)` returns a `root,dirs,files` tuple for every directory it encounters. As `rmdir` can remove `root` only if it's empty, we have to return (and remove) the files on the bottom level first (this is known as depth-first search). If we wanted to visit directories in a top-down fashion instead (also known as breadth-first search), we'd have to change the position of the yield in `_walker`'s code:

```Lua
local function _walker(root)
   local dirs,files = _dirfiles(root)
   coroutine.yield(root,dirs,files)
   for i,d in ipairs(dirs) do
      _walker(path.join(root,d))
   end
end
```

Contemplate this until you see the light.

Here is an all-in-one example for the same thing, approached from a slightly different angle:

```Lua
function dirtree(d)
   local exists, isdir = path.exists, path.isdir
   local sep = path.sep

   local function yieldtree(dir)
      for entry in ldir(dir) do
         if entry ~= "." and entry ~= ".." then
            entry = dir .. sep .. entry
            if exists(entry) then  -- Just in case a symlink is broken.
               local is_dir = isdir(entry)
               yield(entry,is_dir)
               if is_dir then
                  yieldtree(entry)
               end
            end
         end
      end
   end

   return coroutine.wrap(function() yieldtree(d) end)
end
```

###### Chunks

Before discussing our last topic - the module system -, I must introduce you to the concept of *chunks*.

In Lua, there are three functions that deal with loading (and possibly executing) source code:

1. `dofile(filename)` loads the given file, compiles it into a chunk and executes it
2. `loadfile(filename)` loads the given file, compiles it and returns it as a chunk
3. `loadstring(string)` compiles the given string and returns it as a chunk

(There is also the lower-level `load(func)` which can be used to load the source code incrementally, in pieces.)

The code obtained from any of these sources gets compiled as if it were the body of an anonymous function, and the resulting function is called a *chunk*.

As an example, if you create a file `chunk.lua` with the following contents:

```Lua
function add(x,y) return x+y end
function mul(x,y) return x*y end

local a,b = ...
return add(a,b),mul(a,b)
```

Then you can compile it into a chunk and then call it like this:

```Lua
local f = loadfile("chunk.lua")
local res = {f(3,4)}
assert(res[1]==7)
assert(res[2]==12)
```

Note: the functions `add` and `mul` spring into existence when we call `f`: their prototypes - which were compiled when `chunk.lua` was parsed - are instantiated into two closures which are bound into the global environment under the `add` and `mul` keys.

As you see, a chunk can take arguments - through `...` - and return values just like any ordinary function.

###### Modules

In Lua, modules - also known as packages or namespaces - are implemented as tables.

The source code of a module is placed into a separate source file (typically `<modname>.lua`).

The module file looks something like this:

```Lua
-- mymodule.lua

local mymodule = {}

function mymodule.f() ... end
function mymodule.g() ... end
function mymodule.h() ... end

return mymodule
```

and imported like this (in first approximation):

```Lua
local mymodule = dofile("mymodule.lua")
mymodule.g()
```

The problem with this approach is that modules are not cached: any time you `dofile` them, they are loaded and executed again.

Lua provides the following mechanism to deal with this:

The global table `package.loaded` contains already loaded modules (module name => return value of module chunk).

The global function `require(modname)` checks whether the module has been already loaded. If it finds a value at `package.loaded[modname]`, that value is returned. Otherwise it tries to load module `modname` using a set of *loaders* (see the [manual][manual-loaders] for details). If the load succeeds, the module chunk is executed and the result value is placed into `package.loaded[modname]`. Finally, the value at `package.loaded[modname]` is returned to the caller.

[manual-loaders]: http://www.lua.org/manual/5.1/manual.html#5.3

There is one last little detail to be aware of: the `package.path` variable which tells `require` where it should look for modules:

```Lua
./?.lua;/usr/share/luajit-2.0.0/?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua
```

(This is LuaJIT's default value on my machine.)

`require(modname)` splits this string at `;` separators to get a list of paths to try, and replaces each `?` with `modname`.

Relative paths are relative to the current working directory (*not* to the location of the source file calling `require`).

##### Tying loose ends

If you want to get a complete picture of Lua, read up on the following topics in the [Lua manual][]:

[Lua manual]: http://www.lua.org/manual/5.1/manual.html

* bracketed (long) comments and string literals
* numeric literals formats (decimal, scientific, hex)
* rules of automatic coercion between strings and numbers
* the necessity of explicit blocks for `return` and `break` (when used in the middle of another block)
* interpolation of function return values and `...`
  * in the middle of a list
  * at the end of a list
  * within parentheses
* the lack of automatic type conversion in equality comparisons
* the exact semantics of the `#` (length-of) operator when used on tables
* precedence of operators
* tail calls
* the exact semantics of metatables and metamethods
* garbage collection, weak tables
* standard libraries
* the C API (not really needed as LuaJIT has a great FFI)

In the next part, I will introduce the LuaJIT FFI by building an example application which binds to the EGL and OpenVG libraries to draw something tangible on the screen.

Stay tuned.
