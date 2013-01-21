---
title: Introduction to LuaJIT
author: cellux
date: 2013-01-19 20:38
template: article.jade
---

Now that we have [our own Linux system][prev] to work on, we can start writing programs for the Pi.

[prev]: /articles/diy-linux-with-buildroot-part-1/

After much investigation, I decided that I'll write these programs in [Lua][] - more exactly [LuaJIT][], a niche implementation of the Lua 5.1 VM developed by a single person, Mike Pall, who seems to be nothing short of a genius. This guy implemented a just-in-time compiler for Lua which can compile Lua bytecode straight into optimized machine code on the x86/x64, PPC, MIPS *and ARM* architectures. Furthermore, he added a foreign function interface which makes it a breeze to interface Lua code with C libraries.

[Lua]: http://www.lua.org/
[LuaJIT]: http://www.luajit.org/

As LuaJIT is already included in the Buildroot distribution, it's just the flip of a switch to install it into our root fs. There is one catch though: Buildroot 2012.11.1 contains a late beta version of LuaJIT, not the final 2.0.0. If you want the final version, clone the [Buildroot GitHub repository] and replace the `buildroot-2012.11.1/package/luajit` folder with the version from the master branch before running `make`.

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

Here `luaL_newstate` creates a new Lua VM instance, `luaL_openlibs` makes the standard library available to code running in this VM, `luaL_dostring` compiles the program given in its second parameter (a C string) to Lua bytecode - probably machine code in the case of LuaJIT! - and then executes it. `lua_close` destroys the VM instance and takes care of cleanup.

Variables defined in Lua may be accessed from the C side through an easy-to-use API. The programmer can also make C functions and data structures available in Lua. A frequently used pattern is to separate the codebase into two parts: a C/C++ part provides a set of lower-level components (like objects of a 3D engine), while the Lua part glues these components together into the desired app. The application's startup code may look like this:

1. Load and initialize all lower-level C/C++ components, bind them into a Lua VM
2. Load and execute a main() function implemented in Lua

In sophisticated systems, the Lua side may open a network socket and listen for connections from the developer. Through this socket the programmer can send in Lua code which is instantly compiled and executed in the context of the running app. Functions of the app thus may be replaced in real-time - while the app is running - which provides a great environment for experimentation.

The `/usr/bin/luajit` binary is a simple C frontend to `libluajit-5.1.so`: it provides a REPL (read-eval-print loop) and can also run a Lua script file if one is passed as an argument.

The files under `/usr/share/luajit-2.0.0/jit` are part of LuaJIT's `jit` library, which provides a Lua API to the JIT compiler. Through this lib we can control the JIT, disassemble Lua bytecode (and the machine code generated from it) or get a human-readable dump of the code in its various stages as it progresses through the JIT compiler.

##### A tour of the language

In this section I will give a short, concise introduction to Lua. If you are interested in the details - and the intricacies of the C API which I won't discuss here -, I highly recommend reading the [Lua 5.1 manual][] which is a work of art in itself - on par with the [R5RS standard][] if you know what I mean.

[Lua 5.1 manual]: http://www.lua.org/manual/5.1/manual.html
[R5RS standard]: http://schemers.org/Documents/Standards/R5RS/

Lua is a "polyglot" language: you can write Lua programs in procedural, object oriented or functional style - most likely mixing and matching these approaches as you go. It has all the usual control structures: *if..then..elseif..end*, *while..do..end*, *repeat..until* and two variants of the *for* loop. It has *booleans* - `false` or `true`, *numbers* - which correspond to C doubles, *strings* - which are 8-bit clean, counted byte arrays and *tables* - used to implement arrays, maps, records, trees, objects and modules. There is also the special value *nil* - a singleton value serving the same role as *None* in Python or *NULL* in Java (meaning "no value").

*Functions* in Lua are first-class values: they can be stored in variables and passed to functions as arguments. *Threads* allow several independent threads of execution inside a single Lua VM. These are not OS-level threads: there is no built-in scheduler which could pre-empt them, so once in a while they must voluntarily give up control using the `coroutine.yield()` function. (The same model was used in [Windows 3.1][] to implement multitasking.)

[Windows 3.1]: http://en.wikipedia.org/wiki/Scheduling_%28computing%29#Windows

The last two types - *userdata* and *lightuserdata* - are used to represent C data structures and pointers on the Lua side.

Lua has the four standard arithmetic operators (`+`, `-`, `*`, `/`), a modulo operator (`%`), exponentiation (`^`) and a prefix "length-of" operator (`#`). Comparison can be done using `==`, `<`, `>`, `<=` and `>=`. The "not-equal" operator is `~=` (not !=). Booleans and numbers are compared by value. Tables, functions, threads and userdata are considered equal if they reference the same object on the Lua heap. Strings are special: they are interned in a string table (a hash map) which [guarantees][luaS_newlstr] that any given string encountered in the code gets stored in memory only once. This means that after

[luaS_newlstr]: http://www.lua.org/source/5.1/lstring.c.html#luaS_newlstr

```Lua
a = "hello, world"
b = "hello, world"
```

both `a` and `b` reference the same string value. Comparison of two strings thus boils down to a [simple pointer comparison][luaV_equalval]. As a result of this, we can use strings for the same purpose we would use enums in C or C++ without causing speed loss or memory bloat.

[luaV_equalval]: http://www.lua.org/source/5.1/lvm.c.html#luaV_equalval

In the following sections, I will introduce the various areas of the language using small code snippets, mostly originating from Steve Donovan's [Penlight][], a comprehensive library of Lua utility functions. The code has been simplified: I removed error handling and any extra features which would decrease the clarity - and therefore education value - of the examples.

[Penlight]: http://github.com/stevedonovan/Penlight/

Let's start with the definition of a simple function which converts its single numeric argument to a string, with thousands separated by commas (`12345678` => `"12,345,678"`):

```Lua
function comma(val)
   local thou = math.floor(val/1000)
   if thou > 0 then return comma(thou)..','..string.format('%03d', val % 1000)
   else return tostring(val) end
end
```

The first line of the function declares the local variable `thou`. Local variables can be only accessed from the enclosing lexical scope - in this case the body of the function. We initialize `thou` with the value of `math.floor(val/1000)`, using the `floor` function from the built-in `math` module. If `val/1000` is positive, then the original `val` was greater than 1000, therefore we'll need a comma before the last three digits. Here the function goes recursive: it calls itself to return a properly comma-separated string representation of `val/1000` and then concatenates a comma and the last three digits to the result (`..` is the string concatenation operator, `%` is modulo, `string.format` works like `printf` in C). If the `val` we got was less than 1000, then we just return `val` converted to a string.

(The `tostring` function has its brother `tonumber`, which can be used to convert a string to a number.)

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

The `s:gsub()` invocation calls a *method* on string object `s` - the exact meaning of this will be revealed later. The `gsub` method searches for the pattern given in the first argument (`([^\t]*)\t`), calls the function passed as the second arg for every match it finds and substitutes the match with the function's result. If the search pattern contains parenthesized subpatterns (captures), then the function is called with a list of these (as separate arguments), otherwise the entire match gets passed (as a single argument).

This particular `gsub` call looks for groups of non-tab characters followed by a single tab, and replaces every match with the group of non-tab characters (unchanged) plus the right amount of spaces for the last tab. As `#s` returns the length of the string (the group of non-tab chars), `n - #s % n` gives the number of spaces which must be appended to make up for a single tab.

The `(' '):rep()` call invokes the `rep(n)` method which returns the string repeated `n` times.

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

If you want to include a character with any byte value (between 0-255), use `\nnn` where `nnn` is the byte value in decimal:

```Lua
assert("\a\b\f\n\r\t\v\\\"\'" == "\007\008\012\010\013\009\011\092\034\039")
```

(`assert` checks that its argument evaluates to true and throws an error if it doesn't.)

###### Tables

Tables are associative arrays, mapping unique keys to values. Both keys and values may be of an arbitrary type (but not `nil`).

Tables are created with a table constructor:

```Lua
months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
```

This table can be used to map abbreviated month names to month numbers:

```Lua
assert(months["jan"]==1)
assert(months["oct"]==10)
```

For strings keys which are acceptable as Lua identifiers - meaning any string of letters, digits, and underscores not beginning with a digit - the following notation is also accepted:

```Lua
assert(months.jan==1)
assert(months.oct==10)
```

For example, here is a function which converts accented characters in a string to their non-accented counterparts:

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

The function is not particularly efficient, but it works. It uses a `for..in` loop to iterate over the key-value pairs of a particular accent map (identified by `accent_maps[lang]`) and substitutes one kind of accented character on each iteration of the loop. The code assumes that the strings we process and the string literals in the code are encoded with the same character encoding. Lua doesn't know anything about accented characters: the keys in the `accent_maps.hu` table are seen as simple byte strings.

As you probably noticed from the code, the list of items in a table constructor may end with a single comma: this feature helps us avoid a common error we get in other, more strict languages when we add new elements to a table or change the order of elements.

The `gsub` method is used in a slightly different manner than previously: if the second arg is a string, then `gsub` uses that directly as the replacement value.

###### Arrays

In Lua, traditional arrays - with integer indices - are also implemented with tables:

```Lua
arr = { 1,5,10,20 }
```

This table constructor is short-hand for the following one:

```Lua
arr = { [1]=1,[2]=5,[3]=10,[4]=20 }
```

In other words, if we list a value without a key in a table constructor, then it gets an auto-incremented index starting from 1:

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

As you can see, an element which belongs to an already assigned index (`1`) may be later overwritten by explicit specification of the same integer key (`[1]=8`).

The `type` function returns the type of its argument as a string.

###### The for..in loop

The `for..in` loop is arguably the most complicated feature of the language.

In the Lua manual we find the following definition:

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

To help you decipher this definition, study the following code example:

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

The `f` *iterator function* created and returned by `range(1,10)` will be called with the following arguments (pseudo-code):

```Lua
f(s=nil,var=nil) => 1
f(s=nil,var=1) => 2
f(s=nil,var=2) => 3
...
f(s=nil,var=9) => 10
f(s=nil,var=10) => nil
```

Upon the first call, `f` gets `var`=`nil`, which corresponds to the initial `var` value returned by `range`. This special "warm-up" case is handled by returning the first value in the series (`from`).

From here on, `f` will be called with the same `var` which it returned in the previous iteration, and it continues to return `var+1` until `var` has reached the higher limit of `to`. At this point, `f` returns `nil`, which signals the `for..in` mechanism that the loop is over.

In this example, we haven't made use of the `s` state variable, so I'll try to show you a - somewhat contrived and hypothetical (although possible) - example where `s` could be put to good use:

```Lua
function mysql_query(sql,params)
  local stmt = mysql_prepare(sql)
  local resultset = stmt:execute(params)
  local f(res)
    return res:fetch_row()
  end
  return f,resultset
end

for row in mysql_query("SELECT * FROM users WHERE year_of_birth<?",
                       {year_of_birth=1975}) do
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

This version works because Lua functions are actually *closures*: they can hold references to the variables that were in scope at the point of their definition, even after the block of code which created them (`mysql_query` in this case) has returned.

###### Closures

(This section is a bit hard-core, feel free to skip it if you don't understand what is going on.)

Formally, each closure is a `<proto,upvalues,env>` triple, where `proto` is a compiled function skeleton (prototype), `upvalues` is an array of references (pointers) to external local variables used by the closure and `env` is a table used to look up the values of global variables.

When the `mysql_query` function gets compiled - which happens only once, when its code is parsed - the following prototype is created for the iterator function to be returned:

```Lua
function()
  return <uv1>:fetch_row()
end
```

The compiler detects that each iterator function created by `mysql_query` will reference one external local variable (`resultset`). In the compiled code, `<uv1>` becomes a reference to the first element of the closure's `<upvalues>` array, which at this point does not exist yet.

When we actually call `mysql_query` and the argument of the final `return` statement needs to be constructed, the already compiled function prototype is *instantiated*: a new closure is created with its `proto` set to the compiled prototype, `upvalues` set to a newly allocated array of one element (filled in with a reference to the `resultset` variable created *during this particular execution of* `mysql_query`) and `env` set to the environment associated with the `mysql_query` function (which is also a closure).

Functions (= closures) defined at at the top level inherit the environment of the top-level closure, which is initially set to the *global environment*, a singleton table created at VM initialization. (The standard library functions are also registered into this global environment.)

The `env` of a closure can be retrieved and changed using the `getfenv(f)` and `setfenv(f,table)` functions, respectively. The global environment can be acquired by calling `getfenv(0)`. Using these functions, it's relatively easy to set up a sandboxed Lua environment for execution of potentially dangerous Lua code:

```Lua
local safe_env = { print = print, math = math }
local f = loadfile("user-provided-script.lua")
setfenv(f, safe_env)
f()
```

With this setup, the only things `f()` will have access to are the basic language facilities (`if`, `while`, `for`, `function`, etc.), the `print` function and all functions in the `math` module. It cannot get access to the global environment because `getfenv` is not available.

Warning: if you do a `setfenv(0,{})`, you are most likely doomed.

# logical operators (and, or, not)

if list_delim and value:find(list_delim) then ... end

function join(items, sep)
  sep = sep or ','
  ...
end

function readline(file)
  local f = file or io.stdin
  ...
end

i1,j1 = i1 or 1, j1 or 1
local arg = _G.arg or error "not in a main program"

so_ext = path.is_windows and 'dll' or 'so'
year = Y + (Y < 35 and 2000 or 1999)
if finish > start then step = finish > start and 1 or -1 end

if not t.year and not t.month and not t.day then ... end

# while <exp> do <block> end

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
         while part:sub(#part) == self.sep do
            part = part:sub(1,#part-1)
         end
      end
      parts[i] = part
   end
   return table.concat(parts,sep)
end

# repeat <block> until <exp>

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

# break

-- from http://lua-users.org/wiki/SplitJoin
-- coded by Philippe Lhoste

function split(str, delim, maxnb)
   -- Eliminate bad cases...
   if string.find(str, delim) == nil then
      return { str }
   end
   if maxnb == nil or maxnb < 1 then
      maxnb = 0    -- No limit
   end
   local result = {}
   local pat = "(.-)" .. delim .. "()"
   local nb = 0
   local lastpos
   for part, pos in string.gfind(str, pat) do
      nb = nb + 1
      result[nb] = part
      lastpos = pos
      if nb == maxnb then break end
   end
   -- Handle the last field
   if nb ~= maxnb then
      result[nb + 1] = string.sub(str, lastpos)
   end
   return result
end

# for <v> = <e1>, <e2>, <e3> do <block> end

function tail(ls)
   local res = {}
   local append = table.insert
   for i = 2,#ls do
      append(res,ls[i])
   end
   return res
end

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

# for <var_1>, ..., <var_n> in <explist> do <block> end

function table_size(t)
   local i = 0
   for k in pairs(t) do i = i + 1 end
   return i
end

function table_copy(t)
   local res = {}
   for k,v in pairs(t) do
      res[k] = v
   end
   return res
end

function table_foreach(t,fun)
   for k,v in pairs(t) do
      fun(v,k)
   end
end

daily_max_temperatures = {30, 35, 32, 34, 38};

table_foreach(daily_max_temperatures,
              function(temp,day)
                 print("the temperature on day #%d was %d degrees", day, temp)
              end)

function table_find_if(t,cmp,arg)
   for k,v in pairs(t) do
      local c = cmp(v,arg)
      if c then return k,c end
   end
   return nil
end

function table_find_if_exceeds(t,limit)
   return table_find_if(t, function(t,max) return t > max and t-max or false end, limit)
end

function print_first_day_when_temp_exceeded(degrees, templist)
   day,amount = table_find_if_exceeds(templist, degrees)
   print(string.format("The temperature on day #%d exceeded the limit of %d by %d degrees.", day, degrees, amount)
end

print_first_day_when_temp_exceeded(36, daily_max_temperatures)

function readlines(filename)
   local f,err = io.open(filename,'r')
   local res = {}
   for line in f:lines() do
      table.insert(res,line)
   end
   f:close()
   return res
end

if list_delim and value:find(list_delim) then
   value = split(value,list_delim)
   for i,v in ipairs(value) do
      value[i] = process_value(v)
   end
end

function split(s, re)
   local res = {}
   local t_insert = table.insert
   re = '[^'..re..']+'
   for k in s:gmatch(re) do t_insert(res,k) end
   return res
end

local ends = { ['('] = ')', ['{'] = '}', ['['] = ']' }
local begins = {}; for k,v in pairs(ends) do begins[v] = k end

# ...

function table_pack(...)
   local n = select('#',...)
   return {n=n; ...}
end

# metatables

local List = {}
List.__index = List

function List.new(t)
   t = t or {}
   return setmetatable(t, List)
end

local tinsert,tremove = table.insert,table.remove

function List:append(i)
   tinsert(self,i)
   return self
end

List.push = tinsert

function List:extend(L)
   for i = 1,#L do tinsert(self,L[i]) end
   return self
end

function List:insert(i, x)
   tinsert(self,i,x)
   return self
end

function List:remove (i)
   tremove(self,i)
   return self
end

function List:remove_value(x)
   for i=1,#self do
      if self[i]==x then tremove(self,i) return self end
   end
   return self
end

function List:pop(i)
   if not i then i = #self end
   return tremove(self,i)
end

function List:count(x)
   local cnt=0
   for i=1,#self do
      if self[i]==x then cnt=cnt+1 end
   end
   return cnt
end

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

function List:equals(L)
   if #self ~= #L then return false end
   for i = 1,#self do
      if self[i] ~= L[i] then return false end
   end
   return true
end

List.__eq = List.equals

function List:map(f)
   local ls = List.new()
   for i=1,#self do
      ls:append(f(self[i]))
   end
   return ls
end

local function tostring_q(val)
   local s = tostring(val)
   if type(val) == 'string' then
      s = '"'..s..'"'
   end
   return s
end

function List:join(delim,tostrfn)
   delim = delim or ''
   tostrfn = tostrfn or tostring_q
   return table.concat(self:map(tostrfn), delim)
end

function List:__tostring()
   return '{'..self:join(',')..'}'
end

setmetatable(List,{
    __call = function (tbl,arg)
       return List.new(arg)
    end,
})

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

# coroutines

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

local function _walker(root,bottom_up)
   local dirs,files = _dirfiles(root)
   if not bottom_up then coroutine.yield(root,dirs,files) end
   for i,d in ipairs(dirs) do
      _walker(root..path.sep..d,bottom_up)
   end
   if bottom_up then coroutine.yield(root,dirs,files) end
end

local dir = {}

function dir.walk(root,bottom_up)
   return coroutine.wrap(function () _walker(root,bottom_up) end)
end

function dir.rmtree(fullpath)
   for root,dirs,files in dir.walk(fullpath,true) do
      for i,f in ipairs(files) do
         remove(path.join(root,f))
      end
      rmdir(root)
   end
end

function dir.dirtree(d)
   local exists, isdir = path.exists, path.isdir
   local sep = path.sep

   local last = sub (d,-1)
   if last == sep or last == '/' then
      d = sub(d,1,-2)
   end

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

   return wrap(function() yieldtree(d) end)
end


Comments are introduced by `--`, everything on the line after the `--` belongs to the comment:

```Lua
s = "string" -- here we assign a string
```

Multi-line comments may be written using `--[[` ... `]]`:

```Lua
--[[
this is a
multi-line
comment
]]
```

Literal strings can be likewise defined in a multi-line form:

```Lua
s = [[This is
a multi-line
string]]
```

Embedded new-lines are preserved, with one exception: a newline immediately following the opening `[[` is swallowed:

```Lua
s2 = [[
This is
a multi-line
string]]
assert(s == s2)
```

Strings may contain various escape sequences:

```Lua
assert("\a\b\f\n\r\t\v\\\"\'" == "\007\008\012\010\013\009\011\092\034\039")
```

The `\nnn` sequences are decimal ASCII codes which are transformed to the corresponding character. `\a` = bell, `\b` = backspace, `\f` = form feed, `\n` = newline, `\r` = carriage return, `\t` = horizontal tab, `\v` = vertical tab. Strings may have embedded zeroes, so `"zero\000inside"` is a valid Lua string (with a length of 11).

Functions are defined and used like this:

```Lua
function add2(x,y)
  return x + y
end

print("5+3="..add2(5,3))
```

The `..` operator concatenates two strings. The number operand returned by `add2` is automatically coerced to a string following automatic conversion rules (see section [2.2.1][] in the Lua manual).

[2.2.1]: http://www.lua.org/manual/5.1/manual.html#2.2.1

Functions are first-class values in Lua, so the previous definition could be also written like this:

```Lua
add2 = function(x,y)
  return x + y
end
```

Here we create an anonymous function object and then assign it to the variable `add2`.

