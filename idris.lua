#!/bin/lua5.4
local function printUsage()
  print([[

    Idris v1.0
    --------------------------------------------------------------------------------
  
    Convert natural language instructions into executable scripts
  
    Syntax:
    ~~~~~~~~
    lua5.4 idris.lua --lang=<language code> --database=<database with commands> \
      [--prefix=<prefix>] [--shell-output] [--verbose] [--help] 'input 1' 'input 2' ...
  
    Options:
    ~~~~~~~
    --lang=<language code>   =>  Specifies the language to be used.
    --database=<database>    =>  Defines the source of commands.
    --prefix=<prefix>        =>  Adds an optional prefix to commands.
    --shell-output           =>  Formats the output for shell script usage.
    --interactive            =>  Entra no modo iterativo
    --compile, -c            =>  Generate a database from datasheet.tsv file
    --verbose, -v            =>  Activates verbose output.
    --debug, -d              =>  Prints de database location of each command
    --help, -h               =>  Displays this help message.
  
    Example Usage:
    ~~~~~~~~~~~~~~
    lua5.4 idris.lua --lang=pt_BR --database=demonstration \
      'create file test.txt, put the phrase Hello World in it!'

    
    ]])
  os.exit(0)
end

local lang,database,prefix,separator,interactive,shellOutput,debugMode = nil,nil,"","\n",false,false,false

local tokens,contexts,current_context = {},{},{}

local function split(input)
  local words = {}
  for word in input:gmatch "[^%s]+" do
    words[#words+1] = word
  end
  return words
end

local function find(index,base,skip_recursive)
  local block = ""
  local struct = {}
  local next_index = 0

  local candidate = ""

  for i=index,#tokens do
    local token = tokens[i]
    token = Language.normalize((base == DB and candidate == "") and Language.infinitive(token:lower()) or token)

    candidate = candidate == "" and token or candidate.." "..token
    if base[candidate] then
      block = candidate
      next_index = i
      struct = base[candidate]
      break
    end
  end

  if skip_recursive then
    if block == "" and index < #tokens+1 then
      return find(index+1,base,true)
    end
  end

  if block == "" then
    return nil
  end

  return block,struct,next_index
end

local function printContexts(levels,base,_)
  for _,context in ipairs(base) do
    print(("  "):rep(levels)..(levels == 0 and "local db_slice_".._.." = {" or "{"))
    print(("  "):rep(levels).."  trigger = '"..context.trigger:gsub("\n","\\n"):gsub("'","\\'").."',")
    print(("  "):rep(levels).."  arg = '"..context.arg:gsub("\n","\\n"):gsub("'","\\'").."',")
    print(("  "):rep(levels).."  command = '"..context.command:gsub("\n","\\n"):gsub("'","\\'").."',")
    printContexts(levels+1,context)
    print(("  "):rep(levels)..(levels == 0 and "}" or "},"))
  end
end

local function printOutput(levels,base,args)
  for _, context in ipairs(base) do
    if levels == 0 then
      local sub_args = {{context.arg,context.command}}
      printOutput(levels+1,context,sub_args)
      local commandOutput = ""
      if context.command:sub(-1,-1) ~= "\r" then
        for _, arg in ipairs(sub_args) do
          local command = arg[2]
          for j = 1, #sub_args, 1 do
            command = command:gsub("\0{"..j.."}",sub_args[j][1])
          end
          commandOutput = command
        end
        if debugMode then
          printContexts(0,contexts,_)
          io.write("\nlocal command_".._.." = '"..commandOutput:gsub("'","\\'")..separator:gsub("\n","\\n"):gsub("'","\\'").."'\n")
          io.write("\n------------------------------------------------------------------------\n\n")
        else
          io.write((commandOutput)..separator)
        end
      end
    else
      args[#args+1] = {context.arg,context.command}
      printOutput(levels+1,context,args)
    end
  end
end

local function processTokens()
  local i = 1
  while tokens[i] ~= nil do
    local token = tokens[i]

    if current_context.trigger == nil then
      local block,struct,next_index = find(i,DB,false)
      if block then
        contexts[#contexts+1] = {
          trigger = block,
          struct = struct,
          arg = "",
          command = (struct or {[0] = ""})[0] or ""
        }
        current_context = contexts[#contexts]
      end
    else
      if Language.list_separators[token] or Language.list_separators_symbols[token:sub(-1,-1)] then
        local block,struct,next_index = find(i+1,DB,false)
        if block then
          if #token>1 and Language.list_separators_symbols[token:sub(-1,-1)] then
            token = token:sub(1,-2)
            current_context.arg = current_context.arg..(current_context.arg == "" and token or " "..token)
          end
          current_context = {}
        else
          current_context.arg = current_context.arg..(current_context.arg == "" and token or " "..token)
        end
      else
        if Language.personal_pronoun[token] and #current_context == 0 then
          for j=#contexts-1, 1, -1 do
            if contexts[j][1] then
              local trigger = contexts[j][1].trigger
              local arg = contexts[j][1].arg

              if current_context.struct[trigger] then
                local struct = current_context.struct[trigger]
                current_context[#current_context+1] = {
                  trigger = trigger ,
                  struct = struct,
                  arg = arg,
                  command = struct[0] or ""
                }
                current_context = current_context[#current_context]
                token = nil
                break
              end
            end
          end
        end

        if Language.personal_pronoun[token] and #current_context == 0 and #(contexts[#contexts-1] or {}) > 0 and contexts[#contexts] == current_context then
          local testTigger = contexts[#contexts-1][1].trigger
          if current_context.struct[testTigger] then
            local struct = current_context.struct[testTigger]
            local arg = nil
            for j=#contexts-1, 1, -1 do
              if (contexts[j][1] or {}).arg ~= "" and (contexts[j][1] or {}).arg ~= nil then
                arg = (contexts[j][1] or {}).arg
              end
            end
            if arg then
              current_context[#current_context+1] = {
                trigger = testTigger,
                struct = struct,
                arg = arg,
                command = struct[0] or ""
              }
              current_context = current_context[#current_context]
              if current_context.struct[token] then
                current_context[#current_context+1] = {
                  trigger = token,
                  struct = current_context.struct[token],
                  arg = "",
                  command = current_context.struct[token][0] or ""
                }
                current_context = current_context[#current_context]
                token = nil
              end
            end
          end
        end

        local block,struct,next_index = find(Language.pronouns[token] and i+1 or i,current_context.struct,false)
        if block then
          current_context[#current_context+1] = {
            trigger = block,
            struct = struct,
            arg = "",
            command = (struct or {[0] = ""})[0] or ""
          }
          current_context = current_context[#current_context]
          i = next_index or i
        else
          local arg = current_context.arg
          if token ~= "" then
            if shellOutput then
              token = token:gsub("'","'\"'\"'")
            end
            arg = arg..(arg == "" and (token and token or "") or (token and " "..token or ""))
          end
          current_context.arg = arg
        end
      end
    end
    i = i+1
  end
end

local function learn()
  local datasheet = io.open("datasheet.tsv","r")
  local db = {}
  for line in (datasheet):lines("l") do
      local input = line:gsub("\t.*","")
      local command = line:gsub("^.*\t","")
      local tokens = {}
      for token in input:gmatch("[^%s]+") do
          if not (Language.pronouns[token] or Language.personal_pronoun[token] or Language.prepositions[token]) then
              tokens[#tokens+1] = #tokens == 0 and Language.normalize(Language.infinitive(token:lower())) or token
          end
      end

      local n = 1
      for i = 1, #tokens, 1 do
        if command:match(tokens[i]) then
          command = command:gsub(tokens[i],"\\0{"..tostring(i-n).."}")
          n = n+1
          tokens[i] = false
        else
          tokens[i] = Language.normalize(tokens[i])
        end
      end
      for i = #tokens, 1, -1 do
          if tokens[i] == false then
            table.remove(tokens,i)
          end
      end
      local emptyTable = {}
      local currentStruct = emptyTable
      for i, token in ipairs(tokens) do
        if currentStruct == emptyTable then
          db[token] = db[token] or {}
          currentStruct = db[token]
        else
          currentStruct[token] = currentStruct[token] or {}
          currentStruct = currentStruct[token]
          if i == #tokens then
            currentStruct[0] = command
          end
        end
      end
  end
  local printDB
  local dbString = "DB = {\n"
  function printDB (struct,level)
      local padding = ("  "):rep(level)
      for key, value in pairs(struct) do
          if type(value) ~= "string" then
            dbString = dbString..(padding..'["'..key..'"] = {\n')
            printDB(value,level+1)
            dbString = dbString..(padding..'},\n')
          else
            dbString = dbString..(padding.."[0] = \""..value:gsub("\"","\\\"").."\",\n")
          end
      end
  end

  printDB(db,1)
  dbString = dbString.."}"

  print(dbString)
  os.exit()
  local f = io.open("database.lua","w+b") or {}
  f:write(string.dump(load(dbString) or print,true))
  os.exit()
end

local compileMode = false

for i = #arg, 1, -1 do
  local argument = arg[i]
  if argument == "--help" or argument == "-h" then
    printUsage()
  elseif argument:sub(1, 7) == "--lang=" then
    lang = tostring(argument):sub(8, -1)
    table.remove(arg,i)
  elseif argument:sub(1, 11) == "--database=" then
    database = tostring(argument):sub(12, -1)
    table.remove(arg,i)
  elseif argument:sub(1, 9) == "--prefix=" then
    prefix = tostring(argument):sub(10, -1)
    table.remove(arg,i)
  elseif argument == "--shell-output" then
    separator = ";\n"
    shellOutput = true
    table.remove(arg,i)
  elseif argument == "--compile" or argument == "-c" then
    compileMode = true
  elseif argument == "--verbose" or argument == "-v" then
    separator = ";\n"
    warn "@on"
    table.remove(arg,i)
  elseif argument == "--debug" or argument == "-d" then
    debugMode = true
    table.remove(arg,i)
  end
end

if prefix and prefix:gsub("[%s]","") ~= "" then
  table.insert(arg,prefix)
end

if #arg == 0 then
  warn "No inputs, entering in interactive mode..."
  interactive = true
  arg[#arg+1] = ""
end

if lang == nil then
  if io.open("languages/" .. (lang or "") .. ".lua","r") == nil then
    warn "Missing --lang= parameter"
    lang = os.getenv("LANG"):gsub("%.UTF%-8$","")
    if io.open("languages/" .. (lang or "") .. ".lua","r") == nil then
      lang = nil
      print "FATAL: Missing --lang= parameter and env LANG doesn't have a compatible language value"
    end
  end
end

if database == nil then
  warn "Missing --database= parameter, fallback to idris-shell"
  database = "idris-shell"
  if io.open("databases/" .. (lang or "") .. "/" .. database .. ".lua","r") == nil then
    database = nil
    print "FATAL: Missing --database= parameter and idris-shell was not found"
  end
end

if lang == nil or database == nil then
  print ""
  printUsage()
end

require("languages." .. lang)
require("databases." .. lang .. "." .. database)

if compileMode then
  learn()
end

if interactive then
  while true do
    io.write("> ")
    tokens = split(io.read("l"))
    contexts = {}
    current_context = {}

    processTokens()
    printOutput(0,contexts)
  end
else
  for _, input in ipairs(arg) do
    tokens = split(input)
    contexts = {}
    current_context = {}

    processTokens()
    printOutput(0,contexts)
  end
end


