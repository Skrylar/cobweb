
import macros
import json
import tables

type
  # XXX experiment and see if we can get away with ex. a short
  BindingId = int

  Updater* = proc(result: var JsonNode; inlets: openarray[JsonNode]): bool

  Binding = object
    backref: BindingId          # This binding's ID, so updaters can touch
    value: JsonNode             # whatever the binding is storing
    updater: Updater            # run to update value; dependent vars
    inlets: seq[BindingId]      # variables this uses for updating

  Cobweb* = object
    intern_table: Table[string, BindingId] # Maps var names to IDs
    values: seq[Binding]        # Stores the bindings themselves
    order: seq[BindingId]       # Stores topo-sorted call order
    roots: seq[BindingId]       # Stores roots when updating dataflow
    deps: seq[BindingId]        # Stores dependency counts
    inlets: seq[JsonNode]       # Cache for inlets during a call or touch

proc call_updater(self: var Cobweb; b: var Binding): bool =
  if b.updater == nil: return       # short-circuit
  setlen(self.inlets, b.inlets.len) # allocate space for inlets
  var x = 0                         # collect inlets
  for i in b.inlets:
    self.inlets[x] = self.values[i].value
  return b.updater(b.value, self.inlets) # run updater

proc make_cobweb*(): Cobweb =
  result.intern_table = initTable[string, BindingId]()
  newseq(result.values, 0)
  newseq(result.inlets, 0)

proc intern(self: var Cobweb; name: string): BindingId =
  ## Put in a name, get an identifier.  If the name is not known, create an identifier and return that.
  if self.intern_table.haskey(name):
    return self.intern_table[name]
  else:
    result = self.values.len
    self.intern_table[name] = result
    self.values.add(Binding(backref: result, value: nil, updater: nil, inlets: nil))
    self.order.add result

proc update*(self: var Cobweb) =
  ## Informs a cobweb you have finished making changes to it (for now.)
  ## The cobweb will then compute a new dataflow plan.

  # zero out scratch vectors
  setlen(self.roots, 0)
  setlen(self.order, 0)
  setlen(self.deps, self.values.len)
  for i in 0..<self.values.len:
    self.deps[i] = 0

  # fill scratch vector with the number of dependencies to resolve;
  # identify roots along the way
  for i in 0..<self.values.len:
    if self.values[i].inlets != nil:
      self.deps[i] = self.values[i].inlets.high
    if self.values[i].inlets == nil or self.values[i].inlets.high == 0:
      self.roots.add(i)

  # Kahn's algorithm
  while self.roots.len > 0:
    var plate = self.roots.pop() # shift root to order
    self.order.add plate
    for i in 0..<self.values.len: # find dependents
      if plate in self.values[i].inlets:
        dec self.deps[i]      # resolve dependency
        if self.deps[i] == 0: # check if all deps have been resolved
          self.roots.add self.values[i].backref # add as root

  # safety dance; check that we just swept a DAG and nothing bad happened
  for i in 0..<self.values.len:
    if self.deps[i] != 0:
      assert false      # TODO proper exception

proc touch(self: var Cobweb; name: BindingId) =
  setlen(self.deps, 1)        # start with only a single dirty value
  self.deps[0] = name

  for i in 0..<self.order.len:
    var dirty = false
    block dirtycheck:   # check if a marked inlet affects this binding
      for candidate in self.deps:
        if candidate in self.values[self.order[i]].inlets:
          dirty = true
          break dirtycheck
    if dirty:                   # need to run the updater
      if self.call_updater(self.values[self.order[i]]):
        # if updater reports a change, we need to add this variable to the
        # update chain as well
        self.deps.add(self.order[i])

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
  if body[3].kind == nnkFormalParams: # there are parameters.
    expectlen(body[3], 2)       # should be 'empty' and 'identdefs'
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