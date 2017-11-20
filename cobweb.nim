
import macros
import json
import tables

type
  # XXX experiment and see if we can get away with ex. a short
  BindingId = int

  Updater* = proc(result: var JsonNode; inlets: openarray[JsonNode]): bool

  Binding = object
    value: JsonNode

  Cobweb* = object
    intern_table: Table[string, BindingId] # Maps var names to IDs
    values: seq[Binding]             # Stores the bindings themselves
    order: seq[BindingId]                  # Stores topo-sorted call order

proc make_cobweb*(): Cobweb =
  result.intern_table = initTable[string, BindingId]()
  newseq(result.values, 0)

proc intern(self: var Cobweb; name: string): BindingId =
  ## Put in a name, get an identifier.  If the name is not known, create an identifier and return that.
  if self.intern_table.haskey(name):
    return self.intern_table[name]
  else:
    result = self.values.len
    self.intern_table[name] = result
    self.values.add(Binding(value: nil))

proc touch(self: var Cobweb; name: BindingId) =
  discard

proc touch*(self: var Cobweb; name: string) =
  ## Acts as though a variable has been changed, without actually changing it.  Used for complex situations.
  if self.intern_table.haskey(name):
    self.touch self.intern_table[name]

proc `[]=`*(self: var Cobweb; name: string; value: JsonNode) =
  ## Sets a variable in the cobweb.  Notifies the dependency chain within the cobweb of a change.
  let id = self.intern(name)
  self.values[id].value = value
  self.touch id

proc `[]`*(self: Cobweb; name: string): JsonNode =
  ## Retrieves a variable from the cobweb.
  if self.intern_table.haskey(name):
    return self.values[self.intern_table[name]].value
  else:
    return nil

proc internal_add_dependent*(self: var Cobweb; name: string; inlets: openarray[string]; updater: Updater) =
  echo self
  for x in inlets:
    echo x

macro dependent*(cob: var Cobweb; variable_name: untyped, body: untyped): untyped =
  echo variable_name
  echo treerepr(body)

  # must provide a valid identifier for a variable name
  expectkind(variable_name, nnkIdent)

  # last parameter must be a 'do' form
  expectkind(body, nnkDo)
  expectlen(body, 7)

  var inletnode = new_nim_node(nnkBracket)

  # are there any input variables}
  if body[3].kind == nnkFormalParams: # There are parameters.
    expectlen(body[3], 2)       # Should be 'empty' and 'identdefs'
    expectkind(body[3][1], nnkIdentDefs)
    expectminlen(body[3][1], 3)

    for i in 0..(body[3][1].len-3): # Iterate input values.
      expectkind(body[3][1][i], nnkIdent)
      inletnode.add(new_str_lit_node($body[3][1][i]))
  else:                      # There are no parameters.
    assert "bleh" == nil     # TODO proper error; there must be inputs

  let paramlist = gensym(nskParam)
  var out_body = new_nim_node(nnkStmtList)
  var inlet_vars = new_nim_node(nnkStmtList)

  var x = 0
  for inlet in inletnode:
    # paramlist[x]
    var brackets = new_nim_node(nnkBracketExpr)
    brackets.add paramlist
    brackets.add new_int_lit_node x
    # let inlet = ...
    var lnode = new_let_stmt(new_ident_node($inlet), brackets)
    # add it in
    inlet_vars.add lnode

    inc x                       # count inlets
    #new_let_stmt($inlet, )

  out_body.add inlet_vars
  out_body.add body[6]

  var resultpar = new_nim_node(nnkIdentDefs)
  resultpar.add new_ident_node($variable_name)
  var resultpar_var = new_nim_node(nnkVarTy)
  resultpar_var.add new_ident_node("JsonNode")
  resultpar.add resultpar_var
  resultpar.add new_empty_node()

  var parampar = new_nim_node(nnkIdentDefs)
  parampar.add paramlist
  var parampar_var = new_nim_node(nnkBracketExpr)
  parampar_var.add new_ident_node("openarray")
  parampar_var.add new_ident_node("JsonNode")
  parampar.add parampar_var
  parampar.add new_empty_node()

  let lmb = new_proc(newEmptyNode(), # name, which we do not use
    [new_ident_node("bool"), resultpar, parampar], # parameters
    out_body,                                      # proc body
    nnkLambda)                                     # proc type

  #echo repr lmb

  result = newcall(bindsym"internal_add_dependent", cob, new_str_lit_node($variable_name), inletnode, lmb)

  echo repr result

macro butt(input: untyped): untyped =
  echo treerepr(input)

butt(proc(a: openarray[JsonNode]) =
  let x = proc(result: var JsonValue; piss: openarray[string]) = discard)